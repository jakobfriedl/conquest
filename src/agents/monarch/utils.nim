import strformat
import ./common/types

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