import winim/core

# Reference: https://github.com/m4ul3r/malware/blob/main/nim/coff_loader/beaconapi.nim

type va_list {.importc: "va_list", header: "<stdarg.h>".} = object
proc puts(s: pointer): void {.importc, header: "<stdio.h>".}
proc vprintf(format: pointer, args: va_list) {.importc, header: "<stdio.h>".}
proc va_start(va: va_list, fmt: pointer) {.importc, header: "<stdarg.h>".}
proc va_end(va: va_list): void {.importc, header: "<stdarg.h>".}

type datap* {.pure.} = object
    original: PCHAR
    buffer: PCHAR
    length: INT
    size: INT

const
    CALLBACK_OUTPUT* = 0x0
    CALLBACK_OUTPUT_OEM* = 0x1e
    CALLBACK_OUTPUT_UTF8* = 0x20
    CALLBACK_ERROR* = 0xd

proc BeaconDataParse*(parser: ptr datap, buffer: PCHAR, size: INT): void =
    if cast[int](parser) == 0:
        return
    parser.original = buffer
    parser.buffer = buffer
    parser.length = size - 4
    parser.size = size - 4
    parser.buffer = cast[PCHAR](cast[int](buffer) + 4)

proc BeaconDataInt*(parser: ptr datap): INT =
    var fourbyteint: INT = 0
    if (parser.length < 4):
        return 0
    copyMem(fourbyteint.addr, parser.buffer, 4)
    parser.buffer = cast[PCHAR](cast[int](parser.buffer) + 4)
    parser.length = cast[INT](cast[int](parser.length) - 4)

    return fourbyteint

proc BeaconDataShort*(parser: ptr datap): SHORT =
    var retvalue: SHORT = 0
    if (parser.length < 2):
        return 0
    copyMem(retvalue.addr, parser.buffer, 2)
    parser.buffer = cast[PCHAR](cast[int](parser.buffer) + 2)
    parser.length = cast[INT](cast[int](parser.length) - 2)

    return retvalue

proc BeaconDataLength*(parser: ptr datap): INT =
    return parser.length

proc BeaconDataExtract*(parser: ptr datap, size: ptr INT): PCHAR =
    var
        length: INT = 0
        outdata: PCHAR = nil

    if (parser.length < 4):
        return nil

    copyMem(length.addr, parser.buffer, 4)
    parser.buffer = cast[PCHAR](cast[int](parser.buffer) + 4)

    outdata = parser.buffer
    if (outdata == nil):
        return nil

    parser.length = cast[INT](cast[int](parser.length) - 4)
    parser.length = cast[INT](cast[int](parser.length) - length)
    parser.buffer = cast[PCHAR](cast[int](parser.buffer) + length)

    if (size != nil) and (outdata != nil):
        size[] = length

    return outdata

proc BeaconOutput*(typ: int, data: pointer, length: int): void =
    puts(data)

proc BeaconPrintf*(typ: int, fmt: pointer): void {.varargs.} =
    var va: va_list
    va_start(va, fmt)
    vprintf(fmt, va)
    va_end(va)