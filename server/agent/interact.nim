import argparse, times, strformat, terminal, nanoid
import ../[types]
import ./commands

#[
    Agent Argument parsing
]# 
var parser = newParser: 
    help("Conquest Command & Control")

    command("shell"):
        help("Execute a shell command and retrieve the output.")
        arg("command", help="Command", nargs = 1)
        arg("arguments", help="Arguments.", nargs = -1) # Handle 0 or more command-line arguments (seq[string])

    command("sleep"): 
        help("Update sleep delay configuration.")
        arg("delay", help="Delay in seconds.", nargs = 1)

    command("help"):
        nohelpflag()

    command("back"):
        nohelpflag()

proc handleAgentCommand*(cq: Conquest, args: varargs[string]) = 

    # Return if no command (or just whitespace) is entered
    if args[0].replace(" ", "").len == 0: return

    let date: string = now().format("dd-MM-yyyy HH:mm:ss")
    cq.writeLine(fgBlue, styleBright, fmt"[{date}] ", fgYellow, fmt"[{cq.interactAgent.name}] ", resetStyle, styleBright, args[0])

    try:
        let opts = parser.parse(args[0].split(" ").filterIt(it.len > 0))

        case opts.command
    
        of "back": # Return to management mode
            discard

        of "help": # Display help menu
            cq.writeLine(parser.help())

        of "shell":
            var 
                command: string = opts.shell.get.command 
                arguments: seq[string] = opts.shell.get.arguments
            arguments.insert(command, 0)
            cq.taskExecuteShell(arguments)

        of "sleep": 
            cq.taskExecuteSleep(parseInt(opts.sleep.get.delay))

    # Handle help flag
    except ShortCircuit as err:
        if err.flag == "argparse_help":
            cq.writeLine(err.help)
    
    # Handle invalid arguments
    except CatchableError: 
        cq.writeLine(fgRed, styleBright, "[-] ", getCurrentExceptionMsg(), "\n")

