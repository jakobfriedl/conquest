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
```

5. Start the Conquest server with a C2 Profile
```
./bin/server -p ./data/profile.toml
```

