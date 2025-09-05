import tables
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/appImGui

type 
    DockspaceComponent* = ref object of RootObj
        windowClass: ptr ImGuiWindowClass
        dockspaceFlags: ImGuiDockNodeFlags
        windowFlags: ImGuiWindow_Flags

proc Dockspace*(): DockspaceComponent = 
    result = new DockspaceComponent
    result.windowClass = ImGuiWindowClass_ImGuiWindowClass()
    result.dockspaceFlags = ImGuiDockNodeFlags_None.int32
    result.windowFlags =  ImGuiWindowFlags_MenuBar.int32 or ImGuiWindowFlags_NoDocking.int32

proc draw*(component: DockspaceComponent, showComponent: ptr bool, views: Table[string, ptr bool]) = 

    var vp = igGetMainViewport()
    igSetNextWindowPos(vp.WorkPos, ImGui_Cond_None.int32, vec2(0.0f, 0.0f))
    igSetNextWindowSize(vp.WorkSize, 0)
    igSetNextWindowViewport(vp.ID)
    igPushStyleVar_Float(ImGuiStyleVar_WindowRounding.int32, 0.0f)
    igPushStyleVar_Float(ImGuiStyleVar_WindowBorderSize.int32, 0.0f)
    component.windowFlags = component.windowFlags or (
        ImGuiWindowFlags_NoTitleBar.int32 or 
        ImGuiWindowFlags_NoCollapse.int32 or 
        ImGuiWindowFlags_NoResize.int32 or
        ImGuiWindowFlags_NoMove.int32 or
        ImGuiWindowFlags_NoBringToFrontOnFocus.int32 or 
        ImGuiWindowFlags_NoNavFocus.int32
    )

    # Add padding
    igPushStyleVar_Vec2(ImGuiStyleVar_WindowPadding.int32, vec2(10.0f, 10.0f))

    igBegin("Dockspace", showComponent, component.windowFlags)
    defer: igEnd()  

    igPopStyleVar(3)

    # Create dockspace
    igDockSpace(igGetID_Str("Dockspace"), vec2(0.0f, 0.0f), component.dockspaceFlags, component.windowClass)

    # Create menu bar
    if igBeginMenuBar(): 
        if igBeginMenu("Options", true):
            if igMenuItem("Exit", nil, false, (addr showComponent) != nil):
                showComponent[] = false
            igEndMenu() 
        
        if igBeginMenu("Views", true): 
            # Create a menu item to toggle each of the main views of the application
            for view, showView in views: 
                if igMenuItem(view, nil, showView[], showView != nil):
                    showView[] = not showView[]
            igEndMenu()

        igEndMenuBar()