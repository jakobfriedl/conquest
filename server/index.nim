import prologue

# / 
proc root*(ctx: Context) {.async.} =
  resp "<h1>Hello, World!</h1>"

# /auth
proc auth*(ctx: Context) {.async.} =
  resp "<h1>Hello, Auth!</h1>"
