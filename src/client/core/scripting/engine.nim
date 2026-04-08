import nimpy
import ../../utils/globals

pyExportModule("conquest")
include ./pythonApi

#[
    Scripting Engine
    - export Python API function
    - execute scripts to register commands & modules
]#
proc loadScript*(file: string) = 
    try: 
        let script = readFile(file)
        let builtins = pyBuiltinsModule()
        let globals = pyDict()
        globals["__builtins__"] = builtins  

        # Store script in database 
        if not dbScriptExists(file):
            discard dbStoreScript(file)
        
        discard builtins.exec(script, globals)

        # Set 'active' to true if the script was loaded without errors
        cq.scriptManager.scripts[file] = (true, "")

    except: 
        cq.scriptManager.scripts[file] = (false, getCurrentExceptionMsg())        
        echo "Failed to load ", file ,": " , getCurrentExceptionMsg()