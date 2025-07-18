import streams, strutils
import ./types

type 
    Packer* = ref object 
        headerStream: StringStream
        payloadStream: StringStream 

proc initTaskPacker*(): Packer = 
    result = new Packer 
    result.headerStream = newStringStream()
    result.payloadStream = newStringStream() 

proc addToHeader*[T: uint8 | uint16 | uint32 | uint64](packer: Packer, value: T): Packer {.discardable.} =
    packer.headerStream.write(value)
    return packer 

proc addToPayload*[T: uint8 | uint16 | uint32 | uint64](packer: Packer, value: T): Packer {.discardable.} =
    packer.payloadStream.write(value)
    return packer 

proc addDataToHeader*(packer: Packer, data: openArray[byte]): Packer {.discardable.} = 
    packer.headerStream.writeData(data[0].unsafeAddr, data.len)
    return packer

proc addDataToPayload*(packer: Packer, data: openArray[byte]): Packer {.discardable.} = 
    packer.payloadStream.writeData(data[0].unsafeAddr, data.len)
    return packer

proc addArgument*(packer: Packer, arg: TaskArg): Packer {.discardable.} = 
    
    if arg.data.len <= 0: 
        # Optional argument was passed as "", ignore
        return

    packer.addToPayload(arg.argType)

    case arg.argType: 
    of cast[uint8](STRING), cast[uint8](BINARY): 
        # Add length for variable-length data types
        packer.addToPayload(cast[uint32](arg.data.len)) 
        packer.addDataToPayload(arg.data)
    else: 
        packer.addDataToPayload(arg.data)
    return packer

proc packPayload*(packer: Packer): seq[byte] = 
    packer.payloadStream.setPosition(0) 
    let data = packer.payloadStream.readAll() 
    
    result = newSeq[byte](data.len)
    for i, c in data:
        result[i] = byte(c.ord)
    
    packer.payloadStream.setPosition(0) 

proc packHeader*(packer: Packer): seq[byte] = 
    packer.headerStream.setPosition(0) 
    let data = packer.headerStream.readAll() 
    
    # Convert string to seq[byte]
    result = newSeq[byte](data.len)
    for i, c in data:
        result[i] = byte(c.ord)
    
    packer.headerStream.setPosition(0) 