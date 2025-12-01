import ../../../common/types

# Only required for SMB agents
proc createPipe*(ctx: AgentCtx) = 
    discard 

proc link*() = 
    discard 

proc unlink*() = 
    discard 

# Required for all agent types
proc smbWrite*(ctx: AgentCtx, data: seq[byte]): bool = 

    # Check if a pipe is already created, if not: create one
    ctx.createPipe() 

    discard 

proc smbRead*(ctx: AgentCtx): string = 
    discard 