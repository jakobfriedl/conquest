import ./commands/[shell]
export shell

#[
    "Monarch" Agent commands:

    Basic
    ----- 
    [~] shell       : Execute shell command (to be implemented using Windows APIs instead of execCmdEx)
    [ ] pwd         : Get current working directory
    [ ] cd          : Change directory
    [ ] ls/dir      : List all files in directory (including hidden ones)
    [ ] cat/type    : Display contents of a file
    [ ] sleep       : Set sleep obfuscation duration to a different value and persist that value in the agent
    
    Post-exploitation
    -----------------
    [ ] upload      : Upload file from server to agent (upload /local/path/to/file C:\Windows\Tasks)
            - File to be downloaded moved to specific endpoint on listener, e.g. GET /<listener>/<agent>/<upload-task>/file
            - Read from webserver and written to disk 
    [ ] download    : Download file from agent to teamserver
            - Create loot directory for agent to store files in 
            - Read file into memory and send byte stream to specific endpoint, e.g. POST /<listener>/<agent>/<download>-task/file
            - Encrypt file in-transit!!!
    [ ] bof         : Execute Beacon Object File in memory and retrieve output (bof /local/path/file.o)
            - Read from listener endpoint directly to memory
    [ ] pe          : Execute PE file in memory and retrieve output (pe /local/path/mimikatz.exe)
    [ ] dotnet      : Execute .NET assembly inline in memory and retrieve output (dotnet /local/path/Rubeus.exe ) 

]#