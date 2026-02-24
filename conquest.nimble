# Package

version       = "0.1.0"
author        = "Jakob Friedl"
description   = "Conquest command & control/post-exploitation framework"
license       = "BSD-3-Clause"
srcDir        = "src"

# Build tasks 

import os, strformat
let cqRoot = getEnv("CONQUEST_ROOT", getCurrentDir())
task server, "Build conquest server binary": 

    exec fmt"nim c -d:release -d:CONQUEST_ROOT={cqRoot} src/server/main.nim"

task server_debug, "Build conquest client binary in debug mode":
    exec fmt"nim c -d:debug --stackTrace:on --lineTrace:on -d:CONQUEST_ROOT={cqRoot} src/server/main.nim"

task client, "Build conquest client binary": 
    exec fmt"nim c -d:release -d:CONQUEST_ROOT={cqRoot} src/client/main.nim"

task client_debug, "Build conquest client binary in debug mode":
    exec fmt"nim c -d:debug --stackTrace:on --lineTrace:on -d:CONQUEST_ROOT={cqRoot} src/client/main.nim"

# Dependencies

requires "nim >= 2.2.6"

requires "nimcrypto >= 0.6.4"
requires "tiny_sqlite >= 0.2.0"
requires "winim >= 3.9.4"
requires "ptr_math >= 0.3.0"
requires "imguin >= 1.92.4.0"
requires "zippy >= 0.10.16"
requires "mummy >= 0.4.6"
requires "whisky >= 0.1.3"
requires "native_dialogs >= 0.2.0"
requires "pixie >= 5.1.0"
requires "cligen >= 1.9.3"
requires "nimpy >= 0.2.1"