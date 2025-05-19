import winim, os, net

import ./types

# Username
proc getUsername*(): string = 
    const NameSamCompatible = 2 # EXTENDED_NAME_FORMAT (https://learn.microsoft.com/de-de/windows/win32/api/secext/ne-secext-extended_name_format) 
    var
        buffer = newWString(UNLEN + 1) 
        dwSize = DWORD buffer.len

    GetUserNameExW(NameSamCompatible, &buffer, &dwSize)
    return $buffer[0 ..< int(dwSize)]

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


# Current process name
proc getProcessExe*(): string = 
    let 
        hProcess: HANDLE = GetCurrentProcess() 
        buffer = newWString(MAX_PATH + 1)

    try:
        if hProcess != 0: 
            if GetModuleFileNameExW(hProcess, 0, buffer, MAX_PATH): 
                # .extractFilename() from the 'os' module gets the name of the executable from the full process path
                return string($buffer).extractFilename()
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

# Windows Version
proc getOSVersion*(): string = 
    discard