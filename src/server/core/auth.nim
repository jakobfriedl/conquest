import ../../common/profile
import ../../types/server

proc authenticate*(cq: Conquest, username, password: string): bool =     
    let users = cq.profile.getArray("team-server.users")
    for user in users:
        let table = user.getTable() 
        if table.getTableValue("username").getStr() == username and table.getTableValue("password").getStr() == password: 
            return true 

    return false