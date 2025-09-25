import whisky 
import times, tables
import ../views/[sessions, listeners, console, eventlog]
import ../../common/[types, utils, event]
export recvEvent

#[ 
    Server -> Client 
]#




# proc getMessageType*(message: Message): EventType = 
#     var unpacker = Unpacker.init(message.data)
#     return cast[EventType](unpacker.getUint8()) 

# proc receiveAgentPayload*(message: Message): seq[byte] = 
#     var unpacker = Unpacker.init(message.data)
    
#     discard unpacker.getUint8() 
#     return string.toBytes(unpacker.getDataWithLengthPrefix())

# proc receiveAgentConnection*(message: Message, sessions: ptr SessionsTableComponent) = 
#     var unpacker = Unpacker.init(message.data)

#     discard unpacker.getUint8() 
#     let agent = Agent(
#         agentId: Uuid.toString(unpacker.getUint32()),
#         listenerId: Uuid.toString(unpacker.getUint32()),
#         username: unpacker.getDataWithLengthPrefix(), 
#         hostname: unpacker.getDataWithLengthPrefix(),
#         domain: unpacker.getDataWithLengthPrefix(),
#         ip: unpacker.getDataWithLengthPrefix(),
#         os: unpacker.getDataWithLengthPrefix(),
#         process: unpacker.getDataWithLengthPrefix(),
#         pid: int(unpacker.getUint32()),
#         elevated: unpacker.getUint8() != 0,
#         sleep: int(unpacker.getUint32()),
#         tasks: @[],  
#         firstCheckin: cast[int64](unpacker.getUint32()).fromUnix().utc(),
#         latestCheckin: cast[int64](unpacker.getUint32()).fromUnix().utc(),
#     )

#     sessions.agents.add(agent)

# proc receiveAgentCheckin*(message: Message, sessions: ptr SessionsTableComponent)= 
#     var unpacker = Unpacker.init(message.data)

#     discard unpacker.getUint8() 
#     let agentId = Uuid.toString(unpacker.getUint32())
#     let timestamp = cast[int64](unpacker.getUint32())

#     # TODO: Update checkin 

# proc receiveConsoleItem*(message: Message, consoles: ptr Table[string, ConsoleComponent]) = 
#     var unpacker = Unpacker.init(message.data)

#     discard unpacker.getUint8() 
#     let 
#         agentId = Uuid.toString(unpacker.getUint32())
#         logType = cast[LogType](unpacker.getUint8())
#         timestamp = cast[int64](unpacker.getUint32())
#         message = unpacker.getDataWithLengthPrefix()

#     consoles[][agentId].addItem(logType, message, timestamp)

# proc receiveEventlogItem*(message: Message, eventlog: ptr EventlogComponent) = 
#     var unpacker = Unpacker.init(message.data)

#     discard unpacker.getUint8() 
#     let 
#         logType = cast[LogType](unpacker.getUint8())
#         timestamp = cast[int64](unpacker.getUint32())
#         message = unpacker.getDataWithLengthPrefix()
    
#     eventlog[].addItem(logType, message, timestamp)