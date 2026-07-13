-- FlightService · EINE Wahrheit fuer alle Fluege.
-- Status-Maschine tickt auf dem Server (90-s-Slots, je Flug versetzt):
-- SCHEDULED -> CHECKIN_OPEN(x3) -> BOARDING -> FINAL_CALL -> GATE_CLOSED -> DEPARTED -> von vorn.
-- Client bekommt Fluege NUR per GetFlights (RemoteFunction) + FlightsChanged (RemoteEvent).
-- Anzeigetafel + Gate-Displays werden hier beschrieben (AirportServer baut nur die Parts).

local RS = game:GetService("ReplicatedStorage")

local Flight = {}

local SLOT = 90 -- Sekunden pro Status-Schritt
local CYCLE = 8 * SLOT
local STATES = { "SCHEDULED", "CHECKIN_OPEN", "CHECKIN_OPEN", "CHECKIN_OPEN", "BOARDING", "FINAL_CALL", "GATE_CLOSED", "DEPARTED" }
local DISPLAY = {
	SCHEDULED = "SCHEDULED", CHECKIN_OPEN = "OPEN", BOARDING = "BOARDING",
	FINAL_CALL = "FINAL CALL", GATE_CLOSED = "CLOSED", DEPARTED = "DEPARTED",
}
local COLORS = {
	OPEN = Color3.fromRGB(84, 208, 106),
	BOARDING = Color3.fromRGB(255, 215, 94),
	["FINAL CALL"] = Color3.fromRGB(255, 170, 60),
	CLOSED = Color3.fromRGB(255, 99, 99),
	SCHEDULED = Color3.fromRGB(127, 150, 173),
	DEPARTED = Color3.fromRGB(140, 146, 156),
}

local FLIGHTS = {
	{ code = "LH 452", dest = "MÜNCHEN", sched = "14:20", gate = 1 },
	{ code = "AB 118", dest = "BERLIN", sched = "14:35", gate = 2 },
	{ code = "EW 771", dest = "WIEN", sched = "14:50", gate = 3 },
	{ code = "FR 903", dest = "PARIS", sched = "15:05", gate = 4 },
	{ code = "KL 233", dest = "AMSTERDAM", sched = "15:20", gate = 5 },
	{ code = "SK 660", dest = "OSLO", sched = "15:40", gate = 1 },
}

local t0 = os.clock()
local changedEv = Instance.new("RemoteEvent"); changedEv.Name = "FlightsChanged"; changedEv.Parent = RS
local getFn = Instance.new("RemoteFunction"); getFn.Name = "GetFlights"; getFn.Parent = RS

local boardRows = {} -- { row = TextLabel, stat = TextLabel }
local gateGuis = {} -- [gateNr] = { code = TextLabel, status = TextLabel }

local function rawState(i)
	-- Fluege um 120 s versetzt, damit die Tafel lebt und meist 2-3 offen sind
	local slot = math.floor(((os.clock() - t0 + (i - 1) * 120) % CYCLE) / SLOT) + 1
	return STATES[slot]
end

function Flight.getFlights()
	local out = {}
	for i, f in ipairs(FLIGHTS) do
		table.insert(out, {
			code = f.code, dest = f.dest, sched = f.sched, gate = f.gate,
			status = DISPLAY[rawState(i)],
		})
	end
	return out
end

function Flight.flightsAtGate(n)
	local out = {}
	for i, f in ipairs(FLIGHTS) do
		if f.gate == n then
			table.insert(out, { code = f.code, dest = f.dest, gate = f.gate, status = DISPLAY[rawState(i)] })
		end
	end
	return out
end

function Flight.isBoardingOpen(code)
	for i, f in ipairs(FLIGHTS) do
		if f.code == code then
			local s = rawState(i)
			return s == "BOARDING" or s == "FINAL_CALL"
		end
	end
	return false
end

function Flight.gateOf(code)
	for _, f in ipairs(FLIGHTS) do
		if f.code == code then return f.gate end
	end
	return nil
end

local function pad(s, n)
	local len = utf8.len(s) or #s
	return s .. string.rep(" ", math.max(0, n - len))
end

local function updateDisplays()
	local flights = Flight.getFlights()
	for i, f in ipairs(flights) do
		local r = boardRows[i]
		if r then
			r.row.Text = pad(f.code, 8) .. pad(f.dest, 13) .. pad(f.sched, 7) .. "G" .. f.gate
			r.stat.Text = f.status
			r.stat.TextColor3 = COLORS[f.status] or COLORS.SCHEDULED
		end
	end
	-- Gate-Displays: aktivster Flug am Gate (Boarding > Check-in > Rest)
	local RANK = { BOARDING = 1, ["FINAL CALL"] = 1, OPEN = 2, SCHEDULED = 3, CLOSED = 4, DEPARTED = 5 }
	for n, gui in pairs(gateGuis) do
		local best = nil
		for _, f in ipairs(flights) do
			if f.gate == n and (best == nil or (RANK[f.status] or 9) < (RANK[best.status] or 9)) then
				best = f
			end
		end
		if best then
			gui.code.Text = best.code .. " · " .. best.dest
			gui.status.Text = best.status
			gui.status.TextColor3 = COLORS[best.status] or COLORS.SCHEDULED
		else
			gui.code.Text = "—"
			gui.status.Text = "GESCHLOSSEN"
			gui.status.TextColor3 = COLORS.CLOSED
		end
	end
end

function Flight.init()
	getFn.OnServerInvoke = Flight.getFlights

	-- Tafel + Gate-Displays aus der Map einsammeln (AirportServer benennt die Labels)
	task.spawn(function()
		local airport = workspace:WaitForChild("Airport", 30)
		if not airport then return end
		for i = 1, #FLIGHTS do
			local row = airport:FindFirstChild("BRow" .. i, true)
			local stat = airport:FindFirstChild("BStat" .. i, true)
			if row and stat then boardRows[i] = { row = row, stat = stat } end
		end
		for n = 1, 5 do
			local code = airport:FindFirstChild("GDCode" .. n, true)
			local status = airport:FindFirstChild("GDStatus" .. n, true)
			if code and status then gateGuis[n] = { code = code, status = status } end
		end
		updateDisplays()
	end)

	-- Ticker: prueft alle 5 s, feuert nur bei echten Statuswechseln
	task.spawn(function()
		local lastSig = ""
		while true do
			task.wait(5)
			local sig = ""
			for i = 1, #FLIGHTS do sig = sig .. rawState(i) end
			if sig ~= lastSig then
				lastSig = sig
				local ok, err = pcall(function()
					updateDisplays()
					changedEv:FireAllClients(Flight.getFlights())
				end)
				if not ok then warn("[FlightService] " .. tostring(err)) end
			end
		end
	end)
	print("[FlightService] aktiv — " .. #FLIGHTS .. " Flüge, Slot " .. SLOT .. " s.")
end

return Flight
