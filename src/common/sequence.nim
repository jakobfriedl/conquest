import tables
import ./utils
import ../types/[common, protocol]

var egressTable {.global.}: Table[uint32, uint32]   # Outgoing sequence numbers
var ingressTable {.global.}: Table[uint32, uint32]  # Incoming sequence numbers

proc nextSequence*(agentId: uint32): uint32 =
    egressTable[agentId] = egressTable.getOrDefault(agentId, 0'u32) + 1
    return egressTable[agentId]

proc validateSequence(agentId: uint32, seqNr: uint32, packetType: uint8): bool =
    # Heartbeat messages are not used for sequence tracking
    if cast[PacketType](packetType) == MSG_HEARTBEAT:
        return true

    let lastSeqNr = ingressTable.getOrDefault(agentId, 0'u32)

    # Accept seqNr = 1 to allow agents to reconnect after a server restart
    if seqNr == 1'u32:
        ingressTable[agentId] = seqNr
        return true

    # Reject out-of-order and replayed packets
    if seqNr <= lastSeqNr:
        return false

    ingressTable[agentId] = seqNr
    return true

proc validatePacket*(header: Header, expectedType: uint8) = 
    
    # Validate magic number
    if header.magic != MAGIC:
        raise newException(CatchableError, protect("Invalid magic bytes."))

    # Validate packet type
    if header.packetType != expectedType: 
        raise newException(CatchableError, protect("Invalid packet type."))

    # Validate sequence number 
    if not validateSequence(header.agentId, header.seqNr, header.packetType): 
        raise newException(CatchableError, protect("Invalid sequence number."))
