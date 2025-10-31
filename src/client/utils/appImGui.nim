import os, strutils, strformat
import nimgl/[opengl, glfw]
export opengl, glfw

import imguin/[cimgui, glfw_opengl, simple]
export cimgui, glfw_opengl, simple

import ./globals
import ./opengl/loadImage
export loadImage
import ./[saveImage, setupFonts, utils, vecs]
export saveImage, setupFonts, utils, vecs

proc glfwGetPlatform*(): int32 {.importc: "glfwGetPlatform".} # GLFW 3.4 >=

type
    IniData = object
        clearColor*: ccolor
        startupPosX*, startupPosY*: cint
        viewportWidth*, viewportHeight*: cint
        imageSaveFormatIndex*: int
        theme: Theme

    Window* = object
        handle*: glfw.GLFWwindow
        context*: ptr ImGuiContext
        imnodes*: bool
        implot*: bool
        implot3d*: bool
        implotContext: ptr ImPlotContext
        implot3dContext: ptr ImPlot3dContext
        showWindowDelay: int
        ini*: IniData

# Forward definitions
proc setTheme*(this: var Window, theme: Theme): string

# Main setup function
proc createApp*(w: cint = 1024, h: cint = 900, imnodes: bool = false, implot: bool = false, implot3d = false, title: string = "ImGui window", docking: bool = true): Window =
    doAssert glfwInit()
    # result.loadIni()
    result.ini.viewportWidth = w
    result.ini.viewportHeight = h
    result.implot = implot
    result.implot3d = implot3d
    result.imnodes = imnodes

    if result.implot3d:
        result.implot = true

    var
        fDocking = docking
        fViewport = false
        transparentViewport = false
    
    block:
        if transparentViewport:
            fViewport = true
        if fViewport:
            fDocking = true

    var glfwWin: GLFWwindow
    var glsl_version: string
    
    when defined(windows):
        const versions = [[4, 4], [4, 3], [4, 2], [4, 1], [4, 0], [3, 3]]
    else:
        const versions = [[3, 3]]

    for ver in versions:
        let
            major = ver[0].int32
            minor = ver[1].int32
        if transparentViewport:
            glfwWindowHint(GLFWVisible, GLFW_FALSE)
        
        glfwWindowHint(GLFWContextVersionMajor, major)
        glfwWindowHint(GLFWContextVersionMinor, minor)
        glfwWindowHint(GLFWOpenglForwardCompat, GLFW_TRUE)
        glfwWindowHint(GLFWOpenglProfile, GLFW_OPENGL_CORE_PROFILE)
        glfwWindowHint(GLFWResizable, GLFW_TRUE)
        glfwWindowHint(GLFWVisible, GLFW_FALSE)
        glfwWindowHint(GLFWMaximized, GLFW_TRUE)

        glfwWin = glfwCreateWindow(result.ini.viewportWidth, result.ini.viewportHeight, title = title)
        glsl_version = fmt"#version {major * 100 + minor * 10}"
        
        if not glfwWin.isNil:
            break

    if glfwWin.isNil:
        quit(-1)
    
    glfwWin.makeContextCurrent()
    setWindowPos(glfwWin, result.ini.startupPosX, result.ini.startupPosY)
    glfwSwapInterval(1) # Enable vsync

    # Load title bar icon
    var iconName = os.joinPath(fmt"{CONQUEST_ROOT}/src/client/resources/icon.png")
    LoadTileBarIcon(glfwWin, iconName)

    doAssert glInit() # OpenGL init

    # Setup ImGui
    result.context = igCreateContext(nil)

    if result.imnodes: # setup ImNodes
        when defined(ImNodesEnable):
            imnodes_CreateContext()

    if result.implot: # setup ImPlot
        when defined(ImPlotEnable) or defined(ImPlot) or defined(ImPlot3DEnable) or defined(ImPlot3D):
            result.imPlotContext = ImPlot_CreateContext()
        else:
            echo "Fatal Error!: setup ImPlot: Specify option -d:ImPlot"
            quit 1

    if result.implot3d: # setup ImPlot3D
        when defined(ImPlot3DEnable) or defined(ImPlot3D):
            result.imPlot3dContext = ImPlot3d_CreateContext()
        else:
            echo "Fatal Error!: setup ImPlot3D: Specify option -d:ImPlot3DEnable"
            quit 1

    if fDocking:
        var pio = igGetIO()
        pio.ConfigFlags = pio.ConfigFlags or ImGui_ConfigFlags_DockingEnable.cint
        if fViewport:
            pio.ConfigFlags = pio.ConfigFlags or ImGui_ConfigFlags_ViewportsEnable.cint
            pio.ConfigViewports_NoAutomerge = true

    # GLFW + OpenGL
    doAssert ImGui_ImplGlfw_InitForOpenGL(cast[ptr GLFWwindow](glfwwin), true)
    doAssert ImGui_ImplOpenGL3_Init(glsl_version.cstring)

    if transparentViewport:
        result.ini.clearColor = ccolor(elm:(x:0f, y:0f, z:0f, w:0.0f)) # Transparent
    result.handle = glfwWin
    
    var pio = igGetIO()
    pio.IniFileName = fmt"{CONQUEST_ROOT}/src/client/layout.ini".cstring
    setTheme(Dark)
    discard setupFonts() 
    result.showWindowDelay = 2

# pollEvents
proc pollEvents*() =
    glfwPollEvents()

# isIconifySleep
proc isIconifySleep*(win: Window): bool =
    if getWindowAttrib(win.handle, GLFW_ICONIFIED) != 0:
        ImGui_ImplGlfw_Sleep(10)
        return true

# render
proc render*(window: var Window) =
    igRender()
    glClearColor(window.ini.clearColor.elm.x, window.ini.clearColor.elm.y, window.ini.clearColor.elm.z, window.ini.clearColor.elm.w)
    glClear(GL_COLOR_BUFFER_BIT)
    ImGui_ImplOpenGL3_RenderDrawData(igGetDrawData())

    var pio = igGetIO()
    if 0 != (pio.ConfigFlags and ImGui_ConfigFlags_ViewportsEnable.cint):
        var backup_current_window = glfwGetCurrentContext()
        igUpdatePlatformWindows()
        igRenderPlatformWindowsDefault(nil, nil)
        backup_current_window.makeContextCurrent()

    window.handle.swapBuffers()
    
    if window.showWindowDelay > 0:
        dec window.showWindowDelay
    else:
        once: # Avoid flickering screen at startup.
            window.handle.showWindow()

# Cleanup
proc destroyApp*(window: var Window) =
    # window.saveIni()
    ImGui_ImplOpenGL3_Shutdown()
    ImGui_ImplGlfw_Shutdown()

    when defined(ImPlotEnable) or defined(ImPlot):
        if window.implot:
            window.imPlotContext.ImPlotDestroyContext()
    
    when defined(ImPlot3DEnable) or defined(ImPlot3D):
        if window.implot3d:
            window.implot3dContext.ImPlot3dDestroyContext()
    
    when defined(ImNodesEnable):
        if window.imnodes:
            imnodes_DestroyContext(nil)
            
    window.context.igDestroyContext()
    window.handle.destroyWindow()
    glfwTerminate()

# newFrame
proc newFrame*() =
    ImGui_ImplOpenGL3_NewFrame()
    ImGui_ImplGlfw_NewFrame()
    igNewFrame()

proc getFrontendVersionString*(): string =
    fmt"GLFW v{$glfwGetVersionString()}"

proc getBackendVersionString*(): string =
    fmt"OpenGL v{($cast[cstring](glGetString(GL_VERSION))).split[0]} (Backend)"

# setClearColor
proc setClearColor*(win: var Window, col: ccolor) =
    win.ini.clearColor = col

# free
proc free*(mem: pointer) {.importc, header:"<stdlib.h>".}

# setTheme
proc setTheme*(this: var Window, theme: Theme): string =
    this.ini.theme = theme
    utils.setTheme(theme)
    return $theme

# getTheme
proc getTheme*(this: Window): Theme =
    return this.ini.theme

# getThemeLabel
proc getThemeLabel*(this: Window): string =
    return $this.ini.theme