import ./utils/appImGui

proc main() = 
    var app = createApp(1024, 800, imnodes = true, title = "Conquest", docking = true)
    defer: app.destroyApp()

    var showConquest = true

    let io = igGetIO()

    # main loop
    while not app.handle.windowShouldClose:
        pollEvents()

        if app.isIconifySleep():
            continue 
        newFrame()

        # Create fullscreen dockspace as the base where all other windows are placed in 
        block:
            var 
                windowClass = ImGuiWindowClass_ImGuiWindowClass()
                dockspaceFlags: ImGuiDockNodeFlags = ImGuiDockNodeFlags_None.int32
                windowFlags: ImGuiWindow_Flags = ImGuiWindowFlags_MenuBar.int32 or ImGuiWindowFlags_NoDocking.int32
            
            var vp = igGetMainViewport()
            igSetNextWindowPos(vp.WorkPos, ImGui_Cond_None.int32, vec2(0.0f, 0.0f))
            igSetNextWindowSize(vp.WorkSize, 0)
            igSetNextWindowViewport(vp.ID)
            igPushStyleVar_Float(ImGuiStyleVar_WindowRounding.int32, 0.0f)
            igPushStyleVar_Float(ImGuiStyleVar_WindowBorderSize.int32, 0.0f)
            windowFlags = windowFlags or (
                ImGuiWindowFlags_NoTitleBar.int32 or 
                ImGuiWindowFlags_NoCollapse.int32 or 
                ImGuiWindowFlags_NoResize.int32 or
                ImGuiWindowFlags_NoMove.int32 or
                ImGuiWindowFlags_NoBringToFrontOnFocus.int32 or 
                ImGuiWindowFlags_NoNavFocus.int32
            )

            # Add padding
            igPushStyleVar_Vec2(ImGuiStyleVar_WindowPadding.int32, vec2(0.0f, 0.0f))

            igBegin("Conquest", addr showConquest, windowFlags)
            defer: igEnd()  

            igPopStyleVar(3)

            # Create dockspace
            igDockSpace(igGetID_Str("Conquest-Dockspace"), vec2(0.0f, 0.0f), dockspaceFlags, windowClass)

            # Create Dockspace menu bar
            if igBeginMenuBar(): 
                if igBeginMenu("Options", true):

                    if igMenuItem("Exit", nil, false, (addr showConquest) != nil):
                        showConquest = false
                    igEndMenu() 
                igEndMenuBar()


        # Components and widgets
        igShowDemoWindow(nil)

        block: 
            igBegin("Info Window", nil, 0)
            defer: igEnd() 

            igText(cstring(ICON_FA_USER_SHIELD & " " & getFrontendVersionString()))

        # render
        app.render()

        if not showConquest: 
            app.handle.setWindowShouldClose(true)

when isMainModule:
    main()
