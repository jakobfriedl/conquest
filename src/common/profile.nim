import parsetoml, strutils, sequtils, random

import ./types

proc findKey(profile: Profile, path: string): TomlValueRef =
  let keys = path.split(".")
  let target = keys[keys.high]
  
  var current = profile
  for i in 0 ..< keys.high:
    let temp = current.getOrDefault(keys[i])
    if temp == nil:
      return nil
    current = temp
  
  return current.getOrDefault(target)

# Takes a specific "."-separated path as input and returns a default value if the key does not exits 
# Example: cq.profile.getString("http-get.agent.heartbeat.prefix", "not found") returns the string value of the 
#          prefix key, or "not found" if the target key or any sub-tables don't exist 
# '#' characters represent wildcard characters and are replaced with a random alphanumerical character

proc randomChar(): char = 
    let alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return alphabet[rand(alphabet.len - 1)]

proc getRandom*(values: seq[TomlValueRef]): TomlValueRef = 
    if values.len == 0: 
        return nil
    return values[rand(values.len - 1)]

proc getStringValue*(key: TomlValueRef, default: string = ""): string = 
    # In some cases, the profile can define multiple values for a key, e.g. for HTTP headers
    # A random entry is selected from these specifications
    var value: string = ""
    if key.kind == TomlValueKind.String: 
        value = key.getStr(default)
    elif key.kind == TomlValueKind.Array:
        value = key.getElems().getRandom().getStr(default)
    
    # Replace '#' with a random alphanumerical character and return the resulting string
    return value.mapIt(if it == '#': randomChar() else: it).join("")

proc getString*(profile: Profile, path: string, default: string = ""): string =  
    let key = profile.findKey(path)
    if key == nil:
        return default 
    return key.getStringValue(default)

proc getBool*(profile: Profile, path: string, default: bool = false): bool = 
    let key = profile.findKey(path)
    if key == nil: 
        return default 
    return key.getBool(default)

proc getInt*(profile: Profile, path: string, default = 0): int =  
    let key = profile.findKey(path)
    if key == nil: 
        return default 
    return key.getInt(default)

proc getTable*(profile: Profile, path: string): TomlTableRef = 
    let key = profile.findKey(path)
    if key == nil: 
        return new TomlTableRef
    return key.getTable()

proc getArray*(profile: Profile, path: string): seq[TomlValueRef] = 
    let key = profile.findKey(path)
    if key == nil: 
        return @[]
    return key.getElems() 
