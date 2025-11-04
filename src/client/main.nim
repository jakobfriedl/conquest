import whisky
import tables, times, strutils, strformat, json, parsetoml, base64, native_dialogs
import ./utils/[appImGui, globals]
import ./views/[dockspace, sessions, listeners, eventlog, console]
import ./views/loot/[screenshots, downloads]
import ./views/modals/generatePayload
import ../common/[types, utils, crypto]
import ./core/websocket

proc main(ip: string = "localhost", port: int = 37573) = 
    var app = createApp(1024, 800, imnodes = true, title = "Conquest", docking = true)
    defer: app.destroyApp()

    var imPlotContext = ImPlot_CreateContext()
    defer: imPlotContext.ImPlotDestroyContext()
 
    var 
        profile: Profile
        views: Table[string, ptr bool]
        showConquest = true
        showSessionsTable = true
        showListeners = true
        showEventlog = true
        showDownloads = false
        showScreenshots = false
        consoles: Table[string, ConsoleComponent]

    var 
        dockTop: ImGuiID = 0
        dockBottom: ImGuiID = 0
        dockTopLeft: ImGuiID = 0
        dockTopRight: ImGuiID = 0

    views["Sessions [Table View]"] = addr showSessionsTable 
    views["Listeners"] = addr showListeners
    views["Eventlog"] = addr showEventlog
    views["Loot:Downloads"] = addr showDownloads
    views["Loot:Screenshots"] = addr showScreenshots

    # Create components
    var 
        dockspace = Dockspace()
        sessionsTable = SessionsTable(WIDGET_SESSIONS, addr consoles) 
        listenersTable = ListenersTable(WIDGET_LISTENERS)
        eventlog = Eventlog(WIDGET_EVENTLOG)
        lootDownloads = LootDownloads(WIDGET_DOWNLOADS)
        lootScreenshots = LootScreenshots(WIDGET_SCREENSHOTS)

    let io = igGetIO()

    # Create key pair 
    var clientKeyPair = generateKeyPair() 
        
    # Initiate WebSocket connection
    var connection = WsConnection(
        ws: newWebSocket(fmt"ws://{ip}:{$port}"),
        sessionKey: default(Key)
    )
    defer: connection.ws.close() 

    # main loop
    while not app.handle.windowShouldClose:
        pollEvents()

        # Reduce rendering activity when window is minimized 
        if app.isIconifySleep():
            continue 
        newFrame()

        # Initialize dockspace and docking layout
        dockspace.draw(addr showConquest, views, addr dockTop, addr dockBottom, addr dockTopLeft, addr dockTopRight)
        
        #[
            WebSocket communication with the team server
        ]# 
        try: 
            # Receive and parse websocket response message 
            let message = connection.ws.receiveMessage(timeout = 16)    # Use a 16ms timeout to reduce CPU load = ~60FPS 
            if message.isSome():
                let event = recvEvent(message.get(), connection.sessionKey)
                case event.eventType:
                of CLIENT_KEY_EXCHANGE: 
                    connection.sessionKey = deriveSessionKey(clientKeyPair, decode(event.data["publicKey"].getStr()).toKey())            
                    connection.sendPublicKey(clientKeyPair.publicKey)
                    wipeKey(clientKeyPair.privateKey)

                of CLIENT_PROFILE:
                    profile = parsetoml.parseString(event.data["profile"].getStr())
                
                of CLIENT_LISTENER_ADD: 
                    let listener = event.data.to(UIListener)
                    listenersTable.listeners.add(listener)

                of CLIENT_AGENT_ADD: 
                    let agent = event.data.to(UIAgent)

                    # The ImGui Multi Select only works well with seq's, so we maintain a
                    # separate table of the latest agent heartbeats to have the benefit of quick and direct O(1) access
                    sessionsTable.agents.add(agent)
                    sessionsTable.agentActivity[agent.agentId] = agent.latestCheckin

                    if not agent.impersonationToken.isEmptyOrWhitespace():
                        sessionsTable.agentImpersonation[agent.agentId] = agent.impersonationToken

                    # Initialize position of console windows to bottom by drawing them once when they are added
                    # By default, the consoles are attached to the same DockNode as the Listeners table (Default: bottom), 
                    # so if you place your listeners somewhere else, the console windows show up somewhere else too
                    # The only case that is not covered is when the listeners table is hidden and the bottom panel was split
                    var agentConsole = Console(agent)
                    consoles[agent.agentId] = agentConsole
                    let listenersWindow = igFindWindowByName(WIDGET_LISTENERS) 
                    if listenersWindow != nil and listenersWindow.DockNode != nil:
                        igSetNextWindowDockID(listenersWindow.DockNode.ID, ImGuiCond_FirstUseEver.int32)
                    else:
                        igSetNextWindowDockID(dockBottom, ImGuiCond_FirstUseEver.int32)
                    consoles[agent.agentId].draw(connection)
                    consoles[agent.agentId].showConsole = false

                of CLIENT_AGENT_CHECKIN: 
                    sessionsTable.agentActivity[event.data["agentId"].getStr()] = event.timestamp

                of CLIENT_AGENT_PAYLOAD: 
                    let payload = decode(event.data["payload"].getStr())
                    try: 
                        let path = callDialogFileSave("Save Payload")
                        writeFile(path, payload)
                    except IOError:
                        discard 

                    # Close and reset the payload generation modal window when the payload was received
                    listenersTable.generatePayloadModal.resetModalValues()
                    igClosePopupToLevel(0, false)

                of CLIENT_CONSOLE_ITEM: 
                    let agentId = event.data["agentId"].getStr() 
                    consoles[agentId].console.addItem(
                        cast[LogType](event.data["logType"].getInt()), 
                        event.data["message"].getStr(), 
                        event.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss")
                    )
                
                of CLIENT_EVENTLOG_ITEM: 
                    eventlog.textarea.addItem(
                        cast[LogType](event.data["logType"].getInt()), 
                        event.data["message"].getStr(), 
                        event.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss")
                    )

                of CLIENT_BUILDLOG_ITEM:
                    listenersTable.generatePayloadModal.buildLog.addItem(
                        cast[LogType](event.data["logType"].getInt()), 
                        event.data["message"].getStr(), 
                        event.timestamp.fromUnix().local().format("dd-MM-yyyy HH:mm:ss")
                    )

                of CLIENT_LOOT_ADD: 
                    let lootItem = event.data.to(LootItem)
                    case lootItem.itemType:
                    of DOWNLOAD:
                        lootDownloads.items.add(lootItem)
                    of SCREENSHOT:
                        lootScreenshots.items.add(lootItem)
                    else: discard 

                of CLIENT_LOOT_DATA:
                    let
                        lootItem = event.data["loot"].to(LootItem)
                        data = decode(event.data["data"].getStr())
                    
                    case lootItem.itemType: 
                    of DOWNLOAD: 
                        lootDownloads.contents[lootItem.lootId] = data
                    of SCREENSHOT: 
                        lootScreenshots.addTexture(lootItem.lootId, data)
                    else: discard 

                of CLIENT_IMPERSONATE_TOKEN: 
                    let 
                        agentId = event.data["agentId"].getStr()
                        impersonationToken = event.data["username"].getStr()
                    sessionsTable.agentImpersonation[agentId] = impersonationToken

                of CLIENT_REVERT_TOKEN: 
                    sessionsTable.agentImpersonation.del(event.data["agentId"].getStr())
            
                else: discard 
        
            # Draw/update UI components/views
            if showSessionsTable: sessionsTable.draw(addr showSessionsTable, connection)   
            if showListeners: listenersTable.draw(addr showListeners, connection)
            if showEventlog: eventlog.draw(addr showEventlog)
            if showDownloads: lootDownloads.draw(addr showDownloads, connection)
            if showScreenshots: lootScreenshots.draw(addr showScreenshots, connection)

            # Show console windows
            var newConsoleTable: Table[string, ConsoleComponent]
            for agentId, console in consoles.mpairs():
                if console.showConsole:
                    # Ensure that new console windows are docked to the bottom panel by default
                    igSetNextWindowDockID(dockBottom, ImGuiCond_FirstUseEver.int32)
                    console.draw(connection)    
                    newConsoleTable[agentId] = console
                
            if sessionsTable.focusedConsole.len() > 0: 
                igSetWindowFocus_Str(sessionsTable.focusedConsole.cstring)
                sessionsTable.focusedConsole = ""

            # Update the consoles table with only those sessions that have not been closed yet
            # This is done to ensure that closed console windows can be opened again
            consoles = newConsoleTable

        except CatchableError as err:
            echo "[-] ", err.msg
            discard

        # render
        app.render()

        if not showConquest: 
            app.handle.setWindowShouldClose(true)


when isMainModule:
    import cligen; dispatch main
