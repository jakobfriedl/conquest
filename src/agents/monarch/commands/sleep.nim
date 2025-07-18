# import os, strutils, strformat, base64, json

# import ../common/types

# proc taskSleep*(task: Task): TaskResult = 

#     # Parse task parameter
#     let delay = parseJson(task.args)["delay"].getInt()

#     echo fmt"Sleeping for {delay} seconds."

#     try: 
#         sleep(delay * 1000) 
#         return TaskResult(
#             task: task.id, 
#             agent: task.agent, 
#             data: encode(""),
#             status: Completed
#         )

#     except CatchableError as err: 
#         return TaskResult(
#             task: task.id, 
#             agent: task.agent, 
#             data: encode(fmt"An error occured: {err.msg}" & "\n"),
#             status: Failed 
#         )