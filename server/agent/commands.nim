import argparse, times, strformat, terminal
import ../[types]

#[
    Agnet Argument parsing
]# 
var parser = newParser: 
    help("Conquest Command & Control")

    command("shell"):
        help("Execute a shell command.")

    command("help"):
        nohelpflag()

    command("exit"):
        nohelpflag()

proc handleAgentCommand*(cq: Conquest, args: varargs[string]) = 

    # Return if no command (or just whitespace) is entered
    if args[0].replace(" ", "").len == 0: return

    let date: string = now().format("dd-MM-yyyy HH:mm:ss")
    cq.writeLine(fgCyan, fmt"[{date}] ", fgYellow, fmt"[{cq.interactAgent.name}] ", resetStyle, styleBright, args[0])

    try:
        let opts = parser.parse(args[0].split(" ").filterIt(it.len > 0))

        case opts.command
        
        of "exit": # Exit program 
            discard

        of "help": # Display help menu
            cq.writeLine(parser.help())

    # Handle help flag
    except ShortCircuit as err:
        if err.flag == "argparse_help":
            cq.writeLine(err.help)
    
    # Handle invalid arguments
    except UsageError: 
        cq.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg())

    cq.writeLine("")