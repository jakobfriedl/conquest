import strutils, terminal, tables, sequtils, times, strformat
import std/wordwrap

import ./[types]

proc parseOctets*(ip: string): tuple[first, second, third, fourth: int] = 
    # TODO: Verify that address is in correct, expected format
    let octets = ip.split('.')
    return (parseInt(octets[0]), parseInt(octets[1]), parseInt(octets[2]), parseInt(octets[3]))

proc validatePort*(portStr: string): bool = 
    try:
        let port: int = portStr.parseInt
        return port >= 1 and port <= 65535
    except ValueError:
        return false

# Table border characters

type
  Cell = object
    text: string
    fg: ForegroundColor = fgWhite
    bg: BackgroundColor = bgDefault
    style: Style

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

# Wrap cell content
proc wrapCell(text: string, width: int): seq[string] =
    result = text.wrapWords(width).splitLines()

# Format border
proc border(left, mid, right: string, widths: seq[int]): string =
    var line = left
    for i, w in widths:
        line.add(hor.repeat(w + 2))
        line.add(if i < widths.len - 1: mid else: right)
    return line

# Format a row of data
proc formatRow(cells: seq[Cell], widths: seq[int]): seq[seq[Cell]] =
    var wrappedCols: seq[seq[Cell]]
    var maxLines = 1

    for i, cell in cells:
        let wrappedLines = wrapCell(cell.text, widths[i])
        wrappedCols.add(wrappedLines.mapIt(Cell(text: it, fg: cell.fg, bg: cell.bg, style: cell.style)))
        maxLines = max(maxLines, wrappedLines.len)

    for line in 0 ..< maxLines:
        var lineRow: seq[Cell] = @[]
        for i, col in wrappedCols:
            let lineText = if line < col.len: col[line].text else: ""
            let base = cells[i]
            lineRow.add(Cell(text: " " & lineText.alignLeft(widths[i]) & " ", fg: base.fg, bg: base.bg, style: base.style))
        result.add(lineRow)

proc writeRow(cq: Conquest, row: seq[Cell]) =
    stdout.write(vert)
    for cell in row: 
        stdout.styledWrite(cell.fg, cell.bg, cell.style, cell.text, resetStyle, vert)    
    stdout.write("\n")

proc drawTable*(cq: Conquest, listeners: seq[Listener]) = 

    # Column headers and widths
    let headers = @["Name", "Address", "Port", "Protocol", "Agents"]
    let widths = @[8, 15, 5, 8, 6]
    let headerCells = headers.mapIt(Cell(text: it, fg: fgWhite, bg: bgDefault))    

    cq.writeLine(border(topLeft, topMid, topRight, widths))
    for line in formatRow(headerCells, widths):
        cq.hidePrompt()
        cq.writeRow(line)
        cq.showPrompt()
    cq.writeLine(border(midLeft, midMid, midRight, widths))

    for l in listeners:
        # Get number of agents connected to the listener
        let connectedAgents = cq.agents.values.countIt(it.listener == l.name)

        let rowCells = @[
            Cell(text: l.name, fg: fgGreen),
            Cell(text: l.address),
            Cell(text: $l.port),
            Cell(text: $l.protocol),
            Cell(text: $connectedAgents)
        ]

        for line in formatRow(rowCells, widths):
            cq.hidePrompt()
            cq.writeRow(line)
            cq.showPrompt() 

    cq.writeLine(border(botLeft, botMid, botRight, widths)) 

# Calculate time since latest checking in format: Xd Xh Xm Xs
proc timeSince*(agent: Agent, timestamp: DateTime): Cell = 
    
    let 
        now = now()
        duration = now - timestamp
        totalSeconds = int(duration.inSeconds)

    let 
        days = totalSeconds div 86400
        hours = (totalSeconds mod 86400) div 3600
        minutes = (totalSeconds mod 3600) div 60
        seconds = totalSeconds mod 60

    var text = ""

    if days > 0:
        text &= fmt"{days}d "
    if hours > 0 or days > 0:
        text &= fmt"{hours}h "
    if minutes > 0 or hours > 0 or days > 0:
        text &= fmt"{minutes}m "
    text &= fmt"{seconds}s"

    return Cell(
        text: text.strip(),
        # When the agent is 'dead', meaning that the latest checkin occured 
        # more than the agents sleep configuration, dim the text style
        style: if totalSeconds > agent.sleep: styleDim else: styleBright
    )

proc drawTable*(cq: Conquest, agents: seq[Agent]) = 
    
    let headers: seq[string] = @["Name", "Address", "Username", "Hostname", "Operating System", "Process", "PID", "Activity"]
    let widths = @[8, 15, 15, 15, 16, 13, 5, 8]
    let headerCells = headers.mapIt(Cell(text: it, fg: fgWhite, bg: bgDefault))

    cq.writeLine(border(topLeft, topMid, topRight, widths))
    for line in formatRow(headerCells, widths):
        cq.hidePrompt()
        cq.writeRow(line)
        cq.showPrompt()
    cq.writeLine(border(midLeft, midMid, midRight, widths))

    for a in agents:

        var cells = @[
            Cell(text: a.name, fg: fgYellow, style: styleBright),
            Cell(text: a.ip),
            Cell(text: a.username),
            Cell(text: a.hostname),
            Cell(text: a.os),
            Cell(text: a.process, fg: if a.elevated: fgRed else: fgWhite),
            Cell(text: $a.pid, fg: if a.elevated: fgRed else: fgWhite),
            a.timeSince(cq.agents[a.name].latestCheckin)
        ]

        # Highlight agents running within elevated processes
        for line in formatRow(cells, widths):
            cq.hidePrompt()
            cq.writeRow(line)
            cq.showPrompt()

    cq.writeLine(border(botLeft, botMid, botRight, widths)) 