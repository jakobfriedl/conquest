import winim/lean 
import winim/inc/tlhelp32
import strutils, strformat, tables, algorithm
import ../utils/io
import ../../common/[types, utils]
import token

type 
    ProcessInfo* = object 
        pid*: DWORD
        ppid*: DWORD 
        name*: string 
        user*: string
        children*: seq[DWORD]

    # NtQuerySystemInformation = proc(systemInformationClass: SYSTEM_INFORMATION_CLASS, systemInformation: PVOID, systemInformationLength: ULONG, returnLength: PULONG): NTSTATUS {.stdcall.}
    NtOpenProcess = proc(hProcess: PHANDLE, desiredAccess: ACCESS_MASK, oa: PCOBJECT_ATTRIBUTES, clientId: PCLIENT_ID): NTSTATUS {.stdcall.}    
    NtOpenProcessToken = proc(processHandle: HANDLE, desiredAccess: ACCESS_MASK, tokenHandle: PHANDLE): NTSTATUS {.stdcall.}

const PROCESS_QUERY_LIMITED_INFORMATION = 0x00001000'i32

proc cmp*(x, y: ProcessInfo): int = 
    return cmp(x.pid, y.pid)

proc processList*(): Table[DWORD, ProcessInfo] = 
    result = initTable[DWORD, ProcessInfo]() 

    # Take a snapshot of running processes
    let hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if hSnapshot == INVALID_HANDLE_VALUE: 
        raise newException(CatchableError, GetLastError().getError)    
    defer: CloseHandle(hSnapshot)

    var pe32: PROCESSENTRY32
    pe32.dwSize = DWORD(sizeof(PROCESSENTRY32))

    # Loop over processes to fill the map            
    if Process32First(hSnapshot, addr pe32) == FALSE:
        raise newException(CatchableError, GetLastError().getError)
    
    let pNtOpenProcess = cast[NtOpenProcess](GetProcAddress(GetModuleHandleA(protect("ntdll")), protect("NtOpenProcess")))
    let pNtOpenProcessToken = cast[NtOpenProcessToken](GetProcAddress(GetModuleHandleA(protect("ntdll")), protect("NtOpenProcessToken")))
    
    while Process32Next(hSnapshot, addr pe32): 
        var 
            status: NTSTATUS
            hToken: HANDLE 
            hProcess: HANDLE
            oa: OBJECT_ATTRIBUTES
            clientId: CLIENT_ID
        
        var procInfo = ProcessInfo(
            pid: pe32.th32ProcessID,
            ppid: pe32.th32ParentProcessID,
            name: $cast[WideCString](addr pe32.szExeFile[0]),
            children: @[]
        )

        # Retrieve user context    
        InitializeObjectAttributes(addr oa, NULL, 0, 0, NULL)
        clientId.UniqueProcess = cast[HANDLE](pe32.th32ProcessID)
        clientId.UniqueThread = 0

        status = pNtOpenProcess(addr hProcess, PROCESS_QUERY_INFORMATION, addr oa, addr clientId)
        if status == STATUS_SUCCESS and hProcess != 0: 
            status = pNtOpenProcessToken(hProcess, TOKEN_QUERY, addr hToken)
            if status == STATUS_SUCCESS and hToken != 0: 
                procInfo.user = hToken.getTokenUser().username
        
        result[pe32.th32ProcessID] = procInfo

    for pid, procInfo in result.mpairs():
        if result.contains(procInfo.ppid):
            result[procInfo.ppid].children.add(pid)
