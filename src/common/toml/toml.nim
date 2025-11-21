import random, strutils

# Wrapper for the toml-c library
# Original: github.com/arp242/toml-c/ 

{.compile: "toml.c".}

type
    TomlKeyVal = object
        key: cstring
        keylen: cint
        val: cstring

    TomlArrItem = object
        valtype: cint
        val: cstring
        arr: ptr TomlArray
        tbl: ptr TomlTable

    TomlTable = object
        key: cstring
        keylen: cint
        implicit: bool
        readonly: bool
        nkval: cint
        kval: ptr ptr TomlKeyVal
        narr: cint
        arr: ptr ptr TomlArray
        ntbl: cint
        tbl: ptr ptr TomlTable

    TomlArray = object
        key: cstring
        keylen: cint
        kind: cint
        `type`: cint
        nitem: cint
        item: ptr TomlArrItem

    TomlValue = object
        case ok: bool 
        of false: discard
        of true:
            s: cstring
            sl: cint

    TomlTableRef* = ptr TomlTable

    TomlValueKind* = enum
        String, Int, Bool, Float, Table, Array, None
    
    TomlValueRef* = ref object
        case kind*: TomlValueKind
        of String: 
            strVal*: string
        of Int: 
            intVal*: int64
        of Bool: 
            boolVal*: bool
        of Float:
            floatVal*: float64
        of Table: 
            tableVal*: TomlTableRef
        of Array: 
            arrayVal*: ptr TomlArray
        of None: 
            discard

# C library functions
proc toml_parse(toml: cstring, errbuf: cstring, errbufsz: cint): TomlTableRef {.importc, cdecl.}
proc toml_parse_file(fp: File, errbuf: cstring, errbufsz: cint): TomlTableRef {.importc, cdecl.}
proc toml_free(tab: TomlTableRef) {.importc, cdecl.}
proc toml_table_len(tab: TomlTableRef): cint {.importc, cdecl.}
proc toml_table_key(tab: TomlTableRef, keyidx: cint, keylen: ptr cint): cstring {.importc, cdecl.}
proc toml_table_string(tab: TomlTableRef, key: cstring): TomlValue {.importc, cdecl.}
proc toml_table_int(tab: TomlTableRef, key: cstring): TomlValue {.importc, cdecl.}
proc toml_table_bool(tab: TomlTableRef, key: cstring): TomlValue {.importc, cdecl.}
proc toml_table_double(tab: TomlTableRef, key: cstring): TomlValue {.importc, cdecl.}
proc toml_table_array(tab: TomlTableRef, key: cstring): ptr TomlArray {.importc, cdecl.}
proc toml_table_table(tab: TomlTableRef, key: cstring): TomlTableRef {.importc, cdecl.}
proc toml_array_len(arr: ptr TomlArray): cint {.importc, cdecl.}
proc toml_array_table(arr: ptr TomlArray, idx: cint): TomlTableRef {.importc, cdecl.}
proc toml_array_string(arr: ptr TomlArray, idx: cint): TomlValue {.importc, cdecl.}
proc toml_array_int(arr: ptr TomlArray, idx: cint): TomlValue {.importc, cdecl.}

#[ 
    Retrieve a random element from a TOML array
]#
proc getRandom*(arr: ptr TomlArray): TomlValueRef = 
    if arr.isNil:
        return nil
    
    let n = toml_array_len(arr)
    if n == 0:
        return nil
    
    let idx = rand(n.int - 1)
    
    # String
    let strVal {.volatile.} = toml_array_string(arr, idx.cint)
    if strVal.ok:
        let strPtr = cast[ptr cstring](cast[int](addr strVal) + 8)[]
        if not strPtr.isNil:
            return TomlValueRef(kind: String, strVal: $strPtr)
    
    # Table
    let table {.volatile.} = toml_array_table(arr, idx.cint)
    if not table.isNil:
        return TomlValueRef(kind: Table, tableVal: table)
    
    # Int
    let intVal {.volatile.} = toml_array_int(arr, idx.cint)
    if intVal.ok:
        let intPtr = cast[ptr int64](cast[int](addr intVal) + 8)[]
        return TomlValueRef(kind: Int, intVal: intPtr)
    
    return nil

#[
    Parse TOML string or configuration file
]#
proc parseString*(toml: string): TomlTableRef = 
    var errbuf: array[200, char]
    
    var tomlCopy = toml    
    result = toml_parse(tomlCopy.cstring, cast[cstring](addr errbuf[0]), 200)
    
    if result.isNil:
        raise newException(ValueError, "TOML parse error: " & $cast[cstring](addr errbuf[0]))

proc parseFile*(path: string): TomlTableRef =
    var errbuf: array[200, char]
    let fp = open(path, fmRead)
    if fp.isNil:
        raise newException(IOError, "Cannot open file: " & path)
    
    result = toml_parse_file(fp, cast[cstring](addr errbuf[0]), 200)
    fp.close()
    
    if result.isNil:
        raise newException(ValueError, "TOML parse error: " & $cast[cstring](addr errbuf[0]))

proc free*(table: TomlTableRef) =
    if not table.isNil:
        toml_free(table)

#[
    Takes a specific "."-separated path as input and returns the TOML Value that it finds
]#
proc findKey*(profile: TomlTableRef, path: string): TomlValueRef =
    if profile.isNil:
        return TomlValueRef(kind: None)
    
    let keys = path.split(".")
    var current = profile
    
    # Navigate through nested tables
    for i in 0 ..< keys.len - 1:
        let nextTable = toml_table_table(current, keys[i].cstring)
        if nextTable.isNil:
            return TomlValueRef(kind: None)
        current = nextTable
    
    let finalKey = keys[^1].cstring
    
    # Try different types
    # {.volatile.} is added to avoid dangling pointers
    block findStr:
        let val {.volatile.} = toml_table_string(current, finalKey)
        if val.ok:
            let strPtr = cast[ptr cstring](cast[int](addr val) + 8)[]
            if not strPtr.isNil:
                return TomlValueRef(kind: String, strVal: $strPtr)
    
    block checkInt:
        let val {.volatile.} = toml_table_int(current, finalKey)
        if val.ok:
            let intPtr = cast[ptr int64](cast[int](addr val) + 8)[]
            return TomlValueRef(kind: Int, intVal: intPtr)
    
    block checkBool:
        let val {.volatile.} = toml_table_bool(current, finalKey)
        if val.ok:
            let boolPtr = cast[ptr bool](cast[int](addr val) + 8)[]
            return TomlValueRef(kind: Bool, boolVal: boolPtr)
    
    block checkDouble:
        let val {.volatile.} = toml_table_double(current, finalKey)
        if val.ok:
            let dblPtr = cast[ptr float64](cast[int](addr val) + 8)[]
            return TomlValueRef(kind: Float, floatVal: dblPtr)
    
    block checkArray:
        let arr {.volatile.} = toml_table_array(current, finalKey)
        if not arr.isNil:
            return TomlValueRef(kind: Array, arrayVal: arr)
    
    block checkTable:
        let table {.volatile.} = toml_table_table(current, finalKey)
        if not table.isNil:
            return TomlValueRef(kind: Table, tableVal: table)
    
    return TomlValueRef(kind: None)

#[
    Retrieve the actual value from a TOML value
]#
proc getStr*(value: TomlValueRef, default: string = ""): string =
    if value.kind == String:
        return value.strVal
    return default

proc getInt*(value: TomlValueRef, default: int = 0): int =
    if value.kind == Int:
        return value.intVal.int
    return default

proc getBool*(value: TomlValueRef, default: bool = false): bool =
    if value.kind == Bool:
        return value.boolVal
    return default

proc getTable*(value: TomlValueRef): TomlTableRef =
    if value.kind == Table:
        return value.tableVal
    return nil

proc getElems*(value: TomlValueRef): seq[TomlValueRef] =
    if value.kind != Array:
        return @[]
    
    let arr = value.arrayVal
    let n = toml_array_len(arr)
    result = @[]
    
    for i in 0 ..< n:
        # Try table first
        let table {.volatile.} = toml_array_table(arr, i.cint)
        if not table.isNil:
            result.add(TomlValueRef(kind: Table, tableVal: table))
            continue
        
        # Try string
        let strVal = toml_array_string(arr, i.cint)
        if strVal.ok:
            let strPtr {.volatile.} = cast[ptr cstring](cast[int](addr strVal) + 8)[]
            if not strPtr.isNil:
                result.add(TomlValueRef(kind: String, strVal: $strPtr))
                continue
        
        # Try int
        let intVal = toml_array_int(arr, i.cint)
        if intVal.ok:
            let intPtr {.volatile.} = cast[ptr int64](cast[int](addr intVal) + 8)[]
            result.add(TomlValueRef(kind: Int, intVal: intPtr))
    
proc getTableKeys*(profile: TomlTableRef, path: string): seq[tuple[key: string, value: TomlValueRef]] =
    result = @[]
    let key = profile.findKey(path)
    let table = key.getTable()
    if table.isNil:
        return
    
    let numKeys = toml_table_len(table)
    for i in 0 ..< numKeys:
        var keylen: cint
        let keyPtr = toml_table_key(table, i.cint, addr keylen)
        if keyPtr.isNil:
            continue
        
        let key = $keyPtr
        let value = profile.findKey(path & "." & key)
        if value.kind != None:
            result.add((key: key, value: value))

proc getTableValue*(table: TomlTableRef, key: string): TomlValueRef =
    if table.isNil:
        return TomlValueRef(kind: None)
    
    let ckey = key.cstring
    
    block checkString:
        let val {.volatile.} = toml_table_string(table, ckey)
        if val.ok:
            let strPtr = cast[ptr cstring](cast[int](addr val) + 8)[]
            if not strPtr.isNil:
                return TomlValueRef(kind: String, strVal: $strPtr)
    
    block checkInt:
        let val {.volatile.} = toml_table_int(table, ckey)
        if val.ok:
            let intPtr = cast[ptr int64](cast[int](addr val) + 8)[]
            return TomlValueRef(kind: Int, intVal: intPtr)
    
    block checkBool:
        let val {.volatile.} = toml_table_bool(table, ckey)
        if val.ok:
            let boolPtr = cast[ptr bool](cast[int](addr val) + 8)[]
            return TomlValueRef(kind: Bool, boolVal: boolPtr)
    
    return TomlValueRef(kind: None)
