import imguin/[cimgui, glfw_opengl, simple]
import ../utils/appImGui

# https://rgbcolorpicker.com/0-1
const CONSOLE_ERROR* = vec4(0.878f, 0.188f, 0.149f, 1.0f)
const CONSOLE_INFO* = vec4(0.588f, 0.843f, 0.89f, 1.0f)
const CONSOLE_SUCCESS* = vec4(0.176f, 0.569f, 0.075f, 1.0f)
const CONSOLE_WARNING* = vec4(1.0f, 0.5f, 0.0f, 1.0f)
const CONSOLE_COMMAND* = vec4(0.922f, 0.914f, 0.463f, 1.0f)