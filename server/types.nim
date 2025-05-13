import prompt
import prologue
import tables

#[
    Agent
]#
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

    AgentRegistrationData* = object
        username*: string
        hostname*: string
        ip*: string
        os*: string 
        pid*: int 
        elevated*: bool

    Agent* = ref object 
        name*: string
        listener*: string 
        sleep*: int 
        jitter*: float 
        pid*: int
        username*: string 
        hostname*: string
        ip*: string
        os*: string
        elevated*: bool 
        tasks*: seq[Task]

proc newAgent*(name, listener, username, hostname, ip, os: string, pid: int, elevated: bool): Agent = 
    var agent = new Agent
    agent.name = name 
    agent.listener = listener 
    agent.pid = pid 
    agent.username = username 
    agent.hostname = hostname 
    agent.ip = ip 
    agent.os = os
    agent.elevated = elevated 
    agent.sleep = 10
    agent.jitter = 0.2
    agent.tasks = @[]

    return agent

proc newAgent*(name, listener: string, postData: AgentRegistrationData): Agent = 
    var agent = new Agent
    agent.name = name 
    agent.listener = listener 
    agent.pid = postData.pid
    agent.username = postData.username 
    agent.hostname = postData.hostname 
    agent.ip = postData.ip 
    agent.os = postData.os
    agent.elevated = postData.elevated 
    agent.sleep = 10
    agent.jitter = 0.2
    agent.tasks = @[]

    return agent


#[
    Listener 
]#
type 
    Protocol* = enum
        HTTP = "http"

    Listener* = ref object
        name*: string
        address*: string
        port*: int
        protocol*: Protocol
        sleep*: int 
        jitter*: float 

proc newListener*(name: string, address: string, port: int): Listener = 
    var listener = new Listener
    listener.name = name 
    listener.address = address 
    listener.port = port 
    listener.protocol = HTTP
    listener.sleep = 5          # 5 seconds beaconing 
    listener.jitter = 0.2       # 20% Jitter

    return listener

proc stringToProtocol*(protocol: string): Protocol = 
    case protocol
    of "http": 
        return HTTP
    else: discard


#[
    Conquest 
]#
type 
    Conquest* = ref object
        prompt*: Prompt
        dbPath*: string
        listeners*: Table[string, Listener]
        agents*: Table[string, Agent]

proc add*(cq: Conquest, listenerName: string, listener: Listener) = 
    cq.listeners[listenerName] = listener

proc add*(cq: Conquest, agentName: string, agent: Agent) = 
    cq.agents[agentName] = agent

proc delListener*(cq: Conquest, listenerName: string) = 
    cq.listeners.del(listenerName)

proc delAgent*(cq: Conquest, agentName: string) = 
    cq.agents.del(agentName)

proc initConquest*(): Conquest = 
    var cq = new Conquest
    var prompt = Prompt.init()
    cq.prompt = prompt
    cq.dbPath = "db/conquest.db"
    cq.listeners = initTable[string, Listener]()
    cq.agents = initTable[string, Agent]() 

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
