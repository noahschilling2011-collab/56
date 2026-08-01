#!/usr/bin/env python3
"""Headless-Test fuer den Node-Breach-Generator.

Baut Config, Types und NodeBreach zu einer einzigen Luau-Datei zusammen
(die require()-Zeilen fallen weg, die Module werden zu Upvalues) und laesst
sie mit dem luau-Interpreter laufen. Geprueft wird, dass

  * jedes erzeugte Gitter loesbar ist,
  * der Loesungspfad zusammenhaengend und frei von ICE ist,
  * alle Relays auf dem Loesungspfad liegen,
  * das Abgehen des Loesungspfades nie einen Versuch kostet,
  * ungueltige Eingaben zuverlaessig abgelehnt werden.

Aufruf:  python3 tools/test_nodebreach.py [pfad/zu/luau]
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
SRC = HERE / "src"

DROP = re.compile(r"^local\s+\w+\s*=\s*(game:GetService|require)\(", re.M)


def module_source(path: Path) -> str:
    """Modulquelle ohne die Zeilen, die Roblox-Dienste oder Module holen."""
    lines = [ln for ln in path.read_text(encoding="utf-8").split("\n") if not DROP.match(ln)]
    return "\n".join(lines)


STUBS = r"""
-- Minimale Roblox-Stubs, damit die Module ausserhalb von Studio laufen.
local Color3 = {}
function Color3.fromRGB(r, g, b) return { R = r, G = g, B = b } end
function Color3.new(r, g, b) return { R = r, G = g, B = b } end

local RandomClass = {}
RandomClass.__index = RandomClass
function RandomClass.new(seed)
    local self = setmetatable({}, RandomClass)
    self.state = seed or os.time()
    return self
end
function RandomClass:NextNumber(a, b)
    self.state = (self.state * 1103515245 + 12345) % 2147483648
    local u = self.state / 2147483648
    if a and b then return a + u * (b - a) end
    return u
end
function RandomClass:NextInteger(a, b)
    return a + math.floor(self:NextNumber() * (b - a + 1)) % (b - a + 1)
end
local Random = RandomClass
"""

RUNNER = r"""
--==========================================================================
-- Testlauf
--==========================================================================

local OPEN, ICE, RELAY, START, EXIT, MASKED = 0, 1, 2, 3, 4, 5

local failures = 0
local checks = 0

local function check(condition, message)
    checks += 1
    if not condition then
        failures += 1
        print("FEHLER: " .. message)
    end
end

local function toXY(idx, w)
    return (idx - 1) % w + 1, math.floor((idx - 1) / w) + 1
end

local function adjacent(a, b, w)
    local ax, ay = toXY(a, w)
    local bx, by = toXY(b, w)
    return math.abs(ax - bx) + math.abs(ay - by) == 1
end

local rng = Random.new(20260801)
local PER_DIFFICULTY = 300

for difficulty = 1, 10 do
    for round = 1, PER_DIFFICULTY do
        local public, state = NodeBreach.Generate(difficulty, rng)
        local tag = ("D%d/#%d"):format(difficulty, round)

        -- 1) Grundform
        check(#state.Cells == state.Width * state.Height, tag .. ": Zellzahl passt nicht")
        check(state.Cells[state.Start] == START, tag .. ": Startknoten fehlt")
        check(state.Cells[state.Exit] == EXIT, tag .. ": Exitknoten fehlt")
        check(#public.Cells == #state.Cells, tag .. ": oeffentliche Sicht hat andere Groesse")

        -- 2) Getarntes ICE darf im oeffentlichen Gitter nicht sichtbar sein
        local maskedCount = 0
        for i = 1, #state.Cells do
            if state.Cells[i] == MASKED then
                maskedCount += 1
                check(public.Cells[i] == OPEN, tag .. ": getarntes ICE ist durchgesickert")
            else
                check(public.Cells[i] == state.Cells[i], tag .. ": oeffentliche Zelle weicht ab")
            end
        end

        -- 3) Loesungspfad ist zusammenhaengend, frei von ICE und endet am Exit
        local solution = state.Solution
        check(solution[1] == state.Start, tag .. ": Loesung startet woanders")
        check(solution[#solution] == state.Exit, tag .. ": Loesung endet nicht am Exit")
        local seen = {}
        for i = 1, #solution do
            local idx = solution[i]
            check(not seen[idx], tag .. ": Loesung besucht einen Knoten doppelt")
            seen[idx] = true
            local cell = state.Cells[idx]
            check(cell ~= ICE and cell ~= MASKED, tag .. ": ICE liegt auf dem Loesungspfad")
            if i > 1 then
                check(adjacent(solution[i - 1], idx, state.Width), tag .. ": Loesung hat eine Luecke")
            end
        end

        -- 4) Jedes Relay liegt auf dem Loesungspfad
        local relayCount = 0
        for i = 1, #state.Cells do
            if state.Cells[i] == RELAY then
                relayCount += 1
                check(seen[i], tag .. ": Relay liegt abseits des Loesungspfades")
            end
        end
        check(relayCount == state.RelayTotal, tag .. ": RelayTotal stimmt nicht")
        check(public.Relays == state.RelayTotal, tag .. ": Client bekommt falsche Relayzahl")

        -- 5) Den Loesungspfad abgehen muss zum Erfolg fuehren, ohne Versuche
        local solved = false
        local attemptCost = 0
        for i = 2, #solution do
            local res = NodeBreach.Input(state, { Node = solution[i] })
            if res.CostsAttempt then attemptCost += 1 end
            if res.Solved then solved = true end
            if not res.Ok then
                check(false, ("%s: Zug %d auf dem Loesungspfad abgelehnt (%s)"):format(tag, i, res.Reason))
                break
            end
        end
        check(solved, tag .. ": Loesungspfad fuehrt nicht zum Erfolg")
        check(attemptCost == 0, tag .. ": Loesungspfad hat Versuche gekostet")
    end
end

--==========================================================================
-- Eingabepruefung
--==========================================================================

do
    local _, state = NodeBreach.Generate(5, rng)
    local total = state.Width * state.Height

    check(NodeBreach.Input(state, nil).Reason == "BAD_PAYLOAD", "nil-Payload nicht abgelehnt")
    check(NodeBreach.Input(state, {}).Reason == "BAD_PAYLOAD", "leere Payload nicht abgelehnt")
    check(NodeBreach.Input(state, { Node = 0 }).Reason == "BAD_PAYLOAD", "Index 0 nicht abgelehnt")
    check(NodeBreach.Input(state, { Node = total + 1 }).Reason == "BAD_PAYLOAD", "Index over-range nicht abgelehnt")
    check(NodeBreach.Input(state, { Node = 2.5 }).Reason == "BAD_PAYLOAD", "Kommazahl nicht abgelehnt")
    check(NodeBreach.Input(state, { Node = "3" }).Reason == "BAD_PAYLOAD", "String nicht abgelehnt")
    check(NodeBreach.Input(state, { Node = 0 / 0 }).Reason == "BAD_PAYLOAD", "NaN nicht abgelehnt")
    check(NodeBreach.Input(state, { Node = state.Start }).Reason == "ALREADY_HERE", "Klick auf Kopf falsch behandelt")

    -- Ein Knoten weit weg vom Start ist nie benachbart.
    local far = state.Exit
    if adjacent(state.Start, far, state.Width) then far = state.Start + 2 end
    local res = NodeBreach.Input(state, { Node = far })
    check(res.Reason == "NOT_ADJACENT" or res.Reason == "RELAYS_MISSING", "entfernter Knoten falsch behandelt")
end

-- Vor- und Zuruecklaufen muss den Zustand exakt wiederherstellen.
do
    local _, state = NodeBreach.Generate(3, rng)
    local second = state.Solution[2]
    local relaysBefore = state.RelaysVisited
    NodeBreach.Input(state, { Node = second })
    local back = NodeBreach.Input(state, { Node = state.Start })
    check(back.Reason == "BACKTRACK", "Zuruecklaufen wurde nicht erkannt")
    check(#state.Path == 1, "Pfad nach dem Zuruecklaufen nicht zurueckgesetzt")
    check(state.RelaysVisited == relaysBefore, "Relayzaehler nach Zuruecklaufen falsch")
end

-- Getarntes ICE kostet genau einen Versuch und wird danach sichtbar.
do
    local found = false
    for _ = 1, 400 do
        local _, state = NodeBreach.Generate(9, rng)
        for idx = 1, #state.Cells do
            if state.Cells[idx] == MASKED and adjacent(state.Start, idx, state.Width) then
                local res = NodeBreach.Input(state, { Node = idx })
                check(res.CostsAttempt, "getarntes ICE kostet keinen Versuch")
                check(res.Reason == "MASKED_ICE", "getarntes ICE meldet falschen Grund")
                check(state.Cells[idx] == ICE, "getarntes ICE wurde nicht aufgedeckt")
                check(res.Feedback.Reveal == idx, "Aufdeckung wird nicht gemeldet")
                check(#state.Path == 1, "getarntes ICE hat den Pfad veraendert")
                local again = NodeBreach.Input(state, { Node = idx })
                check(not again.CostsAttempt, "aufgedecktes ICE kostet erneut einen Versuch")
                found = true
                break
            end
        end
        if found then break end
    end
    check(found, "kein getarntes ICE zum Testen gefunden")
end

-- Der Exit bleibt gesperrt, solange Relays offen sind.
do
    local blocked = false
    for _ = 1, 400 do
        local _, state = NodeBreach.Generate(7, rng)
        if state.RelayTotal > 0 then
            -- Bis direkt vor den Exit laufen, aber ueber den Pfad ohne Relays
            -- geht nicht - also pruefen wir die Regel direkt am Zustand.
            local sol = state.Solution
            for i = 2, #sol - 1 do
                NodeBreach.Input(state, { Node = sol[i] })
            end
            if state.RelaysVisited == state.RelayTotal then
                state.RelaysVisited = 0 -- kuenstlich zuruecksetzen
                local res = NodeBreach.Input(state, { Node = state.Exit })
                check(res.Reason == "RELAYS_MISSING", "Exit war trotz offener Relays begehbar")
                check(not res.Solved, "Exit hat trotz offener Relays geloest")
                blocked = true
                break
            end
        end
    end
    check(blocked, "Exit-Sperre konnte nicht geprueft werden")
end

print(("%d Pruefungen, %d Fehler"):format(checks, failures))
if failures > 0 then
    error("Node-Breach-Test fehlgeschlagen")
end
print("NODE-BREACH OK")
"""


def main() -> None:
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"

    config = module_source(SRC / "ReplicatedStorage" / "Shared" / "Config.lua")
    types = module_source(SRC / "ReplicatedStorage" / "Shared" / "Types.lua")
    nodebreach = module_source(SRC / "ServerScriptService" / "Systems" / "Minigames" / "NodeBreach.lua")

    program = "\n".join(
        [
            STUBS,
            "local Config = (function()\n" + config + "\nend)()",
            "local Types = (function()\n" + types + "\nend)()",
            "local NodeBreach = (function()\n" + nodebreach + "\nend)()",
            RUNNER,
        ]
    )

    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as f:
        f.write(program)
        temp = f.name

    result = subprocess.run([luau, temp], capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    Path(temp).unlink()
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
