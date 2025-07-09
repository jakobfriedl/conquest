import prompt
import prologue
import tables, sequtils
import times
import terminal

#[
    Agent types & procs
]#
type 

    TaskCommand* = enum 
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
        command*: TaskCommand
        args*: string           # Json string containing all the positional arguments  
                                # Example: """{"command": "whoami", "arguments": "/all"}"""

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

# TODO: Take sleep value from agent registration data (set via nim.cfg file)
proc newAgent*(name, listener: string, firstCheckin: DateTime, postData: AgentRegistrationData): Agent = 
    var agent = new Agent
    agent.name = name 
    agent.listener = listener 
    agent.username = postData.username 
    agent.hostname = postData.hostname 
    agent.domain = postData.domain
    agent.process = postData.process
    agent.pid = postData.pid
    agent.ip = postData.ip 
    agent.os = postData.os
    agent.elevated = postData.elevated 
    agent.sleep = postData.sleep
    agent.jitter = 0.2
    agent.tasks = @[]
    agent.firstCheckin = firstCheckin
    agent.latestCheckin = firstCheckin

    return agent

#[
    Listener types and procs
]#
type 
    Protocol* = enum
        HTTP = "http"

    Listener* = ref object
        name*: string
        address*: string
        port*: int
        protocol*: Protocol

proc newListener*(name: string, address: string, port: int): Listener = 
    var listener = new Listener
    listener.name = name 
    listener.address = address 
    listener.port = port 
    listener.protocol = HTTP

    return listener

proc stringToProtocol*(protocol: string): Protocol = 
    case protocol
    of "http": 
        return HTTP
    else: discard


#[
    Conquest framework types & procs
]#
type 
    Conquest* = ref object
        prompt*: Prompt
        dbPath*: string
        listeners*: Table[string, Listener]
        agents*: Table[string, Agent]
        interactAgent*: Agent

proc add*(cq: Conquest, listener: Listener) = 
    cq.listeners[listener.name] = listener

proc add*(cq: Conquest, agent: Agent) = 
    cq.agents[agent.name] = agent

proc addMultiple*(cq: Conquest, agents: seq[Agent]) = 
    for a in agents: 
        cq.agents[a.name] = a

proc delListener*(cq: Conquest, listenerName: string) = 
    cq.listeners.del(listenerName)

proc delAgent*(cq: Conquest, agentName: string) = 
    cq.agents.del(agentName)

proc getAgentsAsSeq*(cq: Conquest): seq[Agent] = 
    var agents: seq[Agent] = @[]
    for agent in cq.agents.values:
        agents.add(agent)
    return agents

proc initConquest*(dbPath: string): Conquest = 
    var cq = new Conquest
    var prompt = Prompt.init()
    cq.prompt = prompt
    cq.dbPath = dbPath
    cq.listeners = initTable[string, Listener]()
    cq.agents = initTable[string, Agent]() 
    cq.interactAgent = nil 

    return cq

template writeLine*(cq: Conquest, args: varargs[untyped]) = 
    cq.prompt.writeLine(args)
proc readLine*(cq: Conquest): string =
    return cq.prompt.readLine()
template setIndicator*(cq: Conquest, indicator: string) = 
    cq.prompt.setIndicator(indicator)
template showPrompt*(cq: Conquest) = 
    cq.prompt.showPrompt()
template hidePrompt*(cq: Conquest) = 
    cq.prompt.hidePrompt()
template setStatusBar*(cq: Conquest, statusBar: seq[StatusBarItem]) = 
    cq.prompt.setStatusBar(statusBar) 
template clear*(cq: Conquest) = 
    cq.prompt.clear()

# Overwrite withOutput function to handle function arguments
proc withOutput*(cq: Conquest, outputFunction: proc(cq: Conquest, args: varargs[string]), args: varargs[string]) =
    cq.hidePrompt()
    outputFunction(cq, args)
    cq.showPrompt()
