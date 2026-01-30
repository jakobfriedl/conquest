import whisky
import tables, times, strutils, sequtils, strformat, json, base64, native_dialogs
import ./utils/[appImGui, globals]
import ./views/[dockspace, sessions, listeners, eventlog, console, processBrowser, fileBrowser, moduleManager]
import ./views/loot/[screenshots, downloads]
import ./views/modals/[generatePayload, connect]
import ../common/[utils, profile, crypto, serialize]
import ../types/[common, client, event]
import ./core/[websocket, database]
import ./core/scripting/engine

proc main(ip: string = "localhost", port: int = 37573) = 
    var app = createApp(1024, 800, imnodes = true, title = "Conquest", docking = true)
    defer: app.destroyApp()

    var imPlotContext = ImPlot_CreateContext()
    defer: imPlotContext.ImPlotDestroyContext()
 
    var 
        profile: Profile
        views: OrderedTable[string, ptr bool]
        showConquest = true
        showSessionsTable = true
        showListeners = true
        showEventlog = true
        showDownloads = false
        showScreenshots = false
        showProcesses = false
        showFiles = false
        showModules = false

    var 
        dockTop: ImGuiID = 0
        dockBottom: ImGuiID = 0
        dockTopLeft: ImGuiID = 0
        dockTopRight: ImGuiID = 0

    views["Sessions"] = addr showSessionsTable 
    views["Listeners"] = addr showListeners
    views["Eventlog"] = addr showEventlog
    views["Loot:Downloads"] = addr showDownloads
    views["Loot:Screenshots"] = addr showScreenshots
    views["Process Browser"] = addr showProcesses
    views["Filesystem Browser"] = addr showFiles
    views["Module Manager"] = addr showModules

    # Initialize database 
    dbInit()

    # Create components
    var dockspace = Dockspace()
    cq.moduleManager = ModuleManager(WIDGET_MODULE_MANAGER, addr showModules)

    # Modules need to be loaded before other components are created
    loadScript(CONQUEST_ROOT & "/data/modules/default.py")
    for path in dbGetScriptPaths(): 
        loadScript(path)

    cq.sessions = SessionsTable(WIDGET_SESSIONS, addr showSessionsTable) 
    cq.listeners = ListenersTable(WIDGET_LISTENERS, addr showListeners)
    cq.eventlog = Eventlog(WIDGET_EVENTLOG, addr showEventlog)
    cq.downloads = LootDownloads(WIDGET_DOWNLOADS, addr showDownloads)
    cq.screenshots = LootScreenshots(WIDGET_SCREENSHOTS, addr showScreenshots)
    cq.processBrowser = ProcessBrowser(WIDGET_PROCESS_BROWSER, addr showProcesses)
    cq.filebrowser = FileBrowser(WIDGET_FILE_BROWSER, addr showFiles)

    let io = igGetIO()

    # Create key pair 
    var clientKeyPair = generateKeyPair() 
    defer: wipeKey(clientKeyPair.privateKey)
    
    # Team server connection 
    var connectModal = ConnectionModal(ip, port)    
    cq.connection = nil

    # Main client loop
    while not app.handle.windowShouldClose:
        pollEvents()

        if app.isIconifySleep():
            continue 
        newFrame()

        # Initialize dockspace and docking layout 
        dockspace.draw(addr showConquest, views, addr dockTop, addr dockBottom, addr dockTopLeft, addr dockTopRight)

        # Show connection modal if not connected to a team server
        var authInfo: tuple[username, password: string]
        if cq.connection == nil:
            igOpenPopup_str("Connect", ImGui_PopupFlags_None.int32)
            authInfo = connectModal.draw()
                    
        # Draw UI components
        if showSessionsTable: cq.sessions.draw()   
        if showListeners: cq.listeners.draw()
        if showEventlog: cq.eventlog.draw()
        if showDownloads: cq.downloads.draw()
        if showScreenshots: cq.screenshots.draw()
        if showProcesses: cq.processBrowser.draw()
        if showFiles: cq.filebrowser.draw()
        if showModules: cq.moduleManager.draw()

        for agentId, agent in cq.sessions.agents.mpairs():
            if agent.console.showConsole:
                agent.console.draw()
            
        if cq.sessions.focusedConsole.len() > 0: 
            igSetWindowFocus_Str(cq.sessions.focusedConsole.cstring)
            cq.sessions.focusedConsole = ""
        
        #[
            WebSocket communication with the team server
        ]# 
        if cq.connection != nil:
            try: 
                # Receive and parse websocket response message 
                let message = cq.connection.ws.receiveMessage(timeout = 16)    # Use a 16ms timeout to reduce CPU load = ~60FPS 
                if message.isSome():
                    let event = recvEvent(message.get(), cq.connection.sessionKey)
                    case event.eventType:
                    of CLIENT_KEY_EXCHANGE: 
                        cq.connection.sessionKey = deriveSessionKey(clientKeyPair, decode(event.data["publicKey"].getStr()).toKey())            
                        cq.connection.sendPublicKey(clientKeyPair.publicKey)

                        # Authentication 
                        cq.connection.sendAuthentication(authInfo.username, authInfo.password) 

                    of CLIENT_AUTH_RESULT: 
                        if event.data["success"].getBool(): 
                            connectModal.errorMessage.setLen(0)
                            cq.connection.user = authInfo.username
                        
                        else: 
                            connectModal.errorMessage = "Incorrect username or password."
                            # Close websocket connection
                            if cq.connection != nil: 
                                cq.connection.ws.close()
                                cq.connection = nil 

                    of CLIENT_PROFILE:
                        profile = parseString(event.data["profile"].getStr())

                    of CLIENT_LISTENER_ADD: 
                        let listener = event.data.to(UIListener)
                        cq.listeners.listeners[listener.listenerId] = listener

                    of CLIENT_LISTENER_REMOVE:
                        let listenerId = event.data["listenerId"].getStr()
                        cq.listeners.listeners.del(listenerId)

                    of CLIENT_AGENT_ADD: 
                        let agentId = event.data["agentId"].getStr()
                        var agent = UIAgent(
                            agentId: agentId,
                            listenerId: event.data["listenerId"].getStr(),
                            username: event.data["username"].getStr(),
                            impersonationToken: event.data["impersonationToken"].getStr(),
                            hostname: event.data["hostname"].getStr(),
                            domain: event.data["domain"].getStr(),
                            ipInternal: event.data["ipInternal"].getStr(),
                            ipExternal: event.data["ipExternal"].getStr(),
                            os: event.data["os"].getStr(),
                            process: event.data["process"].getStr(),
                            pid: event.data["pid"].getInt(),
                            elevated: event.data["elevated"].getBool(),
                            sleep: event.data["sleep"].getInt(),
                            jitter: event.data["jitter"].getInt(),
                            modules: cast[uint32](event.data["modules"].getInt()),
                            firstCheckin: event.data["firstCheckin"].getInt(),
                            latestCheckin: event.data["latestCheckin"].getInt(),
                            processes: none(Processes),
                            filesystem: none(OrderedTable[string, DirectoryEntry]),
                            workingDirectory: none(string),
                            console: Console(agentId)
                        )
                    
                        agent.consoleTitle = fmt" {ICON_FA_TERMINAL} [{agent.agentId}] {agent.username}@{agent.hostname}"
                        cq.sessions.agents[agent.agentId] = agent

                        # # Initialize position of console windows to bottom by drawing them once when they are added
                        # # By default, the consoles are attached to the same DockNode as the Listeners table (Default: bottom), 
                        # # so if you place your listeners somewhere else, the console windows show up somewhere else too
                        # # The only case that is not covered is when the listeners table is hidden and the bottom panel was split
                        let listenersWindow = igFindWindowByName(WIDGET_LISTENERS) 
                        if listenersWindow != nil and listenersWindow.DockNode != nil:
                            igSetNextWindowDockID(listenersWindow.DockNode.ID, ImGuiCond_FirstUseEver.int32)
                        else:
                            igSetNextWindowDockID(dockBottom, ImGuiCond_FirstUseEver.int32)
                        agent.console.draw()

                    of CLIENT_AGENT_CHECKIN: 
                        cq.sessions.agents[event.data["agentId"].getStr()].latestCheckin = event.timestamp

                    of CLIENT_AGENT_PAYLOAD: 
                        let payload = decode(event.data["payload"].getStr())
                        try: 
                            let path = callDialogFileSave("Save Payload")
                            writeFile(path, payload)
                        except IOError:
                            discard 

                        # Close and reset the payload generation modal window when the payload was received
                        cq.listeners.generatePayloadModal.resetModalValues()
                        cq.listeners.generatePayloadModal.show = false

                    of CLIENT_CONSOLE_ITEM: 
                        let agentId = event.data["agentId"].getStr() 
                        if cq.sessions.agents.hasKey(agentId):
                            cq.sessions.agents[agentId].console.textarea.addItem(
                                cast[LogType](event.data["logType"].getInt()), 
                                event.data["message"].getStr(), 
                                event.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss"),
                                agentId = agentId
                            )
                    
                    of CLIENT_EVENTLOG_ITEM: 
                        cq.eventlog.textarea.addItem(
                            cast[LogType](event.data["logType"].getInt()), 
                            event.data["message"].getStr(), 
                            event.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss")
                        )

                    of CLIENT_BUILDLOG_ITEM:
                        cq.listeners.generatePayloadModal.buildLog.addItem(
                            cast[LogType](event.data["logType"].getInt()), 
                            event.data["message"].getStr(), 
                            event.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss")
                        )

                    of CLIENT_LOOT_ADD: 
                        let lootItem = event.data.to(LootItem)
                        case lootItem.itemType:
                        of DOWNLOAD:
                            cq.downloads.items.add(lootItem)
                        of SCREENSHOT:
                            cq.screenshots.items.add(lootItem)
                        else: discard 

                    of CLIENT_LOOT_DATA:
                        let
                            lootItem = event.data["loot"].to(LootItem)
                            data = decode(event.data["data"].getStr())
                        
                        case lootItem.itemType: 
                        of DOWNLOAD: 
                            cq.downloads.contents[lootItem.lootId] = data
                        of SCREENSHOT: 
                            cq.screenshots.addTexture(lootItem.lootId, data)
                        else: discard 

                    of CLIENT_IMPERSONATE_TOKEN: 
                        let 
                            agentId = event.data["agentId"].getStr()
                            impersonationToken = event.data["username"].getStr()
                        cq.sessions.agents[agentId].impersonationToken = impersonationToken

                    of CLIENT_REVERT_TOKEN: 
                        cq.sessions.agents[event.data["agentId"].getStr()].impersonationToken = ""
                
                    of CLIENT_PROCESSES: 
                        let
                            agentId = event.data["agentId"].getStr()
                            procData = event.data["processes"].getStr()
                            silent = event.data["silent"].getBool()

                        # Display processes in agent console    
                        var unpacker = Unpacker.init(procData)
                        let numProcesses = unpacker.getUint32() 

                        var processTable = initOrderedTable[uint32, ProcessInfo]()
                        for i in 0 ..< numProcesses: 
                            let procInfo = ProcessInfo(
                                pid: unpacker.getUint32(),
                                ppid: unpacker.getUint32(),
                                name: unpacker.getDataWithLengthPrefix(),
                                user: unpacker.getDataWithLengthPrefix(),
                                session: unpacker.getUint32(),
                                children: @[]
                            )
                            processTable[procInfo.pid] = procInfo

                        var rootProcesses: seq[uint32]
                        for pid, procInfo in processTable.mpairs(): 
                            let ppid = procInfo.ppid 
                            if processTable.hasKey(ppid) and ppid != 0: 
                                processTable[ppid].children.add(pid)
                            else: 
                                rootProcesses.add(pid)

                        # Display processes in agent console
                        if not silent: 
                            if cq.sessions.agents.hasKey(agentId):
                                cq.sessions.agents[agentId].console.listProcesses(rootProcesses, processTable) 

                        # Add process information to the process browser
                        cq.sessions.agents[agentId].processes = some(Processes(
                            rootProcesses: rootProcesses, 
                            processTable: processTable,
                            timestamp: event.timestamp
                        ))

                    of CLIENT_DIRECTORY_LISTING: 
                        let
                            agentId = event.data["agentId"].getStr()
                            data = event.data["data"].getStr()
                            silent = event.data["silent"].getBool()
                        
                        var unpacker = Unpacker.init(data)
                        var entries: seq[DirectoryEntry] = @[]
                        
                        let path = unpacker.getDataWithLengthPrefix() 
                        let numEntries = unpacker.getUint32() 

                        for i in 0 ..< int(numEntries): 
                            let 
                                name = unpacker.getDataWithLengthPrefix()
                                flags = unpacker.getUint8()
                                size = unpacker.getUint64()
                                lastWriteTime = unpacker.getInt64()
                                                                    
                            entries.add(DirectoryEntry(
                                name: name,
                                flags: flags,
                                size: size,
                                lastWriteTime: lastWriteTime,
                                isLoaded: false, 
                                children: 
                                    if (flags and cast[uint8](IS_DIR)) != 0: some(initOrderedTable[string, DirectoryEntry]()) 
                                    else: none(OrderedTable[string, DirectoryEntry])
                            ))

                        # Display processes in agent console
                        if not silent:
                            if cq.sessions.agents.hasKey(agentId):
                                cq.sessions.agents[agentId].console.listDirectoryContents(path, entries) 

                        # Add information to the file browser
                        # Initialize filesystem storage
                        if not cq.sessions.agents[agentId].filesystem.isSome(): 
                            cq.sessions.agents[agentId].filesystem = some(initOrderedTable[string, DirectoryEntry]())
                            
                        # Split path into components
                        let cleanPath = path.strip(chars = {'\\', '/'})
                        var parts = cleanPath.split({'\\', '/'}).filterIt(it.len > 0)
                        
                        # Built tree structure
                        var currentTable = addr cq.sessions.agents[agentId].filesystem.get()
                        for i, component in parts:
                            if not currentTable[].hasKey(component):
                                currentTable[][component] = DirectoryEntry(
                                    name: component,
                                    flags: cast[uint8](IS_DIR),
                                    children: some(initOrderedTable[string, DirectoryEntry]())
                                )
                            
                            # Mark target directory as loaded
                            if i == parts.len - 1:
                                currentTable[][component].isLoaded = true
                                
                            # Navigate to next child directory
                            if currentTable[][component].children.isSome():
                                currentTable = addr currentTable[][component].children.get()

                        # Merge entries into the target table
                        for entry in entries:
                            if currentTable[].hasKey(entry.name):
                                currentTable[][entry.name].flags = entry.flags
                                currentTable[][entry.name].size = entry.size
                                currentTable[][entry.name].lastWriteTime = entry.lastWriteTime
                            else:
                                currentTable[][entry.name] = entry

                    of CLIENT_WORKING_DIRECTORY: 
                        let agentId = event.data["agentId"].getStr()
                        if cq.sessions.agents.hasKey(agentId):
                            cq.sessions.agents[agentId].workingDirectory = some(event.data["directory"].getStr())

                    else: discard 
            
            except CatchableError as err:
                connectModal.errorMessage = "Lost connection to team server."
                cq.connection = nil 
                echo "[-] ", err.msg

        # render
        app.render()

        if not showConquest: 
            app.handle.setWindowShouldClose(true)


when isMainModule:
    import cligen; dispatch main