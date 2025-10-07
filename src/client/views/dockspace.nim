import tables, strutils
import imguin/[cimgui, glfw_opengl, simple]
import ../utils/appImGui

type 
    DockspaceComponent* = ref object of RootObj
        windowClass: ptr ImGuiWindowClass
        dockspaceFlags: ImGuiDockNodeFlags
        windowFlags: ImGuiWindow_Flags
        initialized: bool

proc Dockspace*(): DockspaceComponent = 
    result = new DockspaceComponent
    result.windowClass = ImGuiWindowClass_ImGuiWindowClass()
    result.dockspaceFlags = ImGuiDockNodeFlags_None.int32
    result.windowFlags =  ImGuiWindowFlags_MenuBar.int32 or ImGuiWindowFlags_NoDocking.int32
    result.initialized = false

proc draw*(component: DockspaceComponent, showComponent: ptr bool, views: Table[string, ptr bool], dockTop, dockBottom, dockTopLeft, dockTopRight: ptr ImGuiID) = 

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

    # Setup default docking layout
    var dockspaceId = igGetID_Str("Dockspace")
    
    if not component.initialized:
        if igDockBuilderGetNode(dockspaceId) == nil:  
            igDockBuilderRemoveNode(dockspaceId)
            igDockBuilderAddNode(dockspaceId, ImGuiDockNodeFlags_DockSpace.int32)
            igDockBuilderSetNodeSize(dockspaceId, vp.WorkSize)

            discard igDockBuilderSplitNode(dockspaceId, ImGuiDir_Down, 5.0f, dockBottom, dockTop)
            discard igDockBuilderSplitNode(dockTop[], ImGuiDir_Right, 0.5f, dockTopRight, dockTopLeft)

            igDockBuilderDockWindow("Sessions [Table View]", dockTopLeft[])
            igDockBuilderDockWindow("Listeners", dockBottom[])
            igDockBuilderDockWindow("Eventlog", dockTopRight[])
            igDockBuilderDockWindow("Downloads", dockBottom[])
            igDockBuilderDockWindow("Screenshots", dockBottom[])
            igDockBuilderDockWindow("Dear ImGui Demo", dockTopRight[])
            
            igDockBuilderFinish(dockspaceId)
            component.initialized = true

    # Create dockspace
    igDockSpace(dockspaceId, vec2(0.0f, 0.0f), component.dockspaceFlags, component.windowClass)

    # Create menu bar
    if igBeginMenuBar(): 
        if igBeginMenu("Options", true):
            if igMenuItem("Exit", nil, false, (addr showComponent) != nil):
                showComponent[] = false
            igEndMenu() 
        
        if igBeginMenu("Views", true): 
            # Create a menu item to toggle each of the main views of the application
            for view, showView in views: 
                if not view.startsWith("Loot:"):
                    if igMenuItem(view, nil, showView[], showView != nil):
                        showView[] = not showView[]        
                
            if igBeginMenu("Loot", true):
                for view, showView in views: 
                    if view.startsWith("Loot:"):
                        let itemName = view.split(":")[1]
                        if igMenuItem(itemName, nil, showView[], showView != nil):
                            showView[] = not showView[]        
                igEndMenu()

            igEndMenu()

        igEndMenuBar()