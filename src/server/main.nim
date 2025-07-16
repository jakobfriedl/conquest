import prompt, terminal, argparse
import strutils, strformat, times, system, tables

import core/server

# Conquest framework entry point
when isMainModule:
    startServer()