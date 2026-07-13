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

local M = 3.4 -- Studs pro Meter (Welt-Massstab, passt zu Roblox-Avataren)
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

-- Server-Oekonomie (Phase 3): Der Server rechnet Credits/XP, der Client zeigt an
local ecoRS = game:GetService("ReplicatedStorage")
local earnEv = ecoRS:WaitForChild("EarnCredits")
local buyEv = ecoRS:WaitForChild("BuyItem")
local syncEv = ecoRS:WaitForChild("SyncState")
local achEv = ecoRS:WaitForChild("UnlockAch")
local claimEv = ecoRS:WaitForChild("ClaimVehicle")

-- Fehler-Haertung (Phase 4): Systeme starten und laufen isoliert;
-- ein Fehler in einem System legt nicht HUD + Interaktion still.
local function sysInit(name, fn)
	local ok, err = pcall(fn)
	if not ok then warn("[Airport] System '" .. name .. "' konnte nicht starten: " .. tostring(err)) end
end
local sysWarned = {}
local function safeStep(name, fn, a, b)
	local ok, err = pcall(fn, a, b)
	if not ok and not sysWarned[name] then
		sysWarned[name] = true
		warn("[Airport] System '" .. name .. "' Laufzeitfehler (Rest läuft weiter): " .. tostring(err))
	end
end

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
	job = nil,          -- nil | "checkin" | "ramp" | "fuel" | "marshal" | "captain"
	mode = "walk",      -- walk | cart | fly
	vehicle = nil,      -- aktives Fahrzeug (cart | fuelTruck)
	tutorialSeen = {},
	camMode = "chase",  -- Flug: chase | cockpit
}
local UNLOCK_RAMP, UNLOCK_SEC, UNLOCK_FUEL, UNLOCK_MARSHAL, UNLOCK_CAPTAIN = 500, 750, 1000, 1500, 2000
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

-- Zonen-Meldungen vom Server (Zutritt verweigert / Boarding ok)
task.spawn(function()
	local zoneEv = ecoRS:WaitForChild("ZoneDenied")
	zoneEv.OnClientEvent:Connect(function(msg, ok)
		toast(msg, ok and "good" or "bad")
	end)
end)

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
local function hidePanel()
	panelOpen = false
	panelWrap.Visible = false
end
-- Klick auf den dunklen Hintergrund schliesst das Panel (nie wieder festhaengen)
do
	local bg = Instance.new("TextButton")
	bg.BackgroundTransparency = 1; bg.Text = ""
	bg.Size = UDim2.fromScale(1, 1)
	bg.ZIndex = 5
	bg.Parent = panelWrap
	bg.MouseButton1Click:Connect(hidePanel)
end
local function showPanel(build)
	clearPanel()
	panelOpen = true
	panelWrap.Visible = true
	-- Aufbau abgesichert: schlaegt er fehl, bleibt KEIN leerer schwarzer Kasten stehen
	local ok, err = pcall(build, panel)
	if not ok then
		warn("[Airport] Panel-Aufbau fehlgeschlagen: " .. tostring(err))
		label(panel, "Hoppla — Inhalt konnte nicht geladen werden.", UDim2.new(0, 20, 0, 60), UDim2.new(1, -40, 0, 30), TXT, 15)
	end
	local x = button(panel, "✕", UDim2.new(1, -46, 0, 10), UDim2.new(0, 36, 0, 32), Color3.fromRGB(96, 46, 46), hidePanel)
	x.ZIndex = 8
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
	elseif S.credits < UNLOCK_SEC then
		progressL.Text = "Noch " .. (UNLOCK_SEC - S.credits) .. " Credits bis Security"
	elseif S.credits < UNLOCK_FUEL then
		progressL.Text = "Noch " .. (UNLOCK_FUEL - S.credits) .. " Credits bis Tankwagen"
	elseif S.credits < UNLOCK_MARSHAL then
		progressL.Text = "Noch " .. (UNLOCK_MARSHAL - S.credits) .. " Credits bis Marshaller"
	elseif S.credits < UNLOCK_CAPTAIN then
		progressL.Text = "Noch " .. (UNLOCK_CAPTAIN - S.credits) .. " Credits bis Captain"
	else
		progressL.Text = "Alle Jobs freigeschaltet ✈"
	end
end
local function addCredits(n, reason)
	-- optimistische Anzeige; autoritativ rechnet der Server (SyncState ueberschreibt)
	S.credits = math.max(0, S.credits + n)
	updateHUD()
	if n ~= 0 then
		creditPop(n)
		earnEv:FireServer(reason or "misc", n, 0)
	end
	if S.credits >= 1000 then unlock("rich_1000") end
	if S.credits >= UNLOCK_CAPTAIN then unlock("all_jobs") end
end
local function addXP(n)
	local before = level()
	S.xp = S.xp + n
	updateHUD()
	earnEv:FireServer("xp", 0, n)
	if level() > before then celebrateLevelUp(level()) end
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
---------------------------------------------------------------- Game-Feel: Splash · Popups · Level-Up · Erfolge · Minimap
local TweenService = game:GetService("TweenService")
sysInit("Game-Feel", function()
	-- Titelscreen
	local splash = Instance.new("Frame")
	splash.Name = "Splash"
	splash.Size = UDim2.fromScale(1, 1)
	splash.BackgroundColor3 = Color3.fromRGB(15, 32, 54)
	splash.ZIndex = 50
	splash.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(11, 26, 46), Color3.fromRGB(42, 90, 127))
	grad.Rotation = 70
	grad.Parent = splash
	local t1 = label(splash, "✈  AIRPORT SIMULATOR", UDim2.new(0, 0, 0.32, 0), UDim2.new(1, 0, 0, 64), Color3.fromRGB(232, 238, 247), 52, Enum.TextXAlignment.Center)
	t1.Font = Enum.Font.GothamBlack; t1.ZIndex = 51
	local t2 = label(splash, "Vom Check-in-Schalter zum Captain — dein Flughafen, deine Karriere.", UDim2.new(0, 0, 0.44, 0), UDim2.new(1, 0, 0, 24), GREY, 17, Enum.TextXAlignment.Center)
	t2.ZIndex = 51
	local t3 = label(splash, "6 Jobs · 2 Runways · begehbarer A380 · echte Flugphysik · J = Erfolge · M = Minimap", UDim2.new(0, 0, 0.68, 0), UDim2.new(1, 0, 0, 20), GREY, 14, Enum.TextXAlignment.Center)
	t3.ZIndex = 51
	local b = button(splash, "SPIELEN", UDim2.new(0.5, -110, 0.53, 0), UDim2.new(0, 220, 0, 54), Color3.fromRGB(42, 127, 201), function()
		splash:Destroy()
	end)
	b.ZIndex = 52; b.TextSize = 24
end)
-- Credit-Popups
function creditPop(n)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, 30, 0, 116)
	l.Size = UDim2.new(0, 200, 0, 26)
	l.Font = Enum.Font.GothamBlack
	l.TextSize = 20
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = n > 0 and GREEN or REDC
	l.Text = (n > 0 and "+" or "−") .. math.abs(n) .. " Cr"
	l.Parent = gui
	TweenService:Create(l, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, 30, 0, 74), TextTransparency = 1 }):Play()
	task.delay(1.4, function() l:Destroy() end)
end
-- Level-Up
function celebrateLevelUp(lv)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0.5, -250, 0.36, 0)
	l.Size = UDim2.new(0, 500, 0, 60)
	l.Font = Enum.Font.GothamBlack
	l.TextSize = 44
	l.TextColor3 = GOLD
	l.Text = "⭐ LEVEL " .. lv .. "!"
	l.TextTransparency = 1
	l.Parent = gui
	TweenService:Create(l, TweenInfo.new(0.35), { TextTransparency = 0 }):Play()
	task.delay(1.8, function()
		TweenService:Create(l, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		task.delay(0.6, function() l:Destroy() end)
	end)
	-- Konfetti am Charakter
	local r = hrp()
	if r then
		local e = Instance.new("ParticleEmitter")
		e.Rate = 120
		e.Lifetime = NumberRange.new(0.8, 1.6)
		e.Speed = NumberRange.new(8, 16)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Color = ColorSequence.new(Color3.fromRGB(255, 215, 94), Color3.fromRGB(94, 200, 255))
		e.Parent = r
		task.delay(1.2, function() e.Enabled = false task.delay(2, function() e:Destroy() end) end)
	end
end
-- Erfolge
local ACHIEVEMENTS = {
	{ id = "first_shift", name = "Erster Arbeitstag", desc = "Beende deine erste Check-in-Schicht." },
	{ id = "rich_1000", name = "Gut im Geschäft", desc = "Besitze 1.000 Credits." },
	{ id = "all_jobs", name = "Karriereleiter erklommen", desc = "Schalte alle Jobs frei (2.000 Credits)." },
	{ id = "sec_perfect", name = "Adlerauge", desc = "Fehlerfreie Security-Schicht." },
	{ id = "marshal_perfect", name = "Winker-Profi", desc = "Weise einen Jet fehlerfrei ein." },
	{ id = "a380_board", name = "Willkommen an Bord", desc = "Betrete den A380 an Gate 1." },
	{ id = "pd_roof", name = "Über den Dächern", desc = "Steh auf dem Parkdeck-Dach." },
	{ id = "first_mission", name = "Captain im Dienst", desc = "Schließe eine Flugmission ab." },
	{ id = "butter", name = "🧈 Butterweich", desc = "Lande mit unter 200 ft/min." },
	{ id = "alt_1000", name = "Über den Wolken", desc = "Erreiche 1.000 ft Flughöhe." },
	{ id = "shopper", name = "Shopping-Tour", desc = "Kaufe etwas in einem Laden im Terminal." },
}
local achieved = {}
function unlock(id)
	if achieved[id] then return end
	achieved[id] = true
	achEv:FireServer(id) -- Persistenz im Server (Phase 3)
	local a
	for _, x in ipairs(ACHIEVEMENTS) do if x.id == id then a = x break end end
	if not a then return end
	local f = frame(gui, UDim2.new(0.5, -180, 0, 126), UDim2.new(0, 360, 0, 58))
	f.ZIndex = 25
	local l1 = label(f, "🏆 ERFOLG FREIGESCHALTET", UDim2.new(0, 0, 0, 8), UDim2.new(1, 0, 0, 14), GOLD, 12, Enum.TextXAlignment.Center)
	l1.ZIndex = 26
	local l2 = label(f, a.name, UDim2.new(0, 0, 0, 26), UDim2.new(1, 0, 0, 22), TXT, 17, Enum.TextXAlignment.Center)
	l2.Font = Enum.Font.GothamBold; l2.ZIndex = 26
	task.delay(3.2, function() f:Destroy() end)
end

-- Autoritativer Kontostand + gespeicherte Erfolge vom Server (Join + nach jeder Meldung)
syncEv.OnClientEvent:Connect(function(credits, xp, unlocks)
	S.credits = credits
	S.xp = xp
	if unlocks then
		for _, id in ipairs(unlocks) do achieved[id] = true end -- still, ohne Toast
	end
	updateHUD()
end)
syncEv:FireServer() -- Handshake: jetzt steht der Handler, Server schickt den echten Stand
function showAchievements()
	local count = 0
	for _ in pairs(achieved) do count = count + 1 end
	showPanel(function(p)
		local t = label(p, "🏆 Erfolge (" .. count .. "/" .. #ACHIEVEMENTS .. ")", UDim2.new(0, 20, 0, 12), UDim2.new(1, -40, 0, 24), CYAN, 19)
		t.Font = Enum.Font.GothamBold
		for i, a in ipairs(ACHIEVEMENTS) do
			local got = achieved[a.id]
			local row = label(p, (got and "🏆 " or "🔒 ") .. a.name .. " — " .. a.desc,
				UDim2.new(0, 20, 0, 30 + i * 32), UDim2.new(1, -40, 0, 30), got and TXT or GREY, 14)
			row.TextTransparency = got and 0 or 0.4
		end
		button(p, "Schließen", UDim2.new(0, 20, 1, -50), UDim2.new(0, 130, 0, 36), Color3.fromRGB(60, 70, 85), hidePanel)
	end)
end
-- Minimap (statisches Layout + Spieler-Punkt)
local miniDot
sysInit("Minimap", function()
	local mm = frame(gui, UDim2.new(1, -234, 1, -180), UDim2.new(0, 220, 0, 160))
	local X1, X2, Z1, Z2 = -950, 980, -640, 400
	local function r(x1, z1, x2, z2, col)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = col
		f.BorderSizePixel = 0
		f.Position = UDim2.new((x1 - X1) / (X2 - X1), 0, (z1 - Z1) / (Z2 - Z1), 0)
		f.Size = UDim2.new((x2 - x1) / (X2 - X1), 0, (z2 - z1) / (Z2 - Z1), 0)
		f.Parent = mm
	end
	r(-770, -15, 770, 15, Color3.fromRGB(85, 90, 98))
	r(-920, -535, 920, -505, Color3.fromRGB(85, 90, 98))
	r(-770, 72, 770, 88, Color3.fromRGB(67, 71, 78))
	r(-610, 130, 300, 228, Color3.fromRGB(92, 96, 104))
	r(320, 130, 700, 228, Color3.fromRGB(92, 96, 104))
	r(-70, 232, 75, 302, Color3.fromRGB(143, 151, 162))
	r(-685, 180, -595, 290, Color3.fromRGB(143, 151, 162))
	r(685, 180, 775, 290, Color3.fromRGB(143, 151, 162))
	r(-166, 308, -84, 352, Color3.fromRGB(110, 118, 128))
	r(740, 60, 920, 208, Color3.fromRGB(110, 118, 128))
	miniDot = Instance.new("Frame")
	miniDot.Size = UDim2.new(0, 6, 0, 6)
	miniDot.BackgroundColor3 = Color3.new(1, 1, 1)
	miniDot.BorderSizePixel = 0
	miniDot.ZIndex = 3
	miniDot.Parent = mm
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = miniDot
	minimapFrame = mm -- global fuer M-Toggle & Update
end)
function updateMinimap(pos)
	local X1, X2, Z1, Z2 = -950, 980, -640, 400
	miniDot.Position = UDim2.new((pos.X - X1) / (X2 - X1), -3, (pos.Z - Z1) / (Z2 - Z1), -3)
end

-- Sprint
RunService.RenderStepped:Connect(function()
	local h = humanoid()
	if h and S.mode == "walk" then
		local ws = (keys[Enum.KeyCode.LeftShift] or keys[Enum.KeyCode.RightShift]) and 38 or 24
		if S.boostUntil and os.clock() < S.boostUntil then ws = ws * 1.35 end -- ☕ Kaffee-Boost
		h.WalkSpeed = ws
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
	unlock("first_shift")
	checkin.active = false
	S.job = nil
	local allOk = checkin.correct == 8
	if allOk then addCredits(100, "checkin") end
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
		addCredits(pay, "checkin"); addXP(12)
		toast("✔ Richtig! +" .. pay .. " Credits · " .. reason, "good")
	else
		addCredits(-40, "checkin")
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

---------------------------------------------------------------- JOB · SICHERHEITSKONTROLLE (ab 750 Cr)
do -- eigener Scope (Top-Level-Local-Limit)
local SEC_OK = { "Laptop", "Buch", "Kopfhörer", "Jacke", "Snacks", "Kamera", "Regenschirm", "Ladekabel", "Sonnenbrille", "Trinkflasche (leer)" }
local SEC_BAD = { "Taschenmesser", "Wasserflasche 1 L", "Gaskartusche", "Werkzeugset", "Feuerwerk", "Pfefferspray", "Schere (12 cm)" }
local secJob = { active = false, idx = 0, correct = 0, earned = 0, queue = {} }
local function genSecCases()
	local nBad = math.random(2, 3)
	local flags = {}
	for i = 1, 8 do flags[i] = false end
	local placed = 0
	while placed < nBad do
		local i = math.random(8)
		if not flags[i] then flags[i] = true placed = placed + 1 end
	end
	local cases = {}
	for i = 1, 8 do
		local items = {}
		for k = 1, math.random(2, 4) do table.insert(items, SEC_OK[math.random(#SEC_OK)]) end
		if flags[i] then items[math.random(#items)] = SEC_BAD[math.random(#SEC_BAD)] end
		table.insert(cases, { items = items, bad = flags[i], name = NAMES[math.random(#NAMES)] })
	end
	return cases
end
function startSecJob()
	secJob.active = true
	secJob.idx = 0; secJob.correct = 0; secJob.earned = 0
	secJob.queue = genSecCases()
	S.job = "security"
	setJobHUD("SICHERHEITSKONTROLLE", "Durchleuchte 8 Handgepäckstücke.\nDrücke E am Röntgenband für den nächsten Passagier.")
end
local function resolveSec(confiscated)
	hidePanel()
	local c = secJob.queue[secJob.idx + 1]
	local correct = confiscated == c.bad
	if correct then
		secJob.correct = secJob.correct + 1
		secJob.earned = secJob.earned + 50
		addCredits(50, "security"); addXP(10)
		toast(c.bad and "✔ Richtig! Verbotener Gegenstand einkassiert. +50" or "✔ Richtig! Gepäck war sauber. +50", "good")
	else
		addCredits(-35, "security")
		toast(c.bad and "✘ Verbotenen Gegenstand durchgewunken! −35" or "✘ Fehlalarm – Gepäck war sauber! −35", "bad")
	end
	secJob.idx = secJob.idx + 1
	if secJob.idx >= 8 then
		secJob.active = false
		S.job = nil
		local allOk = secJob.correct == 8
		if allOk then addCredits(80, "security") unlock("sec_perfect") end
		showPanel(function(p)
			local t = label(p, "Kontroll-Schicht beendet!", UDim2.new(0, 20, 0, 14), UDim2.new(1, -40, 0, 26), CYAN, 20)
			t.Font = Enum.Font.GothamBold
			label(p, secJob.correct .. " / 8 korrekt geprüft\nVerdient: " .. secJob.earned .. " Credits" ..
				(allOk and "\nFehlerfrei! +80 Bonus" or ""), UDim2.new(0, 20, 0, 52), UDim2.new(1, -40, 0, 80), TXT, 15)
			button(p, "Neue Schicht", UDim2.new(0, 20, 1, -56), UDim2.new(0, 150, 0, 40), Color3.fromRGB(40, 110, 60), function()
				hidePanel(); startSecJob()
			end)
			button(p, "Feierabend", UDim2.new(0, 185, 1, -56), UDim2.new(0, 150, 0, 40), Color3.fromRGB(60, 70, 85), function()
				hidePanel(); setJobHUD("Arbeitslos", "Such dir einen Job an einer leuchtenden Station.")
			end)
		end)
	end
end
local function openSecPanel()
	local c = secJob.queue[secJob.idx + 1]
	showPanel(function(p)
		local t = label(p, "🎒 Röntgenbild " .. (secJob.idx + 1) .. "/8 · " .. c.name, UDim2.new(0, 20, 0, 12), UDim2.new(1, -40, 0, 24), CYAN, 18)
		t.Font = Enum.Font.GothamBold
		label(p, "INHALT DES HANDGEPÄCKS", UDim2.new(0, 20, 0, 44), UDim2.new(1, -40, 0, 16), GREY, 12)
		label(p, "· " .. table.concat(c.items, "\n· "), UDim2.new(0, 20, 0, 64), UDim2.new(1, -40, 0, 120), TXT, 15)
		label(p, "Verboten: Messer & Scheren, Flüssigkeiten > 100 ml, Gas, Feuerwerk, Reizstoffe.",
			UDim2.new(0, 20, 0, 196), UDim2.new(1, -40, 0, 40), GREY, 13)
		button(p, "Durchwinken", UDim2.new(0, 20, 1, -60), UDim2.new(0, 150, 0, 42), Color3.fromRGB(40, 110, 60), function()
			resolveSec(false)
		end)
		button(p, "Konfiszieren", UDim2.new(0, 185, 1, -60), UDim2.new(0, 150, 0, 42), Color3.fromRGB(130, 50, 50), function()
			resolveSec(true)
		end)
	end)
end
-- Station wird nach den anderen Interacts registriert (openSecPanel/startSecJob sind hier definiert)
task.defer(function()
	addInteract({
		x = function() return 10 end, z = function() return 256 end, r = 3.6,
		cond = function() return S.mode == "walk" and (S.job == nil or S.job == "security") end,
		label = function()
			if secJob.active then return "Nächstes Gepäck durchleuchten (" .. (secJob.idx + 1) .. "/8)" end
			if S.credits >= UNLOCK_SEC then return "Security-Schicht starten" end
			return "Security – gesperrt (" .. UNLOCK_SEC .. " Credits nötig)"
		end,
		action = function()
			if secJob.active then openSecPanel() return end
			if S.credits < UNLOCK_SEC then
				toast("Du brauchst " .. UNLOCK_SEC .. " Credits für diesen Job!", "bad")
				return
			end
			showTutorial("security", "JOB: Sicherheitskontrolle",
				"Du sitzt am Röntgenband:\n· Prüfe die Gepäckinhalte auf verbotene Gegenstände\n· Verboten: Messer, Scheren, Flüssigkeiten > 100 ml, Gas, Feuerwerk, Reizstoffe\n· Sauber = durchwinken · gefährlich = konfiszieren\n· +50 richtig · −35 falsch · fehlerfrei = +80 Bonus",
				startSecJob)
		end,
	})
end)
end -- Security-Scope

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
	if okPay > 0 then addCredits(okPay, "ramp"); addXP(math.floor(okPay / 5)); toast("✔ Gepäck verladen: +" .. okPay .. " Credits", "good") end
	if badPay > 0 then addCredits(-badPay, "ramp"); toast("✘ Falscher Flieger! −" .. badPay .. " Credits", "bad") end
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
	if bonus > 0 then addCredits(bonus, "ramp") end
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
-- Fahrbare Autos (Parkplatz + Parkhaus): flotter als der Gepaeckwagen,
-- duerfen auf dem ganzen Gelaende fahren (nicht nur auf dem Vorfeld)
local carA, carB
do
	local function bindCar(nm, yaw)
		local mdl = airport:WaitForChild(nm)
		mdl:WaitForChild("Root")
		return {
			model = mdl, pos = mdl:GetPivot().Position / M, yaw = yaw,
			vel = Vector3.new(), load = {},
			acc = 11, brake = 8, maxF = 19, turn = 2.1,
			bx1 = -900, bx2 = 900, bz1 = -100, bz2 = 390,
			claimName = nm,
		}
	end
	carA = bindCar("CarA", math.rad(90))
	carB = bindCar("CarB", math.rad(90))
end

local CART_COLLIDERS = {
	{ 124, 158, 136, 172 },   -- Spieler-Flugzeug
	{ -134, 246, -126, 254 }, -- Tower
	{ 211, 185, 249, 215 },   -- Hangar
	{ -47, 156, -42, 159 },   -- Boarding-Treppe
}
for _, jx in ipairs({ -40, 200 }) do -- A380 (Gate 1) + Jumbo (Gate 5)
	table.insert(CART_COLLIDERS, { jx - 3.4, 165 - 19.5, jx + 3.4, 165 + 23 }) -- Rumpf
	for _, sx in ipairs({ -1, 1 }) do
		for _, e in ipairs({ { 7.2, 4.6 }, { 13.5, 8.4 } }) do
			table.insert(CART_COLLIDERS, { jx + sx * e[1] - 1.5, 165 + e[2] - 2.2, jx + sx * e[1] + 1.5, 165 + e[2] + 2.2 })
		end
	end
end
table.insert(CART_COLLIDERS, { 37.8, 150, 42.2, 182 })   -- A320-Rumpf (Gate 2)
table.insert(CART_COLLIDERS, { -70.6, 231.4, 75.6, 302.6 }) -- Terminal 1 (Autos bleiben draussen)
table.insert(CART_COLLIDERS, { -122.4, 300.8, -117.6, 305.2 }) -- Tunnel-Haeuschen
table.insert(CART_COLLIDERS, { -54.2, 234.3, -49.8, 238.7 }) -- Keller-Treppe
table.insert(CART_COLLIDERS, { 34.2, 166, 36.6, 169 })   -- A320-Triebwerke
table.insert(CART_COLLIDERS, { 43.4, 166, 45.8, 169 })
table.insert(CART_COLLIDERS, { -187.5, 162, -182.5, 185 }) -- ATR
table.insert(CART_COLLIDERS, { 264, 174, 272, 190 })     -- Bizjet
table.insert(CART_COLLIDERS, { -157, 203.5, -147, 212.5 }) -- Tanklager
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

-- Tankwagen (zweites kinematisches Fahrzeug)
local fuelTruck
sysInit("Tankwagen", function()
	local ftModel = airport:WaitForChild("FuelTruck")
	ftModel:WaitForChild("Root")
	fuelTruck = { model = ftModel, pos = ftModel:GetPivot().Position / M, yaw = 2.0, vel = Vector3.new(), load = {} }
end)
cart.model = cartModel
local fuelJob = { active = false, fueled = { false, false }, fueling = nil, progress = 0, timer = 0 }
local endFuelJob -- forward

local function enterVehicle(v)
	S.mode = "cart"
	S.vehicle = v
	setCharacterHidden(true)
	camera.CameraType = Enum.CameraType.Scriptable
end
-- Multiplayer: erst beim Server anmelden, damit nicht zwei Spieler denselben Wagen fahren
local pendingVehicle = nil
local function requestVehicle(v, claimName)
	if pendingVehicle then return end
	pendingVehicle = v
	v.claimName = claimName
	claimEv:FireServer(claimName, true)
end
claimEv.OnClientEvent:Connect(function(claimName, granted)
	local v = pendingVehicle
	pendingVehicle = nil
	if not v or v.claimName ~= claimName then return end
	if granted then
		enterVehicle(v)
	else
		local nm = claimName == "Cart" and "Der Gepäckwagen" or claimName == "FuelTruck" and "Der Tankwagen" or "Das Auto"
		toast("🚧 " .. nm .. " ist gerade besetzt!", "bad")
	end
end)
local function exitVehicle()
	if S.vehicle and S.vehicle.claimName then claimEv:FireServer(S.vehicle.claimName, false) end
	local v = S.vehicle
	S.mode = "walk"
	S.vehicle = nil
	setCharacterHidden(false)
	camera.CameraType = Enum.CameraType.Custom
	local f = Vector3.new(math.sin(v.yaw), 0, math.cos(v.yaw))
	local side = Vector3.new(-f.Z, 0, f.X)
	local out = (v.pos + side * 2.6) * M
	local r = hrp()
	if r then r.CFrame = CFrame.new(out.X, 3.2, out.Z) end
end

local function cartPrompts()
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
		if edge(Enum.KeyCode.E) then exitVehicle() end
	end
end
local function fuelPrompts(dt)
	local speed = fuelTruck.vel.Magnitude
	if fuelJob.active and fuelJob.fueling then
		local j = JETS[fuelJob.fueling]
		if speed > 0.8 then
			fuelJob.fueling = nil
			toast("Betankung abgebrochen – Wagen bewegt!", "bad")
		else
			fuelJob.progress = fuelJob.progress + dt
			promptL.Text = "⛽ Betanke " .. j.name .. " … " .. math.min(100, math.floor(fuelJob.progress / 8 * 100)) .. "%"
			promptF.Visible = true
			if fuelJob.progress >= 8 then
				fuelJob.fueled[fuelJob.fueling] = true
				fuelJob.fueling = nil
				addCredits(120, "fuel"); addXP(20)
				toast("✔ " .. j.name .. " vollgetankt: +120 Credits", "good")
				if fuelJob.fueled[1] and fuelJob.fueled[2] then endFuelJob(true) end
			end
			return
		end
	end
	local nearIdx = nil
	if fuelJob.active then
		for i, j in ipairs(JETS) do
			if not fuelJob.fueled[i] and math.sqrt((fuelTruck.pos.X - j.x) ^ 2 + (fuelTruck.pos.Z - j.z) ^ 2) < 26 then nearIdx = i end
		end
	end
	if nearIdx then
		promptL.Text = "[E]  Betanken starten: " .. JETS[nearIdx].name
		promptF.Visible = true
		if edge(Enum.KeyCode.E) then fuelJob.fueling = nearIdx; fuelJob.progress = 0 end
	else
		promptL.Text = "[E]  Aussteigen"
		promptF.Visible = true
		if edge(Enum.KeyCode.E) then exitVehicle() end
	end
end

local function updateVehicle(v, dt)
	if not (S.mode == "cart" and S.vehicle == v) then
		v.vel = v.vel * math.exp(-2 * dt)
		return
	end
	local fwd = Vector3.new(math.sin(v.yaw), 0, math.cos(v.yaw))
	local right = Vector3.new(fwd.Z, 0, -fwd.X)
	local acc = 0
	if keys[Enum.KeyCode.W] then acc = acc + (v.acc or 7) end
	if keys[Enum.KeyCode.S] then acc = acc - (v.brake or 5) end
	v.vel = v.vel + fwd * acc * dt
	local fs = v.vel:Dot(fwd)
	local ls = v.vel:Dot(right)
	local steer = 0
	if keys[Enum.KeyCode.A] then steer = steer + 1 end
	if keys[Enum.KeyCode.D] then steer = steer - 1 end
	v.yaw = v.yaw + steer * (v.turn or 1.7) * clamp(fs / 5, -1, 1) * dt
	ls = ls * math.exp(-3.2 * dt)           -- leichtes Driften
	fs = clamp(fs * math.exp(-0.55 * dt), -5, v.maxF or 11)
	local f2 = Vector3.new(math.sin(v.yaw), 0, math.cos(v.yaw))
	local r2 = Vector3.new(f2.Z, 0, -f2.X)
	local speedBefore = v.vel.Magnitude
	v.vel = f2 * fs + r2 * ls
	v.pos = v.pos + v.vel * dt
	v.pos = Vector3.new(clamp(v.pos.X, v.bx1 or -800, v.bx2 or 800), 0, clamp(v.pos.Z, v.bz1 or -60, v.bz2 or 228))
	if ramp.collideCd > 0 then ramp.collideCd = ramp.collideCd - dt end
	local newPos, hit = cartCollide(v.pos, 1.6)
	if hit then
		v.pos = newPos
		local nearJet = false
		for _, j in ipairs(JETS) do
			if math.sqrt((v.pos.X - j.x) ^ 2 + (v.pos.Z - j.z) ^ 2) < 32 then nearJet = true end
		end
		if nearJet and speedBefore > 4 and ramp.collideCd <= 0 then
			ramp.collideCd = 3
			addCredits(-30, "fuel")
			toast("💥 Kollision mit dem Flugzeug! −30 Credits", "bad")
		end
		v.vel = v.vel * -0.25
	end
	v.model:PivotTo(CFrame.new(v.pos * M) * CFrame.Angles(0, v.yaw, 0))
	local pivot = v.model:GetPivot()
	if v == cart then
		for i, c in ipairs(cart.load) do
			local s = CART_SLOTS[i]
			c.obj.CFrame = pivot * CFrame.new(s.X * M, s.Y * M, s.Z * M)
		end
	end
	-- Charakter unsichtbar am Fahrzeug halten
	local r = hrp()
	if r then r.CFrame = pivot * CFrame.new(0, 2 * M, 1.6 * M) end
	-- Kamera-Verfolger (hinter dem Fahrzeug: Fahrtrichtung ist lokal +Z)
	local camPos = pivot * CFrame.new(0, 4.5 * M, -11 * M)
	camera.CFrame = CFrame.lookAt(camPos.Position, pivot.Position + Vector3.new(0, 1.5 * M, 0))
	if v == cart then cartPrompts() elseif v == fuelTruck then fuelPrompts(dt) end
end

endFuelJob = function(success)
	if not fuelJob.active then return end
	fuelJob.active = false
	S.job = nil
	setTimerHUD(nil)
	local n = (fuelJob.fueled[1] and 1 or 0) + (fuelJob.fueled[2] and 1 or 0)
	local bonus = (success and fuelJob.timer > 0) and 60 or 0
	if bonus > 0 then addCredits(bonus, "fuel") end
	if S.mode == "cart" and S.vehicle == fuelTruck then exitVehicle() end
	showPanel(function(p)
		local t = label(p, success and "Beide Jets betankt!" or "Zeit abgelaufen", UDim2.new(0, 20, 0, 14), UDim2.new(1, -40, 0, 26), CYAN, 20)
		t.Font = Enum.Font.GothamBold
		label(p, n .. " / 2 Flugzeuge betankt" .. (bonus > 0 and ("\nRechtzeitig fertig: +" .. bonus .. " Bonus!") or ""),
			UDim2.new(0, 20, 0, 52), UDim2.new(1, -40, 0, 70), TXT, 15)
		button(p, "Neue Schicht", UDim2.new(0, 20, 1, -56), UDim2.new(0, 150, 0, 40), Color3.fromRGB(40, 110, 60), function()
			hidePanel(); startFuelJob()
		end)
		button(p, "Feierabend", UDim2.new(0, 185, 1, -56), UDim2.new(0, 150, 0, 40), Color3.fromRGB(60, 70, 85), function()
			hidePanel(); setJobHUD("Arbeitslos", "Such dir einen Job an einer leuchtenden Station.")
		end)
	end)
end
function startFuelJob()
	fuelJob.active = true
	fuelJob.fueled = { false, false }
	fuelJob.fueling = nil
	fuelJob.timer = 150
	S.job = "fuel"
	setJobHUD("TANKWAGEN", "Betanke beide Jets!\nSteig in den Tankwagen am Fuel Depot (E).")
end
local function updateFuelJob(dt)
	if not fuelJob.active then return end
	fuelJob.timer = fuelJob.timer - dt
	setTimerHUD(math.max(0, fuelJob.timer))
	if fuelJob.timer <= 0 then endFuelJob(false) end
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
sysInit("Flug-HUD", function()
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
end)

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
		unlock("butter")
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
	unlock("first_mission")
	local m = MISSIONS[flight.mIdx]
	local stars, notes = rateLanding(flight.landStats)
	local pay = m.base * stars
	addCredits(pay, "flight")
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
	if plane.pos.Y * FT > 1000 then unlock("alt_1000") end
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
for i = 1, 12 do
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

---------------------------------------------------------------- JOB · MARSHALLER (Einweiser, ab 1500 Cr)
local marshalJet = airport:WaitForChild("MarshalJet")
local marshal = {
	active = false, s = 0, correct = 0, mistakes = 0, waiting = nil, sigIdx = 1, timer = 0,
	pts = { { -700, 80 }, { -130, 80 }, { -130, 158 } },
	signals = {
		{ s = 180, key = Enum.KeyCode.W, sym = "W", what = "Weiter geradeaus rollen" },
		{ s = 400, key = Enum.KeyCode.S, sym = "S", what = "Langsamer!" },
		{ s = 565, key = Enum.KeyCode.A, sym = "A", what = "Nach links einlenken" },
		{ s = 610, key = Enum.KeyCode.W, sym = "W", what = "Weiter vorziehen" },
		{ s = 645, key = Enum.KeyCode.X, sym = "X", what = "STOP – Parkposition erreicht" },
	},
}
marshal.len = 648
-- grosse Zeichen-Anzeige (im marshal-Table, spart Top-Level-Locals)
sysInit("Marshaller-Anzeige", function()
	local f = frame(gui, UDim2.new(0.5, -160, 0.26, 0), UDim2.new(0, 320, 0, 96))
	marshal.gui = f
	marshal.keyL = label(f, "W", UDim2.new(0, 0, 0, 6), UDim2.new(1, 0, 0, 50), GOLD, 44, Enum.TextXAlignment.Center)
	marshal.keyL.Font = Enum.Font.GothamBlack
	marshal.whatL = label(f, "", UDim2.new(0, 0, 0, 58), UDim2.new(1, 0, 0, 30), TXT, 15, Enum.TextXAlignment.Center)
	f.Visible = false
end)

local function marshalPathPos(s)
	local pts = marshal.pts
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local l = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		if s <= l then
			local t = s / l
			return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, (b[1] - a[1]) / l, (b[2] - a[2]) / l
		end
		s = s - l
	end
	local a, b = pts[#pts - 1], pts[#pts]
	local l = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
	return b[1], b[2], (b[1] - a[1]) / l, (b[2] - a[2]) / l
end
local function endMarshal()
	marshal.active = false
	S.job = nil
	setTimerHUD(nil)
	marshal.gui.Visible = false
	local pay = marshal.correct * 40
	local perfect = marshal.mistakes == 0 and marshal.correct == #marshal.signals
	if perfect then unlock("marshal_perfect") end
	local bonus = perfect and 60 or 0
	addCredits(pay + bonus, "marshal"); addXP(15 * marshal.correct)
	showPanel(function(p)
		local t = label(p, "Flugzeug eingewiesen!", UDim2.new(0, 20, 0, 14), UDim2.new(1, -40, 0, 26), CYAN, 20)
		t.Font = Enum.Font.GothamBold
		label(p, marshal.correct .. " / " .. #marshal.signals .. " Zeichen richtig" ..
			(marshal.mistakes > 0 and ("\n" .. marshal.mistakes .. " Fehlzeichen") or "") ..
			(perfect and "\nPerfekt eingewiesen! +60 Bonus" or "") ..
			"\n\n+" .. (pay + bonus) .. " Credits",
			UDim2.new(0, 20, 0, 52), UDim2.new(1, -40, 0, 110), TXT, 15)
		button(p, "Nächster Flieger", UDim2.new(0, 20, 1, -56), UDim2.new(0, 160, 0, 40), Color3.fromRGB(40, 110, 60), function()
			hidePanel(); startMarshal()
		end)
		button(p, "Feierabend", UDim2.new(0, 195, 1, -56), UDim2.new(0, 150, 0, 40), Color3.fromRGB(60, 70, 85), function()
			hidePanel()
			marshalJet:PivotTo(CFrame.new(0, 0, -4200 * M))
			setJobHUD("Arbeitslos", "Such dir einen Job an einer leuchtenden Station.")
		end)
	end)
end
function startMarshal()
	marshal.active = true
	marshal.s = 0; marshal.correct = 0; marshal.mistakes = 0
	marshal.waiting = nil; marshal.sigIdx = 1; marshal.timer = 150
	S.job = "marshal"
	setJobHUD("MARSHALLER", "Ein A320 rollt zu Gate 4.\nBleib an der Einweiser-Position und gib die Zeichen!")
end
local function updateMarshal(dt)
	if not marshal.active then return end
	marshal.timer = marshal.timer - dt
	setTimerHUD(math.max(0, marshal.timer))
	local pp = playerPosM()
	local atStation = math.sqrt((pp.X + 130) ^ 2 + (pp.Z - 148) ^ 2) < 22 and S.mode == "walk"
	if marshal.waiting then
		if not atStation then
			marshal.gui.Visible = false
			setJobHUD("MARSHALLER", "⚠ Geh zur Einweiser-Position an Gate 4 – der Pilot sieht dich nicht!")
		else
			marshal.gui.Visible = true
			marshal.keyL.Text = marshal.waiting.sym
			marshal.whatL.Text = marshal.waiting.what
			for _, kc in ipairs({ Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.X }) do
				if edge(kc) then
					if kc == marshal.waiting.key then
						marshal.correct = marshal.correct + 1
						toast("✔ Richtiges Zeichen!", "good")
						marshal.waiting = nil
						marshal.gui.Visible = false
					else
						marshal.mistakes = marshal.mistakes + 1
						addCredits(-20, "flight")
						toast("✘ Falsches Zeichen! −20 Credits", "bad")
					end
				end
			end
		end
	else
		local spd = marshal.s < 570 and 9 or 3.5
		marshal.s = marshal.s + spd * dt
		local sig = marshal.signals[marshal.sigIdx]
		if sig and marshal.s >= sig.s then
			marshal.waiting = sig
			marshal.sigIdx = marshal.sigIdx + 1
		end
		if marshal.s >= marshal.len then endMarshal() return end
	end
	local x, z, dx, dz = marshalPathPos(math.min(marshal.s, marshal.len))
	marshalJet:PivotTo(CFrame.new(x * M, 0, z * M) * CFrame.Angles(0, math.atan2(-dx, -dz), 0))
end

---------------------------------------------------------------- Keller-Koffer laufen auf den Bändern
local kellerBags = {}
sysInit("Keller-Koffer", function()
	local kb = airport:FindFirstChild("KellerBags", true) -- liegt im Mega-Ordner
	if kb then
		for _, p in ipairs(kb:GetChildren()) do table.insert(kellerBags, p) end
	end
end)
local function updateKellerBags(t)
	if #kellerBags == 0 then return end
	-- Pfad: Sammelband -> Querband -> Steigband (Meter)
	local P = {
		Vector3.new(-45.5, -3.75, 261), Vector3.new(-22, -3.75, 261),
		Vector3.new(-22, -3.75, 250.5), Vector3.new(-21.6, 1.05, 257.9),
	}
	local L = { (P[2] - P[1]).Magnitude, (P[3] - P[2]).Magnitude, (P[4] - P[3]).Magnitude }
	local total = L[1] + L[2] + L[3]
	for i, p in ipairs(kellerBags) do
		local s = (t * 1.25 + (i - 1) * total / #kellerBags) % total
		local seg = 1
		while seg < 3 and s > L[seg] do s = s - L[seg] seg = seg + 1 end
		local pos = P[seg]:Lerp(P[seg + 1], math.min(1, s / L[seg]))
		p.CFrame = CFrame.new(pos * M)
	end
end

---------------------------------------------------------------- Windräder drehen
local turbines = {}
sysInit("Windraeder & Radar", function()
	local landF = airport:FindFirstChild("Landscape")
	if landF then
		for _, m in ipairs(landF:GetChildren()) do
			if m:IsA("Model") and m.Name:sub(1, 11) == "WindTurbine" then
				local hub = m.PrimaryPart
				local blades = {}
				for _, b in ipairs(m:GetChildren()) do
					if b.Name:sub(1, 5) == "Blade" then
						table.insert(blades, { p = b, off = hub.CFrame:ToObjectSpace(b.CFrame) })
					end
				end
				table.insert(turbines, { hub = hub, blades = blades, ang = math.random() * 6 })
			end
		end
	end
	-- Tower-Radar mitdrehen (gleicher Animator, aber um die Y-Achse)
	local designF = airport:FindFirstChild("RealDesign")
	local radarM = designF and designF:FindFirstChild("Radar")
	if radarM then
		local ped = radarM:WaitForChild("Ped")
		local dish = radarM:WaitForChild("Dish")
		table.insert(turbines, { hub = ped, blades = { { p = dish, off = ped.CFrame:ToObjectSpace(dish.CFrame) } }, ang = 0, yAxis = true })
	end
end)
local function updateTurbines(dt)
	for _, t in ipairs(turbines) do
		t.ang = t.ang + dt * 1.1
		local rot = t.yAxis and (t.hub.CFrame * CFrame.Angles(0, t.ang, 0)) or (t.hub.CFrame * CFrame.Angles(0, 0, t.ang))
		for _, b in ipairs(t.blades) do
			b.p.CFrame = rot * b.off
		end
	end
end

---------------------------------------------------------------- Stationen (E-Interaktionen)
addInteract({
	x = function() return -45 end, z = function() return 260.7 end, r = 3.6,
	cond = function() return S.mode == "walk" and (S.job == nil or S.job == "checkin") end,
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
	cond = function() return S.mode == "walk" and (S.job == nil or S.job == "ramp") end,
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
	action = function() requestVehicle(cart, "Cart") end,
})
addInteract({
	x = function() return fuelTruck.pos.X end, z = function() return fuelTruck.pos.Z end, r = 3.4,
	cond = function() return S.mode == "walk" and not ramp.carrying end,
	label = function() return "Tankwagen fahren" end,
	action = function() requestVehicle(fuelTruck, "FuelTruck") end,
})
for _, cv in ipairs({ { nil, "CarA", "🚗 Auto fahren (Parkplatz)" }, { nil, "CarB", "🚗 Auto fahren (Parkhaus)" } }) do
	local nm, lbl = cv[2], cv[3]
	addInteract({
		x = function() return (nm == "CarA" and carA or carB).pos.X end,
		z = function() return (nm == "CarA" and carA or carB).pos.Z end, r = 4.2,
		cond = function() return S.mode == "walk" end,
		label = function() return lbl .. " · WASD, E = aussteigen" end,
		action = function() requestVehicle(nm == "CarA" and carA or carB, nm) end,
	})
end
-- Station: Tankwagen-Job
addInteract({
	x = function() return -152 end, z = function() return 215 end, r = 4,
	cond = function() return S.mode == "walk" and (S.job == nil or S.job == "fuel") end,
	label = function()
		if fuelJob.active then return "Schicht läuft – ab in den Tankwagen!" end
		if S.credits >= UNLOCK_FUEL then return "Tank-Schicht starten (Tankwagen)" end
		return "Tankwagen – gesperrt (" .. UNLOCK_FUEL .. " Credits nötig)"
	end,
	action = function()
		if fuelJob.active then return end
		if S.credits < UNLOCK_FUEL then
			toast("Du brauchst " .. UNLOCK_FUEL .. " Credits für diesen Job!", "bad")
			return
		end
		showTutorial("fuel", "JOB: Tankwagen-Fahrer",
			"Beide Jets brauchen Kerosin:\n· Steig in den Tankwagen am Fuel Depot (E)\n· Fahr dicht an LH 452 bzw. EW 771 heran und drücke E\n· Beim Betanken stillstehen – wegfahren bricht ab!\n· 120 Credits pro Jet · beide in 2:30 = Bonus",
			startFuelJob)
	end,
})
-- Station: Marshaller
addInteract({
	x = function() return -130 end, z = function() return 148 end, r = 4.5,
	cond = function() return S.mode == "walk" and (S.job == nil or S.job == "marshal") end,
	label = function()
		if marshal.active then return "Einweisung läuft – bleib hier stehen!" end
		if S.credits >= UNLOCK_MARSHAL then return "Marshaller-Einsatz starten" end
		return "Marshaller – gesperrt (" .. UNLOCK_MARSHAL .. " Credits nötig)"
	end,
	action = function()
		if marshal.active then return end
		if S.credits < UNLOCK_MARSHAL then
			toast("Du brauchst " .. UNLOCK_MARSHAL .. " Credits für diesen Job!", "bad")
			return
		end
		showTutorial("marshal", "JOB: Marshaller (Einweiser)",
			"Ein A320 rollt vom Taxiway zu Gate 4 – du weist ihn ein:\n· Bleib an der leuchtenden Einweiser-Position stehen\n· Wenn der Jet stoppt, zeigt das HUD das Zeichen: W weiter · S langsamer · A links · X STOP\n· Richtiges Zeichen = +40 Cr · falsches = −20 Cr · fehlerfrei = +60 Bonus",
			startMarshal)
	end,
})
addInteract({
	x = function() return 124 end, z = function() return 172 end, r = 5,
	cond = function() return S.mode == "walk" and S.job == nil end,
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

---------------------------------------------------------------- Ebenen-Teleports + funktionierende Laeden + Kosmetik
sysInit("Ebenen & Shops", function()
	local function py()
		local r = hrp()
		return r and (r.Position.Y / M) or 0
	end
	local function tp(x, ym, z)
		if character then character:PivotTo(CFrame.new(x * M, ym * M + 3, z * M)) end
	end
	-- Tunnel Parkdeck <-> Terminal (Treppen sind Teleports, Tunnel selbst ist begehbar)
	addInteract({ x = function() return -120 end, z = function() return 305 end, r = 3.2,
		cond = function() return S.mode == "walk" and py() > -1 end,
		label = function() return "⬇ Tunnel zum Terminal (UG)" end,
		action = function() tp(-118, -4.6, 290) end })
	addInteract({ x = function() return -118 end, z = function() return 290 end, r = 3.0,
		cond = function() return S.mode == "walk" and py() < -2 end,
		label = function() return "⬆ Treppe: Parkdeck" end,
		action = function() tp(-120, 0, 305.5) end })
	addInteract({ x = function() return -66 end, z = function() return 284.5 end, r = 3.0,
		cond = function() return S.mode == "walk" and py() > -1 and py() < 2 end,
		label = function() return "⬇ Tunnel zum Parkdeck (UG)" end,
		action = function() tp(-63, -4.6, 290) end })
	addInteract({ x = function() return -63 end, z = function() return 290 end, r = 3.0,
		cond = function() return S.mode == "walk" and py() < -2 end,
		label = function() return "⬆ Treppe: Terminal" end,
		action = function() tp(-66, 0, 281.8) end })
	-- Gepaeckkeller (Personal)
	addInteract({ x = function() return -52 end, z = function() return 236.5 end, r = 3.2,
		cond = function() return S.mode == "walk" and py() > -1 end,
		label = function() return "⬇ Gepäckkeller (Personal)" end,
		action = function() tp(-46, -4.6, 241) end })
	addInteract({ x = function() return -46 end, z = function() return 241 end, r = 3.0,
		cond = function() return S.mode == "walk" and py() < -2 end,
		label = function() return "⬆ Treppe: Terminal" end,
		action = function() tp(-51.5, 0, 240) end })
	-- Glas-Aufzug EG <-> Food-Court-Galerie (Rampe geht auch zu Fuss)
	addInteract({ x = function() return 2.5 end, z = function() return 295.6 end, r = 2.8,
		cond = function() return S.mode == "walk" and py() < 2.5 and py() > -1 end,
		label = function() return "🛗 Aufzug: Ebene 2" end,
		action = function() tp(2.5, 4.78, 295) end })
	addInteract({ x = function() return 2.5 end, z = function() return 295 end, r = 2.8,
		cond = function() return S.mode == "walk" and py() > 3.5 end,
		label = function() return "🛗 Aufzug: Erdgeschoss" end,
		action = function() tp(2.5, 0, 295.6) end })

	-- Kaufbare Kosmetik: Sonnenbrille / Kopfhoerer (an den Kopf geschweisst)
	local worn = {}
	local function wear(kind)
		local c = character
		local head = c and c:FindFirstChild("Head")
		if not head or worn[kind] then return end
		local parts = {}
		if kind == "glasses" then
			parts[1] = { Vector3.new(1.1, 0.25, 0.16), CFrame.new(0, 0.18, -0.62), Color3.fromRGB(20, 22, 26) }
		else
			parts[1] = { Vector3.new(0.24, 0.5, 0.42), CFrame.new(-0.72, 0, 0), Color3.fromRGB(194, 59, 46) }
			parts[2] = { Vector3.new(0.24, 0.5, 0.42), CFrame.new(0.72, 0, 0), Color3.fromRGB(194, 59, 46) }
			parts[3] = { Vector3.new(1.5, 0.18, 0.3), CFrame.new(0, 0.68, 0), Color3.fromRGB(20, 22, 26) }
		end
		local made = {}
		for _, d in ipairs(parts) do
			local p = Instance.new("Part")
			p.Size = d[1]; p.Color = d[3]; p.CanCollide = false; p.Massless = true; p.Anchored = false
			p.CFrame = head.CFrame * d[2]
			local w = Instance.new("WeldConstraint"); w.Part0 = head; w.Part1 = p; w.Parent = p
			p.Parent = c
			table.insert(made, p)
		end
		worn[kind] = made
	end

	-- Laeden: EINE Datenquelle (ReplicatedStorage/ShopData) fuer Panel + Prompts
	local SHOPS = require(game:GetService("ReplicatedStorage"):WaitForChild("ShopData"))
	local function applyEffect(eff, nm)
		if eff == "boost" then
			S.boostUntil = os.clock() + 60
			toast("⚡ " .. nm .. ": 60 s schneller unterwegs!", "good")
		elseif eff == "glasses" or eff == "phones" then
			wear(eff)
			toast(eff == "glasses" and "🕶 Sonnenbrille aufgesetzt — stylisch!" or "🎧 Kopfhörer aufgesetzt!", "good")
		elseif eff == "souvenir" then
			addXP(15)
			toast("✈ Mini-A380 eingepackt — ein Stück Flughafen für zu Hause!", "good")
		else
			local n = tonumber(eff:sub(3)) or 5
			addXP(n)
			toast("😋 " .. nm .. " — +" .. n .. " XP", "good")
		end
	end
	local openShopPanel
	local function buyItem(si, ii)
		buyEv:FireServer(si, ii) -- Server prueft Preis gegen ShopData und zieht ab (Phase 3)
	end
	buyEv.OnClientEvent:Connect(function(ok, si, ii, newCredits)
		S.credits = newCredits
		updateHUD()
		local s = SHOPS[si]
		local it = s and s.items[ii]
		if not it then return end
		if ok then
			unlock("shopper")
			applyEffect(it[3], it[1])
			if panelOpen then openShopPanel(si) end
		else
			toast("Zu wenig Credits für " .. it[1] .. "!", "bad")
		end
	end)
	openShopPanel = function(si)
		local s = SHOPS[si]
		showPanel(function(p)
			local t = label(p, s.name, UDim2.new(0, 20, 0, 14), UDim2.new(1, -40, 0, 26), GOLD, 20)
			t.Font = Enum.Font.GothamBold
			label(p, "Guthaben: " .. S.credits .. " Credits", UDim2.new(0, 20, 0, 46), UDim2.new(1, -40, 0, 20), TXT, 14)
			for i, it in ipairs(s.items) do
				local yy = 60 + i * 56
				label(p, it[1], UDim2.new(0, 20, 0, yy + 8), UDim2.new(0, 280, 0, 24), TXT, 16)
				local can = S.credits >= it[2]
				button(p, it[2] .. " Cr", UDim2.new(1, -140, 0, yy), UDim2.new(0, 116, 0, 40),
					can and Color3.fromRGB(40, 110, 60) or Color3.fromRGB(70, 74, 82), function()
						if can then buyItem(si, i) end
					end)
			end
			button(p, "Schließen", UDim2.new(0, 20, 1, -56), UDim2.new(0, 140, 0, 40), Color3.fromRGB(70, 74, 82), hidePanel)
		end)
	end
	for si, s in ipairs(SHOPS) do
		-- Interaktionspunkt = vor der Theke (lokal -3.2 / +0.9), aus pos + rotation gedreht
		local ct, st2 = math.cos(s.rotation), math.sin(s.rotation)
		local ix = s.pos.x + (-3.2) * ct + 0.9 * st2
		local iz = s.pos.z - (-3.2) * st2 + 0.9 * ct
		addInteract({
			x = function() return ix end, z = function() return iz end, r = 4.2,
			cond = function()
				if S.mode ~= "walk" then return false end
				local onG = py() > 3.5
				return (s.ebene == 2 and onG) or (s.ebene == 1 and not onG)
			end,
			label = function() return s.name .. " — einkaufen" end,
			action = function() openShopPanel(si) end,
		})
	end
end)

---------------------------------------------------------------- Hauptschleife
updateHUD()
setJobHUD("Arbeitslos", "Geh zum leuchtenden Check-in-Schalter im Terminal und drücke E.")
resetPlaneToStand()
task.defer(function()
	-- warten, bis der Titelscreen weggeklickt ist — sonst liegt das Panel unsichtbar darunter
	while gui:FindFirstChild("Splash") do task.wait(0.25) end
	showTutorial("welcome", "Willkommen am Flughafen!",
		"Karriereleiter: 500 Ramp · 750 Security · 1000 Tankwagen · 1500 Marshaller · 2000 Captain.\n\n· WASD laufen · Shift sprinten · E an leuchtenden Stationen · H Legende\n· Schau dir den begehbaren A380 an Gate 1 und das Parkdeck an!")
end)

-- Loop-Schritte je System (Phase 4): jeder Schritt laeuft in pcall,
-- ein Laufzeitfehler in einem System legt die anderen nicht still.
local function stepTasten()
	if edge(Enum.KeyCode.H) then legend.Visible = not legend.Visible end
	if edge(Enum.KeyCode.J) and S.mode ~= "fly" and not panelOpen then showAchievements() end
	if edge(Enum.KeyCode.M) then minimapFrame.Visible = not minimapFrame.Visible end
end
local function stepMinimap()
	local mp = S.mode == "fly" and plane.pos or playerPosM()
	updateMinimap(mp)
	local r0 = hrp()
	if r0 and S.mode == "walk" then
		local wy = r0.Position.Y
		if mp.X > -42.4 and mp.X < -37.6 and mp.Z > 151 and mp.Z < 180 and wy > 5 then unlock("a380_board") end
		if mp.X > -166 and mp.X < -84 and mp.Z > 308 and mp.Z < 352 and wy > 12 then unlock("pd_roof") end
	end
end
local function stepFlug(dt)
	updateFlightPhysics(dt)
	updateMission(dt)
	updateFlightHUD()
	updateFlightCamera(dt)
end
local function stepJobs(dt)
	updateCheckin(dt)
	updateRamp(dt)
	updateFuelJob(dt)
	updateMarshal(dt)
end
local function stepFahrzeuge(dt)
	updateVehicle(cart, dt)
	updateVehicle(fuelTruck, dt)
	updateVehicle(carA, dt)
	updateVehicle(carB, dt)
end
local function stepKoffer()
	if ramp.carrying then
		local r = hrp()
		if r then
			ramp.carrying.obj.CFrame = r.CFrame * CFrame.new(0, -0.3, -2.4)
		end
	end
end
local function stepAmbiente(dt)
	updateAmbient(dt)
	updateTraffic(dt)
	updateWindsock()
	updateTurbines(dt)
	updateKellerBags(os.clock())
end
RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 0.05)
	safeStep("Tasten", stepTasten)
	safeStep("Minimap", stepMinimap)
	if not panelOpen then
		if S.mode == "fly" then
			safeStep("Flug", stepFlug, dt)
		else
			safeStep("Jobs", stepJobs, dt)
			safeStep("Fahrzeuge", stepFahrzeuge, dt)
			safeStep("Interaktion", updateInteract)
			safeStep("Koffer", stepKoffer)
		end
	end
	safeStep("Ambiente", stepAmbiente, dt)
	keyEdge = {}
end)

print("[Airport] Client bereit — viel Spass!")
