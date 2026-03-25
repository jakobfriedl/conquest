import mummy, tables, tiny_sqlite
import ./[common, protocol] 

type 
    Agent* = ref object 
        agentId*: string
        listenerId*: string 
        username*: string 
        impersonationToken*: string
        hostname*: string
        domain*: string
        ipInternal*: string
        ipExternal*: string
        os*: string
        process*: string
        pid*: int
        elevated*: bool 
        sleep*: int 
        jitter*: int
        tasks*: seq[Task]
        modules*: uint32
        firstCheckin*: int64
        latestCheckin*: int64
        sessionKey*: Key
        links*: seq[string]

    Listener* = ref object
        server*: Server
        listenerId*: string
        case listenerType*: ListenerType
        of LISTENER_HTTP: 
            hosts*: string
            address*: string
            port*: int
        of LISTENER_SMB: 
            pipe*: string

    UIListener* = ref object
        listenerId*: string
        case listenerType*: ListenerType
        of LISTENER_HTTP: 
            hosts*: string
            address*: string
            port*: int
        of LISTENER_SMB: 
            pipe*: string

    WsConnection* = ref object
        clientId*: string 
        ws*: WebSocket
        sessionKey*: Key
        user*: string

    Download* = object 
        path*: string 
        total*: uint64 
        written*: uint64
        file*: File

# Team server context
type 
    Conquest* = ref object
        db*: DbConn
        listeners*: Table[string, Listener]
        threads*: Table[string, Thread[Listener]]
        agents*: Table[string, Agent]
        keyPair*: KeyPair
        profileString*: string
        profile*: Profile
        clients*: Table[string, WsConnection]
        downloads*: Table[string, Download]