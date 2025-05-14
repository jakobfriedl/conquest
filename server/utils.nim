import re, strutils

import ./types

proc validateIPv4Address*(ip: string): bool = 
    let ipv4Pattern = re"^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$"
    return ip.match(ipv4Pattern)

proc validatePort*(portStr: string): bool = 
    try:
        let port: int = portStr.parseInt
        return port >= 1 and port <= 65535
    except ValueError:
        return false

# Table border characters
const topLeft = "╭"
const topMid  = "┬"
const topRight= "╮"
const midLeft = "├"
const midMid  = "┼"
const midRight= "┤"
const botLeft = "╰"
const botMid  = "┴"
const botRight= "╯"
const hor     = "─"
const vert    = "│"

# Format border
proc border(left, mid, right: string, widths: seq[int]): string =
    var line = left
    for i, w in widths:
        line.add(hor.repeat(w))
        line.add(if i < widths.len - 1: mid else: right)
    return line

# Format a row of data
proc row(cells: seq[string], widths: seq[int]): string =
    var row = vert
    for i, cell in cells:
        row.add(" " & cell.alignLeft(widths[i] - 2) & " " & vert)
    return row

proc drawTable*(cq: Conquest, listeners: seq[Listener]) = 

    # Column headers and widths
    let headers = @["Name", "Address", "Port", "Protocol", "Agents"]
    let widths = @[10, 17, 7, 10, 8]

    cq.writeLine(border(topLeft, topMid, topRight, widths))
    cq.writeLine(row(headers, widths))
    cq.writeLine(border(midLeft, midMid, midRight, widths))

    for l in listeners:
        # TODO: Add number of agents connected to the listener
        let row = @[l.name, l.address, $l.port, $l.protocol, "X"]
        cq.writeLine(row(row, widths)) 

    cq.writeLine(border(botLeft, botMid, botRight, widths)) 


proc drawTable*(cq: Conquest, agents: seq[Agent]) = 
    
    let headers: seq[string] = @["Name", "Address", "Username", "Hostname", "Operating System", "Process", "PID"]
    let widths = @[10, 17, 25, 20, 22, 15, 8]

    cq.writeLine(border(topLeft, topMid, topRight, widths))
    cq.writeLine(row(headers, widths))
    cq.writeLine(border(midLeft, midMid, midRight, widths))

    # TODO: Highlight elevated processes 
    for a in agents:
        let row = @[a.name, a.ip, a.username, a.hostname, a.os, a.process, $a.pid] 
        cq.writeLine(row(row, widths)) 

    cq.writeLine(border(botLeft, botMid, botRight, widths)) 