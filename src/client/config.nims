switch "o", "bin/client"

switch "d", "ssl"
switch "d", "client"
switch "d", "ImGuiTextSelect"
switch "d", "ImPlotEnable"

# Select compiler
var TC = "gcc"                
# var TC = "clang"             

# Dismiss background window
switch "app", "gui"

# Select static link or shared/dll link
when defined(windows):
    const STATIC_LINK_GLFW = false
    const STATIC_LINK_CC = false            #libstd++ or libc
    if TC == "vcc":
        switch "passL","d3d9.lib kernel32.lib user32.lib gdi32.lib winspool.lib"
        switch "passL","comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib"
        switch "passL","uuid.lib odbc32.lib odbccp32.lib"
        switch "passL","imm32.lib"
    else:
        switch "passL","-lgdi32 -limm32 -lcomdlg32 -luser32 -lshell32"
else: # for Linux
    const STATIC_LINK_GLFW = true
    const STATIC_LINK_CC= false

when STATIC_LINK_GLFW: # GLFW static link
    switch "define","glfwStaticLib"
    when defined(windows):
        discard  # Windows-specific handling if needed
    else:  # Linux
        switch "passL","-lglfw"
        switch "passL","-lX11"
        switch "passL","-lXrandr"
        switch "passL","-lXinerama"
        switch "passL","-lXcursor"
        switch "passL","-lXi"
        switch "passL","-lpthread"
        switch "passL","-ldl"
        switch "passL","-lm"
else: # shared/dll
    when defined(windows):
        if TC == "vcc":
            discard
        else:
            switch "passL","-lglfw3.dll"
            switch "define", "glfwDLL"
            #switch "define","cimguiDLL"
    else:
        switch "passL","-lglfw"
        # Add X11 libs for shared linking too
        switch "passL","-lX11"

when STATIC_LINK_CC: # gcc static link
    case TC
        of "vcc":
            discard
        else:
            switch "passC", "-static"
            switch "passL", "-static "

# Set compiler options
case TC
    of "vcc" , "clang_cl":
        switch "define","lto"
    else:
        if "" == findExe(TC): # GCC is default compiler if TC dosn't exist on the PATH
            echo "#### Set to cc = ",TC
            TC = "gcc"
        if "" == findExe(TC): # if gcc dosn't exist, try clang
            TC = "clang"
            echo "#### Set to cc = ",TC

# Reduce code size further
when false:
    switch "gc", "arc"
    switch "define", "useMalloc"
    switch "define", "noSignalHandler"

case TC
    of "gcc":
        switch "passC", "-ffunction-sections"
        switch "passC", "-fdata-sections"
        switch "passL", "-Wl,--gc-sections"
        switch "cc",TC
    of "clang":
        switch "cc.exe","clang"
        switch "cc.linkerexe","clang"
        switch "cc",TC

