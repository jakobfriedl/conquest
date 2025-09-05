import os, strformat
import imguin/[cimgui, simple]

import ./globals
import ../utils/fonticon/IconsFontAwesome6
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
                ("segoeui.ttf", "Seoge UI", 14.4), 
            ]
        )
else: # For Debian/Ubuntu/Mint
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
    result.MergeMode = false
    result.EllipsisChar = cast[ImWchar](-1)

proc setupFonts*(): (bool, string, string) =
    let pio = igGetIO()
    var config {.global.} = new_ImFontConfig()

    # Load first base font
    result = (false, "Default", "ProggyClean.ttf")
    var seqFontNames: seq[(string, string)]
    for (fontName, fontTitle, point) in fontInfo.fontTable:
        let fontFullPath = os.joinPath(fontInfo.osRootDir, fontInfo.fontDir, fontName)
        if os.fileExists(fontFullPath):
            seqFontNames.add((fontName, fontTitle))
            pio.Fonts.ImFontAtlas_AddFontFromFileTTF(fontFullPath.cstring, point.point2px, nil, nil)
            break
    
    if seqFontNames.len > 0:
        result = (true, seqFontNames[0][0].extractFilename, seqFontNames[0][1])
    else:
        pio.Fonts.ImFontAtlas_AddFontDefault(nil)

    # Merge Icon font
    config.MergeMode = true
    var ranges_icon_fonts {.global.} = [ICON_MIN_FA.uint16, ICON_MAX_FA.uint16, 0]
    if os.fileExists(IconfontFullPath):
        pio.Fonts.ImFontAtlas_AddFontFromFileTTF(IconfontFullPath.cstring, 11.point2px, addr config, addr ranges_icon_fonts[0])
    else:
        echo "Error!: Can't find Icon fonts: ", IconfontFullPath