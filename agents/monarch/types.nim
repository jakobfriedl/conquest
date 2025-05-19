import winim 

type
    TaskCommand* = enum 
        ExecuteShell = "shell"
        ExecuteBof = "bof"
        ExecuteAssembly = "dotnet"
        ExecutePe = "pe"

    TaskStatus* = enum 
        Created = "created"
        Completed = "completed"
        Pending = "pending"
        Failed = "failed"
        Cancelled = "cancelled"

    TaskResult* = string 

    Task* = ref object 
        id*: int 
        agent*: string
        command*: TaskCommand
        args*: seq[string]
        result*: TaskResult
        status*: TaskStatus  
