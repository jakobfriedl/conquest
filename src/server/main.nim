import random
import core/server
import strutils

# Conquest framework entry point
when isMainModule:
    randomize()
    startServer()