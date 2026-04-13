import winim/lean

#[
    Reflective DLL Loader
    - Loads DLL from memory into the current process and executes the entry point in a new thread

    References: 
    - https://maldevacademy.com/new/modules/28
    - https://github.com/Helixo32/NimReflectiveLoader
    - https://github.com/S3cur3Th1sSh1t/Nim-RunPE
]#

proc fixIAT() =    
    discard 

proc fixRelocations() = 
    discard 

proc fixMemoryPermissions() = 
    discard

proc loadDll(bytes: seq[byte]): HMODULE = 
    discard 

proc freeDll(hModule: HMODULE) = 
    discard

proc getExportedProcAddress(hModule: HMODULE, name: string): FARPROC
    discard

