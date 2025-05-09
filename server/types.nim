import prompt
import prologue

#[
    Console 
]#
type 
    Console* = ref object
        prompt*: Prompt
        listeners*: int
        agents*: int
        dbPath*: string
        activeListeners*: seq[Prologue]

    Command* = object
        cmd*: string
        execute*: proc(console: Console, args: varargs[string])

proc newConsole*(): Console = 
    var console = new Console
    var prompt = Prompt.init()
    console.prompt = prompt
    console.dbPath = "db/conquest.db"
    console.listeners = 0
    console.agents = 0
    console.activeListeners = @[]

    return console

template writeLine*(console: Console, args: varargs[untyped]) = 
    console.prompt.writeLine(args)
proc readLine*(console: Console): string =
    return console.prompt.readLine()
template setIndicator*(console: Console, indicator: string) = 
    console.prompt.setIndicator(indicator)
template showPrompt*(console: Console) = 
    console.prompt.showPrompt()
template hidePrompt*(console: Console) = 
    console.prompt.hidePrompt()
template setStatusBar*(console: Console, statusBar: seq[StatusBarItem]) = 
    console.prompt.setStatusBar(statusBar) 
template clear*(console: Console) = 
    console.prompt.clear()

# Overwrite withOutput function to handle function arguments
proc withOutput*(console: Console, outputFunction: proc(console: Console, args: varargs[string]), args: varargs[string]) =
    console.hidePrompt()
    outputFunction(console, args)
    console.showPrompt()

#[
    Agent
]#
type 
    Agent* = ref object 
        name*: string

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