import times, strformat, strutils, terminal
import std/[dirs, paths]

import ../globals
import ../../common/types

proc makeAgentLogDirectory*(cq: Conquest, agentId: string): bool = 
    try: 
        createDir(cast[Path](fmt"{CONQUEST_ROOT}/data/logs/{agentId}"))
        return true 
    except OSError:
        return false 

proc log*(logEntry: string, agentId: string = "") = 
    # Write log entry to file 
    var logFile: string 
    if agentId.isEmptyOrWhitespace():
        logFile = fmt"{CONQUEST_ROOT}/data/logs/teamserver.log"
    else: 
        logFile = fmt"{CONQUEST_ROOT}/data/logs/{agentId}/session.log"
    let file = open(logFile, fmAppend)
    file.writeLine(logEntry)
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

proc getTimestamp*(): string = 
    return now().format("dd-MM-yyyy HH:mm:ss")

# Function templates and overwrites
template writeLine*(cq: Conquest, args: varargs[untyped] = "") = 
    stdout.styledWriteLine(args)

# Wrapper functions for logging/console output
template info*(cq: Conquest, args: varargs[untyped] = "") = 
    cq.writeLine(fgBlack, styleBright, fmt"[{getTimestamp()}]", $LOG_INFO, resetStyle, args)

template error*(cq: Conquest, args: varargs[untyped] = "") = 
    cq.writeLine(fgBlack, styleBright, fmt"[{getTimestamp()}]", fgRed, $LOG_ERROR, resetStyle, args)

template success*(cq: Conquest, args: varargs[untyped] = "") = 
    cq.writeLine(fgBlack, styleBright, fmt"[{getTimestamp()}]", fgGreen, $LOG_SUCCESS, resetStyle, args)

template warning*(cq: Conquest, args: varargs[untyped] = "") = 
    cq.writeLine(fgBlack, styleBright, fmt"[{getTimestamp()}]", fgYellow, styleDim, $LOG_WARNING, resetStyle, args)

template output*(cq: Conquest, args: varargs[untyped] = "") = 
    cq.writeLine(args)