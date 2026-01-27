import strutils, strformat, tables
import imguin/cimgui
import ../../types/[common, client]

type
    Vec2* = ImVec2
    Vec4* = ImVec4

proc vec2*(x, y: auto): ImVec2 =
    ImVec2(x: x.cfloat, y: y.cfloat)

proc vec4*(x, y, z, w: auto): ImVec4 =
    ImVec4(x: x.cfloat , y: y.cfloat , z: z.cfloat , w: w.cfloat)

#---------------
#--- setTooltip
#---------------
proc setTooltip*(str:string, delay=Imgui_HoveredFlags_DelayNormal.cint, color=ImVec4(x: 1.0, y: 1.0, z: 1.0, w: 1.0)) =
    if igIsItemHovered(delay):
        if igBeginTooltip():
            igPushStyleColorVec4(ImGuiCol_Text.cint, color)
            igText(str)
            igPopStyleColor(1)
            igEndTooltip()

type
    Theme* = enum
        Light, Dark, Classic

# setTheme
proc setTheme*(themeName: Theme) =
    case themeName
    of Light:
        igStyleColorsLight(nil)
    of Dark:
        igStyleColorsDark(nil)
    of Classic:
        igStyleColorsClassic(nil)

# IM_COL32
proc IM_COL32*(a,b,c,d:uint32): ImU32    =
    return igGetColorU32_Vec4(vec4(a.cfloat/255, b.cfloat/255, c.cfloat/255, d.cfloat/255))

# Modules
proc parseModuleType*(moduleName: string): ModuleType =
    case moduleName.toLower()
    of "shell": return MODULE_SHELL
    of "bof": return MODULE_BOF
    of "dotnet": return MODULE_DOTNET
    of "filesystem": return MODULE_FILESYSTEM
    of "filetransfer": return MODULE_FILETRANSFER
    of "screenshot": return MODULE_SCREENSHOT
    of "systeminfo": return MODULE_SYSTEMINFO
    of "token": return MODULE_TOKEN
    else: discard

proc getModules*(component: ModuleManagerComponent, modules: uint32 = 0): seq[Module] = 
    for _, module in component.modules: 
        if not module.builtin and (modules == 0 or (modules and cast[uint32](parseModuleType(module.name))) != 0):
            result.add(module)

proc getModulesBuiltin*(component: ModuleManagerComponent): seq[Module] = 
    for _, module in component.modules: 
        if module.builtin:
            result.add(module)

proc getCommandsTable*(component: ModuleManagerComponent, modules: uint32 = 0): Table[string, Command] = 
    result = initTable[string, Command]() 
    let modules = component.getModulesBuiltin() & component.getModules(modules)
    for _, module in modules: 
        for cmd in module.commands: 
            result[cmd.name] = cmd

proc getCommands*(component: ModuleManagerComponent, modules: uint32 = 0): seq[Command] = 
    let modules = component.getModulesBuiltin() & component.getModules(modules)
    for _, module in modules: 
        result.add(module.commands)

proc getCommand*(component: ModuleManagerComponent, name: string): Command = 
    try: 
        let commands = component.getCommandsTable()
        return commands[name]
    except ValueError:
        raise newException(ValueError, fmt"The command '{name}' does not exist.")

proc getCommandGroups*(component: ModuleManagerComponent, modules: uint32 = 0): OrderedTable[string, seq[Command]] = 
    result = initOrderedTable[string, seq[Command]]() 
    let modules = component.getModulesBuiltin() & component.getModules(modules)

    for module in modules: 
        if not result.hasKey(module.group):
            result[module.group] = @[]
        result[module.group].add(module.commands)
