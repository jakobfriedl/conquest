import prompt
import tables
import times

# Task structure
type 
    CommandType* = enum 
        ExecuteShell = "shell"
        ExecuteBof = "bof"
        ExecuteAssembly = "dotnet"
        ExecutePe = "pe"
        Sleep = "sleep"
        GetWorkingDirectory = "pwd"
        SetWorkingDirectory = "cd"
        ListDirectory = "ls"
        RemoveFile = "rm"
        RemoveDirectory = "rmdir"
        Move = "move"
        Copy = "copy"

    ArgumentType* = enum 
        String = "string"
        Int = "int"
        Long = "long"
        Bool = "bool"
        Binary = "binary"

    Argument* = object 
        name*: string 
        description*: string 
        argumentType*: ArgumentType
        isRequired*: bool

    Command* = object 
        name*: string
        commandType*: CommandType
        description*: string 
        example*: string 
        arguments*: seq[Argument]
        dispatchMessage*: string

    TaskStatus* = enum 
        Completed = "completed"
        Created = "created"
        Pending = "pending"
        Failed = "failed"
        Cancelled = "cancelled"

    TaskResult* = ref object
        task*: string 
        agent*: string 
        data*: string
        status*: TaskStatus

    Task* = ref object 
        id*: string 
        agent*: string
        command*: CommandType
        args*: string           # Json string containing all the positional arguments  
                                # Example: """{"command": "whoami", "arguments": "/all"}"""

# Agent structure 
type 
    AgentRegistrationData* = object
        username*: string
        hostname*: string
        domain*: string
        ip*: string
        os*: string 
        process*: string
        pid*: int 
        elevated*: bool
        sleep*: int 

    Agent* = ref object 
        name*: string
        listener*: string 
        username*: string 
        hostname*: string
        domain*: string
        process*: string
        pid*: int
        ip*: string
        os*: string
        elevated*: bool 
        sleep*: int 
        jitter*: float 
        tasks*: seq[Task]
        firstCheckin*: DateTime
        latestCheckin*: DateTime

# Listener structure
type 
    Protocol* = enum
        HTTP = "http"

    Listener* = ref object
        name*: string
        address*: string
        port*: int
        protocol*: Protocol

# Server structure
type 
    Conquest* = ref object
        prompt*: Prompt
        dbPath*: string
        listeners*: Table[string, Listener]
        agents*: Table[string, Agent]
        interactAgent*: Agent