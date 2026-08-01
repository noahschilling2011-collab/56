-- ServerScriptService/Systems/Minigames/NodeBreach.lua
--!strict
-- GHOSTNET :: Minispiel A - NODE-BREACH
--
-- SCHNITTSTELLE, an die sich JEDES Minispiel haelt (SignalMatch, CodeCrack,
-- IceBreaker kommen spaeter mit exakt diesen drei Funktionen):
--
--   Generate(difficulty, rng) -> publicState, serverState
--       publicState  geht an den Client, enthaelt NIE etwas Geheimes.
--       serverState  bleibt auf dem Server.
--
--   Input(serverState, payload) -> InputResult
--       Prueft eine einzelne Spielereingabe. Der Server entscheidet, ob sie
--       gilt, ob sie einen Versuch kostet und ob das Raetsel geloest ist.
--
--   Label() -> string   (Anzeigename im Fake-OS)
--
-- SPIELREGELN
--   Vom START-Knoten einen zusammenhaengenden Pfad zum EXIT legen. Unterwegs
--   muessen ALLE Relay-Knoten mitgenommen werden. Sichtbares ICE ist
--   unpassierbar. Zusaetzlich steckt verstecktes ICE im Gitter - das sieht
--   aus wie ein freier Knoten und kostet beim Reintappen einen Versuch.
--   Genau dafuer ist das RAM-Upgrade da.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

type InputResult = Types.InputResult
type State = Types.NodeBreachState

local NodeBreach = {}

-- Zelltypen
local OPEN = 0
local ICE = 1
local RELAY = 2
local START = 3
local EXIT = 4
local MASKED = 5 -- nur serverseitig; der Client sieht hier OPEN

function NodeBreach.Label(): string
	return "NODE-BREACH"
end

--==========================================================================
-- Gitter-Helfer
--==========================================================================

local function toXY(idx: number, w: number): (number, number)
	local x = (idx - 1) % w + 1
	local y = math.floor((idx - 1) / w) + 1
	return x, y
end

local function toIdx(x: number, y: number, w: number): number
	return (y - 1) * w + x
end

local function neighbours(idx: number, w: number, h: number): { number }
	local x, y = toXY(idx, w)
	local out = {}
	if x > 1 then
		table.insert(out, toIdx(x - 1, y, w))
	end
	if x < w then
		table.insert(out, toIdx(x + 1, y, w))
	end
	if y > 1 then
		table.insert(out, toIdx(x, y - 1, w))
	end
	if y < h then
		table.insert(out, toIdx(x, y + 1, w))
	end
	return out
end

local function isAdjacent(a: number, b: number, w: number, h: number): boolean
	for _, n in neighbours(a, w, h) do
		if n == b then
			return true
		end
	end
	return false
end

local function manhattan(a: number, b: number, w: number): number
	local ax, ay = toXY(a, w)
	local bx, by = toXY(b, w)
	return math.abs(ax - bx) + math.abs(ay - by)
end

--==========================================================================
-- Pfadsuche
-- Zufaellige Tiefensuche mit Drang Richtung Exit. Findet immer einen Weg,
-- weil zu diesem Zeitpunkt noch jede Zelle frei ist.
--==========================================================================

local function shuffle(t: { number }, rng: Random)
	for i = #t, 2, -1 do
		local j = rng:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end

local function findPath(rng: Random, w: number, h: number, startIdx: number, exitIdx: number): { number }
	local visited: { [number]: boolean } = { [startIdx] = true }
	local stack: { number } = { startIdx }

	while #stack > 0 do
		local cur = stack[#stack]
		if cur == exitIdx then
			return table.clone(stack)
		end

		local options = neighbours(cur, w, h)
		shuffle(options, rng)

		-- Meistens zuerst den Nachbarn probieren, der naeher am Exit liegt.
		-- Das haelt die Pfade brauchbar kurz, ohne sie berechenbar zu machen.
		if rng:NextNumber() < 0.65 then
			table.sort(options, function(a, b)
				return manhattan(a, exitIdx, w) < manhattan(b, exitIdx, w)
			end)
		end

		local moved = false
		for _, n in options do
			if not visited[n] then
				visited[n] = true
				table.insert(stack, n)
				moved = true
				break
			end
		end

		if not moved then
			table.remove(stack)
		end
	end

	return {}
end

local function tierFor(difficulty: number)
	for _, tier in Config.NodeBreach.Tiers do
		if difficulty <= tier.MaxDifficulty then
			return tier
		end
	end
	return Config.NodeBreach.Tiers[#Config.NodeBreach.Tiers]
end

--==========================================================================
-- Generierung
--==========================================================================

function NodeBreach.Generate(difficulty: number, rng: Random): (Types.NodeBreachPublic, State)
	local tier = tierFor(difficulty)
	local w, h = tier.Width, tier.Height

	local startIdx = toIdx(1, h, w) -- unten links
	local exitIdx = toIdx(w, 1, w) -- oben rechts

	-- Mehrere Pfade erzeugen, den mit der angenehmsten Laenge behalten.
	local wanted = w + h + Config.NodeBreach.PathLengthBonus
	local best: { number } = {}
	local bestScore = math.huge
	for _ = 1, Config.NodeBreach.PathSearchTries do
		local candidate = findPath(rng, w, h, startIdx, exitIdx)
		if #candidate > 0 then
			local score = math.abs(#candidate - wanted)
			if score < bestScore then
				best, bestScore = candidate, score
			end
		end
	end

	-- Notnagel: gerade Treppe. Kann eigentlich nicht eintreten, aber ein
	-- leeres Gitter waere ein unloesbares Raetsel - das lassen wir nicht zu.
	if #best == 0 then
		best = { startIdx }
		local x, y = 1, h
		while x < w do
			x += 1
			table.insert(best, toIdx(x, y, w))
		end
		while y > 1 do
			y -= 1
			table.insert(best, toIdx(x, y, w))
		end
	end

	local inPath: { [number]: boolean } = {}
	for _, idx in best do
		inPath[idx] = true
	end

	-- Zellen anlegen
	local cells: { number } = table.create(w * h, OPEN)
	for i = 1, w * h do
		cells[i] = OPEN
	end

	-- Relays gleichmaessig auf dem Loesungspfad verteilen (ohne Start/Exit).
	local interior = #best - 2
	local relayCount = math.clamp(tier.Relays, 0, math.max(0, interior))
	for r = 1, relayCount do
		local pos = math.floor(r * (interior + 1) / (relayCount + 1)) + 1
		pos = math.clamp(pos, 2, #best - 1)
		local idx = best[pos]
		if cells[idx] == RELAY then
			-- Kollision: naechsten freien Pfadknoten nehmen.
			for k = pos + 1, #best - 1 do
				if cells[best[k]] ~= RELAY then
					idx = best[k]
					break
				end
			end
		end
		cells[idx] = RELAY
	end
	-- tatsaechlich gesetzte Relays zaehlen
	local relayTotal = 0
	for _, v in cells do
		if v == RELAY then
			relayTotal += 1
		end
	end

	-- ICE neben dem Pfad streuen.
	for i = 1, w * h do
		if not inPath[i] then
			local roll = rng:NextNumber()
			if roll < tier.Ice then
				cells[i] = ICE
			elseif roll < tier.Ice + tier.MaskedIce then
				cells[i] = MASKED
			end
		end
	end

	cells[startIdx] = START
	cells[exitIdx] = EXIT

	local state: State = {
		Width = w,
		Height = h,
		Cells = cells,
		Start = startIdx,
		Exit = exitIdx,
		RelayTotal = relayTotal,
		RelaysVisited = 0,
		Path = { startIdx },
		InPath = { [startIdx] = true },
		Revealed = {},
		Solution = best,
	}

	-- Oeffentliche Sicht: verstecktes ICE als freier Knoten getarnt.
	local publicCells = table.create(w * h, OPEN)
	for i = 1, w * h do
		publicCells[i] = if cells[i] == MASKED then OPEN else cells[i]
	end

	local public: Types.NodeBreachPublic = {
		Width = w,
		Height = h,
		Cells = publicCells,
		Start = startIdx,
		Exit = exitIdx,
		Relays = relayTotal,
	}

	return public, state
end

--==========================================================================
-- Eingabe
--==========================================================================

local function result(ok: boolean, reason: string, costs: boolean, solved: boolean, feedback: { [string]: any }): InputResult
	return { Ok = ok, Reason = reason, CostsAttempt = costs, Solved = solved, Feedback = feedback }
end

function NodeBreach.Input(state: State, payload: any): InputResult
	-- Payload-Form pruefen. Alles, was nicht exakt passt, fliegt raus.
	if typeof(payload) ~= "table" then
		return result(false, "BAD_PAYLOAD", false, false, {})
	end
	local node = (payload :: any).Node
	if typeof(node) ~= "number" or node ~= node or node % 1 ~= 0 then
		return result(false, "BAD_PAYLOAD", false, false, {})
	end
	local total = state.Width * state.Height
	if node < 1 or node > total then
		return result(false, "BAD_PAYLOAD", false, false, {})
	end

	local head = state.Path[#state.Path]

	local function pack(extra: { [string]: any }?): { [string]: any }
		local f: { [string]: any } = {
			Path = table.clone(state.Path),
			RelaysLeft = state.RelayTotal - state.RelaysVisited,
		}
		if extra then
			for k, v in extra do
				f[k] = v
			end
		end
		return f
	end

	-- Zurueckgehen: auf den vorletzten Knoten klicken nimmt den letzten weg.
	if #state.Path >= 2 and node == state.Path[#state.Path - 1] then
		local removed = table.remove(state.Path) :: number
		state.InPath[removed] = nil
		if state.Cells[removed] == RELAY then
			state.RelaysVisited -= 1
		end
		return result(true, "BACKTRACK", false, false, pack())
	end

	if node == head then
		return result(false, "ALREADY_HERE", false, false, pack())
	end

	if not isAdjacent(head, node, state.Width, state.Height) then
		return result(false, "NOT_ADJACENT", false, false, pack())
	end

	if state.InPath[node] then
		return result(false, "REVISIT", false, false, pack())
	end

	local cell = state.Cells[node]

	if cell == ICE then
		return result(false, "ICE", false, false, pack())
	end

	-- Verstecktes ICE: der einzige Fall, der einen Versuch kostet.
	if cell == MASKED then
		state.Cells[node] = ICE
		state.Revealed[node] = true
		return result(false, "MASKED_ICE", true, false, pack({ Reveal = node }))
	end

	if cell == EXIT then
		if state.RelaysVisited < state.RelayTotal then
			return result(false, "RELAYS_MISSING", false, false, pack())
		end
		table.insert(state.Path, node)
		state.InPath[node] = true
		return result(true, "SOLVED", false, true, pack())
	end

	table.insert(state.Path, node)
	state.InPath[node] = true
	if cell == RELAY then
		state.RelaysVisited += 1
	end

	return result(true, "OK", false, false, pack({ Relay = cell == RELAY }))
end

return NodeBreach
