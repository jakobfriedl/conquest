import winim, os, net, strformat, strutils, registry

import ./[types, utils]

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
proc getProductType(): ProductType =
    # Instead, we retrieve the product key from the registry
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
    
    proc rtlGetVersion(lpVersionInformation: var types.OSVersionInfoExW): NTSTATUS
        {.cdecl, importc: "RtlGetVersion", dynlib: "ntdll.dll".}

    when defined(windows):
        var osInfo: types.OSVersionInfoExW
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

    