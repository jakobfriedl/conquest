import std/[os,strutils]
import nimgl/[opengl]
import stb_image/write as stbiw

# saveImage
proc saveImage*(fname:string, xs, ys, width, height:int, comp:int = RGB,quality:int = 90) =
    # Image size must be 2*n
    let imageWidth = (width div 2) * 2
    let imageHeight = (height div 2) * 2
    if not (comp == RGB):
        echo "Error!: Color component numbers must be 3 (RGB) at saveImage.nim"
        return
    if 1 > imageWidth or 1 > imageHeight :
        echo "Error!: Rect of save image is mismatch at saveImage.nim"
        return

    var
        texBuffer =    newSeq[GLuByte](imageWidth * imageHeight * comp)
        dataBuffer = newSeq[GLuByte](imageWidth * imageHeight * comp)

    glReadBuffer( GL_BACK )
    glReadPixels( xs.GLint, ys.GLint,
                                imageWidth.GLsizei, imageHeight.GLsizei,
                                GL_RGB,
                                GL_UNSIGNED_BYTE,
                                texBuffer[0].addr
                                )

    # Set upside-down
    let widthStep = 3 * imageWidth
    var n = 0
    for y in 0..<imageHeight:
        for x in 0..<imageWidth:
            dataBuffer[ ( imageHeight - y - 1 ) * widthStep + (x * 3) + 0 ] = texBuffer[n + 0] # copy R
            dataBuffer[ ( imageHeight - y - 1 ) * widthStep + (x * 3) + 1 ] = texBuffer[n + 1] # copy G
            dataBuffer[ ( imageHeight - y - 1 ) * widthStep + (x * 3) + 2 ] = texBuffer[n + 2] # copy B
            inc(n,3)

    # Save image
    var
        (_,_,ext) = fname.splitfile()
        res:bool
    case ext.toLowerAscii()
        of ".jpg",".jpeg":
            # JPEG quality is 90% default. quality=1..100
            res = stbiw.writeJPG(fname, imageWidth, imageHeight, comp, dataBuffer, quality)
        of ".png":
            res = stbiw.writePNG(fname, imageWidth, imageHeight, comp, dataBuffer)
        of ".bmp":
            res = stbiw.writeBMP(fname, imageWidth, imageHeight, comp, dataBuffer)
        of ".tga":
            # if quality == 0 then useRLE == false.
            res = stbiw.writeTGA(fname, imageWidth, imageHeight, comp, dataBuffer, useRLE = (quality > 0))
        else:
            echo "Error! Unrecognize image extension: [",ext,"]"
            res = false
    if not res:
        echo "Error!: at stbiw.writeNNN() function in saveImage.nim"
