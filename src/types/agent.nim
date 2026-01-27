import winim/lean
import tables
import ./common 

type 
    ProcessInfo* = object 
        pid*: uint32
        ppid*: uint32 
        name*: string 
        user*: string
        session*: uint32

    DirectoryEntry* = object 
        name*: string 
        flags*: uint8
        size*: uint64
        lastWriteTime*: int64
        isLoaded*: bool

    TransportSettings* = ref object 
        listenerId*: string
        when defined(TRANSPORT_HTTP): 
            hosts*: string
        when defined(TRANSPORT_SMB): 
            pipe*: string 
            hPipe*: HANDLE

# Agent context
type 
    AgentCtx* = ref object
        agentId*: string
        transport*: TransportSettings
        sleepSettings*: SleepSettings
        killDate*: int64
        sessionKey*: Key
        agentPublicKey*: Key
        profile*: Profile
        registered*: bool
        links*: Table[uint32, uint32]