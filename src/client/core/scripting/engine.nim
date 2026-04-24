import nimpy
import ../database
import ../../utils/globals

pyExportModule("conquest")

# Global variable for storing the current script path
var scriptPath: string = ""

include ./pythonApi

#[
    Scripting Engine
    - export Python API function
    - execute scripts to register commands & modules
]#
proc unregisterCommands(path: string) =
    if not cq.scriptManager.scripts.hasKey(path): return
    for cmd in cq.scriptManager.scripts[path].commands:
        if cq.scriptManager.groups.hasKey(cmd.group):
            cq.scriptManager.groups[cmd.group].del(cmd.name)
            if cq.scriptManager.groups[cmd.group].len == 0:
                cq.scriptManager.groups.del(cmd.group)

proc load_script*(path: string) {.exportpy.} =
    try:
        unregisterCommands(path)
        scriptPath = path
        cq.scriptManager.scripts[path] = (active: false, error: "", commands: @[])

        let script = readFile(path)
        let builtins = pyBuiltinsModule()
        let globals = pyDict()
        globals["__builtins__"] = builtins
        globals["__file__"] = path

        if not dbScriptExists(path):
            discard dbStoreScript(path)

        discard builtins.exec(script, globals)

        if cq.scriptManager.scripts.hasKey(path):
            var entry = cq.scriptManager.scripts[path]
            entry.active = true
            entry.error = ""
            cq.scriptManager.scripts[path] = entry

    except:
        if cq.scriptManager.scripts.hasKey(path):
            var entry = cq.scriptManager.scripts[path]
            entry.active = false
            entry.error = getCurrentExceptionMsg()
            cq.scriptManager.scripts[path] = entry
        echo "Failed to load ", path, ": ", getCurrentExceptionMsg()

    scriptPath = ""

proc unload_script*(path: string) {.exportpy.} =
    try:
        if dbRemoveScript(path):
            unregisterCommands(path)
            cq.scriptManager.scripts.del(path)

    except:
        echo "Failed to unload ", path, ": ", getCurrentExceptionMsg()
