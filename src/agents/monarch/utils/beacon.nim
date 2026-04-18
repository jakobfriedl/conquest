import winim/lean
import ptr_math
import strformat
import ../../../common/utils 

#[
    References: 
    - https://github.com/Cobalt-Strike/bof_template/blob/main/beacon.h
    - https://github.com/frkngksl/NiCOFF/blob/main/BeaconFunctions.nim 
    - https://github.com/trustedsec/COFFLoader/blob/main/beacon_compatibility.c
    - https://github.com/Cracked5pider/CoffeeLdr/blob/main/Source/BeaconApi.c   
]#

const
    CALLBACK_OUTPUT      = 0x0
    CALLBACK_OUTPUT_OEM  = 0x1e
    CALLBACK_ERROR       = 0x0d
    CALLBACK_OUTPUT_UTF8 = 0x20

type
    datap* {.bycopy, packed.} = object
        original*: PCHAR
        buffer*: PCHAR
        length*: int32
        size*: int32

    formatp* {.bycopy, packed.} = object
        original*: PCHAR
        buffer*: PCHAR
        length*: int32
        size*: int32

# va_list support for varargs
# Reference: https://forum.nim-lang.org/t/7352
type va_list* {.importc: "va_list", header: "<stdarg.h>".} = object
proc va_start(ap: va_list, last: pointer) {.importc, header: "<stdarg.h>".}
proc va_end(ap: va_list) {.importc, header: "<stdarg.h>".}
proc vsnprintf(s: cstring, maxlen: csize_t, format: cstring, arg: va_list): cint {.importc, header: "<stdio.h>".}

var beaconCompatibilityOutput: PCHAR = nil
var beaconCompatibilitySize: int = 0
var beaconCompatibilityOffset: int = 0

proc swapEndianess(indata: uint32): uint32 =
    var testInt: uint32 = 0xaabbccdd'u32
    var outInt: uint32 = indata
    if cast[ptr uint8](addr testInt)[] == 0xdd:
        cast[ptr uint8](addr outInt)[] = (cast[ptr uint8](addr indata) + 3)[]
        (cast[ptr uint8](addr outInt) + 1)[] = (cast[ptr uint8](addr indata) + 2)[]
        (cast[ptr uint8](addr outInt) + 2)[] = (cast[ptr uint8](addr indata) + 1)[]
        (cast[ptr uint8](addr outInt) + 3)[] = cast[ptr uint8](addr indata)[]
    return outInt

#[
    Parsing Functions
]#
proc BeaconDataParse(parser: ptr datap, buffer: PCHAR, size: int): void {.stdcall.} =
    if parser == nil or buffer == nil:
        return

    parser.original = buffer
    parser.buffer = buffer
    parser.length = int32(size - 4)
    parser.size = int32(size - 4)
    parser.buffer = cast[PCHAR](cast[uint](parser.buffer) + 4)

proc BeaconDataPtr(parser: ptr datap, size: int): PCHAR {.stdcall.} =
    if parser == nil:
        return NULL
    
    if parser.length < int32(size):
        return NULL
    
    let outData = parser.buffer
    parser.buffer = cast[PCHAR](cast[uint](parser.buffer) + uint(size))
    parser.length -= int32(size)
    return outData

proc BeaconDataInt(parser: ptr datap): int {.stdcall.} =
    if parser == nil:
        return 0

    var fourbyteint: int32 = 0
    if parser.length < 4:
        return 0
    
    copyMem(addr fourbyteint, parser.buffer, 4)
    parser.buffer = cast[PCHAR](cast[uint](parser.buffer) + 4)
    parser.length -= 4
    return int(fourbyteint)

proc BeaconDataShort(parser: ptr datap): int16 {.stdcall.} =
    if parser == nil:
        return 0

    var retvalue: int16 = 0
    if parser.length < 2:
        return 0

    copyMem(addr retvalue, parser.buffer, 2)
    parser.buffer = cast[PCHAR](cast[uint](parser.buffer) + 2)
    parser.length -= 2
    return retvalue

proc BeaconDataLength(parser: ptr datap): int {.stdcall.} =
    if parser == nil:
        return 0
    
    return int(parser.length)

proc BeaconDataExtract(parser: ptr datap, size: ptr int): PCHAR {.stdcall.} =
    if parser == nil:
        return NULL

    var 
        length: uint32 = 0
        outData: PCHAR = nil
    
    if parser.length < 4:
        return NULL
    
    copyMem(addr length, parser.buffer, 4)
    parser.buffer = cast[PCHAR](cast[uint](parser.buffer) + 4)
    parser.length -= 4

    outData = parser.buffer
    if outData == nil:
        return NULL

    parser.length -= int32(length)
    parser.buffer = cast[PCHAR](cast[uint](parser.buffer) + uint(length))

    if size != nil and outData != nil:
        size[] = int(length)
    
    return outData

#[
    Formatting Functions
]#
proc BeaconFormatAlloc(format: ptr formatp, maxsz: int): void {.stdcall.} =
    if format == nil:
        return

    format.original = cast[PCHAR](HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, maxsz))
    format.buffer = format.original
    format.length = 0
    format.size = int32(maxsz)

proc BeaconFormatReset(format: ptr formatp): void {.stdcall.} =
    if format == nil:
        return

    zeroMem(format.original, format.size)
    format.buffer = format.original
    format.length = 0

proc BeaconFormatFree(format: ptr formatp): void {.stdcall.} =
    if format == nil:
        return

    if format.original != nil:
        discard HeapFree(GetProcessHeap(), 0, format.original)
        format.original = nil
    
    format.buffer = nil
    format.length = 0
    format.size = 0

proc BeaconFormatAppend(format: ptr formatp, text: PCHAR, len: int): void {.stdcall.} =
    if format == nil or text == nil:
        return

    if format.length + int32(len) > format.size:
        return

    copyMem(format.buffer, text, len)
    format.buffer = cast[PCHAR](cast[uint](format.buffer) + uint(len))
    format.length += int32(len)

proc BeaconFormatPrintf(format: ptr formatp, fmt: PCHAR): void {.stdcall, varargs.} =
    if format == nil or fmt == nil:
        return
    
    var args: va_list
    var length: cint = 0

    va_start(args, fmt)
    length = vsnprintf(nil, 0, fmt, args)
    va_end(args)
    
    if length <= 0:
        return

    if format.length + length > format.size:
        return

    va_start(args, fmt)
    discard vsnprintf(format.buffer, csize_t(length + 1), fmt, args)
    va_end(args)
    
    format.length += length
    format.buffer = cast[PCHAR](cast[uint](format.buffer) + uint(length))

proc BeaconFormatToString(format: ptr formatp, size: ptr int): PCHAR {.stdcall.} =
    if format == nil:
        return NULL
    if size != nil:
        size[] = int(format.length)
    return format.original

proc BeaconFormatInt(format: ptr formatp, value: int): void {.stdcall.} =
    if format == nil:
        return

    var indata: uint32 = cast[uint32](value)
    var outdata: uint32 = 0
    
    if format.length + 4 > format.size:
        return
        
    outdata = swapEndianess(indata)
    copyMem(format.buffer, addr outdata, 4)
    format.length += 4
    format.buffer = cast[PCHAR](cast[uint](format.buffer) + 4)

#[ 
    Output Functions
]#
proc BeaconPrintf(typeArg: int, fmt: PCHAR): void {.stdcall, varargs.} =
    if fmt == nil:
        return

    var length: cint = 0
    var tempPtr: PCHAR = nil
    var args: va_list
    
    # Calculate required length
    va_start(args, fmt)
    length = vsnprintf(nil, 0, fmt, args)
    va_end(args)

    if length <= 0:
        return

    # Allocate temporary buffer
    var tmpOutput = cast[PCHAR](HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, length + 1))
    if tmpOutput == nil:
        return

    # Format the string
    va_start(args, fmt)
    discard vsnprintf(tmpOutput, csize_t(length + 1), fmt, args)
    va_end(args)

    # Reallocate compatibility output buffer
    if beaconCompatibilityOutput == nil:
        tempPtr = cast[PCHAR](HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, length + 1))
    else:
        tempPtr = cast[PCHAR](HeapReAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, beaconCompatibilityOutput, beaconCompatibilitySize + length + 1))
    
    if tempPtr != nil:
        beaconCompatibilityOutput = tempPtr
        copyMem(cast[pointer](cast[uint](beaconCompatibilityOutput) + uint(beaconCompatibilityOffset)), tmpOutput, length)
        beaconCompatibilitySize += length
        beaconCompatibilityOffset += length

    discard HeapFree(GetProcessHeap(), 0, tmpOutput)
    
proc BeaconOutput(typeArg: int, data: PCHAR, len: int): void {.stdcall.} =
    if data == nil:
        return

    var tempPtr: PCHAR = nil
    
    if beaconCompatibilityOutput == nil:
        tempPtr = cast[PCHAR](HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, len + 1))
    else:
        tempPtr = cast[PCHAR](HeapReAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, beaconCompatibilityOutput, beaconCompatibilitySize + len + 1))
    
    if tempPtr == nil:
        return
        
    beaconCompatibilityOutput = tempPtr
    copyMem(cast[pointer](cast[uint](beaconCompatibilityOutput) + uint(beaconCompatibilityOffset)), data, len)
    beaconCompatibilitySize += len
    beaconCompatibilityOffset += len

proc BeaconDownload(filename: PCHAR, buffer: PCHAR, length: uint): BOOL {.stdcall.} =
    return FALSE

#[
    Token Functions
]#
proc BeaconUseToken(token: HANDLE): BOOL {.stdcall.} =
    if ImpersonateLoggedOnUser(token) == 0: return FALSE
    return TRUE

proc BeaconRevertToken(): void {.stdcall.} =
    discard RevertToSelf()

type 
    NtQueryInformationToken = proc(hToken: HANDLE, tokenInformationClass: TOKEN_INFORMATION_CLASS, tokenInformation: PVOID, tokenInformationLength: ULONG, returnLength: PULONG): NTSTATUS {.stdcall.}
    NtOpenThreadToken = proc(threadHandle: HANDLE, desiredAccess: ACCESS_MASK, openAsSelf: BOOLEAN, tokenHandle: PHANDLE): NTSTATUS {.stdcall.}
    NtOpenProcessToken = proc(processHandle: HANDLE, desiredAccess: ACCESS_MASK, tokenHandle: PHANDLE): NTSTATUS {.stdcall.}

proc BeaconIsAdmin(): BOOL {.stdcall.}=
    let 
        hNtdll = GetModuleHandleA(protect("ntdll"))
        pNtOpenProcessToken = cast[NtOpenProcessToken](GetProcAddress(hNtdll, protect("NtOpenProcessToken")))
        pNtOpenThreadToken = cast[NtOpenThreadToken](GetProcAddress(hNtdll, protect("NtOpenThreadToken")))
        pNtQueryInformationToken = cast[NtQueryInformationToken](GetProcAddress(hNtdll, protect("NtQueryInformationToken")))
    
    var 
        status: NTSTATUS = 0
        hToken: HANDLE 
        returnLength: ULONG = 0
        pElevation: TOKEN_ELEVATION 

    # https://ntdoc.m417z.com/ntopenthreadtoken
    status = pNtOpenThreadToken(cast[HANDLE](-2), TOKEN_QUERY, TRUE, addr hToken)
    if status != STATUS_SUCCESS:
        status = pNtOpenProcessToken(cast[HANDLE](-1), TOKEN_QUERY, addr hToken)
        if status != STATUS_SUCCESS: 
            return FALSE
        
    # Get elevation
    status = pNtQueryInformationToken(hToken, tokenElevation, addr pElevation, cast[ULONG](sizeof(pElevation)), addr returnLength)
    if status != STATUS_SUCCESS: 
        return FALSE

    return cast[bool](pElevation.TokenIsElevated)

#[ 
    Spawn+Inject Functions
]# 
proc BeaconGetSpawnTo(x86: BOOL, buffer: PCHAR, length: int): void {.stdcall.} =
    return

proc BeaconSpawnTemporaryProcess(x86: BOOL, ignoreToken: BOOL, sInfo: ptr STARTUPINFOA, pInfo: ptr PROCESS_INFORMATION): BOOL {.stdcall.} =
    return FALSE

proc BeaconInjectProcess(hProc: HANDLE, pid: int, payload: PCHAR, p_len: int, p_offset: int, arg: PCHAR, a_len: int): void {.stdcall.} =
    return

proc BeaconInjectTemporaryProcess(pInfo: ptr PROCESS_INFORMATION, payload: PCHAR, p_len: int, p_offset: int, arg: PCHAR, a_len: int): void {.stdcall.} =
    return

proc BeaconCleanupProcess(pInfo: ptr PROCESS_INFORMATION): void {.stdcall.} =
    if pInfo != nil:
        discard CloseHandle(pInfo.hThread)
        discard CloseHandle(pInfo.hProcess)

#[
    Utility Functions
]# 
proc toWideChar(src: PCHAR, dst: PWSTR, max: int): BOOL {.stdcall.} =
    if max < sizeof(WCHAR):
        return FALSE
    return if MultiByteToWideChar(CP_ACP, 0, src, -1, dst, int32(max div sizeof(WCHAR))) != 0: TRUE else: FALSE

proc BeaconGetOutputData*(outSize: ptr int): PCHAR {.stdcall.} =
    var outData: PCHAR = beaconCompatibilityOutput
    
    if outSize != nil:
        outSize[] = beaconCompatibilitySize
        
    beaconCompatibilityOutput = nil
    beaconCompatibilitySize = 0
    beaconCompatibilityOffset = 0
    return outData

#[
    Data Storage Functions
]#
import tables
var beaconStorage = initTable[string, pointer]()

proc BeaconAddValue(key: PCHAR, value: PVOID): BOOL {.stdcall.} =
    try:
        let keyStr = $key
        beaconStorage[keyStr] = value
        return TRUE
    except:
        return FALSE

proc BeaconGetValue(key: PCHAR): PVOID {.stdcall.} =
    try:
        let keyStr = $key
        if beaconStorage.hasKey(keyStr):
            return beaconStorage[keyStr]
        else:
            return nil
    except:
        return nil

proc BeaconRemoveValue(key: PCHAR): BOOL {.stdcall.} =
    try:
        let keyStr = $key
        if beaconStorage.hasKey(keyStr):
            beaconStorage.del(keyStr)
            return TRUE
        else:
            return FALSE
    except:
        return FALSE

#[ 
    Async APIs for compatibility
]#

proc BeaconWakeup*() {.stdcall.} = 
    discard 

proc BeaconGetStopJobEvent(): HANDLE {.stdcall.} = 
    discard 

var beaconApiAddresses*: array[34, tuple[name: string, address: PVOID]] = [
    (protect("BeaconDataParse"), BeaconDataParse),
    (protect("BeaconDataPtr"), BeaconDataPtr),
    (protect("BeaconDataInt"), BeaconDataInt),
    (protect("BeaconDataShort"), BeaconDataShort),
    (protect("BeaconDataLength"), BeaconDataLength),
    (protect("BeaconDataExtract"), BeaconDataExtract),
    (protect("BeaconFormatAlloc"), BeaconFormatAlloc),
    (protect("BeaconFormatReset"), BeaconFormatReset),
    (protect("BeaconFormatFree"), BeaconFormatFree),
    (protect("BeaconFormatAppend"), BeaconFormatAppend),
    (protect("BeaconFormatPrintf"), BeaconFormatPrintf),
    (protect("BeaconFormatToString"), BeaconFormatToString),
    (protect("BeaconFormatInt"), BeaconFormatInt),
    (protect("BeaconPrintf"), BeaconPrintf),
    (protect("BeaconOutput"), BeaconOutput),
    (protect("BeaconDownload"), BeaconDownload),
    (protect("BeaconUseToken"), BeaconUseToken),
    (protect("BeaconRevertToken"), BeaconRevertToken),
    (protect("BeaconIsAdmin"), BeaconIsAdmin),
    (protect("BeaconGetSpawnTo"), BeaconGetSpawnTo),
    (protect("BeaconSpawnTemporaryProcess"), BeaconSpawnTemporaryProcess),
    (protect("BeaconInjectProcess"), BeaconInjectProcess),
    (protect("BeaconInjectTemporaryProcess"), BeaconInjectTemporaryProcess),
    (protect("BeaconCleanupProcess"), BeaconCleanupProcess),
    (protect("toWideChar"), toWideChar),
    (protect("BeaconAddValue"), BeaconAddValue),
    (protect("BeaconGetValue"), BeaconGetValue),
    (protect("BeaconRemoveValue"), BeaconRemoveValue),
    (protect("BeaconWakeup"), BeaconWakeup),
    (protect("BeaconGetStopJobEvent"), BeaconGetStopJobEvent),
    (protect("LoadLibraryA"), LoadLibraryA),
    (protect("GetProcAddress"), GetProcAddress),
    (protect("GetModuleHandleA"), GetModuleHandleA),
    (protect("FreeLibrary"), FreeLibrary)
]