-- ZoneService · Der Server besitzt den Zustand: wer darf wo stehen.
-- Zonen sind achsenparallele Boxen in METERN. Durchsetzung: 10-Hz-Loop,
-- unerlaubte Position -> Ruecksetzen auf den letzten legalen Punkt (RootPart.CFrame)
-- + ZoneDenied-Remote fuer den Client-Toast. Teleport-Spruenge (> 8 m/Tick) in
-- gesperrte Zonen werden zusaetzlich im Output gemeldet.
-- Physische Schranken (CanCollide-Parts) oeffnet NUR der Server (Transparency/CanCollide).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local Zone = {}

local M = 3.4 -- wird in init() aus workspace-Attribut ueberschrieben
local prov = nil -- Credential-Provider: hasStaff, hasPass, consumePass, anyPassGate, exemptFlight
local flights = nil -- FlightService (ab Phase 2; ohne ihn sind Gates staff-only)

local deniedEv = Instance.new("RemoteEvent"); deniedEv.Name = "ZoneDenied"; deniedEv.Parent = RS

local GATE_X = { -130, -40, 40, 130, 200 }
local SPAWN = Vector3.new(-30, 1.2, 268) -- Meter, Terminalhalle

local zones = {}
local barriers = {}
local adminCheck = nil -- Admins (Spielbesitzer) sind zonen-exempt

function Zone.setAdminCheck(fn)
	adminCheck = fn
end
local lastLegal = {} -- [pl] = Vector3 (Studs)
local lastPos = {}
local boarded = {} -- [pl] = GateNr (temporaer, bis zurueck im Terminal)
local lastToast = {}

local function toast(pl, msg, ok)
	local t = os.clock()
	if (lastToast[pl] or 0) + 1.5 > t and not ok then return end
	lastToast[pl] = t
	deniedEv:FireClient(pl, msg, ok == true)
end

local function inBox(p, b)
	return p.X >= b.x1 * M and p.X <= b.x2 * M
		and p.Z >= b.z1 * M and p.Z <= b.z2 * M
		and p.Y >= (b.y1 or -3) * M and p.Y <= (b.y2 or 90) * M
end

function Zone.isBoarded(pl)
	return boarded[pl]
end

-- Gate-Anforderung: Personal frei · eingecheckter Passagier frei ·
-- passender Pass + Boarding offen -> Pass wird VERBRAUCHT und Zutritt gemerkt
local function gateReq(n)
	return function(pl)
		if prov.hasStaff(pl) then return true end
		if boarded[pl] == n then return true end
		if flights then
			for _, f in ipairs(flights.flightsAtGate(n)) do
				if prov.hasPass(pl, f.code) then
					if flights.isBoardingOpen(f.code) then
						prov.consumePass(pl, f.code)
						boarded[pl] = n
						return true, "🎫 Boarding " .. f.code .. " nach " .. f.dest .. " — gute Reise!"
					end
					return false, "Gate " .. n .. ": Boarding für " .. f.code .. " hat noch nicht begonnen (" .. f.status .. ")."
				end
			end
			local eigenes = prov.anyPassGate(pl)
			if eigenes and eigenes ~= n then
				return false, "Falsches Gate — dein Flug geht ab Gate " .. eigenes .. "."
			end
		end
		return false, "Gate " .. n .. ": nur mit gültigem Boarding-Pass."
	end
end

local function staffReq(msg)
	return function(pl)
		if prov.hasStaff(pl) then return true end
		return false, msg
	end
end

local function buildZones()
	zones = {}
	for i, px in ipairs(GATE_X) do
		table.insert(zones, { id = "gate" .. i, x1 = px - 14, z1 = 138, x2 = px + 14, z2 = 195, req = gateReq(i) })
	end
	table.insert(zones, {
		id = "walkway", x1 = -150, z1 = 195, x2 = 220, z2 = 231.4,
		req = function(pl)
			if prov.hasStaff(pl) or boarded[pl] or prov.anyPassGate(pl) then return true end
			return false, "🛂 Security: nur mit Boarding-Pass oder Mitarbeiter-Ausweis."
		end,
	})
	table.insert(zones, {
		-- ganzes Flugfeld innerhalb des Zauns (inkl. beider Runways + Cargo) —
		-- sonst laeuft man oestlich ums Vorfeld herum an der Security vorbei
		id = "apron", x1 = -950, z1 = -560, x2 = 950, z2 = 231.4,
		req = function(pl)
			if prov.hasStaff(pl) or boarded[pl] or prov.exemptFlight(pl) then return true end
			return false, "🛂 Vorfeld: NUR PERSONAL (Mitarbeiter-Ausweis ab Level 2)."
		end,
	})
	table.insert(zones, {
		id = "keller", x1 = -51, z1 = 236, x2 = -4, z2 = 267, y1 = -7, y2 = -1,
		req = staffReq("🪪 Gepäckkeller: NUR PERSONAL · Zutritt mit Ausweis."),
	})
end

-- Schranken: Server oeffnet (Transparency + CanCollide), wenn ein Berechtigter davor steht
function Zone.registerBarrier(part, checkFn)
	table.insert(barriers, { part = part, check = checkFn, open = false, baseT = part.Transparency })
end

local function updateBarriers()
	for _, b in ipairs(barriers) do
		if b.part.Parent then
			local want = false
			for _, pl in ipairs(Players:GetPlayers()) do
				local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - b.part.Position).Magnitude < 6 * M
					and (b.check(pl) or (adminCheck ~= nil and adminCheck(pl))) then
					want = true
					break
				end
			end
			if want ~= b.open then
				b.open = want
				b.part.CanCollide = not want
				b.part.Transparency = want and 0.85 or b.baseT
			end
		end
	end
end

local function enforce()
	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if root then
			local p = root.Position
			if (adminCheck and adminCheck(pl)) or prov.exemptFlight(pl) then
				-- Captain im Flug: Flugzeug bewegt den Charakter, keine Zonenpruefung
				lastPos[pl] = p
				lastLegal[pl] = lastLegal[pl] or p
			else
				local denyMsg = nil
				for _, z in ipairs(zones) do
					if inBox(p, z) then
						local ok, msg = z.req(pl)
						if ok then
							if msg then toast(pl, msg, true) end
						else
							denyMsg = msg or "Zutritt verweigert."
						end
						break -- erste passende Zone entscheidet
					end
				end
				if denyMsg then
					if lastPos[pl] and (p - lastPos[pl]).Magnitude > 8 * M then
						warn("[ZoneService] Teleport-Versuch von " .. pl.Name .. " in gesperrte Zone (" ..
							math.floor((p - lastPos[pl]).Magnitude / M) .. " m Sprung) — zurückgesetzt.")
					end
					local back = lastLegal[pl] or (SPAWN * M)
					root.CFrame = CFrame.new(back + Vector3.new(0, 1, 0))
					toast(pl, denyMsg, false)
					lastPos[pl] = back
				else
					lastLegal[pl] = p
					lastPos[pl] = p
				end
				-- Boarding-Status verfaellt, sobald der Spieler zurueck im Terminal ist
				if boarded[pl] and p.Z > 233 * M and p.Y > -1 * M then
					boarded[pl] = nil
				end
			end
		end
	end
end

function Zone.init(provider, flightService)
	prov = provider
	flights = flightService
	M = workspace:GetAttribute("MetersToStuds") or M
	buildZones()

	-- Schranken aus der Map einsammeln (AirportServer baut sie, wir schalten sie)
	task.spawn(function()
		local airport = workspace:WaitForChild("Airport", 30)
		if not airport then return end
		local function hook(name, checkFn)
			local part = airport:FindFirstChild(name, true)
			if part then Zone.registerBarrier(part, checkFn) end
		end
		hook("SecSchranke", function(pl)
			return prov.hasStaff(pl) or boarded[pl] ~= nil or prov.anyPassGate(pl) ~= nil
		end)
		for i = 1, #GATE_X do
			hook("GateSchranke" .. i, function(pl)
				if prov.hasStaff(pl) or boarded[pl] == i then return true end
				if flights then
					for _, f in ipairs(flights.flightsAtGate(i)) do
						if prov.hasPass(pl, f.code) and flights.isBoardingOpen(f.code) then return true end
					end
				end
				return false
			end)
		end
		hook("StaffTuer1", function(pl)
			return prov.hasStaff(pl)
		end)
	end)

	Players.PlayerRemoving:Connect(function(pl)
		lastLegal[pl] = nil
		lastPos[pl] = nil
		boarded[pl] = nil
		lastToast[pl] = nil
	end)

	-- 10 Hz, nicht 60: Heartbeat mit Akkumulator
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc < 0.1 then return end
		acc = 0
		local ok, err = pcall(function()
			enforce()
			updateBarriers()
		end)
		if not ok then warn("[ZoneService] " .. tostring(err)) end
	end)
	print("[ZoneService] aktiv — " .. #zones .. " Zonen, Schranken folgen der Map.")
end

return Zone
