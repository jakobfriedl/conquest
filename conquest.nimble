# Package

version       = "0.1.0"
author        = "Jakob Friedl"
description   = "Command & control framework written in Nim"
license       = "MIT"
srcDir        = "src"

# Build tasks 

import os, strformat
task server, "Build conquest server binary": 
    let cqRoot = getCurrentDir()
    exec fmt"nim c -d:CONQUEST_ROOT={cqRoot} src/server/main.nim"

task client, "Build conquest client binary": 
    discard

# Dependencies

requires "nim >= 2.2.4"

requires "prompt >= 0.0.1"
requires "argparse >= 4.0.2"
requires "parsetoml >= 0.7.2"
requires "nimcrypto >= 0.6.4"
requires "tiny_sqlite >= 0.2.0"
requires "prologue >= 0.6.6" 
requires "winim >= 3.9.4"
