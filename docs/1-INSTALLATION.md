# Installation

1. Clone the Conquest repository
```
git clone https://github.com/jakobfriedl/conquest
cd conquest
```

2. Install Nim.

```bash
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
```

3. The Conquest binaries for team server and client are designed to be compiled on a UNIX system using the `nimble` command. This command installs and updates all dependencies and third-party libraries automatically.
```
nimble server
nimble client
```

4. Start the Conquest team server with a C2 profile. The default profile is located in data/profile.toml and can be adapted by the operator.
```
bin/server -p data/profile
```

On the first start, the Conquest team server creates the Conquest database in the data directory, as well as the team server's private key in data/keys, which is used for the key exchange between team server, client and agent. 

![Team server start](../assets/ts-start.png)

5. Start the Conquest operator client
```
bin/client
```

By default, the Conquest client connects to localhost:37573 to connect to the team server. The address and port can be specified from the command-line using the `-i` and `-p` flags. The team server port is specified in the malleable C2 profile.

```
bin/client -i <team-server-address> -p <team-server-port>
```