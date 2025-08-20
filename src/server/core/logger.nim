import terminal, times, strformat, strutils
import std/[dirs, paths]
import ../../common/[types, profile]

proc makeAgentLogDirectory*(cq: Conquest, agentId: string): bool = 
    try: 
        let cqDir = cq.profile.getString("conquest_directory")
        createDir(cast[Path](fmt"{cqDir}/data/logs/{agentId}"))
        return true 
    except OSError:
        return false 

proc log*(cq: Conquest, logEntry: string) = 
    if cq.interactAgent == nil: 
       return 

    let 
        date = now().format("dd-MM-yyyy")
        timestamp = now().format("dd-MM-yyyy HH:mm:ss")
        cqDir = cq.profile.getString("conquest_directory")
        agentLogPath = fmt"{cqDir}/data/logs/{cq.interactAgent.agentId}/{date}.log"

    # Write log entry to file 
    let file = open(agentLogPath, fmAppend)
    file.writeLine(fmt"[{timestamp}] {logEntry}")
    file.flushFile() 

proc extractStrings(args: string): string =
    if not args.startsWith("("): 
        return args

    # Remove styling arguments, such as fgRed, styleBright, resetStyle, etc. by extracting only arguments that are quoted
    var message: string
    for str in args[1..^2].split(", "): 
        if str.startsWith("\""): 
            message &= str
    return message.replace("\"", "")

template info*(cq: Conquest, args: varargs[untyped]) = 
    cq.writeLine(fgBlack, styleBright, "[*] ", resetStyle, args)
    cq.log("[*] " & extractStrings($(args)))

template error*(cq: Conquest, args: varargs[untyped]) = 
    cq.writeLine(fgRed, styleBright, "[-] ", resetStyle, args)
    cq.log("[-] " & extractStrings($(args)))

template warn*(cq: Conquest, args: varargs[untyped]) = 
    cq.writeLine(fgYellow, "[!] ", resetStyle, args)
    cq.log("[!] " & extractStrings($(args)))

template success*(cq: Conquest, args: varargs[untyped]) = 
    cq.writeLine(fgGreen, "[+] ", resetStyle, args)
    cq.log("[+] " & extractStrings($(args)))

template output*(cq: Conquest, args: varargs[untyped]) = 
    cq.writeLine(args)
    cq.log("[>] " & extractStrings($(args)))
