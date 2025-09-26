import whisky
import tables, strutils, json, parsetoml
import ./utils/appImGui
import ./views/[dockspace, sessions, listeners, eventlog, console]
import ../common/[types, utils]
import ./event/[send, recv]

import sugar 

proc main() = 
    var app = createApp(1024, 800, imnodes = true, title = "Conquest", docking = true)
    defer: app.destroyApp()

    var 
        profile: Profile
        views: Table[string, ptr bool]
        showConquest = true
        showSessionsTable = true
        showListeners = true
        showEventlog = true
        consoles: Table[string, ConsoleComponent]

    var 
        dockTop: ImGuiID = 0
        dockBottom: ImGuiID = 0
        dockTopLeft: ImGuiID = 0
        dockTopRight: ImGuiID = 0

    views["Sessions [Table View]"] = addr showSessionsTable 
    views["Listeners"] = addr showListeners
    views["Eventlog"] = addr showEventlog

    # Create components
    var 
        dockspace = Dockspace()
        sessionsTable = SessionsTable("Sessions [Table View]", addr consoles) 
        listenersTable = ListenersTable("Listeners")
        eventlog = Eventlog("Eventlog")

    let io = igGetIO()

    # Initiate WebSocket connection
    let ws = newWebSocket("ws://localhost:12345")
    defer: ws.close() 

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
        # Continuously send heartbeat messages
        ws.sendHeartbeat()

        # Receive and parse websocket response message 
        let event = recvEvent(ws.receiveMessage().get())
        case event.eventType:
        # of CLIENT_PROFILE:
        #     profile = parsetoml.parseString(event.data["profile"].getStr())
        
        of CLIENT_LISTENER_ADD: 
            let listener = event.data.to(UIListener)
            listenersTable.listeners.add(listener)

        of CLIENT_AGENT_ADD: 
            let agent = event.data.to(UIAgent)
            sessionsTable.agents[agent.agentId] = agent

            # Initialize position of console windows to bottom by drawing them once when they are added
            # By default, the consoles are attached to the same DockNode as the Listeners table (Default: bottom), 
            # so if you place your listeners somewhere else, the console windows show up somewhere else too
            # The only case that is not covered is when the listeners table is hidden and the bottom panel was split
            var agentConsole = Console(agent)
            consoles[agent.agentId] = agentConsole
            let listenersWindow = igFindWindowByName("Listeners") 
            if listenersWindow != nil and listenersWindow.DockNode != nil:
                igSetNextWindowDockID(listenersWindow.DockNode.ID, ImGuiCond_FirstUseEver.int32)
            else:
                igSetNextWindowDockID(dockBottom, ImGuiCond_FirstUseEver.int32)
            consoles[agent.agentId].draw(ws)
            consoles[agent.agentId].showConsole = false

        of CLIENT_AGENT_CHECKIN: 
            sessionsTable.agents[event.data["agentId"].getStr()].latestCheckin = event.timestamp

        of CLIENT_AGENT_PAYLOAD: 
            discard

        of CLIENT_CONSOLE_ITEM: 
            consoles[event.data["agentId"].getStr()].addItem(cast[LogType](event.data["logType"].getInt()), event.data["message"].getStr(), event.timestamp)
        
        of CLIENT_EVENTLOG_ITEM: 
            eventlog.addItem(cast[LogType](event.data["logType"].getInt()), event.data["message"].getStr(), event.timestamp)
        
        else: discard 

        # Draw/update UI components/views
        if showSessionsTable: sessionsTable.draw(addr showSessionsTable)   
        if showListeners: listenersTable.draw(addr showListeners, ws)
        if showEventlog: eventlog.draw(addr showEventlog)

        # Show console windows
        var newConsoleTable: Table[string, ConsoleComponent]
        for agentId, console in consoles.mpairs():
            if console.showConsole:
                # Ensure that new console windows are docked to the bottom panel by default
                igSetNextWindowDockID(dockBottom, ImGuiCond_FirstUseEver.int32)
                console.draw(ws)    
                newConsoleTable[agentId] = console
            
        # Update the consoles table with only those sessions that have not been closed yet
        # This is done to ensure that closed console windows can be opened again
        consoles = newConsoleTable

        #  igShowDemoWindow(nil)

        # render
        app.render()

        if not showConquest: 
            app.handle.setWindowShouldClose(true)

when isMainModule:
    main()
