import core/server
import ../modules/manager

# Conquest framework entry point
when isMainModule:
    loadModules()
    import cligen; dispatch startServer