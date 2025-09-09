import tables
import ./utils/appImGui
import ./views/[dockspace, sessions, listeners, eventlog]

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
        
    views["Sessions [Table View]"] = addr showSessionsTable 
    views["Sessions [Graph View]"] = addr showSessionsGraph
    views["Listeners"] = addr showListeners
    views["Eventlog"] = addr showEventlog

    # Create components
    var 
        dockspace = Dockspace()
        sessionsTable = SessionsTable("Sessions [Table View]") 
        sessionsGraph = SessionsTable("Sessions [Graph View]")
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

        igShowDemoWindow(nil)

        # render
        app.render()

        if not showConquest: 
            app.handle.setWindowShouldClose(true)

when isMainModule:
    main()
