import winim/lean
import macros
import strutils, strformat
import ../../common/utils

const VERBOSE* {.booldefine.} = false

type 
    RtlNtStatusToDosError = proc(status: NTSTATUS): DWORD {.stdcall.}

# Only print to console when VERBOSE mode is enabled
template print*(args: varargs[untyped]): untyped = 
    when defined(VERBOSE) and VERBOSE == true: 
        echo args
    else: 
        discard

# Convert Windows API error to readable value
# https://learn.microsoft.com/de-de/windows/win32/api/winbase/nf-winbase-formatmessage
proc getError*(errorCode: DWORD): string = 
    var msg = newWString(512) 
    FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM or FORMAT_MESSAGE_IGNORE_INSERTS, NULL, errorCode, cast[DWORD](MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT)), msg, cast[DWORD](msg.len()), NULL)
    msg.nullTerminate()
    return strip($msg) & fmt" ({$errorCode})"

# Convert NTSTATUS to readable value 
# https://ntdoc.m417z.com/rtlntstatustodoserror
proc getNtError*(status: NTSTATUS): string = 
    let pRtlNtStatusToDosError = cast[RtlNtStatusToDosError](GetProcAddress(GetModuleHandleA(protect("ntdll")), protect("RtlNtStatusToDosError")))
    let errorCode = pRtlNtStatusToDosError(status)
    return getError(errorCode) 
