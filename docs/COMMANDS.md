# "Monarch" Agent commands:

House-keeping
-------------
- [x] sleep       : Set sleep obfuscation duration to a different value and persist that value in the agent

Basic API-only Commands
-----------------------
- [x] pwd         : Get current working directory
- [x] cd          : Change directory
- [x] ls/dir      : List all files in directory (including hidden ones)
- [x] rm          : Remove a file
- [x] rmdir       : Remove a empty directory
- [x] mv          : Move a file 
- [x] cp          : Copy a file
- [ ] cat/type    : Display contents of a file
- [ ] env         : Display environment variables
- [ ] ps          : List processes
- [ ] whoami      : Get UID and privileges, etc. 

- [ ] token       : Token impersonation
    - [ ] make    : Create a token from a user's plaintext password (LogonUserA, ImpersonateLoggedOnUser)
    - [ ] steal   : Steal the access token from a process (OpenProcess, OpenProcessToken, DuplicateToken, ImpersonateLoggedOnUser)
    - [ ] use     : Impersonate a token from the token vault (ImpersonateLoggedOnUser) -> update username like in Cobalt Strike
- [ ] rev2self    : Revert to original logon session (RevertToSelf)

Execution Commands
------------------
- [x] shell       : Execute shell command (to be implemented using Windows APIs instead of execCmdEx)
- [ ] bof         : Execute Beacon Object File in memory and retrieve output (bof /local/path/file.o)
        - Read from listener endpoint directly to memory
        - Base for all kinds of BOFs (Situational Awareness, ...)
- [ ] pe          : Execute PE file in memory and retrieve output (pe /local/path/mimikatz.exe)
- [ ] dotnet      : Execute .NET assembly inline in memory and retrieve output (dotnet /local/path/Rubeus.exe ) 

Post-Exploitation
-----------------
- [ ] upload      : Upload file from server to agent (upload /local/path/to/file C:\Windows\Tasks)
        - File to be downloaded moved to specific endpoint on listener, e.g. GET /<listener>/<agent>/<upload-task>/file
        - Read from webserver and written to disk 
- [ ] download    : Download file from agent to teamserver
        - Create loot directory for agent to store files in 
        - Read file into memory and send byte stream to specific endpoint, e.g. POST /<listener>/<agent>/<download>-task/file
        - Encrypt file in-transit!!!
