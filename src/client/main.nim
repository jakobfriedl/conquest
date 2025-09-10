import tables
import ./utils/appImGui
import ./views/[dockspace, sessions, listeners, eventlog, console]

proc main() = 
    var app = createApp(1024, 800, imnodes = true, title = "Conquest", docking = true)
    defer: app.destroyApp()

    var 
        views: Table[string, ptr bool]
        showConquest = true
        showSessionsTable = true
        showSessionsGraph = false
        showListeners = false
        showEventlog = true
        consoles: Table[string, ConsoleComponent]
        
    views["Sessions [Table View]"] = addr showSessionsTable 
    views["Sessions [Graph View]"] = addr showSessionsGraph
    views["Listeners"] = addr showListeners
    views["Eventlog"] = addr showEventlog

    # Create components
    var 
        dockspace = Dockspace()
        sessionsTable = SessionsTable("Sessions [Table View]", addr consoles) 
        listenersTable = ListenersTable("Listeners")
        eventlog = Eventlog("Eventlog")

    let io = igGetIO()

    # main loop
    while not app.handle.windowShouldClose:
        pollEvents()

        # Reduce rendering activity when window is minimized 
        if app.isIconifySleep():
            continue 
        newFrame()

        # Draw/update UI components/views
        dockspace.draw(addr showConquest, views)
        if showSessionsTable: sessionsTable.draw(addr showSessionsTable)   
        if showListeners: listenersTable.draw(addr showListeners)
        if showEventlog: eventlog.draw(addr showEventlog)

        # Show console windows
        var newConsoleTable: Table[string, ConsoleComponent]
        for agentId, console in consoles.mpairs():
            if console.showConsole: 
                console.draw()
                newConsoleTable[agentId] = console
            
        # Update the consoles table with only those sessions that have not been closed yet
        # This is done to ensure that closed console windows can be opened again
        consoles = newConsoleTable

        igShowDemoWindow(nil)

        # render
        app.render()

        if not showConquest: 
            app.handle.setWindowShouldClose(true)

when isMainModule:
    main()
