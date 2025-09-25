import mummy
import times, tables, json
import ./send
import ../globals
import ../core/[task, listener]
import ../../common/[types, utils, serialize, event]

#[
    Client -> Server
]#
# proc getMessageType*(message: Message): EventType = 
#     var unpacker = Unpacker.init(message.data)
#     return cast[EventType](unpacker.getUint8()) 

# proc receiveStartListener*(message: Message) = 
#     var unpacker = Unpacker.init(message.data)

#     discard unpacker.getUint8() 
#     let 
#         listenerId = Uuid.toString(unpacker.getUint32())
#         address = unpacker.getDataWithLengthPrefix()
#         port = int(unpacker.getUint16())
#         protocol = cast[Protocol](unpacker.getUint8())
#     cq.listenerStart(listenerId, address, port, protocol)

# proc receiveStopListener*(message: Message) = 
#     var unpacker = Unpacker.init(message.data)

#     discard unpacker.getUint8() 
#     let listenerId = Uuid.toString(unpacker.getUint32())
#     cq.listenerStop(listenerId)

# proc receiveAgentCommand*(message: Message) = 
#     var unpacker = Unpacker.init(message.data)

#     discard unpacker.getUint8() 
#     let 
#         agentId = Uuid.toString(unpacker.getUint32())
#         command = unpacker.getDataWithLengthPrefix() 
    
