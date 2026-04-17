# Package
version     = "0.2.0"
author      = "Jakob Friedl"
description = "Conquest command & control/post-exploitation framework"
license     = "BSD-3-Clause"
srcDir      = "src"

# Dependencies
requires "nim >= 2.2.8"

requires "nimcrypto >= 0.6.4"
requires "tiny_sqlite >= 0.2.0"
requires "winim >= 3.9.4"
requires "ptr_math >= 0.3.0"
requires "imguin >= 1.92.7.0"
requires "zippy >= 0.10.16"
requires "mummy >= 0.4.6"
requires "whisky >= 0.1.3"
requires "pixie >= 5.1.0"
requires "cligen >= 1.9.3"
requires "nimpy >= 0.2.1"
requires "gtk2 >= 1.3"
requires "regex >= 0.26.3"

# Build tasks
import os, strformat

proc build(file: string, debug = false) =
    let cqRoot = getEnv("CONQUEST_ROOT", getCurrentDir())
    let flags = if debug: "-d:debug --stackTrace:on --lineTrace:on" else: "-d:release"
    exec fmt"nim c {flags} -d:CONQUEST_ROOT={cqRoot} {file}"

proc buildResources() =
    # Build post-exploitation resources/DLLs when they don't exist
    for kind, dir in walkDir("data/resources"):
        if kind != pcDir: continue
        let dist = dir / "dist"
        if dirExists(dist) and listFiles(dist).len == 0:
            withDir(dir): exec "nimble dll"

task server, "Build server": 
    build("src/server/main.nim")

task server_debug, "Build server (debug)": 
    build("src/server/main.nim", true)

task client, "Build client":         
    buildResources()
    build("src/client/main.nim")

task client_debug, "Build client (debug)": 
    buildResources()
    build("src/client/main.nim", true)