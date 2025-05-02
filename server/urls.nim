import prologue

import ./[index, client, agent]

let indexPatterns* = @[
  pattern("/", index.root, @[HttpGet]),
  pattern("/auth", index.auth, @[HttpPost])
]

#[
  Client Interfaces
]#
let clientPatterns* = @[
  pattern("/listener/", client.listenerList, @[HttpGet]),
  pattern("/listener/create", client.listenerCreate, @[HttpPost, HttpGet]),
  pattern("/listener/{uuid}/delete", client.listenerDelete, @[HttpGet]),
  pattern("/agent/", client.agentList, @[HttpGet]), 
  pattern("/agent/create", client.agentCreate, @[HttpPost])
]

#[
  Agent API
]#
let agentPatterns* = @[
  pattern("/register", agent.agentRegister, @[HttpPost]),
  pattern("/{uuid}/tasks", agent.agentTasks, @[HttpGet, HttpPost]),
  pattern("/{uuid}/results", agent.agentResults, @[HttpGet, HttpPost])
]