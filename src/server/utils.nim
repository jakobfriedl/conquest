import times, json
import ../common/types

proc `%`*(agent: Agent): JsonNode =
    result = newJObject()
    result["agentId"] = %agent.agentId
    result["listenerId"] = %agent.listenerId
    result["username"] = %agent.username
    result["hostname"] = %agent.hostname
    result["domain"] = %agent.domain
    result["ip"] = %agent.ip
    result["os"] = %agent.os
    result["process"] = %agent.process
    result["pid"] = %agent.pid
    result["elevated"] = %agent.elevated
    result["sleep"] = %agent.sleep
    result["firstCheckin"] = %agent.firstCheckin.toTime().toUnix()
    result["latestCheckin"] = %agent.latestCheckin.toTime().toUnix()

proc `%`*(listener: Listener): JsonNode =
    result = newJObject()
    result["listenerId"] = %listener.listenerId
    result["address"] = %listener.address
    result["port"] = %listener.port 
    result["protocol"] = %listener.protocol