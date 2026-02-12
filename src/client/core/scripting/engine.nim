import nimpy, sets
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

        discard builtins.exec(script, globals)

        # Store script in database 
        if not dbScriptExists(file):
            discard dbStoreScript(file)
        cq.moduleManager.scripts.incl(file)

    except: 
        echo "Failed to load ", file ,": " , getCurrentExceptionMsg()