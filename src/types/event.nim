import json
import ./common

type 
    EventType* = enum
        CLIENT_HEARTBEAT = 0'u8             # Basic checkin 
        CLIENT_KEY_EXCHANGE = 200'u8        # Unencrypted public key sent by both parties for key exchange
        
        # Sent by client 
        CLIENT_AGENT_BUILD = 1'u8           # Generate an agent binary for a specific listener
        CLIENT_AGENT_TASK = 2'u8            # Instruct TS to send queue a command for a specific agent
        CLIENT_LISTENER_START = 3'u8        # Start a listener on the TS
        CLIENT_LISTENER_STOP = 4'u8         # Stop a listener
        CLIENT_LOOT_REMOVE = 5'u8           # Remove loot on the team server
        CLIENT_LOOT_GET = 6'u8              # Request file/screenshot from the team server for preview or download
        CLIENT_AGENT_REMOVE = 7'u8          # Delete agent from the team server database
        CLIENT_LOG = 8'u8                   # Log an entry on the team server (client sends back formatted message)

        CLIENT_AUTH = 98'u8                 # Username & password for client authentication
        CLIENT_AUTH_RESULT = 99'u8          # Username & password for client authentication
        
        # Sent by team server
        CLIENT_PROFILE = 100'u8             # Team server profile and configuration 
        CLIENT_LISTENER_ADD = 101'u8        # Add listener to listeners table
        CLIENT_LISTENER_REMOVE = 102'u8     # Remove listener
        CLIENT_AGENT_ADD = 103'u8           # Add agent to sessions table
        CLIENT_AGENT_CHECKIN = 104'u8       # Update agent checkin
        CLIENT_AGENT_PAYLOAD = 105'u8       # Return agent payload binary 
        CLIENT_CONSOLE_ITEM = 106'u8        # Add entry to a agent's console 
        CLIENT_EVENTLOG_ITEM = 107'u8       # Add entry to the eventlog   
        CLIENT_BUILDLOG_ITEM = 108'u8       # Add entry to the build log
        CLIENT_LOOT_ADD = 109'u8            # Add file or screenshot stored on the team server to preview on the client, only sends metadata and not the actual file content
        CLIENT_LOOT_DATA = 110'u8           # Send file/screenshot bytes to the client to display as preview or to download to the client desktop
        CLIENT_IMPERSONATE_TOKEN = 111'u8   # Access token impersonated
        CLIENT_REVERT_TOKEN = 112'u8        # Revert to original logon session 
        CLIENT_PROCESSES = 113'u8           # Send processes
        CLIENT_DIRECTORY_LISTING = 114'u8   # Send directory listing
        CLIENT_WORKING_DIRECTORY = 115'u8   # Send current woring directory
        CLIENT_CHAT = 116'u8                # Send and display chat message
        CLIENT_SYNC = 117'u8                # Instruct team server to sync data after authentication

    Event* = object 
        eventType*: EventType               
        timestamp*: int64 
        data*: JsonNode 

# Shared types for client & server
type 
    AgentBuildInformation* = ref object 
        listenerId*: string
        payloadType*: PayloadType
        sleepSettings*: SleepSettings
        verbose*: bool
        killDate*: int64
        modules*: uint32

    LootItemType* = enum 
        DOWNLOAD = 0'u8 
        SCREENSHOT = 1'u8

    LootItem* = ref object 
        itemType*: LootItemType
        lootId*: string
        agentId*: string
        host*: string 
        path*: string 
        timestamp*: int64
        size*: int 