import ./console

# Handle CTRL+C,  
proc exit() {.noconv.} = 
    echo "Received CTRL+C. Type \"exit\" to close the application.\n"    

proc main() = 
  # Initialize TUI
  # initUi()

  setControlCHook(exit)

  # Initialize prompt interface
  initPrompt()

#[
  Start main function
]#
main()