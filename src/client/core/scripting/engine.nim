import nimpy
import ../../context

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

        cq.moduleManager.tempModule.path = file
        
        # Parse and execute the loaded script 
        discard builtins.exec(script, globals)

        # Reset placeholder
        cq.moduleManager.tempModule = (name: "", description: "", path: "", commandCount: 0)

    except: 
        echo "Failed to load ", file ,": " , getCurrentExceptionMsg()