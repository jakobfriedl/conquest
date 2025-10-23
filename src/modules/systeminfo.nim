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
    import os, strutils, sequtils, strformat, tables, algorithm
    import ../agent/utils/io
    import ../agent/protocol/result
    import ../common/utils

    # TODO: Add user context to process information
    type 
        ProcessInfo = object 
            pid: DWORD
            ppid: DWORD 
            name: string 
            children: seq[DWORD]

    proc executePs(ctx: AgentCtx, task: Task): TaskResult = 
        
        print "   [>] Listing running processes."
        
        try: 
            var processes: seq[DWORD] = @[]
            var procMap = initTable[DWORD, ProcessInfo]()
            var output: string = ""

            # Take a snapshot of running processes
            let hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
            if hSnapshot == INVALID_HANDLE_VALUE: 
                raise newException(CatchableError, GetLastError().getError)
            
            # Close handle after object is no longer used
            defer: CloseHandle(hSnapshot)

            var pe32: PROCESSENTRY32
            pe32.dwSize = DWORD(sizeof(PROCESSENTRY32))

            # Loop over processes to fill the map            
            if Process32First(hSnapshot, addr pe32) == FALSE:
                raise newException(CatchableError, GetLastError().getError)
            
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

            # Add header row
            let headers = @[protect("PID"), protect("PPID"), protect("Process")]
            output &= fmt"{headers[0]:<10}{headers[1]:<10}{headers[2]:<25}" & "\n"
            output &= "-".repeat(len(headers[0])).alignLeft(10) & "-".repeat(len(headers[1])).alignLeft(10) & "-".repeat(len(headers[2])).alignLeft(25) & "\n"

            # Format and print process
            proc printProcess(pid: DWORD, indentSpaces: int = 0) = 
                if not procMap.contains(pid): 
                    return
                
                var process = procMap[pid]
                let indent = " ".repeat(indentSpaces) 

                output &= fmt"{process.pid:<10}{process.ppid:<10}{indent}{process.name:<25}" & "\n"

                # Recursively print child processes with indentation
                process.children.sort()
                for childPid in process.children:
                    printProcess(childPid, indentSpaces + 2)

            # Iterate over root processes
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