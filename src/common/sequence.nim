import tables 
import ./[types, utils]

var sequenceTable {.global.}: Table[uint32, uint32]

proc nextSequence*(agentId: uint32): uint32 = 
    sequenceTable[agentId] = sequenceTable.getOrDefault(agentId, 0'u32) + 1
    return sequenceTable[agentId]

proc validateSequence(agentId: uint32, seqNr: uint32, packetType: uint8): bool = 
    let lastSeqNr = sequenceTable.getOrDefault(agentId, 0'u32)

    # Heartbeat messages are not used for sequence tracking
    if cast[PacketType](packetType) == MSG_HEARTBEAT: 
        return true

    # In order to keep agents running after server restart, accept all connection with seqNr = 1, to update the table
    if seqNr == 1'u32:
        sequenceTable[agentId] = seqNr
        return true

    # Validate that the sequence number of the current packet is higher than the currently stored one 
    if seqNr < lastSeqNr: 
        return false 

    # Update sequence number
    sequenceTable[agentId] = seqNr
    return true

proc validatePacket*(header: Header, expectedType: uint8) = 
    
    # Validate magic number
    if header.magic != MAGIC:
        raise newException(CatchableError, protect("Invalid magic bytes."))

    # Validate packet type
    if header.packetType != expectedType: 
        raise newException(CatchableError, protect("Invalid packet type."))

    # Validate sequence number 
    # if not validateSequence(header.agentId, header.seqNr, header.packetType): 
        # raise newException(CatchableError, protect("Invalid sequence number."))
