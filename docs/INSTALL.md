# Installation Guide

1. Clone the Conquest repository
```
git clone https://github.com/jakobfriedl/conquest
cd conquest
```

2. Install Nim

```bash
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
```

3. Install Nimble dependencies 
```
nimble install -d
```

4. Build conquest binaries
```
nimble server
nimble client
```

5. Start the Conquest server with a C2 Profile and connect to it with the client
```bash
./bin/server -p ./data/profile.toml
./bin/client -i localhost -p 35753
```

