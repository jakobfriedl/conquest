import os, strformat, strutils, osproc
import imguin/[cimgui, simple]

import ./globals
import ./fonticon/IconsFontAwesome6
export IconsFontAwesome6

let IconfontFullPath = fmt"{CONQUEST_ROOT}/src/client/utils/fonticon/fa6/fa-solid-900.ttf"

# Convert point to pixel
proc point2px*(point: float32): cfloat = ((point * 96) / 72).cfloat

# setupFonts
type
    TFontInfo = object
        fontDir, osRootDir: string
        fontTable: seq[(string, string, float)] # path, name, point

when defined(windows):
    const
        fontInfo = TFontInfo(
            osRootDir: os.getEnv("windir"), # get OS root
            fontDir: "fonts",
            fontTable: @[ #
                ("segoeui.ttf", "Seoge UI", 20.0),
            ]
        )
else: # Linux
    const
        fontInfo = TFontInfo(
            osRootDir: "/",
            fontDir: "usr/share/fonts",
            fontTable: @[
                ("truetype/noto/NotoSansMono-Regular.ttf", "Noto Sans Mono", 20.0)
            ]
        )

proc new_ImFontConfig(): ImFontConfig =
    # Custom constructor with default params taken from imgui.h
    result.FontDataOwnedByAtlas = true
    result.FontNo = 0
    result.OversampleH = 3
    result.OversampleV = 1
    result.PixelSnapH = false
    result.GlyphMaxAdvanceX = float.high
    result.RasterizerMultiply = 1.0
    result.RasterizerDensity = 1.0
    result.ExtraSizeScale = 1.0 # Required for icons since Imgui 1.92.7.0
    result.MergeMode = false
    result.EllipsisChar = cast[ImWchar](-1)

when not defined(windows):
    proc resolveSystemFont(): tuple[path: string, family: string] =
        let f = getEnv("CONQUEST_FONT")
        if f.len > 0 and fileExists(f):
            return (f, f.extractFilename.changeFileExt(""))
        try:
            let (output, exitCode) = execCmdEx("fc-match monospace -f '%{file}\n%{family}'")
            if exitCode == 0:
                let lines = output.strip().splitLines()
                if lines.len >= 1 and fileExists(lines[0]):
                    let family = if lines.len >= 2: lines[1] else: lines[0].extractFilename
                    return (lines[0], family)
        except CatchableError:
            discard
        return ("", "")

proc setupFonts*(): (bool, string, string) =
    let pio = igGetIO()
    var config {.global.} = new_ImFontConfig()

    # Load first base font
    result = (false, "Default", "ProggyClean.ttf")
    var seqFontNames: seq[(string, string)]

    when not defined(windows):
        let (sysPath, sysFamily) = resolveSystemFont()
        if sysPath.len > 0:
            seqFontNames.add((sysPath.extractFilename, sysFamily))
            pio.Fonts.ImFontAtlas_AddFontFromFileTTF(sysPath.cstring, 20.0.point2px, nil, nil)

    if seqFontNames.len == 0:
        for (fontName, fontTitle, point) in fontInfo.fontTable:
            let fontFullPath = os.joinPath(fontInfo.osRootDir, fontInfo.fontDir, fontName)
            if os.fileExists(fontFullPath):
                seqFontNames.add((fontName, fontTitle))
                pio.Fonts.ImFontAtlas_AddFontFromFileTTF(fontFullPath.cstring, point.point2px, nil, nil)
                break

    if seqFontNames.len > 0:
        result = (true, seqFontNames[0][0].extractFilename, seqFontNames[0][1])
    else:
        var defaultConfig = new_ImFontConfig()
        defaultConfig.SizePixels = 20.0.point2px
        pio.Fonts.ImFontAtlas_AddFontDefault(addr defaultConfig)

    # Merge Icon font
    config.MergeMode = true
    var ranges_icon_fonts {.global.} = [ICON_MIN_FA.uint16, ICON_MAX_FA.uint16, 0]
    if os.fileExists(IconfontFullPath):
        pio.Fonts.ImFontAtlas_AddFontFromFileTTF(IconfontFullPath.cstring, 11.point2px, addr config, addr ranges_icon_fonts[0])
    else:
        echo "Error!: Can't find Icon fonts: ", IconfontFullPath
