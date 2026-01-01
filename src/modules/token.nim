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
