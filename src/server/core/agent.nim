import terminal, strformat, strutils, tables, times, system, parsetoml

import ../utils
import ../core/logger
import ../db/database
import ../../common/types
import ../websocket

# Terminate agent and remove it from the database
proc agentKill*(cq: Conquest, name: string) =

    # Check if agent supplied via -n parameter exists in database
    if not cq.dbAgentExists(name.toUpperAscii): 
        cq.error(fmt"Agent {name.toUpperAscii} does not exist.")
        return

    # TODO: Stop the process of the agent on the target system
    # TODO: Add flag to self-delete executable after killing agent


    # Remove the agent from the database
    if not cq.dbDeleteAgentByName(name.toUpperAscii): 
        cq.error("Failed to terminate agent: ", getCurrentExceptionMsg())
        return

    cq.agents.del(name)
    cq.success("Terminated agent ", fgYellow, styleBright, name.toUpperAscii, resetStyle, ".")
