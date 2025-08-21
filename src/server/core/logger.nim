import times, strformat, strutils
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
    let 
        date = now().format("dd-MM-yyyy")
        cqDir = cq.profile.getString("conquest_directory")
        agentLogPath = fmt"{cqDir}/data/logs/{cq.interactAgent.agentId}/{date}.session.log"

    # Write log entry to file 
    let file = open(agentLogPath, fmAppend)
    file.writeLine(fmt"{logEntry}")
    file.flushFile() 

proc extractStrings*(args: string): string =
    if not args.startsWith("("): 
        return args

    # Remove styling arguments, such as fgRed, styleBright, resetStyle, etc. by extracting only arguments that are quoted
    var message: string
    for str in args[1..^2].split(", "): 
        if str.startsWith("\""): 
            message &= str
    return message.replace("\"", "")