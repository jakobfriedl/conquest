import nimgl/[opengl, glfw]
import imguin/glfw_opengl
import ./utils/[lib, windowInit]

proc main(hWin: glfw.GLFWWindow) = 
    var
        clearColor: CColor
        showWindowDelay = 1 
        showMainWindow = true
        windowClass = ImGuiWindowClass_ImGuiWindowClass()
        opt_fullscreen: bool = true 
        opt_padding: bool = false
        dockspaceFlags: ImGuiDockNodeFlags = ImGuiDockNodeFlags_None.int32
        windowFlags: ImGuiWindow_Flags = ImGuiWindowFlags_MenuBar.int32 or ImGuiWindowFlags_NoDocking.int32

    # Setup background and theme colors (Background is only seen when opt_padding = true)
    clearColor = CColor(elm:(x:0.0f, y:0.0f, z:0.0f, w:0.0f))
    igStyleColorsClassic(nil)

    # Setup fonts
    discard setupFonts()

    let io = igGetIO()

    # main loop
    while not hWin.windowShouldClose:
        glfwPollEvents()

        if getWindowAttrib(hWin, GLFW_ICONIFIED) != 0:
            ImGui_ImplGlfw_Sleep(10)
            continue

        # Start ImGUI frame
        ImGui_ImplOpenGL3_NewFrame()
        ImGui_ImplGlfw_NewFrame()
        igNewFrame()

        # Create Dockspace where all windows are placed in
        if opt_fullscreen: 
            var vp = igGetMainViewport()
            igSetNextWindowPos(vp.WorkPos, ImGui_Cond_None.int32, vec2(0.0f, 0.0f))
            igSetNextWindowSize(vp.WorkSize, 0)
            igSetNextWindowViewport(vp.ID)
            igPushStyleVar_Float(ImGuiStyleVar_WindowRounding.int32, 0.0f)
            igPushStyleVar_Float(ImGuiStyleVar_WindowBorderSize.int32, 0.0f)

            windowFlags = windowFlags or ImGuiWindowFlags_NoTitleBar.int32 or ImGuiWindowFlags_NoCollapse.int32 or ImGuiWindowFlags_NoResize.int32 or ImGuiWindowFlags_NoMove.int32
            windowFlags = windowFlags or ImGuiWindowFlags_NoBringToFrontOnFocus.int32 or ImGuiWindowFlags_NoNavFocus.int32

        else: 
            dockspaceFlags = cast[ImGuiDockNodeFlags](dockspaceFlags and not ImGuiDockNodeFlags_PassthruCentralNode.int32)

        if (dockspaceFlags and ImGuiDockNodeFlags_PassthruCentralNode.int32) == ImGuiDockNodeFlags_None.int32: 
            windowFlags = cast[ImGuiWindow_Flags](windowFlags or ImGuiWindowFlags_NoBackground.int32)
        
        if not opt_padding: 
            igPushStyleVar_Vec2(ImGuiStyleVar_WindowPadding.int32, vec2(0.0f, 0.0f))

        igBegin("Conquest", addr showMainWindow, windowFlags)

        if not opt_padding: 
            igPopStyleVar(1)

        if opt_fullscreen: 
            igPopStyleVar(2)

        # Create dockspace
        if (io.ConfigFlags and ImGui_ConfigFlags_DockingEnable.int32) != ImGui_ConfigFlags_None.int32:
            igDockSpace(igGetID_Str("Conquest-Dockspace"), vec2(0.0f, 0.0f), dockspaceFlags, windowClass)

        # Create Dockspace menu bar
        if igBeginMenuBar(): 
            if igBeginMenu("Options", true):

                igMenuItem("Fullscreen", nil, addr opt_fullscreen, true)
                igMenuItem("Padding", nil, addr opt_padding, true)

                if igMenuItem("Close", nil, false, (addr showMainWindow) != nil):
                    showMainWindow = false
                igEndMenu() 
            igEndMenuBar()

        # Components and widgets
        igShowDemoWindow(nil)

                
        

        igEnd()

        # render
        igRender()
        glClearColor(clearColor.elm.x, clearColor.elm.y, clearColor.elm.z, clearColor.elm.w)
        glClear(GL_COLOR_BUFFER_BIT)
        ImGui_ImplOpenGL3_RenderDrawData(igGetDrawData())

        if 0 != (io.ConfigFlags and ImGui_ConfigFlags_ViewportsEnable.int32):
            var backup_current_window = glfwGetCurrentContext()
            igUpdatePlatformWindows()
            igRenderPlatformWindowsDefault(nil, nil)
            backup_current_window.makeContextCurrent()

        hWin.swapBuffers()

        if showWindowDelay > 0:
            dec showWindowDelay
        else:
            once: # Avoid flickering screen at startup.
                hWin.showWindow()

when isMainModule:
    windowInit(main)
