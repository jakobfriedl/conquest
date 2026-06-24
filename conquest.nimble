# Package
version     = "0.4.0"
author      = "Jakob Friedl"
description = "Conquest command & control/post-exploitation framework"
license     = "BSD-3-Clause"
srcDir      = "src"

# Dependencies
requires "nim >= 2.2.10"

requires "nimcrypto >= 0.6.4"
requires "tiny_sqlite >= 0.2.0"
requires "winim >= 3.9.4"
requires "ptr_math >= 0.3.0"
requires "imguin >= 1.92.7.0"
requires "zippy >= 0.10.16"
requires "mummy >= 0.4.8"
requires "whisky >= 0.1.3"
requires "pixie >= 5.1.0"
requires "cligen >= 1.9.3"
requires "nimpy >= 0.2.1"
requires "gtk2 >= 1.3"
requires "regex >= 0.26.3"

# Build tasks
import os, strformat, strutils

# Mummy 0.4.8 has a bug where destroy(true) causes a segfault when we try to stop a listener after any client connection.
# This patches the shutdown path to use destroy(false) instead of destroy(true) which leaks instead of crashing.
proc patchMummy() =
    let 
        mummyDir = gorge("nimble path mummy").strip()
        mummyFile = mummyDir / "mummy.nim"
        content = readFile(mummyFile)
        target = "server.destroy(true)\n      return"
        patched = "server.destroy(false)\n      return"
    
    if target in content:
        writeFile(mummyFile, content.replace(target, patched))

proc build(file: string, debug = false) =
    let cqRoot = getEnv("CONQUEST_ROOT", getCurrentDir())
    let flags = if debug: "-d:debug --stackTrace:on --lineTrace:on" else: "-d:release"
    exec fmt"nim c {flags} -d:CONQUEST_ROOT={cqRoot} {file}"

proc buildResources(buildAlways: bool = false) =
    # Build post-exploitation resources/DLLs when they don't exist
    for kind, dir in walkDir("data/resources"):
        if kind != pcDir: continue
        let dist = dir / "dist"
        if not dirExists(dist):
            mkDir(dist)
        if buildAlways or listFiles(dist).len == 0:
            withDir(dir): exec "nimble dll"

task server, "Build server":
    patchMummy()
    build("src/server/main.nim")

task server_debug, "Build server (debug)":
    patchMummy()
    build("src/server/main.nim", true)

task client, "Build client":         
    buildResources()
    build("src/client/main.nim")

task client_debug, "Build client (debug)": 
    buildResources()
    build("src/client/main.nim", true)

task resources, "Build resources":
    buildResources(buildAlways = true)