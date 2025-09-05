import tables
import ./utils/appImGui
import ./views/[dockspace, agents]

proc main() = 
    var app = createApp(1024, 800, imnodes = true, title = "Conquest", docking = true)
    defer: app.destroyApp()

    var 
        views: Table[string, ptr bool]
        showConquest = true
        showAgentsTable = true
        showAgentsGraph = false
        
    views["Agents [Table View]"] = addr showAgentsTable 
    views["Agents [Graph View]"] = addr showAgentsGraph

    let io = igGetIO()

    # main loop
    while not app.handle.windowShouldClose:
        pollEvents()

        # Reduce rendering activity when window is minimized 
        if app.isIconifySleep():
            continue 
        newFrame()

        # UI components
        Dockspace().draw(addr showConquest, views)
        
        if showAgentsTable: 
            AgentsTable("Agents [Table View]").draw(addr showAgentsTable)   

        if showAgentsGraph: 
            AgentsTable("Agents [Graph View]").draw(addr showAgentsGraph)   


        igShowDemoWindow(nil)

        # render
        app.render()

        if not showConquest: 
            app.handle.setWindowShouldClose(true)

when isMainModule:
    main()
