import winim

type 
    ProductType* = enum
        UNKNOWN = 0
        WORKSTATION = 1
        DC = 2
        SERVER = 3

# API Structs
type OSVersionInfoExW* {.importc: "OSVERSIONINFOEXW", header: "<windows.h>".} = object
    dwOSVersionInfoSize*: ULONG
    dwMajorVersion*: ULONG
    dwMinorVersion*: ULONG
    dwBuildNumber*: ULONG
    dwPlatformId*: ULONG
    szCSDVersion*: array[128, WCHAR]
    wServicePackMajor*: USHORT
    wServicePackMinor*: USHORT
    wSuiteMask*: USHORT
    wProductType*: UCHAR
    wReserved*: UCHAR

type
    AgentConfig* = ref object
        listener*: string
        ip*: string
        port*: int
        sleep*: int