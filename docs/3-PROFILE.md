# Profiles <!-- omit from toc -->

## Contents <!-- omit from toc -->

- [General](#general)
- [Team server settings](#team-server-settings)
- [GET settings](#get-settings)
  - [Data transformation](#data-transformation)
  - [Request options](#request-options)
  - [Response options](#response-options)
- [POST settings](#post-settings)

## General

Conquest supports malleable C2 profiles written using the TOML configuration language. This allows the complete customization of network traffic using data transformation, encoding and randomization. Wildcard characters `#` are replaced by a random alphanumerical character, making it possible to add even more variation to requests via randomized parameters or cookies.  

General settings that are defined at the beginning of the profile are the profile name and the relative location of important files, such as the team server's private key or the Conquest database.

```toml 
name = "cq-default-profile"
private-key-file = "data/keys/conquest-server_x25519_private.key"
database-file = "data/conquest.db"
```

## Team server settings 
The team server settings currently only include the port that the team server uses for the Websocket handler. It is set under the `[toml-server]` block. 

```toml
[team-server]
port = 37573
``` 

## GET settings

The largest part of the malleable C2 profiles is taken up by the configuration of HTTP GET and POST requests. Starting with HTTP GET, it is possible to define the User-Agent that is used for GET requests, as well as the URI endpoints which are requested by the agent. Here, either a regular string or an array of string can be used. While the listener creates a route for each endpoint passed to this array, the agent randomly selects one of the endpoints for each GET request. Endpoints must not include `#` characters, as the randomization is done for each request separately.

```toml
[http-get]
user-agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
endpoints = [
    "/get",
    "/api/v1.2/status.js"
]
```

### Data transformation

A huge advantage of Conquest's C2 profile is the customization of where the heartbeat, or check-in request is placed within the request. This is where data transformation options come into play. The following table shows all available options.

| Name | Type | Description | 
| --- | --- | --- | 
| placement.type | OPTION | Determine where in the request the heartbeat is placed. The following options are available: `header`, `parameter`, `uri`, `body`|
| placement.name | STRING | Name of the header/parameter to place the heartbeat in.| 
| encoding.type | OPTION | Type of encoding to use. The following options are available: `base64`, `none` (default) | 
| encoding.url-safe | BOOL | Only required if encoding.type is set to `base64`. Uses `-` and `_` instead of `+`, `=` and `/`. |
| prefix | STRING | String to prepend before the heartbeat payload. |
| suffix | STRING | String to append after the heartbeat payload. |

The order of operations is: 
1. Encoding
2. Addition of prefix & suffix
3. Placement in the request

On the other hand, the server processes the requests in the following order:
1. Retrieval from the request
2. Removal of prefix & suffix
3. Decoding

> [!NOTE]
> Heartbeat placement is currently only implemented for `header` and `parameter`, as those are the most commonly used options.

To illustrate how that works, the following TOML configuration transforms a base64-encoded heartbeat packet into a string that looks like a JWT token and places it in the Authorization header. In this case, the `#` in the suffix are randomized, ensuring that the token is different for every request.

```toml 
[http-get.agent.heartbeat]
placement = { type = "header", name = "Authorization" }
encoding = { type = "base64", url-safe = true }
prefix = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
suffix = ".######################################-####"
```

![Heartbeat in Authorization Header](../assets/get.png)

Check the [default profile](../data/profile.toml) for more examples.

### Request options

The profile language makes is further possible to add parameters and headers. When arrays are passed to these settings instead of strings, a random member of the array is chosen. Again, character randomization can be used to break up repeating patterns.

```toml
# Defines arbitrary URI parameters that are added to the request
[http-get.agent.parameters]
id = "#####-#####"
lang = [
    "en-US",
    "de-AT"
]

# Defines arbitrary headers that are added by the agent when performing a HTTP GET request 
[http-get.agent.headers]
Host = [ 
    "wikipedia.org", 
    "google.com",
    "127.0.0.1"
]
Connection = "Keep-Alive"
Cache-Control = "no-cache"
```

![GET Traffic with C2 Profiles](../assets/traffic.png)


### Response options

The C2 profile can also be used to change the team server's responses to GET requests that contain the task that are to be executed by the agent. Similar to the requests, headers can be set under the `[http-get.server.headers]` block and the previously mentioned data transformation options can be used in the `[http-get.server.output]` block. The only placement option that is supported for the response is `body`. 

```toml
# Defines arbitrary headers that are added to the server's response
[http-get.server.headers]
Server = "nginx"
Content-Type = "application/octet-stream" 
Connection = "Keep-Alive"

[http-get.server.output]
placement = { type = "body" }
```

## POST settings

HTTP POST requests can be configured in a similar way to GET requests. Here, it is also possible to define alternative request methods, such as PUT. 

```toml 
[http-post]
user-agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"

# Defines URI endpoints for HTTP POST requests
endpoints = [
    "/post",
    "/api/v2/get.js"
]

# Post request can also be sent with the HTTP verb PUT instead
request-methods = [
    "POST",
    "PUT"
]

[http-post.agent.headers]
Host = [ 
    "wikipedia.org", 
    "google.com",
    "127.0.0.1"
]
Content-Type = "application/octet-stream" 
Connection = "Keep-Alive"
Cache-Control = "no-cache"

[http-post.agent.output]
placement = { type = "body" }

[http-post.server.headers]
Server = "nginx"

[http-post.server.output]
placement = { type = "body" }
```

![POST request with task data](../assets/post.png)