import macros
import ../../common/[types, utils]

const VERBOSE* {.booldefine.} = false

# Only print to console when VERBOSE mode is enabled
template print*(args: varargs[untyped]): untyped = 
    when defined(VERBOSE) and VERBOSE == true: 
        echo args
    else: 
        discard

# Convert Windows API error to readable value
# https://learn.microsoft.com/de-de/windows/win32/api/winbase/nf-winbase-formatmessage

# Convert NTSTATUS to readable value 
# https://ntdoc.m417z.com/rtlntstatustodoserror
