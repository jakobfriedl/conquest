#!/bin/bash

CONQUEST_ROOT="/mnt/c/Users/jakob/Documents/Projects/conquest"
nim --os:windows --cpu:amd64 --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc -d:release --outdir:"$CONQUEST_ROOT/bin" -o:"monarch.x64.exe" c $CONQUEST_ROOT/src/agents/monarch/main.nim
