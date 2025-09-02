import os
import nimgl/[opengl, glfw]
import imguin/glfw_opengl
import ./lib

const CONQUEST_ROOT* {.strdefine.} = ""

when defined(windows):
    when not defined(vcc):     # imguinVcc.res TODO WIP
        include ./res/resource
    import tinydialogs

# Forward definitions
proc windowInit*(winMain: proc(win: glfw.GLFWWindow)) =
    doAssert glfwInit()
    defer: glfwTerminate()

    glfwWindowHint(GLFWContextVersionMajor, 3)
    glfwWindowHint(GLFWContextVersionMinor, 3)
    glfwWindowHint(GLFWOpenglForwardCompat, GLFW_TRUE)
    glfwWindowHint(GLFWOpenglProfile, GLFW_OPENGL_CORE_PROFILE)
    glfwWindowHint(GLFWResizable, GLFW_TRUE)
    glfwWindowHint(GLFWVisible, GLFW_FALSE)
    glfwWindowHint(GLFWMaximized, GLFW_TRUE) # Maximize Window on startup 

    var glfwWin = glfwCreateWindow(1024, 800, "Conquest")
    if glfwWin.isNil:
        quit(-1)
    
    glfwWin.makeContextCurrent()
    defer: glfwWin.destroyWindow()

    glfwSwapInterval(1) # Enable vsync

    # TODO: Set application icon (requires imguin_examples/utils/loadImage [https://github.com/dinau/imguin_examples/blob/main/utils/opengl/loadImage.nim])
    # var IconName = joinPath(CONQUEST_ROOT, "src/client/resources/icon.png")
    # LoadTileBarIcon(glfwWin, IconName)
    
    doAssert glInit() # OpenGL init

    # Setup ImGui
    let context = igCreateContext(nil)
    defer: context.igDestroyContext()
    
    # Configure docking
    var pio = igGetIO()
    pio.ConfigFlags = pio.ConfigFlags or ImGui_ConfigFlags_DockingEnable.int32

    # GLFW + OpenGL
    const glsl_version = "#version 130" # GL 3.0 + GLSL 130
    doAssert ImGui_ImplGlfw_InitForOpenGL(cast[ptr GLFWwindow](glfwwin), true)
    defer: ImGui_ImplGlfw_Shutdown()
    doAssert ImGui_ImplOpenGL3_Init(glsl_version)
    defer: ImGui_ImplOpenGL3_Shutdown()

    # Set ini filename
    pio.IniFileName = CONQUEST_ROOT & "/data/layout.ini"

    glfwWin.winMain()

    

