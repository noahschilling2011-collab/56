--[[
	FLUGHAFEN-JOB-SIMULATOR · Client (gesamte Spiellogik, Solo-Play)
	Drei Jobs: Check-in-Agent -> Ramp Agent (500 Cr) -> Captain (2000 Cr).
	Physik intern in Metern; Welt-Skalierung: 1 m = 2 Studs (M).
	KEIN DataStore — Fortschritt lebt nur im Speicher.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local M = 2 -- Meter -> Studs
local KT = 1.94384 -- m/s -> Knoten
local FT = 3.28084 -- m -> Fuss
local FPM = 196.85 -- m/s -> ft/min

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local airport = Workspace:WaitForChild("Airport", 30)
if not airport then error("Airport-Ordner fehlt — AirportServer-Script pruefen!") end

local function waitChar()
	local ch = player.Character or player.CharacterAdded:Wait()
	ch:WaitForChild("HumanoidRootPart")
	ch:WaitForChild("Humanoid")
	return ch
end
local character = waitChar()
player.CharacterAdded:Connect(function(ch)
	character = ch
end)

local function hrp() return character and character:FindFirstChild("HumanoidRootPart") end
local function humanoid() return character and character:FindFirstChildOfClass("Humanoid") end
-- Spielerposition in METERN
local function playerPosM()
	local r = hrp()
	if not r then return Vector3.new(0, 0, 0) end
	return r.Position / M
end

local function clamp(v, a, b) return math.min(b, math.max(a, v)) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, l, dt) return lerp(a, b, 1 - math.exp(-l * dt)) end
local function angNorm(a)
	while a > math.pi do a = a - 2 * math.pi end
	while a < -math.pi do a = a + 2 * math.pi end
	return a
end

---------------------------------------------------------------- Spielzustand
local S = {
	credits = 0, xp = 0,
	job = nil,          -- nil | "checkin" | "ramp" | "captain"
	mode = "walk",      -- walk | cart | fly
	tutorialSeen = {},
	camMode = "chase",  -- Flug: chase | cockpit
}
local UNLOCK_RAMP, UNLOCK_CAPTAIN = 500, 2000
local RWY_X1, RWY_X2, RWY_W = -750, 750, 30
local TDZ = { x1 = RWY_X1 + 60, x2 = RWY_X1 + 400 }

-- Wind: dir = woher (Grad), speed in m/s; vec = wohin er schiebt (m/s)
local wind = { dir = 210, speed = 2, vec = Vector3.new() }
local function setWind(dir, speedKt)
	wind.dir = dir
	wind.speed = speedKt / KT
	local to = math.rad(dir + 180)
	wind.vec = Vector3.new(math.sin(to) * wind.speed, 0, -math.cos(to) * wind.speed)
end
setWind(210, 4)

local FLIGHTS = {
	{ code = "LH 452", dest = "MÜNCHEN", time = "14:20", status = "OPEN" },
	{ code = "AB 118", dest = "BERLIN", time = "14:35", status = "BOARDING" },
	{ code = "EW 771", dest = "WIEN", time = "14:50", status = "OPEN" },
	{ code = "FR 903", dest = "PARIS", time = "15:05", status = "CLOSED" },
	{ code = "KL 233", dest = "AMSTERDAM", time = "15:20", status = "OPEN" },
	{ code = "SK 660", dest = "OSLO", time = "15:40", status = "CLOSED" },
}
local function findFlight(code)
	for _, f in ipairs(FLIGHTS) do
		if f.code == code then return f end
	end
	return nil
end

---------------------------------------------------------------- Eingaben
local keys = {}
local keyEdge = {}
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		keys[input.KeyCode] = true
		keyEdge[input.KeyCode] = true
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		keys[input.KeyCode] = false
	end
end)
local function edge(kc)
	if keyEdge[kc] then keyEdge[kc] = false; return true end
	return false
end

---------------------------------------------------------------- GUI-Grundgeruest
local gui = Instance.new("ScreenGui")
gui.Name = "AirportHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local GLASS = Color3.fromRGB(12, 18, 30)
local TXT = Color3.fromRGB(232, 238, 247)
local GOLD = Color3.fromRGB(255, 215, 94)
local CYAN = Color3.fromRGB(94, 200, 255)
local GREEN = Color3.fromRGB(143, 232, 159)
local REDC = Color3.fromRGB(255, 99, 99)
local GREY = Color3.fromRGB(159, 180, 204)

local function frame(parent, pos, size, transp)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = GLASS
	f.BackgroundTransparency = transp or 0.25
	f.BorderSizePixel = 0
	f.Position = pos
	f.Size = size
	f.Parent = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = f
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(255, 255, 255); st.Transparency = 0.85; st.Parent = f
	return f
end
local function label(parent, text, pos, size, color, textSize, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Font = Enum.Font.Gotham
	l.Text = text
	l.TextColor3 = color or TXT
	l.TextSize = textSize or 15
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.RichText = true
	l.Parent = parent
	return l
end
local function button(parent, text, pos, size, color, cb)
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = color or Color3.fromRGB(50, 90, 130)
	b.BackgroundTransparency = 0.2
	b.Position = pos
	b.Size = size
	b.Font = Enum.Font.GothamBold
	b.Text = text
	b.TextColor3 = TXT
	b.TextSize = 15
	b.Parent = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 9); c.Parent = b
	if cb then b.MouseButton1Click:Connect(cb) end
	return b
end

-- Oben links: Credits / Level / Fortschritt
local tl = frame(gui, UDim2.new(0, 14, 0, 14), UDim2.new(0, 250, 0, 96))
local creditsL = label(tl, "0 Credits", UDim2.new(0, 14, 0, 8), UDim2.new(1, -28, 0, 26), GOLD, 22)
creditsL.Font = Enum.Font.GothamBold
local levelL = label(tl, "Level 1 · 0 XP", UDim2.new(0, 14, 0, 36), UDim2.new(1, -28, 0, 18), GREY, 13)
local progressL = label(tl, "", UDim2.new(0, 14, 0, 62), UDim2.new(1, -28, 0, 30), GREEN, 13)

-- Oben rechts: Job / Ziel / Timer
local tr = frame(gui, UDim2.new(1, -334, 0, 14), UDim2.new(0, 320, 0, 110))
local jobL = label(tr, "Arbeitslos", UDim2.new(0, 14, 0, 8), UDim2.new(1, -28, 0, 22), CYAN, 16, Enum.TextXAlignment.Right)
jobL.Font = Enum.Font.GothamBold
local objL = label(tr, "", UDim2.new(0, 14, 0, 32), UDim2.new(1, -28, 0, 50), TXT, 13, Enum.TextXAlignment.Right)
local timerL = label(tr, "", UDim2.new(0, 14, 0, 82), UDim2.new(1, -28, 0, 24), GOLD, 20, Enum.TextXAlignment.Right)
timerL.Font = Enum.Font.GothamBold

-- Interaktions-Prompt
local promptF = frame(gui, UDim2.new(0.5, -180, 1, -150), UDim2.new(0, 360, 0, 38))
local promptL = label(promptF, "", UDim2.new(0, 10, 0, 0), UDim2.new(1, -20, 1, 0), TXT, 15, Enum.TextXAlignment.Center)
promptF.Visible = false

-- Toasts
local toastHolder = Instance.new("Frame")
toastHolder.BackgroundTransparency = 1
toastHolder.Position = UDim2.new(0.5, -220, 1, -240)
toastHolder.Size = UDim2.new(0, 440, 0, 90)
toastHolder.Parent = gui
local function toast(msg, kind)
	local col = kind == "good" and GREEN or kind == "bad" and REDC or TXT
	local f = frame(toastHolder, UDim2.new(0, 0, 1, -30), UDim2.new(1, 0, 0, 28))
	label(f, msg, UDim2.new(0, 10, 0, 0), UDim2.new(1, -20, 1, 0), col, 14, Enum.TextXAlignment.Center)
	for _, child in ipairs(toastHolder:GetChildren()) do
		if child ~= f and child:IsA("Frame") then
			child.Position = child.Position - UDim2.new(0, 0, 0, 32)
		end
	end
	task.delay(3, function() f:Destroy() end)
end

-- Steuerungs-Legende (H)
local legend = frame(gui, UDim2.new(0, 14, 1, -132), UDim2.new(0, 430, 0, 118))
label(legend,
	"<b>WASD</b> Bewegen · <b>Shift</b> Sprint · <b>E</b> Interagieren · <b>H</b> Legende\n" ..
	"FLUG: <b>W/S</b> Pitch · <b>A/D</b> Roll · <b>Q/E</b> Ruder/Bugrad\n" ..
	"<b>Shift/Strg(X)</b> Schub · <b>G</b> Fahrwerk · <b>F</b> Klappen · <b>B</b> Bremse · <b>C</b> Kamera · <b>R</b> Reset",
	UDim2.new(0, 14, 0, 8), UDim2.new(1, -28, 1, -16), GREY, 14)

-- Modales Panel
local panelWrap = Instance.new("Frame")
panelWrap.BackgroundColor3 = Color3.new(0, 0, 0)
panelWrap.BackgroundTransparency = 0.5
panelWrap.Size = UDim2.fromScale(1, 1)
panelWrap.Visible = false
panelWrap.ZIndex = 5
panelWrap.Parent = gui
local panel = frame(panelWrap, UDim2.new(0.5, -240, 0.5, -220), UDim2.new(0, 480, 0, 440), 0.12)
panel.ZIndex = 6
local panelOpen = false
local function clearPanel()
	for _, c in ipairs(panel:GetChildren()) do
		if c:IsA("TextLabel") or c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
	end
end
local function showPanel(build)
	clearPanel()
	panelOpen = true
	panelWrap.Visible = true
	build(panel)
end
local function hidePanel()
	panelOpen = false
	panelWrap.Visible = false
end

-- Tutorial-Overlay (einmal pro Job)
local function showTutorial(key, title, body, cb)
	if S.tutorialSeen[key] then if cb then cb() end return end
	S.tutorialSeen[key] = true
	showPanel(function(p)
		local t = label(p, title, UDim2.new(0, 20, 0, 14), UDim2.new(1, -40, 0, 26), GOLD, 20)
		t.Font = Enum.Font.GothamBold
		label(p, body, UDim2.new(0, 20, 0, 48), UDim2.new(1, -40, 1, -120), TXT, 14)
		button(p, "Los geht's!", UDim2.new(0, 20, 1, -56), UDim2.new(0, 150, 0, 40), Color3.fromRGB(40, 110, 60), function()
			hidePanel()
			if cb then cb() end
		end)
	end)
end

---------------------------------------------------------------- HUD-Werte
local function level() return math.floor(S.xp / 100) + 1 end
local function updateHUD()
	creditsL.Text = S.credits .. " Credits"
	levelL.Text = "Level " .. level() .. " · " .. S.xp .. " XP"
	if S.credits < UNLOCK_RAMP then
		progressL.Text = "Noch " .. (UNLOCK_RAMP - S.credits) .. " Credits bis Ramp Agent"
	elseif S.credits < UNLOCK_CAPTAIN then
		progressL.Text = "Noch " .. (UNLOCK_CAPTAIN - S.credits) .. " Credits bis Captain"
	else
		progressL.Text = "Alle Jobs freigeschaltet ✈"
	end
end
local function addCredits(n)
	S.credits = math.max(0, S.credits + n)
	updateHUD()
end
local function addXP(n)
	S.xp = S.xp + n
	updateHUD()
end
local function setJobHUD(name, objective)
	jobL.Text = name
	objL.Text = objective
end
local function setTimerHUD(sec)
	if not sec then timerL.Text = "" return end
	local m = math.floor(sec / 60)
	local s = math.floor(sec % 60)
	timerL.Text = string.format("%d:%02d", m, s)
	timerL.TextColor3 = sec < 20 and REDC or GOLD
end

---------------------------------------------------------------- Interaktionssystem (E)
local interactables = {}
local function addInteract(o) table.insert(interactables, o) end
local function updateInteract()
	if panelOpen or S.mode ~= "walk" then
		if S.mode == "fly" then promptF.Visible = false end
		return
	end
	local pp = playerPosM()
	local best, bd = nil, 1e9
	for _, it in ipairs(interactables) do
		if not it.cond or it.cond() then
			local x, z = it.x(), it.z()
			local d = math.sqrt((pp.X - x) ^ 2 + (pp.Z - z) ^ 2)
			if d < it.r and d < bd then bd = d; best = it end
		end
	end
	if best then
		promptL.Text = "[E]  " .. best.label()
		promptF.Visible = true
		if edge(Enum.KeyCode.E) then best.action() end
	else
		promptF.Visible = false
	end
end

---------------------------------------------------------------- Charakter-Extras
local function setCharacterHidden(hidden)
	local ch = character
	if not ch then return end
	for _, d in ipairs(ch:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = hidden and 1 or 0
		elseif d:IsA("Decal") then -- sonst schwebt das Gesicht sichtbar mit
			d.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
	local h = humanoid()
	if h then h.PlatformStand = hidden end
	local r = hrp()
	if r then r.Anchored = hidden end
end
-- Respawn mitten im Fahren/Fliegen: neuen Charakter wieder verstecken/verankern
player.CharacterAdded:Connect(function(ch)
	task.defer(function()
		ch:WaitForChild("HumanoidRootPart")
		ch:WaitForChild("Humanoid")
		if S.mode ~= "walk" then
			setCharacterHidden(true)
		end
	end)
end)
-- Sprint
RunService.RenderStepped:Connect(function()
	local h = humanoid()
	if h and S.mode == "walk" then
		h.WalkSpeed = (keys[Enum.KeyCode.LeftShift] or keys[Enum.KeyCode.RightShift]) and 24 or 16
	end
end)

---------------------------------------------------------------- NPC-Dummy (fuer Check-in)
local function makeNPC()
	local m = Instance.new("Model")
	m.Name = "PassengerNPC"
	local cols = {
		Color3.fromRGB(201, 79, 79), Color3.fromRGB(79, 127, 201),
		Color3.fromRGB(88, 168, 106), Color3.fromRGB(201, 164, 79), Color3.fromRGB(141, 95, 201),
	}
	local shirt = cols[math.random(#cols)]
	local function np(name, sx, sy, sz, x, y, z, color)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.Material = Enum.Material.SmoothPlastic
		p.Size = Vector3.new(sx * M, sy * M, sz * M)
		p.CFrame = CFrame.new(x * M, y * M, z * M)
		p.Color = color
		p.Parent = m
		return p
	end
	local root = np("Root", 0.5, 0.5, 0.5, 0, 0, 0, shirt)
	root.Transparency = 1
	m.PrimaryPart = root
	np("LegL", 0.22, 0.75, 0.24, -0.14, 0.38, 0, Color3.fromRGB(51, 58, 68))
	np("LegR", 0.22, 0.75, 0.24, 0.14, 0.38, 0, Color3.fromRGB(51, 58, 68))
	np("Torso", 0.55, 0.72, 0.32, 0, 1.12, 0, shirt)
	np("ArmL", 0.16, 0.62, 0.18, -0.37, 1.12, 0, shirt)
	np("ArmR", 0.16, 0.62, 0.18, 0.37, 1.12, 0, shirt)
	local head = np("Head", 0.48, 0.48, 0.48, 0, 1.72, 0, Color3.fromRGB(232, 184, 143))
	head.Shape = Enum.PartType.Ball
	np("Bag", 0.55, 0.75, 0.3, 0.55, 0.45, 0, Color3.fromRGB(122, 48, 48))
	m.Parent = Workspace
	return m
end
-- NPC laeuft in Meter-Koordinaten zu Wegpunkten
local function npcStep(npc, wpts, state, dt, speed)
	local target = wpts[state.wp]
	if not target then return true end
	local cur = npc.PrimaryPart.Position / M
	local d = Vector3.new(target.X - cur.X, 0, target.Z - cur.Z)
	local dist = d.Magnitude
	if dist < 0.4 then
		state.wp = state.wp + 1
		return state.wp > #wpts
	end
	d = d.Unit
	local np = cur + d * (speed or 1.9) * dt
	local yaw = math.atan2(d.X, d.Z)
	local bob = math.abs(math.sin(os.clock() * 8)) * 0.06
	npc:PivotTo(CFrame.new(np.X * M, bob * M, np.Z * M) * CFrame.Angles(0, yaw + math.pi, 0))
	return false
end

---------------------------------------------------------------- JOB 1 · CHECK-IN
local NAMES = { "Anna Berger", "Jonas Weber", "Mia Schulz", "Leon Fischer", "Emma Wagner", "Paul Becker",
	"Lena Hoffmann", "Finn Schäfer", "Marie Koch", "Luca Bauer", "Sofia Richter", "Noah Klein",
	"Clara Wolf", "Elias Neumann", "Laura Schwarz", "Tim Zimmermann", "Nina Braun", "Jan Krüger" }

local checkin = { active = false, index = 0, correct = 0, earned = 0, npc = nil, npcState = "none", wpts = {}, wp = 1, current = nil, queue = {} }

local function genShiftCases()
	local open, closed = {}, {}
	for _, f in ipairs(FLIGHTS) do
		if f.status == "CLOSED" then table.insert(closed, f) else table.insert(open, f) end
	end
	local nErr = math.random(2, 3)
	local pool = { "name", "closed", "unknown", "overweight" }
	local types = {}
	for i = 1, nErr do table.insert(types, pool[math.random(4)]) end
	for i = nErr + 1, 8 do table.insert(types, "ok") end
	for i = #types, 2, -1 do
		local j = math.random(i)
		types[i], types[j] = types[j], types[i]
	end
	local used, cases = {}, {}
	for _, tp in ipairs(types) do
		local name
		repeat name = NAMES[math.random(#NAMES)] until not used[name]
		used[name] = true
		local c = { type = tp, name = name, passName = name, flight = open[math.random(#open)], weight = math.random(9, 22) }
		if tp == "name" then
			local other
			repeat other = NAMES[math.random(#NAMES)] until other ~= name
			c.passName = other
		elseif tp == "closed" and #closed > 0 then
			c.flight = closed[math.random(#closed)]
		elseif tp == "unknown" then
			c.flight = { code = "XQ " .. math.random(100, 999), dest = "LISSABON", time = "15:35", status = nil }
		elseif tp == "overweight" then
			c.weight = math.random(24, 32)
		end
		table.insert(cases, c)
	end
	return cases
end

local spawnPassenger -- forward
local function endCheckin()
	checkin.active = false
	S.job = nil
	local allOk = checkin.correct == 8
	if allOk then addCredits(100) end
	showPanel(function(p)
		local t = label(p, "Schicht beendet!", UDim2.new(0, 20, 0, 14), UDim2.new(1, -40, 0, 26), CYAN, 20)
		t.Font = Enum.Font.GothamBold
		label(p, checkin.correct .. " / 8 korrekt abgefertigt\nVerdient: " .. checkin.earned .. " Credits" ..
			(allOk and "\nPerfekte Schicht! +100 Bonus" or ""),
			UDim2.new(0, 20, 0, 52), UDim2.new(1, -40, 0, 90), TXT, 15)
		button(p, "Neue Schicht", UDim2.new(0, 20, 1, -56), UDim2.new(0, 150, 0, 40), Color3.fromRGB(40, 110, 60), function()
			hidePanel()
			startCheckin()
		end)
		button(p, "Feierabend", UDim2.new(0, 185, 1, -56), UDim2.new(0, 150, 0, 40), Color3.fromRGB(60, 70, 85), function()
			hidePanel()
			setJobHUD("Arbeitslos", "Such dir einen Job an einer leuchtenden Station.")
		end)
	end)
	setJobHUD("Arbeitslos", "Schicht vorbei.")
end

spawnPassenger = function()
	if checkin.index >= 8 then endCheckin() return end
	checkin.current = checkin.queue[checkin.index + 1]
	checkin.npc = makeNPC()
	checkin.npc:PivotTo(CFrame.new(-4 * M, 0, 297 * M))
	checkin.npcState = "walkin"
	checkin.wpts = { Vector3.new(-25, 0, 288), Vector3.new(-45, 0, 250), Vector3.new(-45, 0, 255.2) }
	checkin.wp = 1
	setJobHUD("CHECK-IN-AGENT", "Passagier " .. (checkin.index + 1) .. "/8 kommt zum Schalter …")
end

function startCheckin()
	checkin.active = true
	checkin.index = 0; checkin.correct = 0; checkin.earned = 0
	checkin.queue = genShiftCases()
	S.job = "checkin"
	setJobHUD("CHECK-IN-AGENT", "Fertige 8 Passagiere ab.\nPrüfe Name, Flug & Gepäckgewicht!")
	spawnPassenger()
end

local function resolveCheckin(action)
	hidePanel()
	local c = checkin.current
	local bf = findFlight(c.flight.code)
	local docsOk = c.passName == c.name and bf ~= nil and bf.status ~= "CLOSED"
	local correct, reason
	if not docsOk then
		correct = action == "reject"
		if c.passName ~= c.name then reason = "Name auf Pass und Ticket stimmen nicht überein!"
		elseif not bf then reason = "Diesen Flug gibt es gar nicht!"
		else reason = "Der Flug ist bereits geschlossen!" end
	elseif c.weight > 23 then
		correct = action == "fee"
		reason = "Übergepäck (" .. c.weight .. " kg) – Gebühr fällig."
	else
		correct = action == "accept"
		reason = "Alles in Ordnung – Passagier war gültig."
	end
	if correct then
		local pay = 60 + (action == "fee" and 50 or 0)
		checkin.correct = checkin.correct + 1
		checkin.earned = checkin.earned + pay
		addCredits(pay); addXP(12)
		toast("✔ Richtig! +" .. pay .. " Credits · " .. reason, "good")
	else
		addCredits(-40)
		toast("✘ Falsch! −40 Credits · " .. reason, "bad")
	end
	local leaveTo = (docsOk and (action == "accept" or action == "fee")) and Vector3.new(34, 0, 250) or Vector3.new(-4, 0, 299)
	checkin.wpts = { Vector3.new(-38, 0, 250), leaveTo }
	checkin.wp = 1
	checkin.npcState = "leave"
end

local function openCheckinPanel()
	local c = checkin.current
	local bf = findFlight(c.flight.code)
	local boardTxt
	if bf then
		boardTxt = bf.code .. " → " .. bf.dest .. " · " .. bf.time .. " · " .. bf.status
	else
		boardTxt = "Flug nicht auf der Tafel!"
	end
	showPanel(function(p)
		local t = label(p, "Passagier " .. (checkin.index + 1) .. "/8", UDim2.new(0, 20, 0, 12), UDim2.new(1, -40, 0, 24), CYAN, 19)
		t.Font = Enum.Font.GothamBold
		label(p, "✈ TICKET", UDim2.new(0, 20, 0, 44), UDim2.new(0, 210, 0, 16), GREY, 12)
		label(p, c.name .. "\nFlug " .. c.flight.code .. " nach " .. c.flight.dest .. "\nAbflug " .. c.flight.time,
			UDim2.new(0, 20, 0, 62), UDim2.new(0, 210, 0, 62), TXT, 14)
		label(p, "🛂 REISEPASS", UDim2.new(0, 250, 0, 44), UDim2.new(0, 200, 0, 16), GREY, 12)
		label(p, c.passName .. "\nGültig · Foto passt", UDim2.new(0, 250, 0, 62), UDim2.new(0, 200, 0, 62), TXT, 14)
		label(p, "🧳 GEPÄCK AUF DER WAAGE", UDim2.new(0, 20, 0, 134), UDim2.new(1, -40, 0, 16), GREY, 12)
		label(p, c.weight .. " kg  (Freigepäck: 23 kg" .. (c.weight > 23 and (" · " .. (c.weight - 23) .. " kg zu viel!") or "") .. ")",
			UDim2.new(0, 20, 0, 152), UDim2.new(1, -40, 0, 22), c.weight > 23 and REDC or GREEN, 15)
		label(p, "🖥 ABFLUGTAFEL SAGT", UDim2.new(0, 20, 0, 186), UDim2.new(1, -40, 0, 16), GREY, 12)
		label(p, boardTxt, UDim2.new(0, 20, 0, 204), UDim2.new(1, -40, 0, 22),
			(bf and bf.status ~= "CLOSED") and GREEN or REDC, 15)
		button(p, "Einchecken", UDim2.new(0, 20, 1, -60), UDim2.new(0, 135, 0, 42), Color3.fromRGB(40, 110, 60), function()
			resolveCheckin("accept")
		end)
		if c.weight > 23 then
			button(p, "Gebühr (50 Cr) + Check-in", UDim2.new(0, 165, 1, -60), UDim2.new(0, 175, 0, 42), Color3.fromRGB(140, 110, 30), function()
				resolveCheckin("fee")
			end)
		end
		button(p, "Abweisen", UDim2.new(1, -140, 1, -60), UDim2.new(0, 120, 0, 42), Color3.fromRGB(130, 50, 50), function()
			resolveCheckin("reject")
		end)
	end)
end

local function updateCheckin(dt)
	if not checkin.active or not checkin.npc then return end
	if checkin.npcState == "walkin" then
		if npcStep(checkin.npc, checkin.wpts, checkin, dt) then
			checkin.npcState = "waiting"
			setJobHUD("CHECK-IN-AGENT", "Passagier " .. (checkin.index + 1) .. "/8 wartet.\nGeh hinter den Schalter und drücke E.")
		end
	elseif checkin.npcState == "leave" then
		if npcStep(checkin.npc, checkin.wpts, checkin, dt, 2.2) then
			checkin.npc:Destroy()
			checkin.npc = nil
			checkin.index = checkin.index + 1
			task.delay(0.7, spawnPassenger)
		end
	end
end

---------------------------------------------------------------- JOB 2 · RAMP AGENT
local JETS = {
	{ name = "LH 452 · MÜNCHEN", color = Color3.fromRGB(58, 111, 232), x = -40, z = 165 },
	{ name = "EW 771 · WIEN", color = Color3.fromRGB(224, 120, 32), x = 40, z = 165 },
}
local BELT = { x = -20, z1 = 255, z2 = 196 }
local ramp = { active = false, cases = {}, spawned = 0, delivered = 0, deliveredOk = 0, timer = 0, carrying = nil, spawnT = 0, collideCd = 0, nextSlot = 0 }

local function makeCase(jetIdx)
	local p = Instance.new("Part")
	p.Name = "Suitcase"
	p.Anchored = true
	p.CanCollide = false
	p.Material = Enum.Material.SmoothPlastic
	p.Size = Vector3.new(0.72 * M, 0.52 * M, 0.44 * M)
	p.Color = JETS[jetIdx].color
	p.CFrame = CFrame.new(BELT.x * M, 1.35 * M, (BELT.z1 - 1) * M)
	p.Parent = Workspace
	return { obj = p, jetIdx = jetIdx, state = "belt", beltZ = BELT.z1 - 1 }
end

local function nearestCase()
	local pp = playerPosM()
	local best, bd = nil, 2.6
	for _, c in ipairs(ramp.cases) do
		if c.state == "queue" then
			local cp = c.obj.Position / M
			local d = math.sqrt((pp.X - cp.X) ^ 2 + (pp.Z - cp.Z) ^ 2)
			if d < bd then bd = d; best = c end
		end
	end
	return best
end

local function removeCase(c)
	c.obj:Destroy()
	for i, cc in ipairs(ramp.cases) do
		if cc == c then table.remove(ramp.cases, i) break end
	end
end

-- Gepaeckwagen-Zustand (kinematisch, Meter)
local cartModel = airport:WaitForChild("Cart")
cartModel:WaitForChild("Root") -- PrimaryPart muss repliziert sein, sonst stimmt der Pivot nicht
cartModel:WaitForChild("Wheel")
local cart = { pos = cartModel:GetPivot().Position / M, yaw = 0.4, vel = Vector3.new(), load = {} }
local CART_SLOTS = {}
for i = 0, 5 do
	table.insert(CART_SLOTS, Vector3.new((i % 2 == 0) and -0.6 or 0.6, 1.45, -(0.35 + math.floor(i / 2) * 1.0)))
end

local function deliverAtJet(jetIdx, items)
	local okPay, badPay = 0, 0
	for _, c in ipairs(items) do
		ramp.delivered = ramp.delivered + 1
		if c.jetIdx == jetIdx then
			ramp.deliveredOk = ramp.deliveredOk + 1
			okPay = okPay + 40
		else
			badPay = badPay + 30
		end
		removeCase(c)
	end
	if okPay > 0 then addCredits(okPay); addXP(math.floor(okPay / 5)); toast("✔ Gepäck verladen: +" .. okPay .. " Credits", "good") end
	if badPay > 0 then addCredits(-badPay); toast("✘ Falscher Flieger! −" .. badPay .. " Credits", "bad") end
end

local function endRamp()
	if not ramp.active then return end
	ramp.active = false
	S.job = nil
	setTimerHUD(nil)
	for _, c in ipairs(ramp.cases) do c.obj:Destroy() end
	ramp.cases = {}
	ramp.carrying = nil
	cart.load = {}
	local perfect = ramp.deliveredOk == 8
	local bonus = (perfect and ramp.timer > 0) and 80 or 0
	if bonus > 0 then addCredits(bonus) end
	showPanel(function(p)
		local t = label(p, "Gepäck-Welle beendet", UDim2.new(0, 20, 0, 14), UDim2.new(1, -40, 0, 26), CYAN, 20)
		t.Font = Enum.Font.GothamBold
		label(p, ramp.deliveredOk .. " / 8 Koffer richtig verladen" ..
			(bonus > 0 and ("\nRechtzeitig & fehlerfrei: +" .. bonus .. " Bonus!") or ""),
			UDim2.new(0, 20, 0, 52), UDim2.new(1, -40, 0, 70), TXT, 15)
		button(p, "Nächste Welle", UDim2.new(0, 20, 1, -56), UDim2.new(0, 150, 0, 40), Color3.fromRGB(40, 110, 60), function()
			hidePanel(); startRamp()
		end)
		button(p, "Feierabend", UDim2.new(0, 185, 1, -56), UDim2.new(0, 150, 0, 40), Color3.fromRGB(60, 70, 85), function()
			hidePanel()
			setJobHUD("Arbeitslos", "Such dir einen Job an einer leuchtenden Station.")
		end)
	end)
end

function startRamp()
	ramp.active = true
	ramp.cases = {}; ramp.spawned = 0; ramp.delivered = 0; ramp.deliveredOk = 0
	ramp.timer = 180; ramp.spawnT = 0; ramp.carrying = nil; ramp.nextSlot = 0
	cart.load = {}
	S.job = "ramp"
	setJobHUD("RAMP AGENT", "Bring 8 Koffer zu den richtigen Jets!\nBLAU → LH 452 (links) · ORANGE → EW 771 (rechts)")
end

local function updateRamp(dt)
	if not ramp.active then return end
	ramp.timer = ramp.timer - dt
	setTimerHUD(math.max(0, ramp.timer))
	if ramp.timer <= 0 then endRamp() return end
	if ramp.spawned < 8 then
		ramp.spawnT = ramp.spawnT - dt
		if ramp.spawnT <= 0 then
			table.insert(ramp.cases, makeCase(math.random(1, 2)))
			ramp.spawned = ramp.spawned + 1
			ramp.spawnT = 5
		end
	end
	-- feste Warteschlangen-Plaetze: aufgenommene Koffer geben ihren Platz nicht frei
	for _, c in ipairs(ramp.cases) do
		if c.state == "belt" then
			c.beltZ = c.beltZ - 2.5 * dt
			local stopZ = BELT.z2 + 1 + ramp.nextSlot * 1.1
			if c.beltZ <= stopZ then
				c.beltZ = stopZ
				c.state = "queue"
				ramp.nextSlot = ramp.nextSlot + 1
			end
			c.obj.CFrame = CFrame.new(BELT.x * M, 1.35 * M, c.beltZ * M)
		end
	end
	if ramp.delivered >= 8 then endRamp() end
end

---------------------------------------------------------------- Gepaeckwagen fahren
-- 2D-Kollisionsboxen in Metern {x1,z1,x2,z2}: A380-Ruempfe/-Triebwerke, Stand, Tower, Hangar
local CART_COLLIDERS = {
	{ 124, 158, 136, 172 },   -- Spieler-Flugzeug
	{ -134, 246, -126, 254 }, -- Tower
	{ 211, 185, 249, 215 },   -- Hangar
	{ -47, 156, -42, 159 },   -- Boarding-Treppe
}
for _, jx in ipairs({ -40, 40 }) do
	table.insert(CART_COLLIDERS, { jx - 3.4, 165 - 19.5, jx + 3.4, 165 + 23 }) -- Rumpf
	for _, sx in ipairs({ -1, 1 }) do
		for _, e in ipairs({ { 7.2, 4.6 }, { 13.5, 8.4 } }) do
			table.insert(CART_COLLIDERS, { jx + sx * e[1] - 1.5, 165 + e[2] - 2.2, jx + sx * e[1] + 1.5, 165 + e[2] + 2.2 })
		end
	end
end
local function cartCollide(pos, r)
	local hit = false
	local x, z = pos.X, pos.Z
	for _, c in ipairs(CART_COLLIDERS) do
		local nx = clamp(x, c[1], c[3])
		local nz = clamp(z, c[2], c[4])
		local dx, dz = x - nx, z - nz
		local d2 = dx * dx + dz * dz
		if d2 < r * r then
			local d = math.sqrt(d2)
			if d < 0.001 then dx, d = 1, 1 end
			x = nx + dx / d * r
			z = nz + dz / d * r
			hit = true
		end
	end
	return Vector3.new(x, pos.Y, z), hit
end

local function enterCart()
	S.mode = "cart"
	setCharacterHidden(true)
	camera.CameraType = Enum.CameraType.Scriptable
end
local function exitCart()
	S.mode = "walk"
	setCharacterHidden(false)
	camera.CameraType = Enum.CameraType.Custom
	local f = Vector3.new(math.sin(cart.yaw), 0, math.cos(cart.yaw))
	local side = Vector3.new(-f.Z, 0, f.X)
	local out = (cart.pos + side * 2.4) * M
	local r = hrp()
	if r then r.CFrame = CFrame.new(out.X, 3.2, out.Z) end
end

local function updateCart(dt)
	if S.mode ~= "cart" then
		cart.vel = cart.vel * math.exp(-2 * dt)
		return
	end
	local fwd = Vector3.new(math.sin(cart.yaw), 0, math.cos(cart.yaw))
	local right = Vector3.new(fwd.Z, 0, -fwd.X)
	local acc = 0
	if keys[Enum.KeyCode.W] then acc = acc + 7 end
	if keys[Enum.KeyCode.S] then acc = acc - 5 end
	cart.vel = cart.vel + fwd * acc * dt
	local fs = cart.vel:Dot(fwd)
	local ls = cart.vel:Dot(right)
	local steer = 0
	if keys[Enum.KeyCode.A] then steer = steer + 1 end
	if keys[Enum.KeyCode.D] then steer = steer - 1 end
	cart.yaw = cart.yaw + steer * 1.7 * clamp(fs / 5, -1, 1) * dt
	ls = ls * math.exp(-3.2 * dt)           -- leichtes Driften
	fs = clamp(fs * math.exp(-0.55 * dt), -5, 11)
	local f2 = Vector3.new(math.sin(cart.yaw), 0, math.cos(cart.yaw))
	local r2 = Vector3.new(f2.Z, 0, -f2.X)
	local speedBefore = cart.vel.Magnitude
	cart.vel = f2 * fs + r2 * ls
	cart.pos = cart.pos + cart.vel * dt
	cart.pos = Vector3.new(clamp(cart.pos.X, -800, 800), 0, clamp(cart.pos.Z, -60, 228))
	if ramp.collideCd > 0 then ramp.collideCd = ramp.collideCd - dt end
	local newPos, hit = cartCollide(cart.pos, 1.6)
	if hit then
		cart.pos = newPos
		local nearJet = false
		for _, j in ipairs(JETS) do
			if math.sqrt((cart.pos.X - j.x) ^ 2 + (cart.pos.Z - j.z) ^ 2) < 32 then nearJet = true end
		end
		if nearJet and speedBefore > 4 and ramp.collideCd <= 0 then
			ramp.collideCd = 3
			addCredits(-30)
			toast("💥 Kollision mit dem Flugzeug! −30 Credits", "bad")
		end
		cart.vel = cart.vel * -0.25
	end
	cartModel:PivotTo(CFrame.new(cart.pos * M) * CFrame.Angles(0, cart.yaw, 0))
	-- Koffer auf der Ladeflaeche mitbewegen
	local pivot = cartModel:GetPivot()
	for i, c in ipairs(cart.load) do
		local s = CART_SLOTS[i]
		c.obj.CFrame = pivot * CFrame.new(s.X * M, s.Y * M, s.Z * M)
	end
	-- Charakter unsichtbar am Wagen halten
	local r = hrp()
	if r then r.CFrame = pivot * CFrame.new(0, 2 * M, 1.6 * M) end
	-- Kamera-Verfolger (hinter dem Wagen: Fahrtrichtung ist lokal +Z)
	local camPos = pivot * CFrame.new(0, 4.5 * M, -11 * M)
	camera.CFrame = CFrame.lookAt(camPos.Position, pivot.Position + Vector3.new(0, 1.5 * M, 0))
	-- E-Logik im Wagen: abladen oder aussteigen
	local nearJetIdx = nil
	for i, j in ipairs(JETS) do
		if math.sqrt((cart.pos.X - j.x) ^ 2 + (cart.pos.Z - j.z) ^ 2) < 24 then nearJetIdx = i end
	end
	if nearJetIdx and #cart.load > 0 then
		promptL.Text = "[E]  Gepäck abladen bei " .. JETS[nearJetIdx].name
		promptF.Visible = true
		if edge(Enum.KeyCode.E) then
			local items = {}
			for _, c in ipairs(cart.load) do table.insert(items, c) end
			cart.load = {}
			deliverAtJet(nearJetIdx, items)
		end
	else
		promptL.Text = "[E]  Aussteigen"
		promptF.Visible = true
		if edge(Enum.KeyCode.E) then exitCart() end
	end
end

---------------------------------------------------------------- JOB 3 · CAPTAIN — Flugphysik
local planeModel = airport:WaitForChild("PlayerPlane")
-- Auf vollstaendige Replikation warten: Root zuerst, GearRP wird zuletzt gebaut
planeModel:WaitForChild("Root")
planeModel:WaitForChild("GearRP")
local basePivot = planeModel:GetPivot()
local partOffsets = {}
for _, p in ipairs(planeModel:GetChildren()) do
	if p:IsA("BasePart") then
		partOffsets[p] = basePivot:ToObjectSpace(p.CFrame)
	end
end
local PLANE_STAND = { x = 130, z = 165, yaw = math.pi }

local plane = {
	pos = Vector3.new(130, 0, 165), vel = Vector3.new(),
	yaw = math.pi, pitch = 0, roll = 0,
	throttle = 0, gearDown = true, gearAnim = 1, brake = false,
	flaps = 0, flapAnim = 0, -- Klappen: 0°/15°/35°
	onGround = true, stalled = false, propSpin = 0,
	ctl = { pitch = 0, roll = 0, yaw = 0 },
}
local PHYS = { thrustAcc = 7.6, drag0 = 0.0021, liftK = 0.0098, stallKt = 50, rotateKt = 55 }

local function planeCF()
	return CFrame.new(plane.pos.X * M, plane.pos.Y * M, plane.pos.Z * M)
		* CFrame.fromEulerAnglesYXZ(plane.pitch, plane.yaw, -plane.roll)
end
local function planeHeading()
	local h = math.deg(-plane.yaw) % 360
	if h < 0 then h = h + 360 end
	return h
end

local GEAR_HINGES = {}
for _, g in ipairs({ { "GearN", 0, -2.15 }, { "GearL", -1.15, 0.45 }, { "GearR", 1.15, 0.45 } }) do
	local h = Vector3.new(g[2], 1.16, g[3])
	GEAR_HINGES[g[1]] = h
	GEAR_HINGES[g[1] .. "W"] = h
	GEAR_HINGES[g[1] .. "P"] = h
end
local PROP_HUB = CFrame.new(0, 1.32 * M, -3.02 * M)

local function syncPlaneMesh()
	local cf = planeCF()
	local propRot = CFrame.Angles(0, 0, plane.propSpin)
	local gearRot = CFrame.Angles((1 - plane.gearAnim) * 1.9, 0, 0)
	local rpmN = plane.throttle / 100
	local blink = (os.clock() % 1.1) < 0.09
	for p, off in pairs(partOffsets) do
		local n = p.Name
		if n == "Prop1" or n == "Prop2" then
			p.CFrame = cf * PROP_HUB * propRot * PROP_HUB:Inverse() * off
			p.Transparency = rpmN >= 0.45 and 1 or 0 -- Prop-Blur: Blaetter ausblenden
		elseif n == "PropDisc" then
			p.CFrame = cf * off
			p.Transparency = 1 - math.clamp((rpmN - 0.25) * 0.9, 0, 0.4)
		elseif n == "Beacon" then
			p.CFrame = cf * off
			p.Transparency = blink and 0 or 0.85
		elseif n == "FlapL" or n == "FlapR" then
			p.CFrame = cf * off * CFrame.Angles(plane.flapAnim * 0.3, 0, 0)
		elseif GEAR_HINGES[n] then
			local h = GEAR_HINGES[n]
			local hc = CFrame.new(h.X * M, h.Y * M, h.Z * M)
			p.CFrame = cf * hc * gearRot * hc:Inverse() * off
			p.Transparency = plane.gearAnim < 0.05 and 1 or 0
		elseif n == "AilL" then
			-- Hinterkante +Z: positiver Winkel = Kante runter; rechts hoch bei Rechtsrolle
			p.CFrame = cf * off * CFrame.Angles(plane.ctl.roll * 0.55, 0, 0)
		elseif n == "AilR" then
			p.CFrame = cf * off * CFrame.Angles(-plane.ctl.roll * 0.55, 0, 0)
		elseif n == "Elev" then
			p.CFrame = cf * off * CFrame.Angles(-plane.ctl.pitch * 0.55, 0, 0)
		elseif n == "Rud" then
			p.CFrame = cf * off * CFrame.Angles(0, plane.ctl.yaw * 0.6, 0)
		else
			p.CFrame = cf * off
		end
	end
	-- Charakter unsichtbar mitfuehren
	if S.mode == "fly" then
		local r = hrp()
		if r then r.CFrame = cf * CFrame.new(0, 2 * M, 0) end
	end
	return cf
end

local function resetPlaneToStand()
	plane.pos = Vector3.new(PLANE_STAND.x, 0, PLANE_STAND.z)
	plane.vel = Vector3.new()
	plane.yaw = PLANE_STAND.yaw; plane.pitch = 0; plane.roll = 0
	plane.throttle = 0; plane.gearDown = true; plane.gearAnim = 1
	plane.flaps = 0; plane.flapAnim = 0
	plane.onGround = true; plane.stalled = false
	plane.ctl.pitch = 0; plane.ctl.roll = 0; plane.ctl.yaw = 0
	syncPlaneMesh()
end

---------------------------------------------------------------- PAPI
local papiModels = { { m = airport:WaitForChild("PAPI09"), x = -450, apprSign = -1 }, { m = airport:WaitForChild("PAPI27"), x = 450, apprSign = 1 } }
local function updatePapis()
	local px, py = plane.pos.X, plane.pos.Y
	for _, p in ipairs(papiModels) do
		local dist = (p.x - px) * -p.apprSign
		for i = 1, 4 do
			local lamp = p.m:FindFirstChild("Lamp" .. i)
			if lamp then
				local col = Color3.fromRGB(102, 102, 102)
				if dist > 60 and py > 2 then
					local ang = math.deg(math.atan2(py, dist))
					local th = ({ 3.5, 3.2, 2.8, 2.5 })[i]
					col = ang > th and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 34, 34)
				end
				lamp.Color = col
			end
		end
	end
end

---------------------------------------------------------------- Missionen
local MISSIONS = {
	{ name = "RUNDFLUG", base = 200, windDir = 240, windKt = 4,
		desc = "5 Checkpoint-Ringe rund um den Flughafen, dann landen. Wenig Wind.",
		rings = { { 500, -450, 140 }, { -150, -750, 190 }, { -850, -450, 220 }, { -900, 250, 180 }, { -100, 450, 130 } },
		tdzRequired = false, airStart = false },
	{ name = "PLATZRUNDE", base = 300, windDir = 150, windKt = 8,
		desc = "Traffic-Pattern auf ~800 ft: Querabflug → Gegenanflug → Queranflug → Endanflug, dann landen.",
		rings = { { 450, -350, 240 }, { -250, -650, 240 }, { -1000, -500, 220 }, { -1350, 0, 100 } },
		tdzRequired = false, airStart = false },
	{ name = "PRÄZISIONSLANDUNG", base = 500, windDir = 180, windKt = 16,
		desc = "Kurzer Endanflug bei 16 kt Seitenwind. Aufsetzen exakt in der Aufsetzzone!",
		rings = {}, tdzRequired = true, airStart = true },
}
local flight = { active = false, mIdx = 1, phase = "fly", wpIdx = 1, ringModels = {}, landed = false, landStats = nil }

local function clearRings()
	for _, r in ipairs(flight.ringModels) do r:Destroy() end
	flight.ringModels = {}
end
local function buildRings(mission)
	clearRings()
	local prevX, prevZ = RWY_X1 + 25, 0 -- Startpunkt: Runway-Schwelle
	for _, r in ipairs(mission.rings) do
		local x, z, y = r[1], r[2], r[3]
		-- Ring zur Anflugrichtung drehen (Kreis liegt lokal in der XY-Ebene)
		local phi = math.atan2(x - prevX, z - prevZ)
		prevX, prevZ = x, z
		local model = Instance.new("Model")
		model.Name = "Ring"
		for a = 0, 330, 30 do
			local rad = math.rad(a)
			local lx, ly = math.cos(rad) * 30, math.sin(rad) * 30
			local p = Instance.new("Part")
			p.Anchored = true
			p.CanCollide = false
			p.Material = Enum.Material.Neon
			p.Color = Color3.fromRGB(48, 213, 255)
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.new(4 * M, 4 * M, 4 * M)
			p.CFrame = CFrame.new((x + lx * math.cos(phi)) * M, (y + ly) * M, (z - lx * math.sin(phi)) * M)
			p.Parent = model
		end
		model.Parent = Workspace
		table.insert(flight.ringModels, model)
	end
end
local function currentTarget()
	local m = MISSIONS[flight.mIdx]
	if flight.phase == "fly" and flight.wpIdx <= #m.rings then
		local r = m.rings[flight.wpIdx]
		return Vector3.new(r[1], r[3], r[2])
	end
	return Vector3.new(TDZ.x1 + 80, 0, 0)
end
local function missionObjective()
	local m = MISSIONS[flight.mIdx]
	if flight.phase == "fly" then
		local names = m.name == "PLATZRUNDE" and { "Querabflug", "Gegenanflug", "Queranflug", "Endanflug" } or nil
		local lbl = names and names[flight.wpIdx] or ("Ring " .. flight.wpIdx .. "/" .. #m.rings)
		local extra = plane.onGround and "\nVollgas (Shift), bei 55 kt ziehen (S), Fahrwerk G!" or ""
		return "Nächster Wegpunkt: " .. lbl .. extra
	end
	return "Lande auf Runway 09" .. (m.tdzRequired and " – in der Aufsetzzone!" or "") .. "\nPAPI: 2× rot / 2× weiß = Gleitpfad."
end

-- Flug-HUD-Elemente (in Tabelle FH, haelt die Anzahl Top-Level-Locals klein)
local FH = {}
do
	local fhud = Instance.new("Frame")
	fhud.BackgroundTransparency = 1
	fhud.Size = UDim2.fromScale(1, 1)
	fhud.Visible = false
	fhud.Parent = gui
	FH.root = fhud
	local fSpd = frame(fhud, UDim2.new(0, 14, 0.5, -46), UDim2.new(0, 110, 0, 92))
	label(fSpd, "SPEED", UDim2.new(0, 0, 0, 8), UDim2.new(1, 0, 0, 14), GREY, 11, Enum.TextXAlignment.Center)
	FH.spdV = label(fSpd, "0", UDim2.new(0, 0, 0, 24), UDim2.new(1, 0, 0, 32), TXT, 26, Enum.TextXAlignment.Center)
	FH.spdV.Font = Enum.Font.GothamBold
	label(fSpd, "kt", UDim2.new(0, 0, 0, 60), UDim2.new(1, 0, 0, 16), GREY, 12, Enum.TextXAlignment.Center)
	local fAlt = frame(fhud, UDim2.new(1, -124, 0.5, -46), UDim2.new(0, 110, 0, 92))
	label(fAlt, "ALT (ft)", UDim2.new(0, 0, 0, 8), UDim2.new(1, 0, 0, 14), GREY, 11, Enum.TextXAlignment.Center)
	FH.altV = label(fAlt, "0", UDim2.new(0, 0, 0, 24), UDim2.new(1, 0, 0, 32), TXT, 26, Enum.TextXAlignment.Center)
	FH.altV.Font = Enum.Font.GothamBold
	FH.vsV = label(fAlt, "0 ft/min", UDim2.new(0, 0, 0, 60), UDim2.new(1, 0, 0, 16), GREY, 12, Enum.TextXAlignment.Center)
	local fHdg = frame(fhud, UDim2.new(0.5, -110, 0, 14), UDim2.new(0, 220, 0, 36))
	FH.hdgV = label(fHdg, "HDG 090°", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0), TXT, 18, Enum.TextXAlignment.Center)
	FH.hdgV.Font = Enum.Font.GothamBold
	local fWpt = frame(fhud, UDim2.new(0.5, -110, 0, 58), UDim2.new(0, 220, 0, 64))
	FH.arrow = label(fWpt, "▲", UDim2.new(0.5, -16, 0, 2), UDim2.new(0, 32, 0, 32), CYAN, 26, Enum.TextXAlignment.Center)
	FH.wptD = label(fWpt, "", UDim2.new(0, 0, 0, 38), UDim2.new(1, 0, 0, 20), TXT, 13, Enum.TextXAlignment.Center)
	local fBot = frame(fhud, UDim2.new(0.5, -245, 1, -66), UDim2.new(0, 490, 0, 52))
	FH.thrV = label(fBot, "SCHUB 0%", UDim2.new(0, 14, 0, 0), UDim2.new(0, 110, 1, 0), GREEN, 14)
	FH.gearV = label(fBot, "FAHRWERK ✓", UDim2.new(0, 130, 0, 0), UDim2.new(0, 130, 1, 0), GREEN, 14)
	FH.flapsV = label(fBot, "KLAPPEN 0°", UDim2.new(0, 265, 0, 0), UDim2.new(0, 105, 1, 0), TXT, 14)
	FH.windV = label(fBot, "WIND --", UDim2.new(0, 375, 0, 0), UDim2.new(0, 110, 1, 0), TXT, 14)
	FH.warn = label(fhud, "", UDim2.new(0.5, -200, 0.24, 0), UDim2.new(0, 400, 0, 70), REDC, 30, Enum.TextXAlignment.Center)
	FH.warn.Font = Enum.Font.GothamBlack
end

local function setFlightHUD(on)
	FH.root.Visible = on
	legend.Visible = true
end

local function endFlightToApron(msg)
	flight.active = false
	clearRings()
	setWind(210, 4)
	resetPlaneToStand()
	S.job = nil
	S.mode = "walk"
	setCharacterHidden(false)
	camera.CameraType = Enum.CameraType.Custom
	local r = hrp()
	if r then r.CFrame = CFrame.new(122 * M, 3.5, 174 * M) end
	for _, n in ipairs({ "GlassBand", "Windshield" }) do
		local part = planeModel:FindFirstChild(n)
		if part then part.LocalTransparencyModifier = 0 end
	end
	setFlightHUD(false)
	setJobHUD("Arbeitslos", "Such dir einen Job an einer leuchtenden Station.")
	if msg then toast(msg, "info") end
end

local function crash(reason)
	toast("💥 CRASH! " .. reason, "bad")
	flight.active = false
	showPanel(function(p)
		local t = label(p, "CRASH!", UDim2.new(0, 20, 0, 14), UDim2.new(1, -40, 0, 28), REDC, 22)
		t.Font = Enum.Font.GothamBold
		label(p, reason .. "\nMission fehlgeschlagen – keine Bezahlung.", UDim2.new(0, 20, 0, 52), UDim2.new(1, -40, 0, 60), TXT, 15)
		button(p, "Zurück zum Vorfeld", UDim2.new(0, 20, 1, -56), UDim2.new(0, 190, 0, 40), Color3.fromRGB(60, 70, 85), function()
			hidePanel()
			endFlightToApron()
		end)
	end)
end

local function handleTouchdown(vsFpm)
	local onRwy = math.abs(plane.pos.Z) <= RWY_W / 2 + 2 and plane.pos.X >= RWY_X1 - 15 and plane.pos.X <= RWY_X2 + 15
	local gearOk = plane.gearAnim > 0.92
	if not gearOk then crash("Landung ohne Fahrwerk!") return end
	if not onRwy then crash("Neben der Runway aufgesetzt!") return end
	if vsFpm > 1000 then crash("Aufschlag mit " .. math.floor(vsFpm) .. " ft/min!") return end
	if flight.active and flight.phase == "land" then
		flight.landed = true
		flight.landStats = {
			vsFpm = vsFpm,
			centerDev = math.abs(plane.pos.Z),
			inTDZ = plane.pos.X >= TDZ.x1 and plane.pos.X <= TDZ.x2,
		}
	elseif flight.active then
		toast("Aufgesetzt – aber erst alle Wegpunkte abfliegen!", "bad")
	end
end

local function rateLanding(st)
	local m = MISSIONS[flight.mIdx]
	local stars, notes = 5, {}
	if st.vsFpm < 200 then
		table.insert(notes, "🧈 Butterweich (" .. math.floor(st.vsFpm) .. " ft/min)")
	elseif st.vsFpm <= 600 then
		stars = stars - 1
		table.insert(notes, "Okay (" .. math.floor(st.vsFpm) .. " ft/min)")
	else
		stars = stars - 2
		table.insert(notes, "Hart! (" .. math.floor(st.vsFpm) .. " ft/min)")
	end
	if st.centerDev <= 3 then
		table.insert(notes, string.format("Perfekt auf der Centerline (%.1f m)", st.centerDev))
	elseif st.centerDev <= 7 then
		stars = stars - 1
		table.insert(notes, string.format("Leicht neben der Centerline (%.1f m)", st.centerDev))
	else
		stars = stars - 2
		table.insert(notes, string.format("Weit neben der Centerline (%.1f m)", st.centerDev))
	end
	if st.inTDZ then
		table.insert(notes, "Aufsetzzone getroffen ✔")
	else
		stars = stars - (m.tdzRequired and 2 or 1)
		table.insert(notes, "Aufsetzzone verfehlt ✘")
	end
	return clamp(stars, 1, 5), notes
end

local function completeMission()
	local m = MISSIONS[flight.mIdx]
	local stars, notes = rateLanding(flight.landStats)
	local pay = m.base * stars
	addCredits(pay)
	addXP(30 * stars)
	flight.active = false
	showPanel(function(p)
		local t = label(p, "Mission geschafft: " .. m.name, UDim2.new(0, 20, 0, 14), UDim2.new(1, -40, 0, 26), CYAN, 19)
		t.Font = Enum.Font.GothamBold
		local starTxt = string.rep("★", stars) .. string.rep("☆", 5 - stars)
		local sl = label(p, starTxt, UDim2.new(0, 20, 0, 46), UDim2.new(1, -40, 0, 40), GOLD, 32)
		sl.Font = Enum.Font.GothamBold
		label(p, table.concat(notes, "\n") .. "\n\n+" .. pay .. " Credits (" .. m.base .. " Basis × " .. stars .. " Sterne)",
			UDim2.new(0, 20, 0, 94), UDim2.new(1, -40, 0, 140), TXT, 15)
		button(p, "Zurück zum Vorfeld", UDim2.new(0, 20, 1, -56), UDim2.new(0, 190, 0, 40), Color3.fromRGB(40, 110, 60), function()
			hidePanel()
			endFlightToApron()
		end)
	end)
end

function startMission(i)
	hidePanel()
	local m = MISSIONS[i]
	flight.active = true; flight.mIdx = i; flight.wpIdx = 1
	flight.phase = #m.rings > 0 and "fly" or "land"
	flight.landed = false; flight.landStats = nil
	setWind(m.windDir, m.windKt)
	buildRings(m)
	S.job = "captain"
	S.mode = "fly"
	promptF.Visible = false -- E-Prompt der Station ausblenden
	setCharacterHidden(true)
	camera.CameraType = Enum.CameraType.Scriptable
	if m.airStart then
		plane.pos = Vector3.new(RWY_X1 - 1500, 115, 25)
		plane.yaw = -math.pi / 2; plane.pitch = 0; plane.roll = 0
		plane.throttle = 40; plane.gearDown = false; plane.gearAnim = 0
		plane.flaps = 2; plane.flapAnim = 2 -- Landeanflug: volle Klappen
		plane.onGround = false
		local cf = planeCF()
		plane.vel = cf.LookVector * 34 + wind.vec
	else
		plane.pos = Vector3.new(RWY_X1 + 25, 0, 0)
		plane.yaw = -math.pi / 2; plane.pitch = 0; plane.roll = 0
		plane.throttle = 0; plane.gearDown = true; plane.gearAnim = 1
		plane.flaps = 0; plane.flapAnim = 0
		plane.onGround = true
		plane.vel = Vector3.new()
	end
	syncPlaneMesh()
	FH.windV.Text = string.format("WIND %03d°/%dkt", m.windDir, m.windKt)
	setFlightHUD(true)
	setJobHUD("CAPTAIN · " .. m.name, missionObjective())
	toast("Mission gestartet: " .. m.name, "info")
end

local function openMissionSelect()
	showPanel(function(p)
		local t = label(p, "Missionsauswahl · Captain", UDim2.new(0, 20, 0, 12), UDim2.new(1, -40, 0, 24), CYAN, 19)
		t.Font = Enum.Font.GothamBold
		for i, m in ipairs(MISSIONS) do
			local y = 20 + i * 88
			local f = frame(p, UDim2.new(0, 16, 0, y), UDim2.new(1, -32, 0, 80), 0.4)
			f.ZIndex = 7
			local h = label(f, i .. ". " .. m.name .. "  ·  bis " .. (m.base * 5) .. " Cr", UDim2.new(0, 12, 0, 6), UDim2.new(1, -24, 0, 18), GOLD, 15)
			h.ZIndex = 8; h.Font = Enum.Font.GothamBold
			local d = label(f, m.desc .. string.format("  (Wind %03d°/%d kt)", m.windDir, m.windKt), UDim2.new(0, 12, 0, 26), UDim2.new(1, -24, 0, 50), TXT, 13)
			d.ZIndex = 8
			local b = button(f, "Start", UDim2.new(1, -70, 0, 24), UDim2.new(0, 58, 0, 32), Color3.fromRGB(40, 110, 60), function()
				startMission(i)
			end)
			b.ZIndex = 9
		end
		button(p, "Abbrechen", UDim2.new(0, 20, 1, -50), UDim2.new(0, 130, 0, 36), Color3.fromRGB(60, 70, 85), hidePanel)
	end)
end

---------------------------------------------------------------- Flugphysik-Update (deltaTime)
local function updateFlightPhysics(dt)
	local p = plane
	local tP = (keys[Enum.KeyCode.S] and 1 or 0) - (keys[Enum.KeyCode.W] and 1 or 0) -- S = ziehen
	local tR = (keys[Enum.KeyCode.D] and 1 or 0) - (keys[Enum.KeyCode.A] and 1 or 0)
	local tY = (keys[Enum.KeyCode.E] and 1 or 0) - (keys[Enum.KeyCode.Q] and 1 or 0)
	p.ctl.pitch = damp(p.ctl.pitch, tP, 6, dt)
	p.ctl.roll = damp(p.ctl.roll, tR, 6, dt)
	p.ctl.yaw = damp(p.ctl.yaw, tY, 6, dt)
	if keys[Enum.KeyCode.LeftShift] or keys[Enum.KeyCode.RightShift] then
		p.throttle = clamp(p.throttle + 45 * dt, 0, 100)
	end
	if keys[Enum.KeyCode.LeftControl] or keys[Enum.KeyCode.RightControl] or keys[Enum.KeyCode.X] then
		p.throttle = clamp(p.throttle - 45 * dt, 0, 100)
	end
	p.brake = keys[Enum.KeyCode.B] == true
	if edge(Enum.KeyCode.G) then
		if p.onGround and p.gearDown then
			toast("Fahrwerk am Boden nicht einfahrbar!", "bad")
		else
			p.gearDown = not p.gearDown
		end
	end
	p.gearAnim = clamp(p.gearAnim + (p.gearDown and 1 or -1) * dt / 1.2, 0, 1)
	-- Klappen F: 0° -> 15° -> 35° -> 0°
	if edge(Enum.KeyCode.F) then
		p.flaps = (p.flaps + 1) % 3
		toast("Klappen " .. ({ "eingefahren", "15°", "35°" })[p.flaps + 1], "info")
	end
	p.flapAnim = damp(p.flapAnim, p.flaps, 2.2, dt)

	local cf = planeCF()
	local fwd, up = cf.LookVector, cf.UpVector
	local vAir = p.vel - wind.vec
	local speed = vAir.Magnitude
	local kt = speed * KT
	local eff = clamp(kt / 75, 0, 1.35)

	if not p.onGround then
		local auth = p.stalled and 0.35 or 1
		p.roll = clamp(p.roll + p.ctl.roll * 2.0 * eff * auth * dt, -1.25, 1.25)
		p.pitch = clamp(p.pitch + p.ctl.pitch * 0.85 * eff * auth * dt, -0.7, 0.55)
		p.yaw = p.yaw - p.ctl.yaw * 0.55 * eff * dt
		if speed > 8 then
			p.yaw = p.yaw - math.tan(clamp(p.roll, -1.2, 1.2)) * 9.81 / math.max(speed, 18) * dt
		end
	else
		local gs = p.vel.Magnitude
		p.yaw = p.yaw + (-p.ctl.yaw) * 1.1 * clamp(gs / 4, 0, 1) * clamp(1.6 - gs / 26, 0.22, 1) * dt
		p.roll = damp(p.roll, 0, 6, dt)
		if kt >= PHYS.rotateKt and p.ctl.pitch > 0.15 then
			p.pitch = clamp(p.pitch + 0.55 * dt, 0, 0.28)
		else
			p.pitch = damp(p.pitch, 0, 4, dt)
		end
	end

	local acc = fwd * (p.throttle / 100 * PHYS.thrustAcc)
	local gamma = speed > 2 and math.asin(clamp(vAir.Y / speed, -1, 1)) or 0
	local aoa = p.pitch - gamma
	local cl = clamp(0.35 + 0.18 * p.flapAnim + aoa * 4.6, -0.6, 1.85)
	-- Klappen senken die Stallspeed
	p.stalled = (not p.onGround) and kt < (PHYS.stallKt - 4 * p.flapAnim) and p.pos.Y > 1.5
	if p.stalled then
		cl = cl * 0.45
		p.pitch = p.pitch - 0.7 * dt
		p.roll = p.roll + math.sin(os.clock() * 10) * 0.25 * dt
	end
	local liftAcc = clamp(cl * speed * speed * PHYS.liftK, -6, 26)
	-- Bodeneffekt nahe der Bahn
	if not p.onGround and p.pos.Y < 9 then
		liftAcc = liftAcc * (1 + 0.10 * (1 - p.pos.Y / 9))
	end
	acc = acc + up * liftAcc
	if speed > 0.5 then
		local dragK = PHYS.drag0 * (1 + 1.6 * cl * cl) + p.gearAnim * 0.0006 + p.flapAnim * 0.0011
		acc = acc - vAir.Unit * (dragK * speed * speed)
	end
	acc = acc + Vector3.new(0, -9.81, 0)

	vAir = vAir + acc * dt
	if not p.onGround then
		local hv = Vector3.new(vAir.X, 0, vAir.Z)
		local fh = Vector3.new(fwd.X, 0, fwd.Z)
		if fh.Magnitude > 0.01 then
			fh = fh.Unit
			local rh = Vector3.new(fh.Z, 0, -fh.X)
			local fs = hv:Dot(fh)
			local ss = hv:Dot(rh) * math.exp(-1.6 * dt)
			vAir = Vector3.new(fh.X * fs + rh.X * ss, vAir.Y, fh.Z * fs + rh.Z * ss)
		end
	end
	p.vel = vAir + wind.vec

	if p.onGround then
		local fh = Vector3.new(fwd.X, 0, fwd.Z).Unit
		local fs = p.vel:Dot(fh)
		local fr = 0.35 + (p.brake and 5.5 or 0)
		if fs > 0 then fs = math.max(0, fs - fr * dt) else fs = math.min(0, fs + fr * dt) end
		local vy = 0
		if liftAcc > 9.81 then vy = math.max(0, vAir.Y) end
		p.vel = fh * fs + Vector3.new(0, vy, 0)
	end

	p.pos = p.pos + p.vel * dt

	local gh = p.gearAnim > 0.5 and 0 or -0.55
	local sink = -p.vel.Y
	if p.pos.Y <= gh and p.vel.Y <= 0 then
		if not p.onGround then
			handleTouchdown(sink * FPM)
		end
		p.pos = Vector3.new(p.pos.X, gh, p.pos.Z)
		p.onGround = true
		p.vel = Vector3.new(p.vel.X, 0, p.vel.Z)
	elseif p.pos.Y > gh + 0.05 then
		p.onGround = false
	end

	p.propSpin = p.propSpin + (2 + p.throttle * 0.55) * dt * 10
	syncPlaneMesh()
	updatePapis()
end

local function updateMission(dt)
	if not flight.active then return end
	local m = MISSIONS[flight.mIdx]
	if flight.phase == "fly" then
		local t = currentTarget()
		if (plane.pos - t).Magnitude < 45 then
			local ring = flight.ringModels[flight.wpIdx]
			if ring then
				for _, part in ipairs(ring:GetChildren()) do
					part.Color = Color3.fromRGB(84, 208, 106)
					part.Transparency = 0.7
				end
			end
			flight.wpIdx = flight.wpIdx + 1
			if flight.wpIdx > #m.rings then
				flight.phase = "land"
				toast("Alle Wegpunkte! Jetzt landen – Runway 09.", "good")
			else
				toast("Wegpunkt " .. (flight.wpIdx - 1) .. "/" .. #m.rings .. " ✔", "good")
			end
			setJobHUD("CAPTAIN · " .. m.name, missionObjective())
		end
	elseif flight.landed then
		if plane.onGround and plane.vel.Magnitude < 2.5 then
			flight.landed = false
			completeMission()
		elseif not plane.onGround and plane.pos.Y > 8 then
			flight.landed = false
		end
	end
	if edge(Enum.KeyCode.R) then
		endFlightToApron("Mission abgebrochen – zurück am Vorfeld.")
	end
end

local function updateFlightHUD()
	local vAir = plane.vel - wind.vec
	FH.spdV.Text = tostring(math.floor(vAir.Magnitude * KT + 0.5))
	FH.altV.Text = tostring(math.max(0, math.floor(plane.pos.Y * FT + 0.5)))
	local vs = math.floor(plane.vel.Y * FPM / 10 + 0.5) * 10
	FH.vsV.Text = (vs > 0 and "+" or "") .. vs .. " ft/min"
	FH.hdgV.Text = string.format("HDG %03d°", math.floor(planeHeading() + 0.5) % 360)
	FH.thrV.Text = "SCHUB " .. math.floor(plane.throttle) .. "%"
	if plane.gearAnim > 0.95 then
		FH.gearV.Text = "FAHRWERK ✓"
		FH.gearV.TextColor3 = GREEN
	elseif plane.gearAnim < 0.05 then
		FH.gearV.Text = "FAHRWERK EIN"
		FH.gearV.TextColor3 = GREY
	else
		FH.gearV.Text = "FAHRWERK …"
		FH.gearV.TextColor3 = GOLD
	end
	FH.flapsV.Text = "KLAPPEN " .. ({ "0°", "15°", "35°" })[plane.flaps + 1]
	FH.flapsV.TextColor3 = plane.flaps > 0 and GOLD or TXT
	local warn = {}
	if plane.stalled then table.insert(warn, "STALL") end
	if flight.active and flight.phase == "land" and plane.pos.Y < 150 and plane.vel.Y < 0 and not plane.onGround and plane.gearAnim < 0.95 then
		table.insert(warn, "GEAR!")
	end
	FH.warn.Text = table.concat(warn, "   ")
	FH.warn.Visible = #warn > 0 and (math.floor(os.clock() * 3) % 2 == 0)
	if flight.active then
		local t = currentTarget()
		local dx, dz = t.X - plane.pos.X, t.Z - plane.pos.Z
		local brg = math.deg(math.atan2(dx, -dz)) % 360
		local rel = (brg - planeHeading() + 540) % 360 - 180
		FH.arrow.Rotation = rel
		local dist = math.sqrt(dx * dx + dz * dz)
		local what = flight.phase == "fly" and "Wegpunkt" or "Runway 09"
		if dist > 1000 then
			FH.wptD.Text = what .. " · " .. string.format("%.1f km", dist / 1000)
		else
			FH.wptD.Text = what .. " · " .. math.floor(dist) .. " m"
		end
	end
end

local camP = Vector3.new(0, 10, 0)
local function updateFlightCamera(dt)
	if edge(Enum.KeyCode.C) then
		S.camMode = S.camMode == "chase" and "cockpit" or "chase"
	end
	local cf = planeCF()
	local cockpit = S.camMode == "cockpit"
	-- Scheiben in der Cockpit-Ansicht ausblenden (freie Sicht)
	for _, n in ipairs({ "GlassBand", "Windshield" }) do
		local part = planeModel:FindFirstChild(n)
		if part then part.LocalTransparencyModifier = cockpit and 1 or 0 end
	end
	if cockpit then
		camera.CFrame = cf * CFrame.new(0, 2.06 * M, -0.15 * M)
		return
	end
	local fwd = cf.LookVector
	local fh = Vector3.new(fwd.X, 0, fwd.Z)
	if fh.Magnitude > 0.01 then fh = fh.Unit end
	local wantM = plane.pos - fh * 16 + Vector3.new(0, 5.5, 0)
	local want = Vector3.new(wantM.X * M, math.max(wantM.Y, 1.2) * M, wantM.Z * M)
	local k = 1 - math.exp(-4.2 * dt)
	camP = camP:Lerp(want, k)
	local look = (plane.pos + fwd * 12) * M + cf.UpVector * 1.5 * M
	camera.CFrame = CFrame.lookAt(camP, look)
end

---------------------------------------------------------------- Windsack · Deko-Verkehr · Ambient-NPCs
local sockPart = airport:WaitForChild("Windsock"):WaitForChild("Sock")
local function updateWindsock()
	local toDir = math.rad(wind.dir + 180)
	local liftT = clamp(wind.speed / 8, 0.06, 1)
	local droop = -(1 - liftT) * 1.25 + math.sin(os.clock() * 4) * 0.06 * (1.2 - liftT)
	sockPart.CFrame = CFrame.new(-200 * M, 7.8 * M, 55 * M)
		* CFrame.Angles(0, -toDir, 0)
		* CFrame.Angles(droop, 0, 0)
		* CFrame.new(0, 0, -1.9 * M)
end

local trafficJet = airport:WaitForChild("TrafficJet")
local traffic = { state = "idle", t = 0, nextT = 12, takeoff = true }
local function updateTraffic(dt)
	if traffic.state == "idle" then
		traffic.nextT = traffic.nextT - dt
		if traffic.nextT <= 0 then
			traffic.state = traffic.takeoff and "to" or "ldg"
			traffic.takeoff = not traffic.takeoff
			traffic.t = 0
			traffic.nextT = 90
		end
		return
	end
	traffic.t = traffic.t + dt
	local x, y, pitch, yaw
	if traffic.state == "to" then
		local v0, a = 4, 3.2
		x = -700 + v0 * traffic.t + 0.5 * a * traffic.t * traffic.t
		local spd = v0 + a * traffic.t
		yaw = -math.pi / 2
		if spd > 68 then
			local tc = traffic.t - (68 - v0) / a
			y = math.min(300, 0.5 * 9 * tc * tc * 0.35 + tc * 8)
			pitch = 0.14
		else
			y = 0; pitch = 0
		end
		if x > 2600 then
			traffic.state = "idle"
			trafficJet:PivotTo(CFrame.new(0, 0, -4000 * M))
			return
		end
	else
		x = 2400 - 70 * traffic.t
		yaw = math.pi / 2
		y = x > 620 and (x - 620) * 0.052 or 0
		pitch = 0
		if x < -680 then
			traffic.state = "idle"
			trafficJet:PivotTo(CFrame.new(0, 0, -4000 * M))
			return
		end
	end
	trafficJet:PivotTo(CFrame.new(x * M, y * M, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0))
end

-- Ambient-NPCs in der Halle
local ambient = {}
for i = 1, 6 do
	local npc = makeNPC()
	local st = { npc = npc, wpts = { Vector3.new(math.random(-50, 55), 0, math.random(240, 294)) }, wp = 1, wait = math.random(0, 4) }
	npc:PivotTo(CFrame.new(math.random(-50, 55) * M, 0, math.random(240, 294) * M))
	table.insert(ambient, st)
end
local function updateAmbient(dt)
	for _, a in ipairs(ambient) do
		if a.wait > 0 then
			a.wait = a.wait - dt
			if a.wait <= 0 then
				a.wpts = { Vector3.new(math.random(-50, 55), 0, math.random(240, 294)) }
				a.wp = 1
			end
		else
			if npcStep(a.npc, a.wpts, a, dt, 1.5) then
				a.wait = math.random(2, 8)
			end
		end
	end
end

---------------------------------------------------------------- Stationen (E-Interaktionen)
addInteract({
	x = function() return -45 end, z = function() return 260.7 end, r = 3.6,
	cond = function() return S.mode == "walk" and S.job ~= "ramp" and S.job ~= "captain" end,
	label = function()
		if checkin.active then
			return checkin.npcState == "waiting" and "Passagier abfertigen" or "Warten auf Passagier …"
		end
		return "Check-in-Schicht starten"
	end,
	action = function()
		if checkin.active then
			if checkin.npcState == "waiting" then openCheckinPanel() end
			return
		end
		showTutorial("checkin", "JOB: Check-in-Agent",
			"Passagiere kommen zu deinem Schalter. Prüfe:\n· Name auf Ticket und Pass muss übereinstimmen\n· Der Flug muss auf der Tafel stehen und offen sein (nicht CLOSED)\n· Gepäck über 23 kg → Übergepäck-Gebühr kassieren\n\nRichtig = Credits + XP · Fehler durchgewunken = Abzug!",
			startCheckin)
	end,
})
addInteract({
	x = function() return -14 end, z = function() return 192 end, r = 4,
	cond = function() return S.mode == "walk" and not checkin.active and S.job ~= "captain" end,
	label = function()
		if ramp.active then return "Welle läuft …" end
		if S.credits >= UNLOCK_RAMP then return "Gepäck-Schicht starten (Ramp Agent)" end
		return "Ramp Agent – gesperrt (" .. UNLOCK_RAMP .. " Credits nötig)"
	end,
	action = function()
		if ramp.active then return end
		if S.credits < UNLOCK_RAMP then
			toast("Du brauchst " .. UNLOCK_RAMP .. " Credits für diesen Job!", "bad")
			return
		end
		showTutorial("ramp", "JOB: Ramp Agent",
			"Koffer kommen aufs Band – farbcodiert:\n· BLAU → LH 452 (linker Jet) · ORANGE → EW 771 (rechter Jet)\n· E: Koffer aufnehmen, am Wagen E: aufladen (max. 6)\n· In den Wagen einsteigen (E), zum Jet fahren, dort abladen\n· Kollision mit einem Flugzeug kostet Credits!\n\n8 Koffer in 3 Minuten – fehlerfrei & rechtzeitig gibt Bonus.",
			startRamp)
	end,
})
addInteract({
	x = function()
		local c = nearestCase()
		return c and c.obj.Position.X / M or 99999
	end,
	z = function()
		local c = nearestCase()
		return c and c.obj.Position.Z / M or 99999
	end,
	r = 2.6,
	cond = function() return S.mode == "walk" and ramp.active and not ramp.carrying end,
	label = function() return "Koffer aufnehmen" end,
	action = function()
		local c = nearestCase()
		if not c then return end
		c.state = "carried"
		ramp.carrying = c
	end,
})
addInteract({
	x = function() return cart.pos.X end, z = function() return cart.pos.Z end, r = 3.6,
	cond = function() return S.mode == "walk" and ramp.carrying ~= nil end,
	label = function()
		return #cart.load < 6 and ("Auf Wagen laden (" .. #cart.load .. "/6)") or "Wagen ist voll!"
	end,
	action = function()
		if #cart.load >= 6 then return end
		local c = ramp.carrying
		ramp.carrying = nil
		c.state = "cart"
		table.insert(cart.load, c)
		local s = CART_SLOTS[#cart.load]
		c.obj.CFrame = cartModel:GetPivot() * CFrame.new(s.X * M, s.Y * M, s.Z * M)
	end,
})
for i, j in ipairs(JETS) do
	addInteract({
		x = function() return j.x end, z = function() return j.z end, r = 20,
		cond = function() return S.mode == "walk" and ramp.carrying ~= nil end,
		label = function() return "Koffer abgeben bei " .. j.name end,
		action = function()
			local c = ramp.carrying
			ramp.carrying = nil
			deliverAtJet(i, { c })
		end,
	})
end
addInteract({
	x = function() return cart.pos.X end, z = function() return cart.pos.Z end, r = 3.2,
	cond = function() return S.mode == "walk" and not ramp.carrying end,
	label = function() return "Gepäckwagen fahren" end,
	action = enterCart,
})
addInteract({
	x = function() return 124 end, z = function() return 172 end, r = 5,
	cond = function() return S.mode == "walk" and not checkin.active and not ramp.active end,
	label = function()
		if S.credits >= UNLOCK_CAPTAIN then return "Ins Flugzeug steigen (Captain)" end
		return "Captain – gesperrt (" .. UNLOCK_CAPTAIN .. " Credits nötig)"
	end,
	action = function()
		if S.credits < UNLOCK_CAPTAIN then
			toast("Du brauchst " .. UNLOCK_CAPTAIN .. " Credits für die Captain-Lizenz!", "bad")
			return
		end
		showTutorial("captain", "JOB: Captain",
			"Dein eigenes Propellerflugzeug!\n· Shift/Strg(X) Schub · W/S Pitch (S = ziehen) · A/D Roll · Q/E Ruder/Bugrad\n· Abheben erst ab ~55 kt, dann Fahrwerk G einfahren\n· F Klappen (0°/15°/35°): mehr Auftrieb, weniger Stallspeed – ideal zum Landen\n· Unter 50 kt droht der Stall – Nase runter, Schub rein!\n· Der Wind versetzt dich seitlich – Vorhaltewinkel fliegen\n· Landung: PAPI 2× rot / 2× weiß, sanft < 200 ft/min = Butter 🧈\n· C Kamera · B Bremse · R Reset ans Vorfeld",
			openMissionSelect)
	end,
})

---------------------------------------------------------------- Hauptschleife
updateHUD()
setJobHUD("Arbeitslos", "Geh zum leuchtenden Check-in-Schalter im Terminal und drücke E.")
resetPlaneToStand()
task.defer(function()
	showTutorial("welcome", "Willkommen am Flughafen!",
		"Du fängst ganz unten an: am Check-in-Schalter. Verdiene Credits, schalte den Ramp-Agent-Job frei (500 Cr) und arbeite dich zum Captain hoch (2000 Cr)!\n\n· WASD laufen · Shift sprinten · E an leuchtenden Stationen\n· H blendet die Steuerungslegende ein/aus")
end)

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 0.05)
	if edge(Enum.KeyCode.H) then legend.Visible = not legend.Visible end
	if not panelOpen then
		if S.mode == "fly" then
			updateFlightPhysics(dt)
			updateMission(dt)
			updateFlightHUD()
			updateFlightCamera(dt)
		else
			updateCheckin(dt)
			updateRamp(dt)
			updateCart(dt)
			updateInteract()
			-- getragener Koffer folgt dem Charakter
			if ramp.carrying then
				local r = hrp()
				if r then
					ramp.carrying.obj.CFrame = r.CFrame * CFrame.new(0, -0.3, -2.4)
				end
			end
		end
	end
	updateAmbient(dt)
	updateTraffic(dt)
	updateWindsock()
	keyEdge = {}
end)

print("[Airport] Client bereit — viel Spass!")
