import times, strformat, strutils, prompt, terminal
import std/[dirs, paths]

import ../globals
import ../../common/types

proc makeAgentLogDirectory*(cq: Conquest, agentId: string): bool = 
    try: 
        createDir(cast[Path](fmt"{CONQUEST_ROOT}/data/logs/{agentId}"))
        return true 
    except OSError:
        return false 

proc log*(cq: Conquest, logEntry: string) = 
    # TODO: Fix issue where log files are written to the wrong agent when the interact agent is changed in the middle of command execution
    # Though that problem would not occur when a proper GUI is used in the future
    let agentLogPath = fmt"{CONQUEST_ROOT}/data/logs/{cq.interactAgent.agentId}/session.log"

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

proc getTimestamp*(): string = 
    return now().format("dd-MM-yyyy HH:mm:ss")

# Function templates and overwrites
template writeLine*(cq: Conquest, args: varargs[untyped] = "") = 
    cq.prompt.writeLine(args)
    if cq.interactAgent != nil: 
        cq.log(extractStrings($(args)))

# Wrapper functions for logging/console output
template info*(cq: Conquest, args: varargs[untyped] = "") = 
    cq.writeLine(fgBlack, styleBright, fmt"[{getTimestamp()}]", $LOG_INFO, resetStyle, args)

template error*(cq: Conquest, args: varargs[untyped] = "") = 
    cq.writeLine(fgBlack, styleBright, fmt"[{getTimestamp()}]", fgRed, $LOG_ERROR, resetStyle, args)

template success*(cq: Conquest, args: varargs[untyped] = "") = 
    cq.writeLine(fgBlack, styleBright, fmt"[{getTimestamp()}]", fgGreen, $LOG_SUCCESS, resetStyle, args)

template warning*(cq: Conquest, args: varargs[untyped] = "") = 
    cq.writeLine(fgBlack, styleBright, fmt"[{getTimestamp()}]", fgYellow, styleDim, $LOG_WARNING, resetStyle, args)

template input*(cq: Conquest, args: varargs[untyped] = "") = 
    if cq.interactAgent != nil: 
        cq.writeLine(fgBlue, styleBright, fmt"[{getTimestamp()}] ", fgYellow, fmt"[{cq.interactAgent.agentId}] ", resetStyle, args)
    else: 
        cq.writeLine(fgBlue, styleBright, fmt"[{getTimestamp()}] ", resetStyle, args)

template output*(cq: Conquest, args: varargs[untyped] = "") = 
    cq.writeLine(args)