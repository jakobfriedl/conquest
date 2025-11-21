import strutils, sequtils, random, base64, algorithm
import ./[types, utils]
import ./toml/toml
export parseFile, parseString, free, getTableKeys, getRandom

# Takes a specific "."-separated path as input and returns a default value if the key does not exits 
# Example: cq.profile.getString("http-get.agent.heartbeat.prefix", "not found") returns the string value of the 
#          prefix key, or "not found" if the target key or any sub-tables don't exist 
# '#' characters represent wildcard characters and are replaced with a random alphanumerical character (a-zA-Z0-9)
# '$' characters are replaced with a random number (0-9)

#[
    Helper functions
]#
proc randomChar(): char = 
    let alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return alphabet[rand(alphabet.len - 1)]

proc randomNumber(): char = 
    let numbers = "0123456789"
    return numbers[rand(numbers.len - 1)]

proc getRandom*(values: seq[TomlValueRef]): TomlValueRef = 
    if values.len == 0: 
        return nil
    return values[rand(values.len - 1)]

#[
    Wrapper functions
]# 
proc getStringValue*(key: TomlValueRef, default: string = ""): string = 
    if key.isNil or key.kind == None:
        return default
    
    var value: string = ""
    if key.kind == String: 
        value = key.strVal
    elif key.kind == Array:
        let randomElem = getRandom(key.arrayVal)
        if randomElem != nil and randomElem.kind == String:
            value = randomElem.strVal
    
    # Replace '#' with random alphanumerical character
    return value.mapIt(if it == '#': randomChar() elif it == '$': randomNumber() else: it).join("")

proc getString*(profile: Profile, path: string, default: string = ""): string =
    let key = profile.findKey(path)
    return key.getStringValue(default)

proc getInt*(profile: Profile, path: string, default: int = 0): int =
    let key = profile.findKey(path)
    return key.getInt(default)

proc getBool*(profile: Profile, path: string, default: bool = false): bool =
    let key = profile.findKey(path)
    return key.getBool(default)

proc getTable*(profile: Profile, path: string): TomlTableRef =
    let key = profile.findKey(path)
    return key.getTable()

proc getArray*(profile: Profile, path: string): seq[TomlValueRef] = 
    let key = profile.findKey(path)
    if key.kind != Array: 
        return @[]
    return key.getElems()

proc isArray*(profile: Profile, path: string): bool = 
    let key = profile.findKey(path)
    return key.kind == Array

#[
    Data transformation
]#
proc applyDataTransformation*(profile: Profile, path: string, data: seq[byte]): string = 
    # 1. Encoding 
    var steps: seq[TomlTableRef] = @[]

    # Apply all encoding techniques in the order specified in the profile    
    if profile.isArray(path & protect(".encoding")):
        for encoding in profile.getArray(path & protect(".encoding")): 
            steps.add(encoding.getTable())
    else: 
        steps = @[profile.getTable(path & protect(".encoding"))]

    var dataString: string = Bytes.toString(data) 
    for step in steps: 
        case step.getTableValue(protect("type")).getStr(default = "none")
        of protect("base64"):
            dataString = encode(dataString, safe = step.getTableValue(protect("url-safe")).getBool()).replace("=", "")
        of protect("hex"):
            dataString = dataString.toHex().toLowerAscii() 
        of protect("rot"):
            dataString = Bytes.toString(encodeRot(string.toBytes(dataString), step.getTableValue(protect("key")).getInt(default = 13)))
        of protect("xor"):
            dataString = Bytes.toString(xorBytes(string.toBytes(dataString), step.getTableValue(protect("key")).getInt(default = 1)))
        of protect("none"): 
            discard

    # 2. Add prefix & suffix
    let prefix = profile.getString(path & protect(".prefix"))
    let suffix = profile.getString(path & protect(".suffix"))
    
    return prefix & dataString & suffix

proc reverseDataTransformation*(profile: Profile, path: string, data: string): seq[byte] = 
    # 1. Remove prefix & suffix
    let 
        prefix = profile.getString(path & protect(".prefix"))
        suffix = profile.getString(path & protect(".suffix"))
    var dataString = data[len(prefix) ..^ len(suffix) + 1]

    # 2. Decoding
    var steps: seq[TomlTableRef] = @[]

    # Apply all encoding techniques in reverse order    
    if profile.isArray(path & protect(".encoding")):
        for encoding in profile.getArray(path & protect(".encoding")): 
            steps.add(encoding.getTable())
    else: 
        steps = @[profile.getTable(path & protect(".encoding"))]

    for step in steps.reversed():
        case step.getTableValue(protect("type")).getStr(default = "none")
        of protect("base64"):
            dataString = decode(dataString)
        of protect("hex"):
            dataString = parseHexStr(dataString)
        of protect("rot"):
            dataString = Bytes.toString(decodeRot(string.toBytes(dataString), step.getTableValue(protect("key")).getInt(default = 13)))
        of protect("xor"):
            dataString = Bytes.toString(xorBytes(string.toBytes(dataString), step.getTableValue(protect("key")).getInt(default = 1)))
        of protect("none"): 
            discard

    return string.toBytes(dataString)