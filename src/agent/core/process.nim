import winim/lean 
import tables
import ../utils/io
import ../../common/utils
import token

type 
    ProcessInfo* = object 
        pid*: DWORD
        ppid*: DWORD 
        name*: string 
        user*: string
        session*: ULONG
        children*: seq[DWORD]

    NtQuerySystemInformation = proc(systemInformationClass: SYSTEM_INFORMATION_CLASS, systemInformation: PVOID, systemInformationLength: ULONG, returnLength: PULONG): NTSTATUS {.stdcall.}
    NtOpenProcess = proc(hProcess: PHANDLE, desiredAccess: ACCESS_MASK, oa: PCOBJECT_ATTRIBUTES, clientId: PCLIENT_ID): NTSTATUS {.stdcall.}    
    NtOpenProcessToken = proc(processHandle: HANDLE, desiredAccess: ACCESS_MASK, tokenHandle: PHANDLE): NTSTATUS {.stdcall.}
    NtClose = proc(handle: HANDLE): NTSTATUS {.stdcall.}

proc cmp*(x, y: ProcessInfo): int = 
    return cmp(x.pid, y.pid)

#[
    Retrieve snapshot of all currently running processes using NtQuerySystemInformation
]#
proc processSnapshot*(): PSYSTEM_PROCESS_INFORMATION = 
    var
        pSystemProcInfo: PSYSTEM_PROCESS_INFORMATION
        status: NTSTATUS = 0
        returnLength: ULONG = 0
    
    let pNtQuerySystemInformation = cast[NtQuerySystemInformation](GetProcAddress(GetModuleHandleA(protect("ntdll")), protect("NtQuerySystemInformation")))

    # Retrieve returnLength and allocate sufficient memory
    discard pNtQuerySystemInformation(systemProcessInformation, NULL, 0, addr returnLength)
    pSystemProcInfo = cast[PSYSTEM_PROCESS_INFORMATION](LocalAlloc(LMEM_FIXED, returnLength))
    if pSystemProcInfo == NULL:
        raise newException(CatchableError, "1.2" & GetLastError().getError())
    
    # Retrieve system process information
    status = pNtQuerySystemInformation(systemProcessInformation, cast[PVOID](pSystemProcInfo), returnLength, addr returnLength)
    if status != STATUS_SUCCESS:
        raise newException(CatchableError, "b" & status.getNtError())
    
    return pSystemProcInfo

#[
    Retrieve information about running processes
]#
proc processList*(): Table[DWORD, ProcessInfo] = 
    result = initTable[DWORD, ProcessInfo]() 

    # Take a snapshot of running processes
    var sysProcessInfo = processSnapshot() 
    defer: LocalFree(cast[HLOCAL](sysProcessInfo))

    let pNtOpenProcess = cast[NtOpenProcess](GetProcAddress(GetModuleHandleA(protect("ntdll")), protect("NtOpenProcess")))
    let pNtOpenProcessToken = cast[NtOpenProcessToken](GetProcAddress(GetModuleHandleA(protect("ntdll")), protect("NtOpenProcessToken")))
    let pNtClose = cast[NtClose](GetProcAddress(GetModuleHandleA(protect("ntdll")), protect("NtClose")))
    
    while true: 
        var 
            status: NTSTATUS
            hToken: HANDLE = 0
            hProcess: HANDLE = 0
            oa: OBJECT_ATTRIBUTES
            clientId: CLIENT_ID
        
        var 
            pid = cast[DWORD](sysProcessInfo.UniqueProcessId)
            ppid = cast[DWORD](sysProcessInfo.InheritedFromUniqueProcessId)

        # Retrieve process information
        result[pid] = ProcessInfo(
            pid: pid,
            ppid: ppid,
            name: $sysProcessInfo.ImageName.Buffer,
            session: sysProcessInfo.SessionId,
            children: @[]
        )

        # Retrieve user context    
        InitializeObjectAttributes(addr oa, NULL, 0, 0, NULL)
        clientId.UniqueProcess = cast[HANDLE](pid)
        clientId.UniqueThread = 0

        status = pNtOpenProcess(addr hProcess, PROCESS_QUERY_INFORMATION, addr oa, addr clientId)
        if status == STATUS_SUCCESS and hProcess != 0: 
            status = pNtOpenProcessToken(hProcess, TOKEN_QUERY, addr hToken)
            if status == STATUS_SUCCESS and hToken != 0: 
                result[pid].user = hToken.getTokenUser().username
                discard pNtClose(hToken)
            else: 
                result[pid].user = ""
            discard pNtClose(hProcess)

        # Move to next process
        if sysProcessInfo.NextEntryOffset == 0: 
            break
            
        sysProcessInfo = cast[PSYSTEM_PROCESS_INFORMATION](cast[ULONG_PTR](sysProcessInfo) + sysProcessInfo.NextEntryOffset)