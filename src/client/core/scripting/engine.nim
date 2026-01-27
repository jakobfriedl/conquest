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

        # Parse and execute the loaded script 
        cq.moduleManager.tempPath = file
        discard builtins.exec(script, globals)
    except: 
        echo "Failed to load ", file ,": " , getCurrentExceptionMsg()