import tables 
import ./[types, utils]

var sequenceTable {.global.}: Table[uint32, uint64]

proc nextSequence*(agentId: uint32): uint64 = 
    sequenceTable[agentId] = sequenceTable.getOrDefault(agentId, 0'u64) + 1
    return sequenceTable[agentId]

proc validateSequence*(agentId: uint32, seqNr: uint64, packetType: uint8): bool = 
    let lastSeqNr = sequenceTable.getOrDefault(agentId, 0'u64)

    # Heartbeat messages are not used for sequence tracking
    if cast[PacketType](packetType) == MSG_HEARTBEAT: 
        return true

    # In order to keep agents running after server restart, accept all connection with seqNr = 1, to update the table
    if seqNr == 1'u64:
        sequenceTable[agentId] = seqNr
        return true

    # Validate that the sequence number of the current packet is higher than the currently stored one 
    if seqNr <= lastSeqNr: 
        return false 

    # Update sequence number
    sequenceTable[agentId] = seqNr
    return true
