--[[
	FLUGHAFEN-JOB-SIMULATOR · Server
	Baut den kompletten Flughafen beim Start auf (keine externen Assets).
	Masseinheit: 1 m = 2 Studs (Skalierungsfaktor M).
	Norden = -Z, Osten = +X. Runway 09/27 entlang der X-Achse.

	Die gesamte Spiellogik (Jobs, Flugphysik, HUD) laeuft im LocalScript
	"AirportClient" in StarterPlayerScripts — ausgelegt auf Solo-Play.
]]

local M = 3.4 -- Studs pro Meter (muss zum Client passen)
workspace:SetAttribute("MetersToStuds", M) -- Services (Zone/Flight/Inventory) lesen den Massstab hier

local Workspace = game:GetService("Workspace")

-- Alte Version entfernen (bei Re-Run in Studio)
local old = Workspace:FindFirstChild("Airport")
if old then old:Destroy() end

local airport = Instance.new("Folder")
airport.Name = "Airport"
airport.Parent = Workspace

-- Atmosphaere / Fog
-- Lighting (Technology=Future, TimeOfDay 15:00, Atmosphere/Bloom/ColorCorrection)
-- kommt als Item direkt aus der .rbxlx — hier nichts mehr ueberschreiben (Phase 5).

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

-- Groesse/Position in Metern angeben
local function mpart(parent, name, sx, sy, sz, x, y, z, color, props)
	local p = part({
		Name = name,
		Size = Vector3.new(sx * M, sy * M, sz * M),
		CFrame = CFrame.new(x * M, y * M, z * M),
		Color = color,
	})
	if props then
		for k, v in pairs(props) do p[k] = v end
	end
	p.Parent = parent
	return p
end

local COL = {
	grass = Color3.fromRGB(111, 158, 82),
	asphalt = Color3.fromRGB(60, 63, 69),
	taxi = Color3.fromRGB(72, 75, 82),
	apron = Color3.fromRGB(84, 87, 94),
	white = Color3.fromRGB(232, 232, 232),
	yellow = Color3.fromRGB(216, 182, 42),
	wall = Color3.fromRGB(207, 214, 222),
	glass = Color3.fromRGB(159, 212, 232),
	dark = Color3.fromRGB(44, 47, 54),
	blue = Color3.fromRGB(58, 111, 232),
	orange = Color3.fromRGB(224, 120, 32),
	red = Color3.fromRGB(194, 59, 46),
	cream = Color3.fromRGB(245, 240, 232),
}

-- Eine Wahrheit fuer alle Shops (Geometrie hier, Prompts/Panels im Client)
local ShopData = require(game:GetService("ReplicatedStorage"):WaitForChild("ShopData"))

-- Fehler-Haertung (Phase 4): ein fehlgeschlagener Map-Abschnitt reisst nicht den Rest mit
local function sysInit(name, fn)
	local ok, err = pcall(fn)
	if not ok then warn("[AirportServer] Abschnitt '" .. name .. "' fehlgeschlagen: " .. tostring(err)) end
end

---------------------------------------------------------------- Boden
-- Roblox kappt Part-Groessen bei 2048 Studs pro Achse -> grosse Flaechen kacheln!
-- Kachel-Helfer: teilt sx/sz in Stuecke von maximal 1000 m (= 2000 Studs)
local function tiled(parent, name, sx, sy, sz, x, y, z, color, props)
	local MAXM = 590 -- 590 m * M=3.4 = 2006 Studs, sicher unter dem 2048er-Part-Limit
	local nx = math.ceil(sx / MAXM)
	local nz = math.ceil(sz / MAXM)
	local tw, td = sx / nx, sz / nz
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			mpart(parent, name, tw, sy, td,
				x - sx / 2 + tw * (ix + 0.5), y, z - sz / 2 + td * (iz + 0.5), color, props)
		end
	end
end
tiled(airport, "Ground", 7000, 1, 7000, 0, -0.5, 0, COL.grass, { Material = Enum.Material.Grass })

-- ein paar Low-Poly-Baeume und Haeuser als Deko
local deko = Instance.new("Folder"); deko.Name = "Deko"; deko.Parent = airport
math.randomseed(42)
for i = 1, 60 do
	local x, z
	repeat
		x, z = math.random(-2600, 2600), math.random(-2600, 2600)
	until math.abs(x) > 1350 or z < -300 or z > 450
	local s = 0.8 + math.random() * 0.8
	mpart(deko, "Trunk", 1 * s, 5 * s, 1 * s, x, 2.5 * s, z, Color3.fromRGB(110, 74, 47), { CanCollide = false })
	local crown = mpart(deko, "Crown", 6 * s, 8 * s, 6 * s, x, (5 + 4) * s, z, Color3.fromRGB(57, 112, 46), { CanCollide = false })
	crown.Shape = Enum.PartType.Ball
end
for i = 1, 24 do
	local x, z
	repeat
		x, z = math.random(-2200, 2200), math.random(-2200, 2200)
	until math.abs(x) > 1400 or z < -350 or z > 500
	mpart(deko, "House", 9, 6, 8, x, 3, z, Color3.fromRGB(216, 207, 192))
	local roof = mpart(deko, "Roof", 10, 3, 9, x, 7.5, z, Color3.fromRGB(160, 82, 45))
	roof.Shape = Enum.PartType.Wedge
end

---------------------------------------------------------------- Runway 09/27 (1500 m)
local RWY_L, RWY_W = 1500, 30
tiled(airport, "Runway", RWY_L + 40, 0.4, RWY_W, 0, 0.05, 0, COL.asphalt, { Material = Enum.Material.Asphalt })
-- Centerline
for x = -660, 660, 60 do
	mpart(airport, "CL", 30, 0.1, 0.9, x, 0.3, 0, COL.white, { CanCollide = false })
end
-- Schwellen (Piano Keys) + Aufsetzzonen-Streifen + Nummern
for _, t in ipairs({ { -750, 1, "09" }, { 750, -1, "27" } }) do
	local tx, dir, num = t[1], t[2], t[3]
	for i = 0, 5 do
		local z = -RWY_W / 2 + 3.2 + i * (RWY_W - 6.4) / 5
		mpart(airport, "Piano", 18, 0.1, 1.7, tx + dir * 14, 0.3, z, COL.white, { CanCollide = false })
	end
	for k = 1, 3 do
		local x = tx + dir * (90 + k * 75)
		mpart(airport, "TDZ", 20, 0.1, 1.5, x, 0.3, -7, COL.white, { CanCollide = false })
		mpart(airport, "TDZ", 20, 0.1, 1.5, x, 0.3, 7, COL.white, { CanCollide = false })
	end
	local numP = mpart(airport, "Num" .. num, 10, 0.1, 18, tx + dir * 52, 0.3, 0, COL.asphalt, { CanCollide = false })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Top
	sg.CanvasSize = Vector2.new(200, 360)
	sg.Parent = numP
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = num
	tl.TextColor3 = COL.white
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBlack
	-- SurfaceGui-Top-Face: "oben" zeigt Richtung +X -> 0° fuer 09 (Anflug aus Westen), 180° fuer 27
	tl.Rotation = (dir == 1) and 0 or 180
	tl.Parent = sg
end
-- Randbefeuerung + Schwellenlichter
local lights = Instance.new("Folder"); lights.Name = "RunwayLights"; lights.Parent = airport
for x = -750, 750, 50 do
	for _, zz in ipairs({ -RWY_W / 2 - 1.5, RWY_W / 2 + 1.5 }) do
		mpart(lights, "Edge", 0.8, 0.8, 0.8, x, 0.5, zz, Color3.fromRGB(255, 246, 204), { Material = Enum.Material.Neon, CanCollide = false })
	end
end
for i = 0, 8 do
	local z = -RWY_W / 2 + i * RWY_W / 8
	mpart(lights, "Grn", 0.7, 0.7, 0.7, -754, 0.4, z, Color3.fromRGB(34, 255, 85), { Material = Enum.Material.Neon, CanCollide = false })
	mpart(lights, "Red", 0.7, 0.7, 0.7, -756.5, 0.4, z, Color3.fromRGB(255, 51, 51), { Material = Enum.Material.Neon, CanCollide = false })
	mpart(lights, "Grn", 0.7, 0.7, 0.7, 754, 0.4, z, Color3.fromRGB(34, 255, 85), { Material = Enum.Material.Neon, CanCollide = false })
	mpart(lights, "Red", 0.7, 0.7, 0.7, 756.5, 0.4, z, Color3.fromRGB(255, 51, 51), { Material = Enum.Material.Neon, CanCollide = false })
end

-- PAPI: je 4 Lampen (Client faerbt sie rot/weiss)
local function papi(name, x, z)
	local m = Instance.new("Model"); m.Name = name; m.Parent = airport
	for i = 0, 3 do
		local zz = z + i * 3 * (z > 0 and 1 or -1)
		mpart(m, "Base", 0.8, 1.1, 0.8, x, 0.55, zz, Color3.fromRGB(51, 51, 51))
		mpart(m, "Lamp" .. (i + 1), 0.7, 0.5, 0.4, x, 1.0, zz, COL.white, { Material = Enum.Material.Neon, CanCollide = false })
	end
end
papi("PAPI09", -450, -RWY_W / 2 - 8) -- Anflug von Westen
papi("PAPI27", 450, RWY_W / 2 + 8)   -- Anflug von Osten

---------------------------------------------------------------- Taxiway + Vorfeld
tiled(airport, "Taxiway", RWY_L + 40, 0.35, 16, 0, 0.02, 80, COL.taxi, { Material = Enum.Material.Asphalt })
for x = -750, 740, 30 do
	mpart(airport, "TL", 15, 0.1, 0.5, x + 7, 0.3, 80, COL.yellow, { CanCollide = false })
end
for _, cx in ipairs({ -700, 0, 700 }) do
	mpart(airport, "Conn", 16, 0.35, 66, cx, -0.02, 40, COL.taxi) -- leicht tiefer gegen Z-Fighting
	for z = 18, 70, 15 do
		mpart(airport, "TL", 0.5, 0.1, 8, cx, 0.3, z, COL.yellow, { CanCollide = false })
	end
end
mpart(airport, "Conn2", 20, 0.35, 55, 60, -0.02, 115, COL.taxi)
mpart(airport, "Apron", 510, 0.35, 95, 45, 0.02, 182, COL.apron, { Material = Enum.Material.Concrete })
for _, px in ipairs({ -130, -40, 40, 130, 200 }) do
	mpart(airport, "Stand", 0.6, 0.1, 22, px, 0.3, 176, COL.yellow, { CanCollide = false })
	mpart(airport, "Stand", 14, 0.1, 0.6, px, 0.3, 165, COL.yellow, { CanCollide = false })
end

---------------------------------------------------------------- Deko-Jets: Airbus A380 (Doppeldecker, 4 Triebwerke)
local AIRLINE_NAMES = { "SKYJET", "LUFTAIR", "NORDWIND", "SUNLINE", "PACIFIC AIR" }
local function airlineTitle(m, x, y, z, w, h)
	-- Schriftzug beidseitig am Rumpf (SurfaceGui auf duennem Part)
	local title = AIRLINE_NAMES[math.random(#AIRLINE_NAMES)]
	for _, sx in ipairs({ -1, 1 }) do
		local tp = mpart(m, "Title", 0.04, h, w, sx * x, y, z, COL.cream, { CanCollide = false })
		local sg = Instance.new("SurfaceGui")
		sg.Face = sx > 0 and Enum.NormalId.Right or Enum.NormalId.Left
		sg.CanvasSize = Vector2.new(w * 50, h * 50); sg.Parent = tp
		local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBold; tl.TextScaled = true
		tl.TextColor3 = Color3.fromRGB(28, 39, 51); tl.Text = title; tl.Parent = sg
	end
end
local function finLogo(m, color, thick, y, z, d)
	-- Logo-Scheiben durch die Flosse (Zylinderachse X = beidseitig sichtbar)
	local ring = mpart(m, "LogoRing", thick + 0.2, d, d, 0, y, z, Color3.fromRGB(255, 255, 255), { CanCollide = false })
	ring.Shape = Enum.PartType.Cylinder
	local inner = mpart(m, "LogoInner", thick + 0.26, d * 0.65, d * 0.65, 0, y, z, color, { CanCollide = false })
	inner.Shape = Enum.PartType.Cylinder
end
local ENGINE_POS = { { 7.2, 4.6 }, { 13.5, 8.4 } } -- {|x|, z} unter dem gepfeilten Fluegel
local function makeJet(name, color, x, z, yawDeg)
	local m = Instance.new("Model"); m.Name = name
	local root = mpart(m, "Root", 1, 1, 1, 0, 0, 0, color, { Transparency = 1, CanCollide = false })
	m.PrimaryPart = root
	-- Doppeldecker-Rumpf (Zylinderachse X -> um 90 Grad drehen)
	-- Rumpf ohne Kollision (sonst waere die Kabine unzugaenglich); unsichtbarer Blocker unten
	local tube = mpart(m, "Tube", 34, 4.6, 4.6, 0, 3.0, 0, COL.cream, { CanCollide = false })
	tube.Shape = Enum.PartType.Cylinder
	tube.CFrame = CFrame.new(0, 3.0 * M, 0) * CFrame.Angles(0, math.rad(90), 0)
	mpart(m, "BellyBlock", 4.4, 1.55, 33, 0, 0.8, 0, COL.cream, { Transparency = 1 })
	local hump = mpart(m, "Hump", 30, 3.5, 3.5, 0, 5.85, -0.5, COL.cream, { CanCollide = false })
	hump.Shape = Enum.PartType.Cylinder
	hump.CFrame = CFrame.new(0, 5.85 * M, -0.5 * M) * CFrame.Angles(0, math.rad(90), 0)
	-- A380-Nase
	local nose = mpart(m, "Nose", 4.6, 4.6, 4.6, 0, 3.0, -17, COL.cream, { CanCollide = false }); nose.Shape = Enum.PartType.Ball
	local noseUp = mpart(m, "NoseUp", 3.5, 3.5, 3.5, 0, 5.6, -15.4, COL.cream, { CanCollide = false }); noseUp.Shape = Enum.PartType.Ball
	mpart(m, "CockpitWin", 2.6, 0.55, 0.6, 0, 4.35, -17.6, Color3.fromRGB(16, 21, 28), { CanCollide = false })
	-- Heckkonus
	mpart(m, "Tailc", 1.8, 2.6, 8, 0, 3.6, 20.5, COL.cream, { CanCollide = false })
	mpart(m, "TailcUp", 1.2, 1.8, 7, 0, 5.9, 18.2, COL.cream, { CanCollide = false })
	-- Fensterbaender + Guertelstreifen
	for _, sx in ipairs({ -1, 1 }) do
		mpart(m, "WinMain", 0.08, 0.35, 30, sx * 2.28, 3.7, 0, Color3.fromRGB(42, 54, 68), { CanCollide = false })
		mpart(m, "WinUp", 0.08, 0.35, 26, sx * 1.72, 6.2, -1, Color3.fromRGB(42, 54, 68), { CanCollide = false })
		mpart(m, "Belt", 0.06, 0.5, 33, sx * 2.31, 4.45, 0, color, { CanCollide = false })
		for _, dz in ipairs({ -13.5, -7.5, 0, 8, 14.5 }) do
			mpart(m, "Door", 0.08, 1.9, 1.0, sx * 2.29, 3.0, dz, Color3.fromRGB(154, 164, 176), { CanCollide = false })
		end
	end
	-- Gepfeilte Fluegel + 4 Triebwerke
	for _, sx in ipairs({ -1, 1 }) do
		local wing = mpart(m, "Wing", 25, 0.45, 7, 0, 0, 0, COL.cream, { CanCollide = false })
		wing.CFrame = CFrame.new(sx * 1.8 * M, 2.7 * M, 0.5 * M)
			* CFrame.Angles(0, sx > 0 and -0.5 or (math.pi + 0.5), sx * 0.055)
			* CFrame.new(12.5 * M, 0, 1.5 * M)
		for _, e in ipairs(ENGINE_POS) do
			local eng = mpart(m, "Eng", 3.8, 2.3, 2.3, sx * e[1], 1.55, e[2], Color3.fromRGB(170, 176, 184))
			eng.Shape = Enum.PartType.Cylinder
			eng.CFrame = CFrame.new(sx * e[1] * M, 1.55 * M, e[2] * M) * CFrame.Angles(0, math.rad(90), 0)
			mpart(m, "Fan", 0.3, 1.85, 1.85, sx * e[1], 1.55, e[2] - 1.95, Color3.fromRGB(34, 38, 44), { CanCollide = false })
			local sp = mpart(m, "Spin", 0.55, 0.55, 0.55, sx * e[1], 1.55, e[2] - 2.05, Color3.fromRGB(226, 226, 226), { CanCollide = false })
			sp.Shape = Enum.PartType.Ball
			mpart(m, "Pylon", 0.4, 1.5, 2.6, sx * e[1], 2.8, e[2] + 1.2, COL.cream, { CanCollide = false })
		end
	end
	airlineTitle(m, 2.34, 4.45, -10, 8, 1.0)
	-- Leitwerk
	local fin = mpart(m, "Fin", 0.5, 9.5, 5.5, 0, 9.0, 19.8, color, { CanCollide = false })
	fin.CFrame = CFrame.new(0, 9.0 * M, 19.8 * M) * CFrame.Angles(-0.32, 0, 0)
	finLogo(m, color, 0.5, 10.0, 20.1, 2.5)
	for _, sx in ipairs({ -1, 1 }) do
		local hs = mpart(m, "HStab", 8.5, 0.3, 3.4, 0, 0, 0, COL.cream, { CanCollide = false })
		hs.CFrame = CFrame.new(sx * 0.4 * M, 4.7 * M, 20 * M)
			* CFrame.Angles(0, sx > 0 and -0.55 or (math.pi + 0.55), 0)
			* CFrame.new(4.25 * M, 0, 1.1 * M)
	end
	-- Fahrwerk: Bug + 4 Hauptfahrwerks-Bogies
	local function bogie(bx, bz, n)
		mpart(m, "Strut", 0.44, 2.0, 0.44, bx, 1.4, bz, Color3.fromRGB(58, 61, 68))
		for i = 0, n - 1 do
			mpart(m, "Whl", 0.85, 1.0, 1.0, bx, 0.5, bz - (n - 1) * 0.55 + i * 1.1, Color3.fromRGB(20, 22, 26))
		end
	end
	bogie(0, -13.5, 2)
	bogie(-2.6, 1.5, 3); bogie(2.6, 1.5, 3)
	bogie(-1.4, 3.6, 2); bogie(1.4, 3.6, 2)
	m.Parent = airport
	m:PivotTo(CFrame.new(x * M, 0, z * M) * CFrame.Angles(0, math.rad(yawDeg or 0), 0))
	return m
end
-- Weitere Typen: A320 / B747 / ATR-Turboprop / Businessjet
local function makeNarrowbody(name, color, x, z, yawDeg)
	local m = Instance.new("Model"); m.Name = name
	local root = mpart(m, "Root", 1, 1, 1, 0, 0, 0, color, { Transparency = 1, CanCollide = false })
	m.PrimaryPart = root
	local tube = mpart(m, "Tube", 24, 3.3, 3.3, 0, 2.6, 0, COL.cream, { CanCollide = false })
	tube.Shape = Enum.PartType.Cylinder
	tube.CFrame = CFrame.new(0, 2.6 * M, 0) * CFrame.Angles(0, math.rad(90), 0)
	mpart(m, "Belly", 3.1, 1.4, 23, 0, 0.9, 0, COL.cream, { Transparency = 1 })
	local nose = mpart(m, "Nose", 3.3, 3.3, 3.3, 0, 2.6, -12.2, COL.cream, { CanCollide = false }); nose.Shape = Enum.PartType.Ball
	mpart(m, "CWin", 1.9, 0.45, 0.5, 0, 3.4, -13.0, Color3.fromRGB(16, 21, 28), { CanCollide = false })
	mpart(m, "Tailc", 1.2, 1.9, 7, 0, 3.1, 14.5, COL.cream, { CanCollide = false })
	for _, sx in ipairs({ -1, 1 }) do
		mpart(m, "Win", 0.06, 0.3, 21, sx * 1.63, 3.1, 0, Color3.fromRGB(42, 54, 68), { CanCollide = false })
		mpart(m, "Belt", 0.05, 0.4, 24, sx * 1.66, 2.2, 0, color, { CanCollide = false })
		local wing = mpart(m, "Wing", 15, 0.32, 4.4, 0, 0, 0, COL.cream, { CanCollide = false })
		wing.CFrame = CFrame.new(sx * 1.4 * M, 1.9 * M, 0.6 * M)
			* CFrame.Angles(0, sx > 0 and -0.45 or (math.pi + 0.45), sx * 0.06)
			* CFrame.new(7.5 * M, 0, 1.1 * M)
		mpart(m, "Winglet", 0.15, 1.6, 1.2, sx * 14.4, 3.0, 6.8, color, { CanCollide = false })
		local eng = mpart(m, "Eng", 2.8, 1.9, 1.9, sx * 4.6, 1.35, 2.2, Color3.fromRGB(170, 176, 184))
		eng.Shape = Enum.PartType.Cylinder
		eng.CFrame = CFrame.new(sx * 4.6 * M, 1.35 * M, 2.2 * M) * CFrame.Angles(0, math.rad(90), 0)
		local sp = mpart(m, "Spin", 0.45, 0.45, 0.45, sx * 4.6, 1.35, 0.85, Color3.fromRGB(226, 226, 226), { CanCollide = false })
		sp.Shape = Enum.PartType.Ball
		local hs = mpart(m, "HStab", 6, 0.25, 2.6, 0, 0, 0, COL.cream, { CanCollide = false })
		hs.CFrame = CFrame.new(sx * 0.3 * M, 3.3 * M, 14.6 * M)
			* CFrame.Angles(0, sx > 0 and -0.5 or (math.pi + 0.5), 0)
			* CFrame.new(3 * M, 0, 0.8 * M)
	end
	local fin = mpart(m, "Fin", 0.35, 6, 3.6, 0, 6.2, 14.6, color, { CanCollide = false })
	fin.CFrame = CFrame.new(0, 6.2 * M, 14.6 * M) * CFrame.Angles(-0.3, 0, 0)
	finLogo(m, color, 0.35, 6.8, 15.0, 1.7)
	airlineTitle(m, 1.69, 3.6, -7, 6, 0.85)
	for _, g in ipairs({ { 0, -9.5 }, { -1.9, 1.4 }, { 1.9, 1.4 } }) do
		mpart(m, "Whl", 0.7, 0.84, 0.84, g[1], 0.42, g[2], Color3.fromRGB(20, 22, 26))
	end
	m.Parent = airport
	m:PivotTo(CFrame.new(x * M, 0, z * M) * CFrame.Angles(0, math.rad(yawDeg or 0), 0))
	return m
end
local function makeSmallPlane(name, kind, color, x, z, yawDeg)
	-- kind = "atr" (Hochdecker-Turboprop) oder "biz" (Businessjet)
	local m = Instance.new("Model"); m.Name = name
	local root = mpart(m, "Root", 1, 1, 1, 0, 0, 0, color, { Transparency = 1, CanCollide = false })
	m.PrimaryPart = root
	local r = kind == "atr" and 1.25 or 0.85
	local len = kind == "atr" and 17 or 11
	local cy = kind == "atr" and 2.2 or 1.7
	local tube = mpart(m, "Tube", len, r * 2, r * 2, 0, cy, 0, COL.cream)
	tube.Shape = Enum.PartType.Cylinder
	tube.CFrame = CFrame.new(0, cy * M, 0) * CFrame.Angles(0, math.rad(90), 0)
	local nose = mpart(m, "Nose", r * 2, r * 2, r * 2, 0, cy, -len / 2, COL.cream, { CanCollide = false }); nose.Shape = Enum.PartType.Ball
	if kind == "atr" then
		mpart(m, "Wing", 19, 0.3, 2.6, 0, 3.5, -0.5, COL.cream)
		for _, sx in ipairs({ -1, 1 }) do
			mpart(m, "Eng", 1.1, 1.2, 3.2, sx * 3.6, 3.1, -1.2, Color3.fromRGB(170, 176, 184))
			local disc = mpart(m, "Prop", 0.15, 3.4, 3.4, sx * 3.6, 3.1, -2.9, Color3.fromRGB(48, 52, 58), { Transparency = 0.6, CanCollide = false })
			disc.Shape = Enum.PartType.Cylinder
			disc.CFrame = CFrame.new(sx * 3.6 * M, 3.1 * M, -2.9 * M) * CFrame.Angles(0, math.rad(90), 0)
		end
		local fin = mpart(m, "Fin", 0.3, 4.2, 2.6, 0, 5.2, 9.6, color, { CanCollide = false })
		fin.CFrame = CFrame.new(0, 5.2 * M, 9.6 * M) * CFrame.Angles(-0.25, 0, 0)
		mpart(m, "TTail", 7, 0.22, 2.0, 0, 7.15, 10.4, COL.cream, { CanCollide = false })
	else
		for _, sx in ipairs({ -1, 1 }) do
			local wing = mpart(m, "Wing", 7.5, 0.2, 2.2, 0, 0, 0, COL.cream, { CanCollide = false })
			wing.CFrame = CFrame.new(sx * 0.7 * M, 1.2 * M, 0.6 * M)
				* CFrame.Angles(0, sx > 0 and -0.45 or (math.pi + 0.45), sx * 0.09)
				* CFrame.new(3.75 * M, 0, 0.7 * M)
			local eng = mpart(m, "Eng", 1.9, 1.0, 1.0, sx * 1.35, 2.3, 4.9, Color3.fromRGB(154, 160, 168))
			eng.Shape = Enum.PartType.Cylinder
			eng.CFrame = CFrame.new(sx * 1.35 * M, 2.3 * M, 4.9 * M) * CFrame.Angles(0, math.rad(90), 0)
		end
		local fin = mpart(m, "Fin", 0.22, 2.8, 2.0, 0, 3.6, 5.9, color, { CanCollide = false })
		fin.CFrame = CFrame.new(0, 3.6 * M, 5.9 * M) * CFrame.Angles(-0.3, 0, 0)
		mpart(m, "TTail", 4.6, 0.16, 1.5, 0, 5.05, 6.5, COL.cream, { CanCollide = false })
	end
	for _, g in ipairs({ { 0, -len / 2 + 2 }, { -1.0, 0.8 }, { 1.0, 0.8 } }) do
		mpart(m, "Whl", 0.5, 0.7, 0.7, g[1], 0.35, g[2], Color3.fromRGB(20, 22, 26))
	end
	m.Parent = airport
	m:PivotTo(CFrame.new(x * M, 0, z * M) * CFrame.Angles(0, math.rad(yawDeg or 0), 0))
	return m
end

makeJet("JetA", COL.blue, -40, 165, 0)             -- LH 452 · A380 · BLAU (begehbar)
makeNarrowbody("JetB", COL.orange, 40, 165, 0)     -- EW 771 · A320 · ORANGE
makeJet("Jumbo747", Color3.fromRGB(42, 122, 74), 200, 168, 0) -- B747-Ersatz (A380-Bauform, gruen)
makeSmallPlane("ATR", "atr", Color3.fromRGB(176, 48, 48), -185, 172, 0)
makeSmallPlane("Bizjet", "biz", Color3.fromRGB(74, 90, 143), 268, 182, 30)
local trafficJet = makeJet("TrafficJet", Color3.fromRGB(153, 153, 153), 0, -4000, 0) -- Deko-Verkehr (Client animiert)
local marshalJet = makeNarrowbody("MarshalJet", Color3.fromRGB(138, 143, 153), 0, -4200, 0) -- Marshaller-Jet (Client animiert)

---------------------------------------------------------------- Terminal (x -70..75, z 232..302)
local T = { x1 = -70, x2 = 75, z1 = 232, z2 = 302, h = 11 }
local term = Instance.new("Model"); term.Name = "Terminal"; term.Parent = airport
-- Zwei-Ton-Kachelboden (Marble/Granite) im Schachbrett (Phase 5)
do
	local tileCols = { Color3.fromRGB(206, 208, 212), Color3.fromRGB(178, 182, 190) }
	local tileMats = { Enum.Material.Marble, Enum.Material.Granite }
	local nx, nz = 15, 7
	local tw, td = (T.x2 - T.x1) / nx, (T.z2 - T.z1) / nz
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local k = (ix + iz) % 2 + 1
			mpart(term, "Floor", tw, 0.5, td, T.x1 + tw * (ix + 0.5), 0.15, T.z1 + td * (iz + 0.5), tileCols[k], { Material = tileMats[k] })
		end
	end
end
mpart(term, "Roof", T.x2 - T.x1 + 4, 0.7, T.z2 - T.z1 + 4, (T.x1 + T.x2) / 2, T.h, (T.z1 + T.z2) / 2, Color3.fromRGB(138, 146, 158))
local function wallSeg(nm, x1, x2, z, color, transp)
	mpart(term, nm, x2 - x1, T.h, 0.6, (x1 + x2) / 2, T.h / 2, z, color,
		transp and { Transparency = 0.6, Material = Enum.Material.Glass } or { Material = Enum.Material.Concrete })
end
-- Glasfront Nord (zum Vorfeld), Tuer bei x 28..36
-- Glasfront West mit Crew-Tuer bei x -60 (StaffTuer1 oeffnet nur der ZoneService)
wallSeg("GlassW1", T.x1, -62.6, T.z1, COL.glass, true)
wallSeg("GlassW2", -57.4, 28, T.z1, COL.glass, true)
mpart(term, "StaffTuerSturz", 5.2, T.h - 3.4, 0.6, -60, 3.4 + (T.h - 3.4) / 2, T.z1, COL.glass, { Transparency = 0.6, Material = Enum.Material.Glass })
mpart(term, "StaffTuer1", 5.0, 3.3, 0.3, -60, 1.65, T.z1, Color3.fromRGB(255, 170, 60), { Transparency = 0.35, Material = Enum.Material.Glass })
do
	local s = mpart(term, "StaffTuerSchild", 5.6, 0.8, 0.14, -60, 3.85, T.z1 + 0.45, Color3.fromRGB(58, 42, 16), { CanCollide = false })
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui"); sg.Face = face; sg.CanvasSize = Vector2.new(520, 62); sg.Parent = s
		local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = Color3.fromRGB(255, 215, 94)
		tl.Text = "🪪 CREW-GANG · NUR PERSONAL · ZUTRITT MIT AUSWEIS"; tl.Parent = sg
	end
end
-- Crew-Leitlinie von der Tuer zum Gate-Walkway
mpart(airport, "CrewLinie", 0.35, 0.05, 33, -60, 0.22, 215, Color3.fromRGB(255, 170, 60), { CanCollide = false })
wallSeg("GlassE", 36, T.x2, T.z1, COL.glass, true)
-- Suedwand mit Eingang bei x -8..0
wallSeg("BackW", T.x1, -8, T.z2, COL.wall)
wallSeg("BackE", 0, T.x2, T.z2, COL.wall)
-- Seitenwaende MIT Notausgang-Oeffnungen (3.2 m breit, 3.4 m hoch — begehbar!)
local function sideWall(nm, x, exits)
	local zs = T.z1
	local segs = {}
	for _, ez in ipairs(exits) do
		table.insert(segs, { zs, ez - 1.6 })
		mpart(term, nm .. "Sturz", 0.6, T.h - 3.4, 3.2, x, 3.4 + (T.h - 3.4) / 2, ez, COL.wall, { Material = Enum.Material.Concrete })
		zs = ez + 1.6
	end
	table.insert(segs, { zs, T.z2 })
	for i, s in ipairs(segs) do
		mpart(term, nm .. i, 0.6, T.h, s[2] - s[1], x, T.h / 2, (s[1] + s[2]) / 2, COL.wall, { Material = Enum.Material.Concrete })
	end
end
sideWall("SideW", T.x1, { 246, 288 })
sideWall("SideE", T.x2, { 238, 286 })
-- Metall-Akzentleisten an den Innenwaenden (Phase 5)
mpart(term, "LeisteN", T.x2 - T.x1, 0.14, 0.08, (T.x1 + T.x2) / 2, 2.3, T.z2 - 0.42, Color3.fromRGB(196, 202, 210), { Material = Enum.Material.Metal, CanCollide = false })
mpart(term, "LeisteW", 0.08, 0.14, T.z2 - T.z1, T.x1 + 0.42, 2.3, (T.z1 + T.z2) / 2, Color3.fromRGB(196, 202, 210), { Material = Enum.Material.Metal, CanCollide = false })
mpart(term, "LeisteE", 0.08, 0.14, T.z2 - T.z1, T.x2 - 0.42, 2.3, (T.z1 + T.z2) / 2, Color3.fromRGB(196, 202, 210), { Material = Enum.Material.Metal, CanCollide = false })
for x = T.x1 + 15, T.x2 - 5, 22 do
	local c = mpart(term, "Pillar", 1, T.h, 1, x, T.h / 2, (T.z1 + T.z2) / 2, Color3.fromRGB(170, 178, 188))
	c.Shape = Enum.PartType.Cylinder
	c.CFrame = CFrame.new(x * M, T.h / 2 * M, (T.z1 + T.z2) / 2 * M) * CFrame.Angles(0, 0, math.rad(90))
	c.Size = Vector3.new(T.h * M, 1 * M, 1 * M)
end
-- Check-in-Schalter (3 Stueck)
for i = 0, 2 do
	local dx = -45 + i * 16
	mpart(term, "Desk" .. (i + 1), 6, 1.2, 2.2, dx, 0.6, 258, Color3.fromRGB(53, 80, 110))
	mpart(term, "DeskTop", 6, 0.15, 2.4, dx, 1.25, 258, Color3.fromRGB(94, 200, 255), { CanCollide = false })
	mpart(term, "DeskBack", 6, 3.2, 0.4, dx, 1.6, 262.5, Color3.fromRGB(45, 61, 82))
	mpart(term, "DeskSign", 4.4, 1, 0.15, dx, 3.4, 262.4, i == 0 and Color3.fromRGB(94, 200, 255) or Color3.fromRGB(53, 80, 110),
		{ Material = i == 0 and Enum.Material.Neon or Enum.Material.SmoothPlastic, CanCollide = false })
end
mpart(term, "Waage", 2, 0.4, 2, -39.5, 0.2, 255.5, Color3.fromRGB(119, 127, 137))
-- Lichtleisten-Raster unter der Decke (~8 m) mit PointLights (Phase 5)
for x = T.x1 + 8, T.x2 - 4, 8 do
	for _, lz in ipairs({ 250, 285 }) do
		local strip = mpart(term, "LichtLeiste", 1.2, 0.08, 6, x, T.h - 0.55, lz, Color3.fromRGB(255, 250, 236), { Material = Enum.Material.Neon, CanCollide = false })
		local lpl = Instance.new("PointLight")
		lpl.Brightness = 0.55; lpl.Range = 44; lpl.Color = Color3.fromRGB(255, 244, 219); lpl.Parent = strip
	end
end
-- Teppichzonen vor den Gates + Westhalle (Phase 5)
mpart(term, "GateTeppich", 36, 0.06, 19, 34, 0.43, 251.5, Color3.fromRGB(42, 60, 86), { Material = Enum.Material.Fabric, CanCollide = false })
mpart(term, "WestTeppich", 28, 0.06, 13, -55, 0.43, 272.5, Color3.fromRGB(42, 60, 86), { Material = Enum.Material.Fabric, CanCollide = false })
-- Gate-Sitzreihen (einheitliche Akzentfarbe, Stoff)
for r = 0, 3 do
	for c = 0, 9 do
		mpart(term, "Seat", 1.6, 0.9, 1.4, 18 + c * 3.2, 0.45, 244 + r * 4.5, Color3.fromRGB(42, 109, 181), { Material = Enum.Material.Fabric })
	end
end
mpart(term, "GateSign", 5, 1.4, 0.2, 34, 4.5, 234, Color3.fromRGB(42, 157, 92), { Material = Enum.Material.Neon, CanCollide = false })

-- Abflugtafel (SurfaceGui, Client haelt die Flugdaten identisch)
local board = mpart(term, "DepartureBoard", 16, 9, 0.4, -25, 6.2, 297.5, Color3.fromRGB(11, 18, 32))
local bsg = Instance.new("SurfaceGui")
bsg.Face = Enum.NormalId.Front -- Front zeigt nach -Z (in die Halle)
bsg.CanvasSize = Vector2.new(640, 360)
bsg.Parent = board
local function boardLine(txt, y, color, size)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -40, 0, size or 30)
	l.Position = UDim2.new(0, 24, 0, y)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Code
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextSize = size or 24
	l.TextColor3 = color
	l.Text = txt
	l.Parent = bsg
	return l
end
boardLine("ABFLÜGE · DEPARTURES", 10, Color3.fromRGB(255, 215, 94), 30)
boardLine("FLUG    ZIEL         ZEIT   GATE  STATUS", 55, Color3.fromRGB(127, 150, 173), 22)
-- Die Zeilen fuellt der FlightService (eine Wahrheit fuer alle Fluege) — hier nur benannte Labels
for i = 1, 6 do
	local row = boardLine("…", 60 + i * 38, Color3.fromRGB(232, 238, 247), 22)
	row.Name = "BRow" .. i
	local st = boardLine("…", 60 + i * 38, Color3.fromRGB(127, 150, 173), 22)
	st.Name = "BStat" .. i
	st.Position = UDim2.new(0, 470, 0, 60 + i * 38)
end

-- Security-Schranke an der Suedtuer: einziger legaler Landside->Airside-Weg zu Fuss.
-- CanCollide=true; oeffnen tut sie NUR der ZoneService (Transparency/CanCollide).
mpart(term, "SecSchrankePfostenW", 0.4, 3.4, 0.5, 27.6, 1.7, 232, Color3.fromRGB(138, 146, 158))
mpart(term, "SecSchrankePfostenE", 0.4, 3.4, 0.5, 36.4, 1.7, 232, Color3.fromRGB(138, 146, 158))
mpart(term, "SecSchranke", 8, 3.2, 0.3, 32, 1.6, 232, Color3.fromRGB(159, 212, 232), { Transparency = 0.35, Material = Enum.Material.Glass })
do
	local s = mpart(term, "SecSchild", 6, 0.9, 0.14, 32, 3.9, 231.6, Color3.fromRGB(21, 32, 47), { CanCollide = false })
	local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(460, 70); sg.Parent = s
	local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
	tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = Color3.fromRGB(255, 215, 94)
	tl.Text = "🛂 SECURITY — Boarding-Pass oder Ausweis bereithalten"; tl.Parent = sg
end

---------------------------------------------------------------- Gepaeckband Terminal -> Vorfeld
local belt = Instance.new("Model"); belt.Name = "Belt"; belt.Parent = airport
mpart(belt, "BeltBody", 3, 0.9, 64, -20, 0.45, 226, COL.dark)
mpart(belt, "BeltTop", 3.4, 0.2, 64.4, -20, 0.95, 226, Color3.fromRGB(28, 30, 36))
mpart(belt, "BeltEndT", 3.6, 1.6, 1.2, -20, 0.8, 257, Color3.fromRGB(96, 103, 116))
mpart(belt, "BeltEndA", 3.6, 1.6, 1.2, -20, 0.8, 195, Color3.fromRGB(96, 103, 116))

---------------------------------------------------------------- Echte Gates (Zustand kommt vom FlightService)
-- Pro Stand: Gate-Counter mit Live-Display (GDCode/GDStatus), Boarding-Schranke
-- (CanCollide — schaltet der ZoneService) und ueberdachte Gangway zur Parkposition.
local function makeGate(nr, px)
	local g = Instance.new("Model"); g.Name = "Gate" .. nr; g.Parent = airport
	-- Counter
	mpart(g, "GCounter", 3.2, 1.1, 1.1, px - 5.4, 0.55, 197.5, Color3.fromRGB(53, 80, 110))
	mpart(g, "GCounterTop", 3.3, 0.08, 1.2, px - 5.4, 1.14, 197.5, Color3.fromRGB(94, 200, 255), { CanCollide = false })
	-- Display auf Pole (zeigt zur Wartezone im Norden, Face Back = +Z)
	mpart(g, "GDPole", 0.18, 3.0, 0.18, px - 5.4, 1.5, 196.6, Color3.fromRGB(102, 110, 120))
	local disp = mpart(g, "GateDisplay" .. nr, 2.9, 1.5, 0.16, px - 5.4, 3.6, 196.6, Color3.fromRGB(11, 18, 32), { CanCollide = false })
	local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Back; sg.CanvasSize = Vector2.new(360, 190); sg.Parent = disp
	local title = Instance.new("TextLabel"); title.Size = UDim2.new(1, 0, 0, 48); title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack; title.TextSize = 34; title.TextColor3 = Color3.fromRGB(255, 215, 94)
	title.Text = "GATE " .. nr; title.Parent = sg
	local code = Instance.new("TextLabel"); code.Size = UDim2.new(1, 0, 0, 56); code.Position = UDim2.new(0, 0, 0, 52)
	code.BackgroundTransparency = 1; code.Font = Enum.Font.GothamBold; code.TextSize = 30
	code.TextColor3 = Color3.fromRGB(232, 238, 247); code.Text = "…"; code.Name = "GDCode" .. nr; code.Parent = sg
	local status = Instance.new("TextLabel"); status.Size = UDim2.new(1, 0, 0, 56); status.Position = UDim2.new(0, 0, 0, 116)
	status.BackgroundTransparency = 1; status.Font = Enum.Font.GothamBlack; status.TextSize = 38
	status.TextColor3 = Color3.fromRGB(127, 150, 173); status.Text = "…"; status.Name = "GDStatus" .. nr; status.Parent = sg
	-- Boarding-Schranke quer zum Standzugang (oeffnet NUR der ZoneService)
	mpart(g, "GSPfostenW", 0.35, 3.0, 0.4, px - 3.1, 1.5, 195, Color3.fromRGB(138, 146, 158))
	mpart(g, "GSPfostenE", 0.35, 3.0, 0.4, px + 3.1, 1.5, 195, Color3.fromRGB(138, 146, 158))
	local schranke = mpart(g, "GateSchranke" .. nr, 5.9, 2.8, 0.25, px, 1.4, 195, Color3.fromRGB(159, 212, 232), { Transparency = 0.35, Material = Enum.Material.Glass })
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local ssg = Instance.new("SurfaceGui"); ssg.Face = face; ssg.CanvasSize = Vector2.new(400, 180); ssg.Parent = schranke
		local stl = Instance.new("TextLabel"); stl.Size = UDim2.fromScale(1, 1); stl.BackgroundTransparency = 1
		stl.Font = Enum.Font.GothamBlack; stl.TextScaled = true; stl.TextColor3 = Color3.fromRGB(21, 32, 47)
		stl.Text = "✋ GATE " .. nr; stl.Parent = ssg
	end
	-- Zaunstuecke links/rechts, damit man nicht um die Schranke herumlaeuft
	mpart(g, "GFenceW", 10.4, 1.4, 0.2, px - 8.5, 0.7, 195, Color3.fromRGB(154, 163, 173))
	mpart(g, "GFenceE", 10.4, 1.4, 0.2, px + 8.5, 0.7, 195, Color3.fromRGB(154, 163, 173))
	-- Gangway: kurzer ueberdachter Korridor von der Schranke Richtung Flugzeug
	-- (endet bei z 189 — die Jet-Hecks reichen bis ~186, nichts clippt)
	for _, sx in ipairs({ -2.4, 2.4 }) do
		mpart(g, "GRail", 0.14, 1.05, 5.6, px + sx, 0.55, 192, Color3.fromRGB(170, 178, 188))
	end
	mpart(g, "GDach", 5.6, 0.16, 5.8, px, 3.3, 192, Color3.fromRGB(190, 199, 209), { CanCollide = false })
	for _, dz in ipairs({ 190, 194 }) do
		mpart(g, "GDachPfosten", 0.14, 3.2, 0.14, px - 2.4, 1.65, dz, Color3.fromRGB(170, 178, 188))
		mpart(g, "GDachPfosten", 0.14, 3.2, 0.14, px + 2.4, 1.65, dz, Color3.fromRGB(170, 178, 188))
	end
	mpart(g, "GPfad", 4.6, 0.05, 28, px, 0.2, 181, Color3.fromRGB(216, 182, 42), { CanCollide = false })
end
for nr, px in ipairs({ -130, -40, 40, 130, 200 }) do
	makeGate(nr, px)
end
-- Captain-Stand: eigene Parkmarkierung abseits der Gates (Flugzeug parkt bei 255/180)
mpart(airport, "CaptainStand", 0.6, 0.1, 20, 255, 0.24, 172, COL.yellow, { CanCollide = false })
mpart(airport, "CaptainStandQ", 13, 0.1, 0.6, 255, 0.24, 182, COL.yellow, { CanCollide = false })

-- Leitlinie auf dem Gate-Walkway: von der Suedtuer zu den Gates
mpart(airport, "WalkwayLinie", 340, 0.05, 0.35, 35, 0.22, 198.5, COL.yellow, { CanCollide = false })
mpart(airport, "WalkwayLinie2", 0.35, 0.05, 33, 32, 0.22, 215, COL.yellow, { CanCollide = false })

-- Gepaecktunnel-Ausstieg (Rollfeld, neben dem Bandende) + Technikgang-Luke (Fuel Depot)
for _, ox in ipairs({ -1.6, 1.6 }) do
	mpart(airport, "GTunnelRail", 0.14, 1.0, 3.6, -14 + ox, 0.5, 197.5, Color3.fromRGB(170, 178, 188))
	mpart(airport, "TechRail", 0.14, 1.0, 3.4, -146 + ox, 0.5, 214, Color3.fromRGB(170, 178, 188))
end
do
	local function pSchild(nm, x, z, txt)
		local s = mpart(airport, nm, 4.6, 0.7, 0.14, x, 2.5, z, Color3.fromRGB(58, 42, 16), { CanCollide = false })
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			local sg = Instance.new("SurfaceGui"); sg.Face = face; sg.CanvasSize = Vector2.new(420, 56); sg.Parent = s
			local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
			tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = Color3.fromRGB(255, 215, 94)
			tl.Text = txt; tl.Parent = sg
		end
	end
	pSchild("GTunnelSchild", -14, 195.4, "🧳 GEPÄCKTUNNEL · NUR PERSONAL")
	pSchild("TechSchild", -146, 212, "🛠 TECHNIKGANG · NUR PERSONAL")
end

---------------------------------------------------------------- Gepaeckwagen
local cart = Instance.new("Model"); cart.Name = "Cart"; cart.Parent = airport
local croot = mpart(cart, "Root", 1, 1, 1, 0, 0, 0, COL.dark, { Transparency = 1, CanCollide = false })
cart.PrimaryPart = croot
mpart(cart, "Chassis", 2.4, 0.5, 5.2, 0, 0.65, 0, Color3.fromRGB(42, 109, 181))
mpart(cart, "Cab", 2.2, 1.5, 1.6, 0, 1.6, 1.6, Color3.fromRGB(42, 109, 181))
mpart(cart, "Windshield", 2, 0.7, 0.15, 0, 2.0, 0.85, COL.glass, { Transparency = 0.5, Material = Enum.Material.Glass, CanCollide = false })
mpart(cart, "Bed", 2.3, 0.15, 3.2, 0, 0.95, -1.4, Color3.fromRGB(139, 149, 161))
for _, w in ipairs({ { -1.1, -1.8 }, { 1.1, -1.8 }, { -1.1, 1.8 }, { 1.1, 1.8 } }) do
	-- Zylinderachse = X = Radachse (links/rechts): keine Zusatzrotation noetig
	local wh = mpart(cart, "Wheel", 0.8, 0.35, 0.8, w[1], 0.4, w[2], Color3.fromRGB(22, 24, 28))
	wh.Shape = Enum.PartType.Cylinder
	wh.Size = Vector3.new(0.35 * M, 0.8 * M, 0.8 * M)
end
cart:PivotTo(CFrame.new(-2 * M, 0, 186 * M) * CFrame.Angles(0, 0.4, 0))

---------------------------------------------------------------- Spieler-Propellerflugzeug (Hochdecker, Cessna-artig)
local plane = Instance.new("Model"); plane.Name = "PlayerPlane"; plane.Parent = airport
local proot = mpart(plane, "Root", 1, 1, 1, 0, 0, 0, COL.cream, { Transparency = 1, CanCollide = false })
plane.PrimaryPart = proot
local function pp(name, sx, sy, sz, x, y, z, color, props)
	return mpart(plane, name, sx, sy, sz, x, y, z, color, props)
end
-- Rumpf: Cowling -> Kabine -> Heckkonus
pp("Cowl", 1.1, 1.1, 1.2, 0, 1.32, -2.35, COL.cream)
pp("CowlInlet", 1.04, 0.34, 1.2, 0, 0.86, -2.3, COL.dark, { CanCollide = false })
pp("Nose", 1.25, 1.25, 0.9, 0, 1.35, -1.3, COL.red)
pp("Fus", 1.15, 1.25, 2.5, 0, 1.55, 0.1, COL.cream)
pp("GlassBand", 1.17, 0.5, 1.7, 0, 1.95, -0.15, COL.glass, { Transparency = 0.45, Material = Enum.Material.Glass, CanCollide = false })
pp("Windshield", 1.1, 0.62, 0.12, 0, 1.95, -1.15, COL.glass, { Transparency = 0.45, Material = Enum.Material.Glass, CanCollide = false })
pp("Dash", 1.0, 0.3, 0.35, 0, 1.68, -1.0, COL.dark, { CanCollide = false })
pp("Tailcone", 0.55, 0.7, 3.4, 0, 1.55, 3.0, COL.cream, { CanCollide = false })
-- Propeller + Spinner + Blur-Scheibe
pp("Prop1", 0.14, 2.15, 0.08, 0, 1.32, -3.02, COL.dark, { CanCollide = false })
pp("Prop2", 2.15, 0.14, 0.08, 0, 1.32, -3.02, COL.dark, { CanCollide = false })
local spin = pp("Spinner", 0.45, 0.45, 0.5, 0, 1.32, -3.25, COL.red, { CanCollide = false })
spin.Shape = Enum.PartType.Ball
local disc = pp("PropDisc", 2.2, 2.2, 0.05, 0, 1.32, -3.02, Color3.fromRGB(48, 52, 58), { Transparency = 1, CanCollide = false })
disc.Shape = Enum.PartType.Cylinder
disc.Size = Vector3.new(0.05 * M, 2.2 * M, 2.2 * M)
disc.CFrame = CFrame.new(0, 1.32 * M, -3.02 * M) * CFrame.Angles(0, math.rad(90), 0)
-- Hochdecker-Fluegel mit Streben, Querrudern, Klappen
pp("Wing", 11.0, 0.15, 1.55, 0, 2.32, -0.3, COL.cream)
pp("WingStripe", 11.0, 0.06, 0.28, 0, 2.41, -0.95, COL.red, { CanCollide = false })
pp("TipL", 0.55, 0.13, 1.35, -5.5, 2.32, -0.3, COL.red, { CanCollide = false })
pp("TipR", 0.55, 0.13, 1.35, 5.5, 2.32, -0.3, COL.red, { CanCollide = false })
for _, sx in ipairs({ -1, 1 }) do
	local strut = pp("Strut", 0.1, 2.05, 0.1, sx * 1.5, 1.6, 0.05, COL.cream, { CanCollide = false })
	strut.CFrame = CFrame.new(sx * 1.5 * M, 1.6 * M, 0.05 * M) * CFrame.Angles(0, 0, sx * 0.9)
end
pp("AilL", 1.9, 0.09, 0.48, -4.2, 2.32, 0.62, COL.red, { CanCollide = false })
pp("AilR", 1.9, 0.09, 0.48, 4.2, 2.32, 0.62, COL.red, { CanCollide = false })
pp("FlapL", 2.2, 0.09, 0.5, -1.6, 2.30, 0.63, COL.cream, { CanCollide = false })
pp("FlapR", 2.2, 0.09, 0.5, 1.6, 2.30, 0.63, COL.cream, { CanCollide = false })
pp("NavL", 0.16, 0.16, 0.16, -5.72, 2.32, -0.3, Color3.fromRGB(255, 40, 40), { Material = Enum.Material.Neon, CanCollide = false })
pp("NavR", 0.16, 0.16, 0.16, 5.72, 2.32, -0.3, Color3.fromRGB(40, 255, 70), { Material = Enum.Material.Neon, CanCollide = false })
-- Leitwerk
pp("HStab", 3.7, 0.11, 1.05, 0, 1.62, 4.75, COL.cream, { CanCollide = false })
pp("Elev", 3.7, 0.08, 0.5, 0, 1.62, 5.5, COL.red, { CanCollide = false })
local fin = pp("VStab", 0.11, 1.9, 1.15, 0, 2.55, 4.7, COL.cream, { CanCollide = false })
fin.CFrame = CFrame.new(0, 2.55 * M, 4.7 * M) * CFrame.Angles(-0.22, 0, 0)
pp("FinTip", 0.13, 0.55, 1.1, 0, 3.35, 4.95, COL.red, { CanCollide = false })
pp("Rud", 0.09, 1.7, 0.6, 0, 2.6, 5.65, COL.red, { CanCollide = false })
pp("Beacon", 0.18, 0.18, 0.18, 0, 3.68, 4.95, Color3.fromRGB(255, 60, 0), { Material = Enum.Material.Neon, CanCollide = false })
-- Fahrwerk mit Radverkleidungen (einziehbar)
for _, g in ipairs({ { "GearN", 0, -2.15 }, { "GearL", -1.15, 0.45 }, { "GearR", 1.15, 0.45 } }) do
	pp(g[1], 0.12, 0.85, 0.12, g[2], 0.74, g[3], COL.dark, { CanCollide = false })
	pp(g[1] .. "W", 0.6, 0.28, 0.6, g[2], 0.3, g[3], Color3.fromRGB(20, 22, 25), { CanCollide = false })
	pp(g[1] .. "P", 0.26, 0.42, 0.85, g[2], 0.36, g[3], COL.red, { CanCollide = false })
end
plane:PivotTo(CFrame.new(130 * M, 0, 165 * M) * CFrame.Angles(0, math.rad(180), 0))

---------------------------------------------------------------- Tower, Hangar, Windsack
local tower = Instance.new("Model"); tower.Name = "Tower"; tower.Parent = airport
local shaft = mpart(tower, "Shaft", 6, 26, 6, -130, 13, 250, Color3.fromRGB(201, 207, 216))
shaft.Shape = Enum.PartType.Cylinder
shaft.CFrame = CFrame.new(-130 * M, 13 * M, 250 * M) * CFrame.Angles(0, 0, math.rad(90))
shaft.Size = Vector3.new(26 * M, 6 * M, 6 * M)
mpart(tower, "Cab", 10, 4.5, 10, -130, 28, 250, Color3.fromRGB(36, 55, 74))
mpart(tower, "CabGlass", 9.4, 2.4, 9.4, -130, 28.4, 250, COL.glass, { Transparency = 0.5, Material = Enum.Material.Glass, CanCollide = false })
mpart(tower, "Beacon", 0.8, 0.8, 0.8, -130, 32.5, 250, Color3.fromRGB(255, 136, 0), { Material = Enum.Material.Neon, CanCollide = false })

local hangar = Instance.new("Model"); hangar.Name = "Hangar"; hangar.Parent = airport
mpart(hangar, "Back", 36, 12, 0.8, 230, 6, 214, Color3.fromRGB(143, 154, 166))
mpart(hangar, "SideL", 0.8, 12, 28, 212, 6, 200, Color3.fromRGB(143, 154, 166))
mpart(hangar, "SideR", 0.8, 12, 28, 248, 6, 200, Color3.fromRGB(143, 154, 166))
mpart(hangar, "HRoof", 38, 0.8, 30, 230, 12.2, 200, Color3.fromRGB(110, 122, 135))

local ws = Instance.new("Model"); ws.Name = "Windsock"; ws.Parent = airport
mpart(ws, "Pole", 0.3, 8, 0.3, -200, 4, 55, Color3.fromRGB(221, 221, 221))
local sock = mpart(ws, "Sock", 1.0, 1.0, 3.5, -200, 7.8, 53, Color3.fromRGB(255, 90, 31), { CanCollide = false })

---------------------------------------------------------------- Leuchtende Job-Marker
local function marker(name, x, z, color)
	local mk = mpart(airport, name, 2.2, 5, 2.2, x, 2.5, z, color,
		{ Transparency = 0.72, Material = Enum.Material.Neon, CanCollide = false })
	mk.Shape = Enum.PartType.Cylinder
	mk.CFrame = CFrame.new(x * M, 2.5 * M, z * M) * CFrame.Angles(0, 0, math.rad(90))
	mk.Size = Vector3.new(5 * M, 2.2 * M, 2.2 * M)
	return mk
end
marker("MarkerCheckin", -45, 260.7, Color3.fromRGB(94, 200, 255))
marker("MarkerRamp", -14, 192, Color3.fromRGB(224, 160, 32))
marker("MarkerPlane", 250, 185, Color3.fromRGB(143, 232, 159)) -- eigener Captain-Stand, frei von Gate 4
marker("MarkerFuel", -152, 215, Color3.fromRGB(217, 165, 32))
marker("MarkerMarshal", -130, 148, Color3.fromRGB(255, 136, 68))

-- Parkhaus-Deko: Buchtenlinien, Ebenen-Farben P1-P3, Licht, Schranke, P-Totem
sysInit("Parkhaus-Deko", function()
	local X1, X2, Z1, Z2 = -166, -84, 308, 352
	local weiss = Color3.fromRGB(235, 238, 242)
	local LEVELS = {
		{ 0, "P1", Color3.fromRGB(58, 111, 232) },
		{ 3.45, "P2", Color3.fromRGB(42, 157, 92) },
		{ 6.85, "P3", Color3.fromRGB(224, 120, 32) },
	}
	for _, lv in ipairs(LEVELS) do
		local y, nm, col = lv[1], lv[2], lv[3]
		-- Parkbuchten-Linien beidseitig + gelbe Mittellinie
		for x = X1 + 8, X2 - 10, 4.2 do
			mpart(pd, "PBucht", 0.14, 0.05, 5.4, x, y + 0.18, Z1 + 5.6, weiss, { CanCollide = false })
			mpart(pd, "PBucht", 0.14, 0.05, 5.4, x, y + 0.18, Z2 - 5.6, weiss, { CanCollide = false })
		end
		mpart(pd, "PMittel", X2 - X1 - 18, 0.05, 0.3, (X1 + X2) / 2, y + 0.18, (Z1 + Z2) / 2, COL.yellow, { CanCollide = false })
		-- Fahrtrichtungs-Pfeile
		for x = X1 + 18, X2 - 16, 18 do
			mpart(pd, "PPfeil", 2.4, 0.05, 0.4, x, y + 0.19, (Z1 + Z2) / 2, weiss, { CanCollide = false })
			local sp = mpart(pd, "PPfeilKopf", 0.9, 0.05, 0.9, x + 1.4, y + 0.19, (Z1 + Z2) / 2, weiss, { CanCollide = false })
			sp.CFrame = sp.CFrame * CFrame.Angles(0, math.rad(45), 0)
		end
		-- Ebenen-Farbbaender an den Pfeilern + grosses Ebenen-Schild
		for x = X1 + 6, X2 - 4, 16 do
			for _, z in ipairs({ Z1 + 8, Z2 - 8 }) do
				mpart(pd, "PBand", 0.85, 0.55, 0.85, x, y + 2.2, z, col, { CanCollide = false })
			end
		end
		local s = mpart(pd, "PEbene", 0.16, 1.6, 3.6, X1 + 1.2, y + 2.2, (Z1 + Z2) / 2, Color3.fromRGB(21, 32, 47), { CanCollide = false })
		local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Right; sg.CanvasSize = Vector2.new(320, 140); sg.Parent = s
		local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBlack; tl.TextScaled = true; tl.TextColor3 = col; tl.Text = "🅿 " .. nm; tl.Parent = sg
		-- Lichtbaender unter der Decke (P3 ist offen)
		if y < 6 then
			for x = X1 + 14, X2 - 10, 16 do
				local strip = mpart(pd, "PLicht", 4.5, 0.07, 0.55, x, y + 3.12, (Z1 + Z2) / 2, Color3.fromRGB(255, 250, 236), { Material = Enum.Material.Neon, CanCollide = false })
				local pl = Instance.new("PointLight"); pl.Brightness = 0.6; pl.Range = 30; pl.Color = Color3.fromRGB(255, 244, 219); pl.Parent = strip
			end
		end
	end
	-- Absturz-Gelaender auf P2 + P3 (Luecke an den Rampen im Osten)
	for _, gy in ipairs({ 3.45, 6.85 }) do
		local rc = Color3.fromRGB(170, 178, 186)
		mpart(pd, "PRailN", X2 - X1, 1.0, 0.18, (X1 + X2) / 2, gy + 0.6, Z1 + 0.2, rc)
		mpart(pd, "PRailS", X2 - X1, 1.0, 0.18, (X1 + X2) / 2, gy + 0.6, Z2 - 0.2, rc)
		mpart(pd, "PRailW", 0.18, 1.0, Z2 - Z1, X1 + 0.2, gy + 0.6, (Z1 + Z2) / 2, rc)
		-- Ostkante: Gelaender nur ausserhalb der Rampengasse (x X2-9 .. X2-1)
		mpart(pd, "PRailE1", 0.18, 1.0, 14, X2 - 0.4, gy + 0.6, Z1 + 7, rc)
		mpart(pd, "PRailE2", 0.18, 1.0, 14, X2 - 0.4, gy + 0.6, Z2 - 7, rc)
	end

	-- Einfahrt Sued-Ost: Schranke (rot/weiss) + Ticketautomat
	mpart(pd, "SchrankenSockel", 0.55, 1.15, 0.55, -92.5, 0.58, 305.5, Color3.fromRGB(138, 146, 158))
	for i = 0, 3 do
		mpart(pd, "SchrankenArm", 1.05, 0.14, 0.26, -91.4 + i * 1.05, 1.1, 305.5,
			i % 2 == 0 and Color3.fromRGB(194, 59, 46) or weiss, { CanCollide = false })
	end
	mpart(pd, "Ticket", 0.75, 1.45, 0.75, -95.5, 0.72, 305.5, Color3.fromRGB(53, 80, 110))
	mpart(pd, "TicketScreen", 0.5, 0.36, 0.06, -95.5, 1.15, 305.1, Color3.fromRGB(84, 208, 106), { Material = Enum.Material.Neon, CanCollide = false })
	-- P-Totem an der Zufahrt
	mpart(pd, "PTotemFuss", 1.3, 7, 1.3, -170, 3.5, 330, Color3.fromRGB(26, 58, 122))
	mpart(pd, "PTotemBand", 1.4, 0.5, 1.4, -170, 5.6, 330, Color3.fromRGB(255, 215, 94), { Material = Enum.Material.Neon, CanCollide = false })
	local pt = mpart(pd, "PTotemSchild", 2.6, 2.6, 0.3, -170, 8.3, 330, Color3.fromRGB(26, 58, 122))
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui"); sg.Face = face; sg.CanvasSize = Vector2.new(120, 120); sg.Parent = pt
		local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBlack; tl.TextScaled = true; tl.TextColor3 = Color3.new(1, 1, 1); tl.Text = "P"; tl.Parent = sg
	end
end)

---------------------------------------------------------------- Landschaft (Fluss, See, Stadt, Berge, Autobahn, Windraeder)
local land = Instance.new("Folder"); land.Name = "Landscape"; land.Parent = airport
math.randomseed(31)
-- Maeandernder Fluss noerdlich der Bahn
for x = -3400, 3200, 250 do
	local z1 = -1250 + math.sin(x * 0.0012) * 320
	local z2 = -1250 + math.sin((x + 250) * 0.0012) * 320
	local seg = mpart(land, "River", 280, 0.3, 130, x + 125, -0.2, (z1 + z2) / 2, Color3.fromRGB(58, 122, 191), { CanCollide = false })
	seg.CFrame = seg.CFrame * CFrame.Angles(0, -math.atan2(z2 - z1, 250), 0)
end
-- See
-- 580 m Durchmesser: 580 * M=3.4 = 1972 Studs, bleibt unter dem 2048er-Part-Limit
local lake = mpart(land, "Lake", 580, 0.3, 580, -1700, -0.2, -900, Color3.fromRGB(58, 122, 191), { CanCollide = false })
lake.Shape = Enum.PartType.Cylinder
lake.CFrame = CFrame.new(-1700 * M, -0.2 * M, -900 * M) * CFrame.Angles(0, 0, math.rad(90))
lake.Size = Vector3.new(0.3 * M, 580 * M, 580 * M)
-- Stadt-Skyline + Fernsehturm
for i = 1, 55 do
	local a, rr = math.random() * 6.28, math.sqrt(math.random()) * 440
	local bx, bz = 1800 + math.cos(a) * rr, 1500 + math.sin(a) * rr
	local h = rr < 200 and (35 + math.random(60)) or (12 + math.random(28))
	local cols = { Color3.fromRGB(154, 164, 176), Color3.fromRGB(127, 140, 154), Color3.fromRGB(184, 194, 204), Color3.fromRGB(111, 143, 168) }
	mpart(land, "Tower", 14 + math.random(16), h, 14 + math.random(16), bx, h / 2, bz, cols[math.random(#cols)])
end
mpart(land, "TVTurm", 6, 130, 6, 1800, 65, 1500, Color3.fromRGB(197, 204, 212))
local kugel = mpart(land, "TVKugel", 18, 18, 18, 1800, 105, 1500, Color3.fromRGB(143, 168, 191)); kugel.Shape = Enum.PartType.Ball
-- Berge mit Schneekappen am Horizont
for i = 1, 14 do
	local a = math.random() * 6.28
	local rr = 3000 + math.random(800)
	local mx, mz = math.cos(a) * rr, math.sin(a) * rr
	local h = 260 + math.random(280)
	local berg = mpart(land, "Berg", h * 3, h, h * 3, mx, h / 2 - 40, mz, Color3.fromRGB(93, 114, 99))
	berg.Shape = Enum.PartType.Ball
	local schnee = mpart(land, "Schnee", h * 0.9, h * 0.5, h * 0.9, mx, h - 40, mz, Color3.fromRGB(238, 242, 245), { CanCollide = false })
	schnee.Shape = Enum.PartType.Ball
end
-- Autobahn Terminal -> Stadt (2 Segmente, gekachelt)
local roadPts = { { 0, 352 }, { 0, 1000 }, { 1640, 1380 } }
for i = 1, #roadPts - 1 do
	local a, b = roadPts[i], roadPts[i + 1]
	local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
	local seg = mpart(land, "Road", 14, 0.4, len + 8, (a[1] + b[1]) / 2, 0.05, (a[2] + b[2]) / 2, Color3.fromRGB(68, 71, 78))
	seg.CFrame = seg.CFrame * CFrame.Angles(0, -math.atan2(b[1] - a[1], b[2] - a[2]), 0)
	-- statische Autos auf der Strecke
	for k = 1, math.floor(len / 160) do
		local t = k / math.floor(len / 160 + 1)
		local cx2, cz2 = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
		mpart(land, "RoadCar", 2, 1.2, 4.2, cx2 + (k % 2 == 0 and 3 or -3), 0.85, cz2,
			({ Color3.fromRGB(184, 184, 184), Color3.fromRGB(143, 47, 36), Color3.fromRGB(58, 111, 176) })[1 + k % 3], { CanCollide = false })
	end
end
-- Windraeder (Client dreht die Rotoren)
for i, p in ipairs({ { -1750, 350 }, { -1950, 620 }, { -2150, 200 }, { -1600, 800 } }) do
	local wt = Instance.new("Model"); wt.Name = "WindTurbine" .. i; wt.Parent = land
	mpart(wt, "Mast", 1.8, 46, 1.8, p[1], 23, p[2], Color3.fromRGB(232, 236, 239))
	mpart(wt, "Gondel", 3.2, 2.2, 2.2, p[1], 46.5, p[2], Color3.fromRGB(221, 226, 230))
	local hub = mpart(wt, "Hub", 1, 1, 1, p[1], 46.5, p[2] - 1.6, Color3.fromRGB(221, 226, 230), { CanCollide = false })
	wt.PrimaryPart = hub
	for b = 0, 2 do
		local blade = mpart(wt, "Blade" .. b, 1.4, 19, 0.35, p[1], 46.5 + 9.5, p[2] - 1.6, Color3.fromRGB(242, 245, 247), { CanCollide = false })
		blade.CFrame = CFrame.new(p[1] * M, 46.5 * M, (p[2] - 1.6) * M) * CFrame.Angles(0, 0, b * math.pi * 2 / 3) * CFrame.new(0, 9.5 * M, 0)
	end
end

---------------------------------------------------------------- Parkdeck (3 Ebenen, echt begehbar ueber Rampen)
-- Huebscher Auto-Bauer: Karosserie, Kabine mit Glas, Haube, Stossstangen,
-- Grill, Neon-Scheinwerfer/Ruecklichter, Zylinder-Raeder. Root = exakter Pivot.
local CAR_COLS = {
	Color3.fromRGB(196, 198, 204), Color3.fromRGB(47, 58, 74), Color3.fromRGB(155, 43, 34),
	Color3.fromRGB(58, 111, 176), Color3.fromRGB(230, 168, 44), Color3.fromRGB(52, 120, 82),
	Color3.fromRGB(240, 240, 244), Color3.fromRGB(40, 40, 44),
}
local function makeCar(parent, name, x, z, yawDeg, color, yBase)
	color = color or CAR_COLS[math.random(#CAR_COLS)]
	local m = Instance.new("Model"); m.Name = name; m.Parent = parent
	local root = mpart(m, "Root", 0.4, 0.4, 0.4, 0, 0, 0, color, { Transparency = 1, CanCollide = false })
	m.PrimaryPart = root
	local dunkel = Color3.fromRGB(30, 33, 38)
	mpart(m, "Wanne", 2.0, 0.55, 4.5, 0, 0.78, 0, color)
	mpart(m, "Haube", 1.9, 0.2, 1.15, 0, 1.1, -1.62, color, { CanCollide = false })
	mpart(m, "Heck", 1.9, 0.2, 0.85, 0, 1.1, 1.78, color, { CanCollide = false })
	mpart(m, "Kabine", 1.8, 0.6, 2.3, 0, 1.42, 0.15, color)
	local fs = mpart(m, "Frontscheibe", 1.68, 0.62, 0.1, 0, 1.42, -1.0, COL.glass, { Transparency = 0.4, Material = Enum.Material.Glass, CanCollide = false })
	fs.CFrame = fs.CFrame * CFrame.Angles(-0.3, 0, 0)
	local hs = mpart(m, "Heckscheibe", 1.68, 0.55, 0.1, 0, 1.42, 1.32, COL.glass, { Transparency = 0.4, Material = Enum.Material.Glass, CanCollide = false })
	hs.CFrame = hs.CFrame * CFrame.Angles(0.35, 0, 0)
	for _, sx in ipairs({ -1, 1 }) do
		mpart(m, "Seitenglas", 0.06, 0.42, 2.0, sx * 0.92, 1.46, 0.15, dunkel, { CanCollide = false })
		mpart(m, "Spiegel", 0.28, 0.16, 0.1, sx * 1.1, 1.25, -0.85, color, { CanCollide = false })
		mpart(m, "LichtF", 0.4, 0.16, 0.07, sx * 0.68, 0.95, -2.28, Color3.fromRGB(255, 244, 214), { Material = Enum.Material.Neon, CanCollide = false })
		mpart(m, "LichtB", 0.4, 0.14, 0.07, sx * 0.68, 0.95, 2.28, Color3.fromRGB(194, 40, 40), { Material = Enum.Material.Neon, CanCollide = false })
		for _, wz in ipairs({ -1.45, 1.45 }) do
			local rad = mpart(m, "Rad", 0.34, 0.68, 0.68, sx * 0.98, 0.34, wz, Color3.fromRGB(20, 22, 26))
			rad.Shape = Enum.PartType.Cylinder
		end
	end
	mpart(m, "Grill", 1.25, 0.22, 0.07, 0, 0.68, -2.28, dunkel, { CanCollide = false })
	mpart(m, "StossF", 2.06, 0.24, 0.2, 0, 0.45, -2.32, Color3.fromRGB(60, 64, 70))
	mpart(m, "StossB", 2.06, 0.24, 0.2, 0, 0.45, 2.32, Color3.fromRGB(60, 64, 70))
	m:PivotTo(CFrame.new(x * M, (yBase or 0) * M, z * M) * CFrame.Angles(0, math.rad(yawDeg or 0), 0))
	return m
end

local pd = Instance.new("Model"); pd.Name = "Parkdeck"; pd.Parent = airport
sysInit("Parkdeck", function()
	local X1, X2, Z1, Z2 = -166, -84, 308, 352
	local cx, cz, w, d = (X1 + X2) / 2, (Z1 + Z2) / 2, X2 - X1, Z2 - Z1
	mpart(pd, "PD0", w, 0.3, d, cx, 0.05, cz, Color3.fromRGB(88, 91, 98), { Material = Enum.Material.Concrete })
	for _, y in ipairs({ 3.3, 6.7 }) do
		mpart(pd, "PDSlab", w, 0.3, d, cx, y, cz, Color3.fromRGB(96, 100, 106), { Material = Enum.Material.Concrete })
	end
	for _, y in ipairs({ 4.15, 7.55 }) do
		mpart(pd, "PDRail", w, 1.0, 0.3, cx, y, Z1, Color3.fromRGB(170, 178, 186))
		mpart(pd, "PDRail", w, 1.0, 0.3, cx, y, Z2, Color3.fromRGB(170, 178, 186))
		mpart(pd, "PDRail", 0.3, 1.0, d, X1, y, cz, Color3.fromRGB(170, 178, 186))
		mpart(pd, "PDRail", 0.3, 1.0, d, X2, y, cz, Color3.fromRGB(170, 178, 186))
	end
	for x = X1 + 6, X2 - 4, 16 do
		for _, z in ipairs({ Z1 + 8, Z2 - 8 }) do
			mpart(pd, "PDPillar", 0.7, 6.7, 0.7, x, 3.35, z, Color3.fromRGB(154, 162, 170))
		end
	end
	-- begehbare Rampen: EG -> E2 -> E3 (Wedges, Anstieg entlang +Z)
	for i, y in ipairs({ 0, 3.45 }) do
		local ramp = mpart(pd, "PDRamp" .. i, 6, 3.3, 26, X2 - 5, y + 1.65, cz, Color3.fromRGB(96, 100, 106))
		ramp.Shape = Enum.PartType.Wedge
		if i == 2 then
			ramp.CFrame = ramp.CFrame * CFrame.Angles(0, math.pi, 0) -- zweite Rampe andersherum
		end
	end
	-- Autos auf allen Ebenen: richtige Modelle, in Buchten geparkt (Nase zur Wand)
	-- eindeutige Namen -> die im Erdgeschoss sind alle fahrbar (Claims brauchen Namen)
	math.randomseed(17)
	local pdNr = 0
	for _, y in ipairs({ 0.15, 3.6, 7.0 }) do
		for x = X1 + 10, X2 - 12, 4.2 do
			if math.random() > 0.45 then
				pdNr = pdNr + 1
				local south = math.random() < 0.5
				makeCar(pd, "PDCar" .. pdNr, x, south and (Z1 + 5.8) or (Z2 - 5.8), south and 180 or 0, nil, y)
			end
		end
	end
	local ps = mpart(pd, "PSign", 3, 3, 0.3, -161, 9.5, 311, Color3.fromRGB(26, 58, 122), { CanCollide = false })
	local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(120, 120); sg.Parent = ps
	local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
	tl.Font = Enum.Font.GothamBlack; tl.TextScaled = true; tl.TextColor3 = Color3.new(1, 1, 1); tl.Text = "P"; tl.Parent = sg
end)

---------------------------------------------------------------- Realismus-Ausstattung
local deco2 = Instance.new("Folder"); deco2.Name = "Dressing"; deco2.Parent = airport
-- Runway-Seitenstreifen
mpart(deco2, "EdgeLine", RWY_L + 30, 0.1, 0.9, 0, 0.28, -RWY_W / 2 + 0.8, COL.white, { CanCollide = false })
mpart(deco2, "EdgeLine", RWY_L + 30, 0.1, 0.9, 0, 0.28, RWY_W / 2 - 0.8, COL.white, { CanCollide = false })
-- Gummiabrieb in den Aufsetzzonen
math.randomseed(7)
for _, t in ipairs({ { -750, 1 }, { 750, -1 } }) do
	for i = 1, 14 do
		mpart(deco2, "Rubber", 7 + math.random() * 10, 0.08, 0.35 + math.random() * 0.35,
			t[1] + t[2] * (80 + math.random(250)), 0.29, -7.5 + math.random() * 15,
			Color3.fromRGB(30, 32, 38), { CanCollide = false, Transparency = 0.35 })
	end
end
-- Hold-Short-Linien + Runway-Schilder an den Verbindern
for _, cx in ipairs({ -700, 0, 700 }) do
	mpart(deco2, "HoldA", 16, 0.1, 0.4, cx, 0.3, 22, COL.yellow, { CanCollide = false })
	mpart(deco2, "HoldB", 16, 0.1, 0.4, cx, 0.3, 23, COL.yellow, { CanCollide = false })
	for x = -7, 7, 2.2 do
		mpart(deco2, "HoldD", 1.1, 0.1, 0.4, cx + x, 0.3, 24.4, COL.yellow, { CanCollide = false })
		mpart(deco2, "HoldD", 1.1, 0.1, 0.4, cx + x, 0.3, 25.5, COL.yellow, { CanCollide = false })
	end
	local sign = mpart(deco2, "RwySign", 2.6, 0.9, 0.15, cx - 9.5, 1.0, 24, Color3.fromRGB(160, 32, 32), { CanCollide = false })
	local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(260, 90); sg.Parent = sign
	local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
	tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = Color3.new(1, 1, 1); tl.Text = "09-27"; tl.Parent = sg
end
-- Blaue Taxiway-Randbefeuerung
for x = -750, 750, 40 do
	for _, zz in ipairs({ 70.5, 89.5 }) do
		mpart(deco2, "TaxiLight", 0.5, 0.5, 0.5, x, 0.4, zz, Color3.fromRGB(77, 139, 255), { Material = Enum.Material.Neon, CanCollide = false })
	end
end
-- Anflugbefeuerung (ALS) vor beiden Schwellen
for _, t in ipairs({ { -750, -1 }, { 750, 1 } }) do
	for i = 1, 6 do
		local x = t[1] + t[2] * (20 + i * 28)
		for k = -2, 2 do
			mpart(deco2, "ALS", 0.5, 0.5, 0.5, x, 0.6, k * 2.4, Color3.fromRGB(255, 242, 204), { Material = Enum.Material.Neon, CanCollide = false })
		end
	end
end
-- Vorfeld: rote Sicherheitslinie, Gate-Schilder, Pylonen
mpart(deco2, "RedLine", 490, 0.1, 0.35, 45, 0.3, 141, Color3.fromRGB(176, 48, 48), { CanCollide = false })
for i, px in ipairs({ -130, -40, 40, 130, 200 }) do
	local gs = mpart(deco2, "GateSign", 4.2, 1.4, 0.15, px, 5.2, 138, Color3.fromRGB(21, 32, 47), { CanCollide = false })
	local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(420, 140); sg.Parent = gs
	local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
	tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = Color3.fromRGB(255, 215, 94); tl.Text = "GATE " .. i; tl.Parent = sg
	mpart(deco2, "GateSignPole", 0.24, 5.2, 0.24, px, 2.6, 138.2, Color3.fromRGB(102, 110, 120))
end
for _, jx in ipairs({ -40, 40 }) do
	for _, o in ipairs({ { -9, -9 }, { 9, -9 }, { -12, 4 }, { 12, 4 }, { -6, 14 }, { 6, 14 } }) do
		local cone = mpart(deco2, "Cone", 0.45, 0.55, 0.45, jx + o[1], 0.28, 165 + o[2], Color3.fromRGB(232, 106, 16), { CanCollide = false })
		cone.Shape = Enum.PartType.Wedge
	end
end
-- Bodengeraete: Tankwagen, Treppe, Pushback-Tug
local function gse(name, x, z, yaw, build)
	local m = Instance.new("Model"); m.Name = name; m.Parent = deco2
	build(m)
	m:PivotTo(CFrame.new(x * M, 0, z * M) * CFrame.Angles(0, yaw, 0))
end
-- Fahrbarer Tankwagen (parkt am Fuel Depot; Client steuert kinematisch)
local ftm = Instance.new("Model"); ftm.Name = "FuelTruck"; ftm.Parent = airport
local ftroot = mpart(ftm, "Root", 1, 1, 1, 0, 0, 0, COL.dark, { Transparency = 1, CanCollide = false })
ftm.PrimaryPart = ftroot
mpart(ftm, "Body", 2.4, 1.1, 6.4, 0, 1.0, 0, Color3.fromRGB(217, 210, 196))
local fttank = mpart(ftm, "Tank", 4.6, 2.0, 2.0, 0, 1.9, -0.6, Color3.fromRGB(202, 194, 178))
fttank.Shape = Enum.PartType.Cylinder
fttank.CFrame = CFrame.new(0, 1.9 * M, -0.6 * M) * CFrame.Angles(0, math.rad(90), 0)
mpart(ftm, "Cab", 2.2, 1.3, 1.6, 0, 1.1, 3.1, Color3.fromRGB(143, 47, 36)) -- Kabine vorn (+Z)
for _, w in ipairs({ { -1.05, 2.2 }, { 1.05, 2.2 }, { -1.05, -1.6 }, { 1.05, -1.6 }, { -1.05, -2.6 }, { 1.05, -2.6 } }) do
	mpart(ftm, "Whl", 0.4, 1.0, 1.0, w[1], 0.5, w[2], Color3.fromRGB(22, 24, 28))
end
ftm:PivotTo(CFrame.new(-146 * M, 0, 216 * M) * CFrame.Angles(0, 2.0, 0))
-- Tanklager
for _, dz in ipairs({ -4, 4 }) do
	local t = mpart(deco2, "DepotTank", 9, 4.4, 4.4, -152, 2.4, 208 + dz, Color3.fromRGB(217, 210, 196))
	t.Shape = Enum.PartType.Cylinder
end
mpart(deco2, "DepotPad", 10, 0.4, 14, -152, 0.2, 208, Color3.fromRGB(86, 90, 96))
-- Boarding-Rampe zur vorderen linken A380-Tuer (begehbar)
gse("BoardingStairs", -44.6, 157.5, 0, function(m)
	local ramp = mpart(m, "Ramp", 4.2, 1.55, 1.8, -0.9, 0.78, 0, Color3.fromRGB(183, 190, 200))
	ramp.Shape = Enum.PartType.Wedge
	ramp.CFrame = CFrame.new(-0.9 * M, 0.78 * M, 0) * CFrame.Angles(0, math.rad(-90), 0)
	ramp.Size = Vector3.new(1.8 * M, 1.55 * M, 4.2 * M) -- Wedge: steigt entlang +Z
	mpart(m, "Platform", 1.6, 0.16, 1.9, 1.9, 1.55, 0, Color3.fromRGB(154, 162, 172))
	for _, sz in ipairs({ -0.95, 0.95 }) do
		mpart(m, "Rail", 4.8, 0.08, 0.08, 0, 1.75, sz, Color3.fromRGB(216, 221, 226), { CanCollide = false })
	end
end)
gse("Tug", 78, 195, 2.2, function(m)
	mpart(m, "Body", 1.8, 0.8, 3.4, 0, 0.65, 0, Color3.fromRGB(154, 162, 58))
	mpart(m, "Cab", 1.6, 0.9, 1.2, 0, 1.4, 0.8, Color3.fromRGB(154, 162, 58))
end)
-- Terminal: Schriftzug, Vordach, Deckenlicht, Absperrbaender, Kiosk, Pflanzen
local ts = mpart(deco2, "TerminalSign", 22, 2.2, 0.2, 2, 9.3, 231.4, Color3.fromRGB(21, 32, 47), { CanCollide = false })
local tsg = Instance.new("SurfaceGui"); tsg.Face = Enum.NormalId.Front; tsg.CanvasSize = Vector2.new(1100, 110); tsg.Parent = ts
local tst = Instance.new("TextLabel"); tst.Size = UDim2.fromScale(1, 1); tst.BackgroundTransparency = 1
tst.Font = Enum.Font.GothamBold; tst.TextScaled = true; tst.TextColor3 = Color3.fromRGB(232, 238, 247); tst.Text = "✈  TERMINAL 1"; tst.Parent = tsg
mpart(deco2, "Canopy", 150, 0.4, 5, 2.5, 7.6, 229.6, Color3.fromRGB(119, 128, 140))
mpart(deco2, "Ceiling", 143, 0.2, 68, 2.5, 10.4, 267, Color3.fromRGB(216, 221, 228), { CanCollide = false })
for x = -60, 70, 16 do
	mpart(deco2, "CeilLight", 1.2, 0.15, 56, x, 10.25, 267, Color3.fromRGB(255, 255, 255), { Material = Enum.Material.Neon, CanCollide = false })
end
for _, z in ipairs({ 250, 253 }) do
	for x = -52, -24, 7 do
		mpart(deco2, "QPost", 0.18, 1.05, 0.18, x, 0.52, z, Color3.fromRGB(153, 161, 171))
	end
	mpart(deco2, "QBand", 28, 0.1, 0.08, -38, 0.95, z, Color3.fromRGB(176, 48, 48), { CanCollide = false })
end
for _, p in ipairs({ { -62, 240 }, { -62, 290 }, { 8, 238 }, { 70, 250 }, { 12, 296 }, { -36, 266 }, { 55.5, 247 }, { -10, 236 } }) do
	mpart(deco2, "Pot", 1.0, 0.8, 1.0, p[1], 0.4, p[2], Color3.fromRGB(119, 80, 60))
	local bush = mpart(deco2, "Bush", 1.5, 1.5, 1.5, p[1], 1.35, p[2], Color3.fromRGB(47, 122, 58), { CanCollide = false })
	bush.Shape = Enum.PartType.Ball
end
-- Parkplatz mit Autos hinter dem Terminal
mpart(deco2, "ParkLot", 110, 0.25, 34, -8, 0, 322, Color3.fromRGB(88, 91, 98), { Material = Enum.Material.Concrete })
for x = -58, 40, 7 do
	mpart(deco2, "ParkLine", 0.35, 0.1, 5.5, x, 0.2, 312, COL.white, { CanCollide = false })
end
math.randomseed(11)
local carNr = 0
for x = -54.5, 40, 7 do
	if math.random() > 0.35 then
		carNr = carNr + 1
		makeCar(deco2, "Car" .. carNr, x, 309.8, 180 + math.random(-6, 6))
	end
end
-- Zwei FAHRBARE Autos: eines am Parkplatz, eines im Parkhaus (E zum Einsteigen)
makeCar(airport, "CarA", -24, 318.5, 90, Color3.fromRGB(58, 111, 232))
makeCar(airport, "CarB", -100, 330, 90, Color3.fromRGB(155, 43, 34))
-- Wolken
math.randomseed(23)
for i = 1, 10 do
	local cx, cy, cz = math.random(-2400, 2400), math.random(380, 620), math.random(-2400, 2400)
	for k = 1, math.random(3, 4) do
		local s = 28 + math.random() * 26
		local c = mpart(deco2, "Cloud", s * 2, s * 0.9, s * 1.4, cx + math.random(-50, 50), cy + math.random(-8, 8), cz + math.random(-25, 25),
			Color3.fromRGB(250, 250, 252), { CanCollide = false, Transparency = 0.15 })
		c.Shape = Enum.PartType.Ball
	end
end

---------------------------------------------------------------- A380-Kabine (Jet A, begehbar; Welt-Koordinaten)
local cabin = Instance.new("Model"); cabin.Name = "A380Cabin"; cabin.Parent = airport
sysInit("A380-Kabine", function()
	local JX, JZ = -40, 165
	local wallC = Color3.fromRGB(221, 226, 232)
	local carpet = Color3.fromRGB(58, 69, 82)
	local seatC = Color3.fromRGB(46, 74, 122)
	local premC = Color3.fromRGB(201, 177, 143)
	local function cp(name, sx, sy, sz, ox, y, oz, color, props)
		return mpart(cabin, name, sx, sy, sz, JX + ox, y, JZ + oz, color, props)
	end
	-- Hauptdeck: Boden 1,62 m · Decke 3,9 m (Decke ohne Kollision wegen Charakterhoehe)
	cp("Floor", 4.75, 0.14, 29.6, 0, 1.55, 1, carpet)
	cp("Ceil", 4.75, 0.1, 29.6, 0, 3.9, 1, wallC, { CanCollide = false, Material = Enum.Material.Neon, Transparency = 0.35 })
	-- Seitenwaende mit Tuer-Oeffnung links bei z 157,5
	cp("WallR", 0.14, 2.34, 29.6, 2.36, 2.79, 1, wallC)
	cp("WallL1", 0.14, 2.34, 5.4, -2.36, 2.79, -10.1, wallC)
	cp("WallL2", 0.14, 2.34, 21.6, -2.36, 2.79, 5.0, wallC)
	cp("DoorTop", 0.14, 0.5, 2.2, -2.36, 3.6, -7.4, wallC, { CanCollide = false })
	-- Fensterreihen (leuchten)
	for _, sx in ipairs({ -1, 1 }) do
		for zz = -10, 13, 2 do
			cp("Win", 0.08, 0.55, 0.95, sx * 2.28, 2.8, zz, Color3.fromRGB(191, 217, 238), { Material = Enum.Material.Neon, CanCollide = false })
		end
	end
	-- Bulkhead mit Cockpit-Tuer + Heckwand
	cp("BulkL", 1.7, 2.34, 0.14, -1.5, 2.79, -12.6, wallC)
	cp("BulkR", 1.7, 2.34, 0.14, 1.5, 2.79, -12.6, wallC)
	cp("Aft", 4.75, 2.34, 0.14, 0, 2.79, 15.8, wallC)
	-- Galley
	cp("Galley1", 1.6, 1.15, 0.9, 1.4, 2.2, -10.5, Color3.fromRGB(174, 182, 191))
	cp("Galley2", 1.6, 1.15, 0.9, 1.4, 2.2, -8.4, Color3.fromRGB(174, 182, 191))
	-- Economy 2-3-2 (Sitze ohne Kollision, damit die Gaenge frei bleiben)
	for _, off in ipairs({ -1.85, -1.35, -0.5, 0, 0.5, 1.35, 1.85 }) do
		for zz = -6.2, 13, 0.92 do
			cp("Seat", 0.48, 0.14, 0.5, off, 2.05, zz, seatC, { CanCollide = false })
			cp("SeatB", 0.48, 0.62, 0.12, off, 2.4, zz + 0.26, seatC, { CanCollide = false })
		end
	end
	-- Interne Rampe zum Oberdeck (begehbar)
	local up = mpart(cabin, "UpRamp", 1, 1, 1, JX - 1.4, 0, JZ - 9.7, Color3.fromRGB(183, 190, 200))
	up.Shape = Enum.PartType.Wedge
	up.Size = Vector3.new(1.1 * M, 2.36 * M, 3.4 * M)
	up.CFrame = CFrame.new((JX - 1.4) * M, 2.8 * M, (JZ - 9.7) * M)
	-- Oberdeck (Boden 3,98 m)
	cp("UpFloor", 3.3, 0.12, 16.6, 0, 3.98, -1, Color3.fromRGB(74, 64, 56))
	cp("UpCeil", 3.3, 0.08, 16.6, 0, 6.35, -1, wallC, { CanCollide = false, Material = Enum.Material.Neon, Transparency = 0.35 })
	cp("UpWallL", 0.12, 2.3, 16.6, -1.68, 5.2, -1, wallC)
	cp("UpWallR", 0.12, 2.3, 16.6, 1.68, 5.2, -1, wallC)
	cp("UpFront", 3.3, 2.3, 0.12, 0, 5.2, -9.3, wallC)
	cp("UpAft", 3.3, 2.3, 0.12, 0, 5.2, 7.3, wallC)
	for _, off in ipairs({ -1.15, -0.3, 0.3, 1.15 }) do
		for zz = -6.8, 6, 1.35 do
			cp("PSeat", 0.6, 0.16, 0.62, off, 4.5, zz, premC, { CanCollide = false })
			cp("PSeatB", 0.6, 0.75, 0.14, off, 4.92, zz + 0.3, premC, { CanCollide = false })
		end
	end
	-- Cockpit (verkleidete Kanzel mit Panel, Pedestal, Sidesticks; hinter der Nasenkugel)
	cp("CFloor", 4.0, 0.14, 3.0, 0, 1.55, -13.8, carpet)
	cp("CCeil", 4.0, 0.12, 3.2, 0, 3.78, -13.9, Color3.fromRGB(185, 192, 200), { CanCollide = false })
	cp("CWallL", 0.12, 2.3, 3.2, -1.98, 2.7, -13.9, Color3.fromRGB(185, 192, 200))
	cp("CWallR", 0.12, 2.3, 3.2, 1.98, 2.7, -13.9, Color3.fromRGB(185, 192, 200))
	cp("CFront", 4.0, 1.15, 0.12, 0, 2.1, -15.3, Color3.fromRGB(185, 192, 200))
	cp("CGlass", 3.4, 0.8, 0.1, 0, 3.4, -15.25, Color3.fromRGB(168, 207, 232), { Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false })
	local panel = cp("Panel", 3.6, 1.1, 0.14, 0, 2.75, -14.8, Color3.fromRGB(26, 33, 43))
	local psg = Instance.new("SurfaceGui"); psg.Face = Enum.NormalId.Back; psg.CanvasSize = Vector2.new(720, 220); psg.Parent = panel
	for i = 0, 5 do
		local d = Instance.new("Frame")
		d.Size = UDim2.new(0, 90, 0, 88); d.Position = UDim2.new(0, 30 + i * 115, 0, 40)
		d.BackgroundColor3 = Color3.fromRGB(10, 42, 26); d.BorderColor3 = Color3.fromRGB(84, 208, 106)
		d.Parent = psg
	end
	cp("Pedestal", 0.9, 0.8, 1.4, 0, 2.0, -13.9, Color3.fromRGB(35, 40, 48))
	for _, sx in ipairs({ -1, 1 }) do
		cp("PilotSeat", 0.62, 0.16, 0.6, sx * 1.1, 2.05, -13.3, Color3.fromRGB(48, 54, 62), { CanCollide = false })
		cp("PilotSeatB", 0.62, 0.7, 0.14, sx * 1.1, 2.45, -13.0, Color3.fromRGB(48, 54, 62), { CanCollide = false })
		cp("Sidestick", 0.1, 0.35, 0.1, sx * 1.85, 2.15, -13.4, Color3.fromRGB(20, 22, 26), { CanCollide = false })
	end
end)

---------------------------------------------------------------- Mega-Airport: Piers, Terminal 2+3, Runway 2, Cargo, Feuerwache
local mega = Instance.new("Folder"); mega.Name = "Mega"; mega.Parent = airport
local function pier(x1, x2, letter)
	tiled(mega, "PierApron", x2 - x1 + 60, 0.3, 100, (x1 + x2) / 2, 0.0, 178, COL.apron, { Material = Enum.Material.Concrete })
	mpart(mega, "Pier", x2 - x1, 5.5, 16, (x1 + x2) / 2, 5.7, 196, COL.glass, { Transparency = 0.45, Material = Enum.Material.Glass })
	mpart(mega, "PierRoof", x2 - x1 + 2, 0.6, 18, (x1 + x2) / 2, 8.6, 196, Color3.fromRGB(138, 146, 158))
	mpart(mega, "PierFloor", x2 - x1 + 2, 0.5, 18, (x1 + x2) / 2, 3.0, 196, Color3.fromRGB(119, 128, 140))
	local gnum = 1
	for gx = x1 + 25, x2 - 15, 45 do
		local br = mpart(mega, "Bridge", 3, 2.6, 22, gx, 5.0, 176, Color3.fromRGB(185, 194, 204), { CanCollide = false })
		br.CFrame = br.CFrame * CFrame.Angles(0.09, 0, 0)
		mpart(mega, "BridgeHead", 4, 3, 4, gx, 4.0, 165, Color3.fromRGB(168, 178, 188))
		-- vereinfachter geparkter Jet
		local cols = { COL.blue, COL.orange, Color3.fromRGB(42, 138, 143), Color3.fromRGB(143, 47, 36), Color3.fromRGB(42, 122, 74) }
		local jc = cols[1 + gnum % #cols]
		local fus = mpart(mega, "PJet", 24, 3.2, 3.2, gx, 2.6, 158, COL.cream)
		fus.Shape = Enum.PartType.Cylinder
		fus.CFrame = CFrame.new(gx * M, 2.6 * M, 158 * M) * CFrame.Angles(0, math.rad(90), 0)
		mpart(mega, "PJetWing", 22, 0.3, 4.4, gx, 2.2, 159, jc, { CanCollide = false })
		mpart(mega, "PJetFin", 0.35, 5.5, 3.4, gx, 5.4, 170.5, jc, { CanCollide = false })
		local gs = mpart(mega, "PGate", 3.4, 1.2, 0.15, gx, 7.2, 187.8, Color3.fromRGB(21, 32, 47), { CanCollide = false })
		local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(280, 100); sg.Parent = gs
		local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = Color3.fromRGB(255, 215, 94); tl.Text = letter .. gnum; tl.Parent = sg
		gnum = gnum + 1
	end
end
pier(-580, -230, "B")
pier(320, 670, "C")
for _, t in ipairs({ { -640, "TERMINAL 2" }, { 730, "TERMINAL 3" } }) do
	mpart(mega, "T2", 90, 12, 110, t[1], 6, 235, COL.glass, { Transparency = 0.5, Material = Enum.Material.Glass })
	mpart(mega, "T2Roof", 94, 0.8, 114, t[1], 12.2, 235, Color3.fromRGB(138, 146, 158))
	local gs = mpart(mega, "T2Sign", 30, 3, 0.2, t[1], 10, 179.4, Color3.fromRGB(21, 32, 47), { CanCollide = false })
	local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(900, 100); sg.Parent = gs
	local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
	tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = Color3.fromRGB(232, 238, 247); tl.Text = "✈ " .. t[2]; tl.Parent = sg
end
-- Runway 2 (07/25)
tiled(mega, "Runway2", 1840, 0.4, 30, 0, 0.05, -520, COL.asphalt, { Material = Enum.Material.Asphalt })
for x = -810, 810, 60 do
	mpart(mega, "R2CL", 30, 0.1, 0.9, x, 0.3, -520, COL.white, { CanCollide = false })
end
for x = -900, 900, 50 do
	for _, zz in ipairs({ -536.5, -503.5 }) do
		mpart(mega, "R2Edge", 0.8, 0.8, 0.8, x, 0.5, zz, Color3.fromRGB(255, 246, 204), { Material = Enum.Material.Neon, CanCollide = false })
	end
end
tiled(mega, "R2Taxi", 16, 0.35, 400, -700, 0.02, -300, COL.taxi)
-- Cargo-Center
tiled(mega, "CargoApron", 220, 0.3, 150, 830, 0.0, 130, COL.apron, { Material = Enum.Material.Concrete })
-- Cargohalle begehbar: 2 offene Tore (je 46 m breit, 10 m hoch) nach Sueden
mpart(mega, "CargoHallBack", 120, 14, 0.6, 840, 7, 207.5, Color3.fromRGB(143, 154, 166))
mpart(mega, "CargoHallL", 0.6, 14, 55, 780, 7, 180, Color3.fromRGB(143, 154, 166))
mpart(mega, "CargoHallR", 0.6, 14, 55, 900, 7, 180, Color3.fromRGB(143, 154, 166))
mpart(mega, "CargoHallRoof", 120, 0.7, 55, 840, 14, 180, Color3.fromRGB(110, 122, 135))
mpart(mega, "CargoHallSturz", 120, 4, 0.6, 840, 12, 152.5, Color3.fromRGB(143, 154, 166))
mpart(mega, "CargoHallPfeiler", 8, 10, 0.6, 840, 5, 152.5, Color3.fromRGB(143, 154, 166))
mpart(mega, "CargoHallPfeilerL", 10, 10, 0.6, 785, 5, 152.5, Color3.fromRGB(143, 154, 166))
mpart(mega, "CargoHallPfeilerR", 10, 10, 0.6, 895, 5, 152.5, Color3.fromRGB(143, 154, 166))
math.randomseed(41)
for i = 0, 25 do
	mpart(mega, "LD", 1.8, 1.6, 1.5, 770 + (i % 9) * 2.4, 0.8, 135 + math.floor(i / 9) * 2.6,
		({ Color3.fromRGB(185, 194, 204), Color3.fromRGB(143, 154, 166), Color3.fromRGB(201, 164, 79) })[1 + i % 3])
end
makeJet("Freighter", Color3.fromRGB(119, 127, 137), 810, 95, 0)
-- Feuerwache + 2 Loeschfahrzeuge
-- Feuerwache begehbar: offene Tore zur Vorfahrt
mpart(mega, "FireStationBack", 46, 9, 0.5, -300, 4.5, 133, Color3.fromRGB(176, 48, 48))
mpart(mega, "FireStationL", 0.5, 9, 26, -323, 4.5, 120, Color3.fromRGB(176, 48, 48))
mpart(mega, "FireStationR", 0.5, 9, 26, -277, 4.5, 120, Color3.fromRGB(176, 48, 48))
mpart(mega, "FireStationRoof", 46, 0.6, 26, -300, 9.2, 120, Color3.fromRGB(122, 31, 31))
mpart(mega, "FireStationSturz", 46, 2.0, 0.5, -300, 8.0, 107, Color3.fromRGB(176, 48, 48))
mpart(mega, "FireStationPfeiler", 4, 7, 0.5, -300, 3.5, 107, Color3.fromRGB(176, 48, 48))
mpart(mega, "FireStationPfeilerL", 5, 7, 0.5, -320.5, 3.5, 107, Color3.fromRGB(176, 48, 48))
mpart(mega, "FireStationPfeilerR", 5, 7, 0.5, -279.5, 3.5, 107, Color3.fromRGB(176, 48, 48))
for _, fx in ipairs({ -312, -288 }) do
	mpart(mega, "FireTruck", 3, 2.4, 8.5, fx, 1.6, 98, Color3.fromRGB(194, 59, 46))
	mpart(mega, "FireCab", 2.8, 1.3, 2, fx, 3.1, 100.8, Color3.fromRGB(194, 59, 46))
	mpart(mega, "FireArm", 0.4, 0.4, 6, fx + 0.8, 3.0, 97, Color3.fromRGB(216, 216, 216), { CanCollide = false })
	mpart(mega, "FireLight", 0.4, 0.4, 0.4, fx, 3.85, 100.8, Color3.fromRGB(34, 85, 255), { Material = Enum.Material.Neon, CanCollide = false })
end
-- Follow-Me, Busse, Catering
mpart(mega, "FollowMe", 1.9, 0.85, 3.9, 90, 0.75, 200, Color3.fromRGB(242, 193, 30))
mpart(mega, "FollowMeCab", 1.7, 0.65, 1.9, 90, 1.5, 200.2, Color3.fromRGB(26, 26, 26))
for _, b in ipairs({ { -95, 214 }, { 70, 216 } }) do
	mpart(mega, "Bus", 2.5, 2.7, 11, b[1], 1.7, b[2], Color3.fromRGB(232, 238, 247))
	mpart(mega, "BusStripe", 2.55, 1.0, 11.05, b[1], 1.1, b[2], Color3.fromRGB(42, 109, 181), { CanCollide = false })
end
mpart(mega, "Catering", 2.5, 2.6, 4.6, 163, 2.6, 201, Color3.fromRGB(217, 210, 196))
mpart(mega, "CateringCab", 2.4, 1.2, 3, 163, 1.0, 204.5, Color3.fromRGB(232, 238, 247))
-- Terminal-Innen: Security, Passkontrolle, Duty-Free, Lounge, Gepaeckband, Kiosks
for _, az in ipairs({ 246, 252 }) do
	mpart(mega, "SecArchL", 0.35, 2.3, 0.5, 10 - 1.05, 1.15, az, Color3.fromRGB(138, 146, 158))
	mpart(mega, "SecArchR", 0.35, 2.3, 0.5, 10 + 1.05, 1.15, az, Color3.fromRGB(138, 146, 158))
	mpart(mega, "SecArchT", 2.45, 0.35, 0.5, 10, 2.45, az, Color3.fromRGB(138, 146, 158), { CanCollide = false })
end
mpart(mega, "XrayBelt", 1.6, 1.0, 5, 13.5, 0.5, 249, COL.dark)
mpart(mega, "XrayTunnel", 2.0, 1.6, 1.8, 13.5, 0.8, 249, Color3.fromRGB(138, 146, 158))
for _, bx in ipairs({ 7, 12 }) do
	mpart(mega, "PassBooth", 1.8, 2.4, 1.8, bx, 1.2, 268, Color3.fromRGB(53, 80, 110))
end
for _, s in ipairs({ { -64, 240 }, { -64, 244 }, { -58, 240 }, { -58, 244 } }) do
	mpart(mega, "Sofa", 2.2, 0.55, 1.1, s[1], 0.28, s[2], Color3.fromRGB(106, 74, 90))
end
local carousel = mpart(mega, "Carousel", 13, 1.0, 13, -54, 0.5, 287, Color3.fromRGB(58, 63, 71))
carousel.Shape = Enum.PartType.Cylinder
carousel.CFrame = CFrame.new(-54 * M, 0.5 * M, 287 * M) * CFrame.Angles(0, 0, math.rad(90))
carousel.Size = Vector3.new(1.0 * M, 13 * M, 13 * M)
for i = 0, 3 do
	mpart(mega, "Kiosk2", 0.7, 1.5, 0.7, -18 + i * 3, 0.75, 272, Color3.fromRGB(232, 238, 247))
end
local marker2 = marker("MarkerSecurity", 10, 256, Color3.fromRGB(154, 95, 208))
-- Einkaufs-Arkade (6 Laeden mit Leucht-Schildern)
-- Begehbarer Shop-Raum aus einem ShopData-Eintrag.
-- Lokales Koordinatensystem: Front = +Z (Tueroeffnung 3.6 m breit, 2.71 m hoch, garantiert frei),
-- Theke bei (-3.2 / -0.8) -> Interaktionspunkt des Clients liegt davor bei (-3.2 / +0.9).
local function shop(sd)
	local col = sd.akzentfarbe
	local baseY = sd.ebene == 2 and 4.78 or 0
	local dk = Color3.fromRGB(44, 51, 60)
	local grau = Color3.fromRGB(96, 103, 116)
	local m = Instance.new("Model"); m.Name = "Shop_" .. sd.id; m.Parent = mega
	if sd.theke then
		-- Nur-Schalter (Ticketschalter): Theke an derselben lokalen Position wie im
		-- Raum-Layout (-3.2/-0.8), damit der Client-Interaktionspunkt identisch passt
		local root0 = mpart(m, "Root", 0.4, 0.4, 0.4, 0, 0, 0, dk, { Transparency = 1, CanCollide = false })
		m.PrimaryPart = root0
		mpart(m, "Theke", 4.2, 1.05, 1.2, -3.2, 0.52, -0.8, dk)
		mpart(m, "ThekeTop", 4.3, 0.08, 1.3, -3.2, 1.09, -0.8, col)
		mpart(m, "Rueckwand", 4.6, 2.6, 0.3, -3.2, 1.3, -1.9, Color3.fromRGB(53, 80, 110))
		mpart(m, "Monitor", 0.8, 0.5, 0.08, -4.4, 1.45, -1.1, Color3.fromRGB(84, 208, 106), { Material = Enum.Material.Neon, CanCollide = false })
		local sign = mpart(m, "Schild", 5.4, 0.8, 0.15, -3.2, 3.2, -1.85, Color3.fromRGB(21, 32, 47), { CanCollide = false })
		local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Back; sg.CanvasSize = Vector2.new(460, 68); sg.Parent = sign
		local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = col; tl.Text = sd.name; tl.Parent = sg
		local spl = Instance.new("PointLight"); spl.Brightness = 0.7; spl.Range = 14; spl.Color = col; spl.Parent = sign
		m:PivotTo(CFrame.new(sd.pos.x * M, baseY * M, sd.pos.z * M) * CFrame.Angles(0, sd.rotation, 0))
		return
	end
	-- Root am lokalen Ursprung als PrimaryPart, sonst pivotiert PivotTo um die Bounding-Box
	local root = mpart(m, "Root", 0.4, 0.4, 0.4, 0, 0, 0, dk, { Transparency = 1, CanCollide = false })
	m.PrimaryPart = root
	-- Raum: Boden, Rueckwand, zwei Seitenwaende, Decke — Front offen
	mpart(m, "Floor", 12.8, 0.18, 4.9, 0, 0.09, -1.1, Color3.fromRGB(64, 70, 78))
	mpart(m, "Back", 13, 3.6, 0.25, 0, 1.8, -3.72, dk)
	mpart(m, "SideL", 0.25, 3.6, 5.2, -6.4, 1.8, -1.1, dk)
	mpart(m, "SideR", 0.25, 3.6, 5.2, 6.4, 1.8, -1.1, dk)
	mpart(m, "Ceil", 13.4, 0.25, 5.5, 0, 3.72, -1.05, dk)
	-- Front: Sockel + Schaufenster beidseitig, Tuerrahmen in Akzentfarbe — Oeffnung bleibt frei
	for _, sx in ipairs({ -1, 1 }) do
		mpart(m, "FrontSockel", 4.4, 0.9, 0.25, sx * 4.3, 0.45, 1.4, dk)
		mpart(m, "Schaufenster", 4.4, 2.7, 0.18, sx * 4.3, 2.25, 1.4, COL.glass, { Transparency = 0.55, Material = Enum.Material.Glass })
		mpart(m, "TuerRahmen", 0.3, 3.6, 0.3, sx * 2.25, 1.8, 1.4, col)
	end
	mpart(m, "TuerSturz", 4.2, 0.3, 0.25, 0, 3.42, 1.4, col, { CanCollide = false }) -- lichte Hoehe 3.27 m
	-- Theke mit Akzent-Abdeckung
	mpart(m, "Theke", 4.2, 1.05, 1.2, -3.2, 0.52, -0.8, dk)
	mpart(m, "ThekeTop", 4.3, 0.08, 1.3, -3.2, 1.09, -0.8, col)
	-- Deckenlampe: Neon-Part + PointLight
	local lamp = mpart(m, "Lampe", 2.4, 0.1, 0.7, 0, 3.55, -0.9, Color3.fromRGB(255, 244, 214), { Material = Enum.Material.Neon, CanCollide = false })
	local pl = Instance.new("PointLight")
	pl.Brightness = 1.1; pl.Range = 36; pl.Color = Color3.fromRGB(255, 240, 210); pl.Parent = lamp
	-- Einrichtung nach Thema
	local FOOD = { burger = true, pizza = true, cafe = true, sushi = true, taco = true, eiscafe = true }
	if FOOD[sd.id] then
		-- Vitrine auf der Theke + Regal an der Rueckwand
		mpart(m, "Vitrine", 2.6, 0.7, 0.95, -3.2, 1.5, -0.8, COL.glass, { Transparency = 0.5, Material = Enum.Material.Glass, CanCollide = false })
		for k = 0, 2 do
			mpart(m, "Ware", 0.5, 0.32, 0.5, -4.05 + k * 0.85, 1.32, -0.8, col, { CanCollide = false })
		end
		mpart(m, "Regal", 5, 1.9, 0.5, 2.6, 0.95, -3.35, grau)
		for k = 0, 3 do
			mpart(m, "Ware", 0.55, 0.5, 0.4, 0.9 + k * 1.15, 2.15, -3.3, col, { CanCollide = false })
		end
	elseif sd.id == "mode" then
		-- Kleiderstaender aus Parts + Regal
		for _, kx in ipairs({ 2.2, 4.6 }) do
			mpart(m, "StaenderFuss", 1.6, 0.12, 0.5, kx, 0.12, -1.6, Color3.fromRGB(138, 146, 158))
			mpart(m, "StaenderPfostenL", 0.1, 1.7, 0.1, kx - 0.7, 1.0, -1.6, Color3.fromRGB(138, 146, 158))
			mpart(m, "StaenderPfostenR", 0.1, 1.7, 0.1, kx + 0.7, 1.0, -1.6, Color3.fromRGB(138, 146, 158))
			mpart(m, "StaenderStange", 1.5, 0.07, 0.07, kx, 1.82, -1.6, Color3.fromRGB(138, 146, 158), { CanCollide = false })
			for k = 0, 3 do
				mpart(m, "Kleid", 0.28, 0.75, 0.06, kx - 0.55 + k * 0.36, 1.4, -1.6,
					k % 2 == 0 and col or Color3.fromRGB(232, 238, 247), { CanCollide = false })
			end
		end
		mpart(m, "Regal", 5, 1.9, 0.5, 2.6, 0.95, -3.35, grau)
	else
		-- Standard: 2 Regale an der rechten Wand + 1 an der Rueckwand, Waren in Akzentfarbe
		for _, rz in ipairs({ -2.4, 0.2 }) do
			mpart(m, "Regal", 0.5, 1.9, 2.6, 5.95, 0.95, rz, grau)
			for k = 0, 1 do
				mpart(m, "Ware", 0.4, 0.5, 0.55, 5.9, 0.75 + k * 0.75, rz - 0.6, col, { CanCollide = false })
				mpart(m, "Ware", 0.4, 0.5, 0.55, 5.9, 0.75 + k * 0.75, rz + 0.6, col, { CanCollide = false })
			end
		end
		mpart(m, "Regal", 5, 1.9, 0.5, 2.6, 0.95, -3.35, grau)
		for k = 0, 3 do
			mpart(m, "Ware", 0.55, 0.5, 0.4, 0.9 + k * 1.15, 2.15, -3.3, col, { CanCollide = false })
		end
	end
	-- Aussen: Neon-Band + beleuchtetes Schild
	mpart(m, "Band", 13, 0.85, 0.2, 0, 3.92, 1.55, col, { Material = Enum.Material.Neon, CanCollide = false })
	-- Schild: breiter und beleuchtet; im EG flacher, damit es nicht in den Galerie-Boden ragt
	local sw, sh, sy = 11, 1.5, 4.45
	if sd.ebene == 1 then sh, sy = 0.72, 4.0 end
	local sign = mpart(m, "Schild", sw, sh, 0.15, 0, sy, 1.6, Color3.fromRGB(21, 32, 47), { CanCollide = false })
	local spl = Instance.new("PointLight")
	spl.Brightness = 0.8; spl.Range = 18; spl.Color = col; spl.Parent = sign
	local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Back; sg.CanvasSize = Vector2.new(560, 84); sg.Parent = sign
	local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
	tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = Color3.new(1, 1, 1); tl.Text = sd.name; tl.Parent = sg
	m:PivotTo(CFrame.new(sd.pos.x * M, baseY * M, sd.pos.z * M) * CFrame.Angles(0, sd.rotation, 0))
end
-- Begehbare Raeume fuer alle Erdgeschoss-Shops aus ShopData
for _, sd in ipairs(ShopData) do
	if sd.ebene == 1 then shop(sd) end
end

-- Gebaeude-Upgrade: Notausgaenge, Security-Ausbau, WC, Geldautomaten, Feuerloescher
sysInit("Gebaeude-Upgrade", function()
	local function exitDoor(x, z, dir) -- dir = +1: Tuer zeigt nach Osten (+X), -1: nach Westen
		-- Die Wand hat hier eine echte Oeffnung — die Tuer steht aufgeschwungen daneben
		local tuer = mpart(mega, "ExitDoor", 0.16, 3.0, 2.2, x - dir * 0.6, 1.5, z + 2.2, Color3.fromRGB(61, 143, 79))
		tuer.CFrame = CFrame.new((x - dir * 0.6) * M, 1.5 * M, (z + 2.2) * M) * CFrame.Angles(0, math.rad(65 * dir), 0)
		mpart(mega, "ExitPad", 2.4, 0.1, 3.0, x - dir * 1.6, 0.06, z, Color3.fromRGB(61, 143, 79), { CanCollide = false }) -- gruener Auftritt draussen
		local sign = mpart(mega, "ExitSign", 0.14, 0.62, 2.6, x, 3.7, z, Color3.fromRGB(29, 122, 58), { CanCollide = false, Material = Enum.Material.Neon })
		for _, face in ipairs({ Enum.NormalId.Right, Enum.NormalId.Left }) do
			local sg = Instance.new("SurfaceGui")
			sg.Face = face
			sg.CanvasSize = Vector2.new(420, 100); sg.Parent = sign
			local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
			tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = Color3.fromRGB(234, 255, 240)
			tl.Text = "🏃 NOTAUSGANG"; tl.Parent = sg
		end
	end
	exitDoor(-69.5, 246, 1); exitDoor(-69.5, 288, 1)  -- Westwand
	exitDoor(74.5, 238, -1); exitDoor(74.5, 286, -1)  -- Ostwand
	-- Sicherheitskontrolle Spur 2 + Koerperscanner + Wannen + Warteschlange
	for _, az in ipairs({ 246, 252 }) do
		mpart(mega, "SecArchL2", 0.35, 2.3, 0.5, 2 - 1.05, 1.15, az, Color3.fromRGB(138, 146, 158))
		mpart(mega, "SecArchR2", 0.35, 2.3, 0.5, 2 + 1.05, 1.15, az, Color3.fromRGB(138, 146, 158))
		mpart(mega, "SecArchT2", 2.45, 0.35, 0.5, 2, 2.45, az, Color3.fromRGB(138, 146, 158), { CanCollide = false })
		mpart(mega, "SecLamp", 0.3, 0.18, 0.18, 2, 2.7, az, Color3.fromRGB(84, 208, 106), { Material = Enum.Material.Neon, CanCollide = false })
	end
	mpart(mega, "XrayBelt2", 1.6, 1.0, 5, -1.5, 0.5, 249, COL.dark)
	mpart(mega, "XrayTunnel2", 2.0, 1.6, 1.8, -1.5, 0.8, 249, Color3.fromRGB(138, 146, 158))
	local scan = mpart(mega, "BodyScan", 2.6, 2.2, 2.2, 6, 1.3, 252, COL.glass, { Transparency = 0.55, Material = Enum.Material.Glass, CanCollide = false })
	scan.Shape = Enum.PartType.Cylinder
	scan.CFrame = CFrame.new(6 * M, 1.3 * M, 252 * M) * CFrame.Angles(0, 0, math.rad(90))
	for i = 0, 3 do
		mpart(mega, "Tray", 0.9, 0.12, 0.6, 13.5, 1.06 + i * 0.14, 245.4, Color3.fromRGB(127, 140, 154), { CanCollide = false })
		mpart(mega, "Tray", 0.9, 0.12, 0.6, -1.5, 1.06 + i * 0.14, 245.4, Color3.fromRGB(127, 140, 154), { CanCollide = false })
	end
	for _, b in ipairs({ 242, 239 }) do
		for bx = 0, 12, 4 do
			mpart(mega, "QPole", 0.14, 1.0, 0.14, bx, 0.5, b, Color3.fromRGB(138, 146, 158))
		end
		mpart(mega, "QBand", 12, 0.06, 0.1, 6, 0.95, b, Color3.fromRGB(194, 59, 46), { CanCollide = false })
	end
	-- Sicherheitspersonal (2 Posten)
	for _, o in ipairs({ { 13.5, 253.5 }, { 0.5, 245 } }) do
		mpart(mega, "OffiTorso", 0.62, 0.85, 0.4, o[1], 1.08, o[2], Color3.fromRGB(36, 55, 74), { CanCollide = false })
		mpart(mega, "OffiLegs", 0.5, 0.68, 0.42, o[1], 0.34, o[2], Color3.fromRGB(44, 51, 60), { CanCollide = false })
		local hd = mpart(mega, "OffiHead", 0.42, 0.42, 0.42, o[1], 1.68, o[2], Color3.fromRGB(217, 180, 143), { CanCollide = false })
		hd.Shape = Enum.PartType.Ball
		mpart(mega, "OffiWeste", 0.7, 0.1, 0.42, o[1], 1.42, o[2], Color3.fromRGB(255, 215, 94), { CanCollide = false })
	end
	-- WC-Ecke Nordwest
	mpart(mega, "WCWall", 0.25, 3.2, 10, -63.5, 1.6, 296, COL.wall)
	mpart(mega, "WCFill", 1.2, 3.2, 5.2, -63.05, 1.6, 298.9, COL.wall) -- schliesst den Schlitz zum Burger-Raum
	mpart(mega, "WCWall2", 6.5, 3.2, 0.25, -66.5, 1.6, 291, COL.wall)
	local wc = mpart(mega, "WCSign", 3.6, 0.8, 0.14, -65, 3.9, 291.2, Color3.fromRGB(26, 58, 122), { CanCollide = false })
	local wsg = Instance.new("SurfaceGui"); wsg.Face = Enum.NormalId.Front; wsg.CanvasSize = Vector2.new(300, 66); wsg.Parent = wc
	local wtl = Instance.new("TextLabel"); wtl.Size = UDim2.fromScale(1, 1); wtl.BackgroundTransparency = 1
	wtl.Font = Enum.Font.GothamBold; wtl.TextScaled = true; wtl.TextColor3 = Color3.new(1, 1, 1); wtl.Text = "🚻 WC"; wtl.Parent = wsg
	-- Geldautomaten
	for _, ax in ipairs({ -2, 0.2 }) do
		mpart(mega, "ATM", 0.8, 1.7, 0.7, ax, 0.85, 285.6, Color3.fromRGB(53, 80, 110))
		mpart(mega, "ATMScreen", 0.55, 0.4, 0.06, ax, 1.35, 285.2, Color3.fromRGB(84, 208, 106), { Material = Enum.Material.Neon, CanCollide = false })
	end
	-- Feuerloescher + Alarmknoepfe an den Stuetzen, Erste-Hilfe-Kasten
	for _, fxp in ipairs({ -55, -11, 33 }) do
		mpart(mega, "Extinguisher", 0.24, 0.55, 0.24, fxp + 0.55, 1.2, 267, Color3.fromRGB(194, 59, 46), { CanCollide = false })
		mpart(mega, "AlarmBtn", 0.16, 0.16, 0.06, fxp + 0.55, 1.9, 266.9, Color3.fromRGB(194, 59, 46), { Material = Enum.Material.Neon, CanCollide = false })
	end
	mpart(mega, "FirstAid", 0.5, 0.5, 0.14, 11.55, 1.9, 267, Color3.fromRGB(42, 157, 92), { CanCollide = false })
	mpart(mega, "FirstAidH", 0.36, 0.1, 0.06, 11.55, 1.9, 266.9, Color3.new(1, 1, 1), { CanCollide = false })
	mpart(mega, "FirstAidV", 0.1, 0.36, 0.06, 11.55, 1.9, 266.9, Color3.new(1, 1, 1), { CanCollide = false })
	-- PA-Lautsprecher + Muelleimer
	for _, l in ipairs({ { -40, 250 }, { -40, 285 }, { 20, 250 }, { 20, 285 }, { 55, 267 } }) do
		mpart(mega, "PASpeaker", 0.5, 0.4, 0.5, l[1], 10.1, l[2], Color3.fromRGB(44, 51, 60), { CanCollide = false })
	end
	for _, l in ipairs({ { -30, 254 }, { 15, 256 }, { -10, 280 }, { 50, 262 }, { -60, 280 } }) do
		local bin = mpart(mega, "Bin", 0.64, 0.85, 0.64, l[1], 0.43, l[2], Color3.fromRGB(96, 103, 116))
		bin.Shape = Enum.PartType.Cylinder
		bin.CFrame = CFrame.new(l[1] * M, 0.43 * M, l[2] * M) * CFrame.Angles(0, 0, math.rad(90))
		bin.Size = Vector3.new(0.85 * M, 0.64 * M, 0.64 * M)
	end
end)

-- Moderne Inneneinrichtung: Sky Lounge, Ruhezone, Ladesaeulen, Screens, Brunnen
sysInit("Inneneinrichtung", function()
	local function carpet(x, z, w, d, col)
		mpart(mega, "Carpet", w, 0.06, d, x, 0.28, z, col, { CanCollide = false, Material = Enum.Material.Fabric })
	end
	local function sitSpot(mdl, ox, oy, oz, w)
		-- unsichtbarer, funktionierender Sitzplatz (Roblox-Seat)
		local st = Instance.new("Seat")
		st.Anchored = true; st.CanCollide = false; st.Transparency = 1
		st.Size = Vector3.new((w or 1.2) * M, 0.3, 1.0 * M)
		st.CFrame = CFrame.new(ox * M, oy * M, oz * M) * CFrame.Angles(0, math.pi, 0)
		st.Parent = mdl
	end
	local function sofa(x, z, ry, col, len)
		local mdl = Instance.new("Model"); mdl.Name = "Sofa"; mdl.Parent = mega
		local root = mpart(mdl, "Root", 0.3, 0.3, 0.3, 0, 0, 0, col, { Transparency = 1, CanCollide = false })
		mdl.PrimaryPart = root
		mpart(mdl, "Seat", len, 0.42, 1.05, 0, 0.44, 0, col, { CanCollide = false })
		mpart(mdl, "Back", len, 0.8, 0.28, 0, 0.88, -0.5, col, { CanCollide = false })
		mpart(mdl, "ArmL", 0.28, 0.5, 1.05, -len / 2 + 0.14, 0.78, 0, col, { CanCollide = false })
		mpart(mdl, "ArmR", 0.28, 0.5, 1.05, len / 2 - 0.14, 0.78, 0, col, { CanCollide = false })
		mpart(mdl, "Rail", len - 0.4, 0.1, 0.75, 0, 0.15, 0, Color3.fromRGB(138, 146, 158), { CanCollide = false })
		sitSpot(mdl, 0, 0.75, 0.05, len - 0.7)
		mdl:PivotTo(CFrame.new(x * M, 0, z * M) * CFrame.Angles(0, ry, 0))
	end
	local function ltable(x, z, r)
		local top = mpart(mega, "LTable", 0.07, r * 2, r * 2, x, 0.47, z, Color3.fromRGB(217, 210, 196), { CanCollide = false })
		top.Shape = Enum.PartType.Cylinder
		top.CFrame = CFrame.new(x * M, 0.47 * M, z * M) * CFrame.Angles(0, 0, math.rad(90))
		mpart(mega, "LTableLeg", 0.12, 0.44, 0.12, x, 0.22, z, Color3.fromRGB(138, 146, 158), { CanCollide = false })
	end
	local function floorLamp(x, z)
		mpart(mega, "LampPole", 0.1, 1.9, 0.1, x, 0.95, z, Color3.fromRGB(102, 110, 120), { CanCollide = false })
		local b = mpart(mega, "LampBall", 0.6, 0.6, 0.6, x, 2.0, z, Color3.fromRGB(255, 242, 204), { Material = Enum.Material.Neon, CanCollide = false })
		b.Shape = Enum.PartType.Ball
	end
	local function planter(x, z)
		local pot = mpart(mega, "Pot", 0.72, 1.2, 1.2, x, 0.36, z, Color3.fromRGB(58, 63, 70))
		pot.Shape = Enum.PartType.Cylinder
		pot.CFrame = CFrame.new(x * M, 0.36 * M, z * M) * CFrame.Angles(0, 0, math.rad(90))
		mpart(mega, "Trunk", 0.2, 1.0, 0.2, x, 1.2, z, Color3.fromRGB(90, 70, 50), { CanCollide = false })
		local k = mpart(mega, "Crown", 1.6, 1.6, 1.6, x, 2.1, z, Color3.fromRGB(63, 125, 70), { CanCollide = false })
		k.Shape = Enum.PartType.Ball
	end
	local function pendant(x, z)
		mpart(mega, "PendRod", 0.06, 2.2, 0.06, x, 9.4, z, Color3.fromRGB(102, 110, 120), { CanCollide = false })
		local l = mpart(mega, "PendLamp", 0.22, 1.1, 1.1, x, 8.2, z, Color3.fromRGB(255, 242, 204), { Material = Enum.Material.Neon, CanCollide = false })
		l.Shape = Enum.PartType.Cylinder
		l.CFrame = CFrame.new(x * M, 8.2 * M, z * M) * CFrame.Angles(0, 0, math.rad(90))
	end
	local function recliner(x, z, ry)
		local mdl = Instance.new("Model"); mdl.Name = "Recliner"; mdl.Parent = mega
		local root = mpart(mdl, "Root", 0.3, 0.3, 0.3, 0, 0, 0, Color3.fromRGB(74, 106, 85), { Transparency = 1, CanCollide = false })
		mdl.PrimaryPart = root
		mpart(mdl, "Seat", 0.8, 0.35, 1.8, 0, 0.35, 0.2, Color3.fromRGB(74, 106, 85), { CanCollide = false })
		local back = mpart(mdl, "Back", 0.8, 0.12, 1.15, 0, 0.78, -1.02, Color3.fromRGB(74, 106, 85), { CanCollide = false })
		back.CFrame = back.CFrame * CFrame.Angles(0.65, 0, 0)
		mpart(mdl, "Base", 0.7, 0.12, 0.5, 0, 0.12, 0.2, Color3.fromRGB(138, 146, 158), { CanCollide = false })
		sitSpot(mdl, 0, 0.62, 0.3, 0.7)
		mdl:PivotTo(CFrame.new(x * M, 0, z * M) * CFrame.Angles(0, ry, 0))
	end
	local function textOn(part, face, txt, fg, w, h)
		local sg = Instance.new("SurfaceGui"); sg.Face = face; sg.CanvasSize = Vector2.new(w, h); sg.Parent = part
		local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = fg; tl.Text = txt; tl.Parent = sg
	end
	local function chargePillar(x, z)
		mpart(mega, "Charger", 0.42, 1.35, 0.42, x, 0.68, z, Color3.fromRGB(232, 238, 247))
		mpart(mega, "ChargerScreen", 0.3, 0.34, 0.05, x, 1.05, z + 0.21, Color3.fromRGB(84, 208, 106), { Material = Enum.Material.Neon, CanCollide = false })
		local s = mpart(mega, "ChargerSign", 2.4, 0.5, 0.08, x, 1.8, z, Color3.fromRGB(21, 32, 47), { CanCollide = false })
		textOn(s, Enum.NormalId.Front, "⚡ LADESTATION", Color3.fromRGB(84, 208, 106), 300, 62)
		textOn(s, Enum.NormalId.Back, "⚡ LADESTATION", Color3.fromRGB(84, 208, 106), 300, 62)
	end
	local function adScreen(x, z, txt, fg)
		local s = mpart(mega, "AdScreen", 3.3, 2.0, 0.2, x, 3.2, z, Color3.fromRGB(21, 32, 47), { CanCollide = false })
		textOn(s, Enum.NormalId.Front, txt, fg, 480, 290)
		textOn(s, Enum.NormalId.Back, txt, fg, 480, 290)
	end
	local function zoneSign(x, z, txt, fg)
		local s = mpart(mega, "ZoneSign", 6.5, 1.0, 0.14, x, 3.4, z, Color3.fromRGB(22, 34, 46), { CanCollide = false })
		textOn(s, Enum.NormalId.Front, txt, fg, 460, 70)
	end
	-- Business Lounge West: Teppich, Glaswand, Sofa, Lampe
	carpet(-61, 243.5, 13, 9.5, Color3.fromRGB(58, 50, 68))
	mpart(mega, "LoungeGlass", 0.12, 2.2, 9.5, -54.5, 1.1, 243.5, COL.glass, { Transparency = 0.55, Material = Enum.Material.Glass })
	mpart(mega, "LoungeGlass2", 13, 2.2, 0.12, -61, 1.1, 248.2, COL.glass, { Transparency = 0.55, Material = Enum.Material.Glass })
	sofa(-61, 246.8, math.pi, Color3.fromRGB(106, 74, 90), 2.4)
	ltable(-61, 242, 0.7)
	floorLamp(-67, 246.5); planter(-56, 246.5)
	-- Ruhezone West
	carpet(-60.5, 255.5, 14, 8, Color3.fromRGB(46, 68, 54))
	for _, rx in ipairs({ -65.5, -62.5, -59.5, -56.5 }) do recliner(rx, 255.5, math.pi) end
	planter(-67.5, 258.5); planter(-54, 258.5); floorLamp(-54, 252.5)
	zoneSign(-60.5, 251.6, "🌙 RUHEZONE", Color3.fromRGB(143, 232, 159))
	-- Sky Lounge im Gate-Bereich
	carpet(32, 271, 23, 13.5, Color3.fromRGB(34, 54, 72))
	sofa(25, 267.2, math.pi, Color3.fromRGB(42, 143, 143), 3.2); sofa(21.6, 271, math.pi / 2, Color3.fromRGB(42, 143, 143), 3.0)
	ltable(25.5, 271, 0.85)
	sofa(39, 267.2, math.pi, Color3.fromRGB(224, 120, 32), 3.2); sofa(42.4, 271, -math.pi / 2, Color3.fromRGB(224, 120, 32), 3.0)
	ltable(38.5, 271, 0.85)
	sofa(28, 275.8, 0, Color3.fromRGB(201, 164, 79), 3.2); sofa(36, 275.8, 0, Color3.fromRGB(141, 95, 201), 3.2)
	ltable(32, 274, 0.7)
	pendant(25.5, 271); pendant(38.5, 271)
	planter(32, 264.8); planter(45.5, 276); floorLamp(18.5, 276)
	zoneSign(32, 263.4, "☁ SKY LOUNGE", Color3.fromRGB(159, 212, 232))
	-- Stehtische + Springbrunnen
	for _, t in ipairs({ { -13, 289 }, { -9, 292 } }) do
		local top = mpart(mega, "BarTable", 0.06, 1.1, 1.1, t[1], 1.12, t[2], Color3.fromRGB(217, 210, 196), { CanCollide = false })
		top.Shape = Enum.PartType.Cylinder
		top.CFrame = CFrame.new(t[1] * M, 1.12 * M, t[2] * M) * CFrame.Angles(0, 0, math.rad(90))
		mpart(mega, "BarPole", 0.1, 1.1, 0.1, t[1], 0.55, t[2], Color3.fromRGB(138, 146, 158), { CanCollide = false })
		for _, sx in ipairs({ -0.9, 0.9 }) do
			mpart(mega, "Stool", 0.55, 0.72, 0.55, t[1] + sx, 0.36, t[2], Color3.fromRGB(53, 80, 110), { CanCollide = false })
		end
	end
	local basin = mpart(mega, "Fountain", 0.55, 4.2, 4.2, -32, 0.28, 243, Color3.fromRGB(74, 80, 88))
	basin.Shape = Enum.PartType.Cylinder
	basin.CFrame = CFrame.new(-32 * M, 0.28 * M, 243 * M) * CFrame.Angles(0, 0, math.rad(90))
	local water = mpart(mega, "FountainWater", 0.1, 3.44, 3.44, -32, 0.55, 243, Color3.fromRGB(58, 122, 191), { Material = Enum.Material.Neon, CanCollide = false })
	water.Shape = Enum.PartType.Cylinder
	water.CFrame = CFrame.new(-32 * M, 0.55 * M, 243 * M) * CFrame.Angles(0, 0, math.rad(90))
	mpart(mega, "FountainCol", 0.35, 1.1, 0.35, -32, 0.9, 243, Color3.fromRGB(138, 146, 158), { CanCollide = false })
	local fb = mpart(mega, "FountainBall", 0.6, 0.6, 0.6, -32, 1.5, 243, Color3.fromRGB(159, 212, 232), { Material = Enum.Material.Neon, CanCollide = false })
	fb.Shape = Enum.PartType.Ball
	-- Werbescreens, Ladesaeulen, Pendelleuchten, Wandkunst
	adScreen(-33, 267, "SKYJET ✈ JETZT BUCHEN", Color3.fromRGB(159, 212, 232))
	adScreen(55, 267, "✨ DUTY FREE SALE ✨", Color3.fromRGB(255, 215, 94))
	adScreen(-14, 296, "☕ CAFÉ · FRISCH GERÖSTET", Color3.fromRGB(255, 215, 94))
	chargePillar(16, 260.5); chargePillar(48.5, 260.5); chargePillar(-41.5, 272); chargePillar(58, 278)
	pendant(-45, 252); pendant(-15, 262); pendant(10, 276); pendant(-40, 286); pendant(55, 276)
	for _, p in ipairs({ { 256, Color3.fromRGB(42, 143, 143) }, { 261, Color3.fromRGB(224, 120, 32) }, { 266, Color3.fromRGB(201, 164, 79) } }) do
		mpart(mega, "WallArt", 0.1, 2.6, 2.0, -69.45, 4.2, p[1], p[2], { CanCollide = false })
	end
end)

-- Zwei neue Ebenen: Food-Court-Galerie (Ebene 2, begehbar ueber Rampe) + UG-Tunnel
sysInit("Ebenen & Tunnel", function()
	local grey = Color3.fromRGB(170, 178, 188)
	-- Galerie-Boden + Gelaender (Luecke an der Rolltreppen-Rampe x 50..57)
	mpart(mega, "GalleryFloor", 74, 0.4, 37.5, 35, 4.58, 281.75, Color3.fromRGB(226, 230, 235))
	mpart(mega, "GalRailS1", 52.8, 1.1, 0.1, 24.4, 5.35, 263, COL.glass, { Transparency = 0.5, Material = Enum.Material.Glass })
	mpart(mega, "GalRailS2", 15, 1.1, 0.1, 64.5, 5.35, 263, COL.glass, { Transparency = 0.5, Material = Enum.Material.Glass })
	mpart(mega, "GalRailW", 0.1, 1.1, 37.5, -2, 5.35, 281.75, COL.glass, { Transparency = 0.5, Material = Enum.Material.Glass })
	for _, cx in ipairs({ 8, 28, 48, 68 }) do
		mpart(mega, "GalCol", 0.7, 4.6, 0.7, cx, 2.3, 263.8, grey)
	end
	-- begehbare Rolltreppen-Rampe EG -> Galerie (Anstieg entlang +Z wie Parkdeck)
	local esc = mpart(mega, "GalRamp", 6.4, 4.78, 13.6, 53.5, 2.39, 256.2, Color3.fromRGB(96, 100, 106))
	esc.Shape = Enum.PartType.Wedge
	local escSign = mpart(mega, "GalSign", 7, 1.1, 0.14, 53.5, 3.3, 248.6, Color3.fromRGB(21, 32, 47), { CanCollide = false })
	do
		local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(480, 76); sg.Parent = escSign
		local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = Color3.fromRGB(143, 232, 159)
		tl.Text = "⬆ EBENE 2 · FOOD COURT"; tl.Parent = sg
	end
	-- Aufzug-Optik an der Nordwand (Teleport uebernimmt der Client)
	for _, ox in ipairs({ 1.2, 3.8 }) do
		mpart(mega, "LiftFrame", 0.36, 9.6, 2.6, ox, 4.8, 298.4, grey)
	end
	mpart(mega, "LiftGlass", 2.8, 9.6, 0.2, 2.5, 4.8, 297.1, COL.glass, { Transparency = 0.5, Material = Enum.Material.Glass })
	mpart(mega, "LiftGlass2", 2.8, 9.6, 0.2, 2.5, 4.8, 299.7, COL.glass, { Transparency = 0.5, Material = Enum.Material.Glass })
	mpart(mega, "LiftTop", 2.8, 0.3, 2.8, 2.5, 9.7, 298.4, grey, { CanCollide = false })
	-- Food-Court-Laeden: begehbare Raeume wie im EG (shop() setzt die Galerie-Hoehe selbst)
	for _, sd in ipairs(ShopData) do
		if sd.ebene == 2 then shop(sd) end
	end
	-- Food-Court-Tische mit Hockern (2 davon echte Sitzplaetze)
	for _, t in ipairs({ { 10, 276 }, { 22, 279 }, { 34, 274 }, { 46, 280 }, { 58, 274 }, { 64, 285 } }) do
		local top = mpart(mega, "FCTable", 0.07, 1.5, 1.5, t[1], 4.78 + 0.78, t[2], Color3.fromRGB(217, 210, 196), { CanCollide = false })
		top.Shape = Enum.PartType.Cylinder
		top.CFrame = CFrame.new(t[1] * M, (4.78 + 0.78) * M, t[2] * M) * CFrame.Angles(0, 0, math.rad(90))
		mpart(mega, "FCLeg", 0.14, 0.78, 0.14, t[1], 4.78 + 0.39, t[2], Color3.fromRGB(138, 146, 158), { CanCollide = false })
		for _, o in ipairs({ { -1.1, 0 }, { 1.1, 0 }, { 0, -1.1 }, { 0, 1.1 } }) do
			mpart(mega, "FCStool", 0.6, 0.55, 0.6, t[1] + o[1], 4.78 + 0.28, t[2] + o[2], Color3.fromRGB(53, 80, 110), { CanCollide = false })
		end
		if t[1] == 22 or t[1] == 46 then
			local st = Instance.new("Seat")
			st.Anchored = true; st.CanCollide = false; st.Transparency = 1
			st.Size = Vector3.new(1.1 * M, 0.3, 1.0 * M)
			st.CFrame = CFrame.new((t[1] - 1.1) * M, (4.78 + 0.62) * M, t[2] * M) * CFrame.Angles(0, math.rad(90), 0)
			st.Parent = mega
		end
	end
	-- Sitzbaenke im Gate-Bereich: echte Sitzplaetze auf drei Baenken
	for _, s in ipairs({ { 24, 245.5, 0 }, { 37, 254.5, 0 }, { -55, 272.5, 180 } }) do
		local st = Instance.new("Seat")
		st.Anchored = true; st.CanCollide = false; st.Transparency = 1
		st.Size = Vector3.new(1.3 * M, 0.3, 1.2 * M)
		st.CFrame = CFrame.new(s[1] * M, 0.95 * M, s[2] * M) * CFrame.Angles(0, math.rad(s[3]), 0)
		st.Parent = mega
	end
	-- UG-Tunnel Parkdeck <-> Terminal (Boden bei -3.8 m, Decke = Unterseite des Bodens)
	mpart(mega, "TunFloor", 69, 0.3, 8, -90.5, -4.75, 290, Color3.fromRGB(58, 63, 70))
	mpart(mega, "TunWallN", 69, 3.8, 0.3, -90.5, -2.7, 293.7, Color3.fromRGB(216, 221, 228))
	mpart(mega, "TunWallS", 69, 3.8, 0.3, -90.5, -2.7, 286.3, Color3.fromRGB(216, 221, 228))
	mpart(mega, "TunEndW", 0.3, 3.8, 8, -122.8, -2.7, 290, Color3.fromRGB(216, 221, 228))
	mpart(mega, "TunEndE", 0.3, 3.8, 8, -58.2, -2.7, 290, Color3.fromRGB(216, 221, 228))
	mpart(mega, "TunCeil", 69, 0.25, 8, -90.5, -1.05, 290, Color3.fromRGB(138, 146, 158), { CanCollide = false })
	for _, zz in ipairs({ 286.5, 293.5 }) do
		mpart(mega, "TunStripe", 69, 0.5, 0.08, -90.5, -4.1, zz, Color3.fromRGB(42, 143, 143), { CanCollide = false })
	end
	for lx = -118, -62, 8 do
		mpart(mega, "TunLight", 1.8, 0.06, 1.0, lx, -1.2, 290, Color3.fromRGB(255, 255, 255), { Material = Enum.Material.Neon, CanCollide = false })
	end
	mpart(mega, "TunWalk", 44, 0.08, 1.9, -90.5, -4.54, 288.4, Color3.fromRGB(34, 38, 44), { CanCollide = false })
	for _, hz in ipairs({ 287.4, 289.4 }) do
		mpart(mega, "TunRail", 44, 0.1, 0.12, -90.5, -3.65, hz, Color3.fromRGB(22, 24, 28), { CanCollide = false })
	end
	local function tunAd(x, txt, fg)
		local s = mpart(mega, "TunAd", 6, 1.0, 0.1, x, -2.3, 293.5, Color3.fromRGB(21, 32, 47), { CanCollide = false })
		local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(420, 70); sg.Parent = s
		local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = fg; tl.Text = txt; tl.Parent = sg
	end
	tunAd(-105, "SKYJET ✈ JETZT BUCHEN", Color3.fromRGB(159, 212, 232))
	tunAd(-90, "✨ DUTY FREE SALE ✨", Color3.fromRGB(255, 215, 94))
	tunAd(-75, "☕ CAFÉ · EBENE 2", Color3.fromRGB(255, 215, 94))
	-- Treppenhaeuschen am Parkdeck + Treppenabgang im Terminal (Optik, Client teleportiert)
	for _, ox in ipairs({ -2.1, 2.1 }) do
		mpart(mega, "TunHutWall", 0.2, 3.0, 4.4, -120 + ox, 1.5, 303, COL.glass, { Transparency = 0.5, Material = Enum.Material.Glass })
	end
	mpart(mega, "TunHutBack", 4.4, 3.0, 0.2, -120, 1.5, 300.9, COL.glass, { Transparency = 0.5, Material = Enum.Material.Glass })
	mpart(mega, "TunHutRoof", 4.4, 0.25, 4.4, -120, 3.0, 303, COL.glass, { Transparency = 0.45, Material = Enum.Material.Glass, CanCollide = false })
	local hs = mpart(mega, "TunHutSign", 6, 1.0, 0.14, -120, 3.9, 305.2, Color3.fromRGB(21, 32, 47), { CanCollide = false })
	do
		local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(420, 70); sg.Parent = hs
		local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = Color3.fromRGB(143, 232, 159)
		tl.Text = "⬇ TUNNEL · TERMINAL 1"; tl.Parent = sg
	end
	for _, ox in ipairs({ -1.9, 1.9 }) do
		mpart(mega, "TunStairRail", 0.16, 1.05, 4.2, -66 + ox, 0.55, 284.5, COL.glass, { Transparency = 0.5, Material = Enum.Material.Glass })
	end
	local ts = mpart(mega, "TunStairSign", 6.5, 1.0, 0.14, -66, 2.6, 281.9, Color3.fromRGB(21, 32, 47), { CanCollide = false })
	do
		local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(460, 70); sg.Parent = ts
		local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = Color3.fromRGB(159, 212, 232)
		tl.Text = "⬇ TUNNEL ZUM PARKDECK"; tl.Parent = sg
	end
end)

-- Gepaeck-Sortierkeller unter dem Terminal (Baender, Buchten, Wagen; Client animiert Koffer)
sysInit("Gepaeckkeller", function()
	local KX1, KX2, KZ1, KZ2 = -50, -5, 237, 266
	local kcx, kcz = (KX1 + KX2) / 2, (KZ1 + KZ2) / 2
	local wallC = Color3.fromRGB(185, 191, 199)
	mpart(mega, "KFloor", KX2 - KX1 + 2, 0.3, KZ2 - KZ1 + 2, kcx, -4.77, kcz, Color3.fromRGB(68, 72, 79))
	mpart(mega, "KWallS", KX2 - KX1 + 2, 3.8, 0.3, kcx, -2.7, KZ1 - 0.85, wallC)
	mpart(mega, "KWallN", KX2 - KX1 + 2, 3.8, 0.3, kcx, -2.7, KZ2 + 0.85, wallC)
	mpart(mega, "KWallW", 0.3, 3.8, KZ2 - KZ1 + 2, KX1 - 0.85, -2.7, kcz, wallC)
	mpart(mega, "KWallE", 0.3, 3.8, KZ2 - KZ1 + 2, KX2 + 0.85, -2.7, kcz, wallC)
	mpart(mega, "KCeil", KX2 - KX1 + 2, 0.25, KZ2 - KZ1 + 2, kcx, -1.05, kcz, Color3.fromRGB(127, 135, 144), { CanCollide = false })
	for _, p in ipairs({ { -30, 250 }, { -16, 250 }, { -30, 260 }, { -16, 260 } }) do
		mpart(mega, "KPillar", 0.55, 3.6, 0.55, p[1], -2.8, p[2], Color3.fromRGB(138, 146, 158))
	end
	for lx = KX1 + 6, KX2 - 1, 9 do
		mpart(mega, "KLight", 1.8, 0.06, 1.0, lx, -1.22, 252, Color3.fromRGB(255, 255, 255), { Material = Enum.Material.Neon, CanCollide = false })
		mpart(mega, "KLight", 1.8, 0.06, 1.0, lx, -1.22, 261, Color3.fromRGB(255, 255, 255), { Material = Enum.Material.Neon, CanCollide = false })
	end
	for _, zz in ipairs({ KZ1 - 0.68, KZ2 + 0.68 }) do
		mpart(mega, "KWarn", KX2 - KX1 + 2, 0.4, 0.06, kcx, -4.15, zz, COL.yellow, { CanCollide = false })
	end
	-- Baender: Sammelband, Querband, Steigband aufs Rollfeld-Band
	mpart(mega, "KBelt1", 25, 0.18, 1.7, -33.5, -4.05, 261, Color3.fromRGB(96, 103, 116))
	mpart(mega, "KBelt1T", 25, 0.06, 1.3, -33.5, -3.92, 261, Color3.fromRGB(34, 38, 44), { CanCollide = false })
	mpart(mega, "KBelt2", 1.7, 0.18, 11, -22, -4.05, 255.5, Color3.fromRGB(96, 103, 116))
	mpart(mega, "KBelt2T", 1.3, 0.06, 11, -22, -3.92, 255.5, Color3.fromRGB(34, 38, 44), { CanCollide = false })
	local inc = mpart(mega, "KIncline", 1.7, 0.2, 9.8, -21.6, -1.55, 253.9, Color3.fromRGB(96, 103, 116), { CanCollide = false })
	inc.CFrame = inc.CFrame * CFrame.Angles(-0.58, 0, 0)
	-- Rutschen von den Check-in-Schaltern
	for _, cx in ipairs({ -45, -29, -13 }) do
		local ch = mpart(mega, "KChute", 1.4, 0.14, 4.2, cx, -2.3, 259.6, Color3.fromRGB(154, 164, 176), { CanCollide = false })
		ch.CFrame = ch.CFrame * CFrame.Angles(0.82, 0, 0)
	end
	-- Abzweig zur Gepaeckausgabe
	mpart(mega, "KBelt3", 1.7, 0.18, 6, -44, -4.05, 262.5, Color3.fromRGB(96, 103, 116))
	local up2 = mpart(mega, "KIncline2", 1.7, 0.2, 5.2, -44, -2.6, 264.6, Color3.fromRGB(96, 103, 116), { CanCollide = false })
	up2.CFrame = up2.CFrame * CFrame.Angles(-0.6, 0, 0)
	-- Sortier-Buchten (Farben wie beim Ramp-Job) + Regale + Kofferstapel
	local function kSign(txt, x, y, z, w, fg)
		local s = mpart(mega, "KSign", w, w * 0.16, 0.1, x, y, z, Color3.fromRGB(21, 32, 47), { CanCollide = false })
		local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(w * 60, w * 9.6); sg.Parent = s
		local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = fg; tl.Text = txt; tl.Parent = sg
	end
	local BAYS = {
		{ x = -42, col = Color3.fromRGB(58, 111, 232), paint = Color3.fromRGB(42, 75, 143), name = "LH 452 · MÜNCHEN" },
		{ x = -33, col = Color3.fromRGB(224, 120, 32), paint = Color3.fromRGB(143, 90, 31), name = "EW 771 · WIEN" },
	}
	for _, b in ipairs(BAYS) do
		mpart(mega, "KBay", 7, 0.06, 8, b.x, -4.59, 244, b.paint, { CanCollide = false })
		mpart(mega, "KBayLine", 6.4, 0.14, 0.5, b.x, -4.52, 248.2, b.col, { CanCollide = false })
		kSign(b.name, b.x, -1.7, 240.6, 5.5, b.col)
		mpart(mega, "KRack", 6.4, 1.7, 1.0, b.x, -3.9, 241, Color3.fromRGB(96, 103, 116))
		mpart(mega, "KRackTop", 6.4, 0.1, 1.0, b.x, -3.3, 241, Color3.fromRGB(138, 146, 158), { CanCollide = false })
		for k = 0, 5 do
			mpart(mega, "KBag", 0.78, 0.52, 0.42, b.x - 2.4 + (k % 3) * 2.4, k < 3 and -2.96 or -4.3, k < 3 and 241 or (244.6 + (k - 3) * 0.2), b.col, { CanCollide = false })
		end
	end
	-- Gepaeckwagen-Zuege
	for _, t in ipairs({ { -11, 246, 0.3 }, { -38, 254, -1.4 } }) do
		local mdl = Instance.new("Model"); mdl.Name = "KCart"; mdl.Parent = mega
		local root = mpart(mdl, "Root", 0.3, 0.3, 0.3, 0, 0, 0, Color3.fromRGB(42, 109, 181), { Transparency = 1, CanCollide = false })
		mdl.PrimaryPart = root
		mpart(mdl, "Tug", 1.5, 0.8, 2.2, 0, -4.2, 0, Color3.fromRGB(42, 109, 181))
		for a = 1, 2 do
			mpart(mdl, "Trailer", 1.5, 0.14, 2.0, 0, -4.35, -a * 2.6, Color3.fromRGB(139, 149, 161))
			mpart(mdl, "TBag", 0.9, 0.5, 1.2, 0, -4.05, -a * 2.6, a == 1 and Color3.fromRGB(58, 111, 232) or Color3.fromRGB(224, 120, 32))
		end
		mdl:PivotTo(CFrame.new(t[1] * M, 0, t[2] * M) * CFrame.Angles(0, t[3], 0))
	end
	-- laufende Koffer (Client bewegt sie den Pfad entlang)
	local kb = Instance.new("Folder"); kb.Name = "KellerBags"; kb.Parent = mega
	local bagCols = { Color3.fromRGB(58, 111, 232), Color3.fromRGB(224, 120, 32), Color3.fromRGB(122, 48, 48), Color3.fromRGB(48, 80, 122), Color3.fromRGB(201, 164, 79) }
	for i = 1, 7 do
		mpart(kb, "FlowBag" .. i, 0.78, 0.52, 0.42, -45.5, -3.75, 261, bagCols[1 + (i % #bagCols)], { CanCollide = false })
	end
	kSign("🧳 GEPÄCKSORTIERUNG · NUR PERSONAL", kcx, -1.6, KZ1 - 0.6, 10, Color3.fromRGB(255, 215, 94))
	kSign("⬆ ROLLFELD · GEPÄCKBAND", -21.6, -1.5, 249.9, 6.5, Color3.fromRGB(255, 215, 94))
	kSign("⬆ GEPÄCKAUSGABE 1", -44, -1.5, 262.4, 5.5, Color3.fromRGB(159, 212, 232))
	-- Personal-Treppe im EG (Optik; Client teleportiert)
	for _, ox in ipairs({ -1.7, 1.7 }) do
		mpart(mega, "KStairRail", 0.16, 1.05, 3.8, -52 + ox, 0.55, 236.5, COL.glass, { Transparency = 0.5, Material = Enum.Material.Glass })
	end
	kSign("⬇ GEPÄCKKELLER · PERSONAL", -52, 2.4, 234.2, 6.5, Color3.fromRGB(255, 215, 94))
end)

---------------------------------------------------------------- Design-Upgrade: Bogendach, Totem, Flutlicht, Zaun, Radar, Stand-Nummern, ILS
local design = Instance.new("Folder"); design.Name = "RealDesign"; design.Parent = airport
-- Gewoelbtes Terminaldach (Halbellipse aus 10 Segmenten)
sysInit("Bogendach", function()
	local cz, a, b, N = (T.z1 + T.z2) / 2, 36, 13, 10
	local w = T.x2 - T.x1 + 8
	for i = 0, N - 1 do
		local t1, t2 = math.pi * i / N, math.pi * (i + 1) / N
		local sz1, sy1 = cz - a * math.cos(t1), T.h + b * math.sin(t1)
		local sz2, sy2 = cz - a * math.cos(t2), T.h + b * math.sin(t2)
		local len = math.sqrt((sz2 - sz1) ^ 2 + (sy2 - sy1) ^ 2)
		local seg = mpart(design, "Vault", w, 0.35, len + 0.4, (T.x1 + T.x2) / 2, (sy1 + sy2) / 2, (sz1 + sz2) / 2,
			Color3.fromRGB(190, 199, 209), { CanCollide = false })
		seg.CFrame = seg.CFrame * CFrame.Angles(-math.atan2(sy2 - sy1, sz2 - sz1), 0, 0)
	end
end)
-- Flughafen-Totem an der Vorfahrt
sysInit("Totem", function()
	mpart(design, "TotemPylon", 3.0, 15, 1.2, 22, 7.5, 344, Color3.fromRGB(36, 55, 74))
	mpart(design, "TotemBand", 3.2, 0.6, 1.3, 22, 12.2, 344, Color3.fromRGB(255, 215, 94), { Material = Enum.Material.Neon, CanCollide = false })
	local bar = mpart(design, "TotemBar", 19, 3.0, 1.0, 22, 16.5, 344, Color3.fromRGB(21, 32, 47))
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui"); sg.Face = face; sg.CanvasSize = Vector2.new(950, 150); sg.Parent = bar
		local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = Color3.fromRGB(232, 238, 247)
		tl.Text = "FLUGHAFEN INTERNATIONAL"; tl.Parent = sg
	end
end)
-- Flutlichtmasten am Vorfeld
for _, fx in ipairs({ -85, 0, 85, 165, 240 }) do
	mpart(design, "FloodPole", 0.7, 19, 0.7, fx, 9.5, 146, Color3.fromRGB(138, 146, 158))
	mpart(design, "FloodBar", 4.2, 0.5, 0.4, fx, 18.6, 146, Color3.fromRGB(102, 110, 120), { CanCollide = false })
	for i = 0, 3 do
		mpart(design, "FloodLamp", 0.8, 0.55, 0.25, fx - 1.5 + i, 18.2, 146.4, Color3.fromRGB(255, 242, 204), { Material = Enum.Material.Neon, CanCollide = false })
	end
end
-- Umzaeunung des Flugfelds (mit Tor-Luecke an der Zufahrt)
sysInit("Zaun", function()
	local FX1, FX2, FZ1, FZ2, STEP = -1150, 1150, -640, 386, 30
	local pc = Color3.fromRGB(122, 130, 140)
	for x = FX1, FX2, STEP do
		mpart(design, "FencePost", 0.14, 2.3, 0.14, x, 1.15, FZ1, pc, { CanCollide = false })
		if math.abs(x) > 16 then
			mpart(design, "FencePost", 0.14, 2.3, 0.14, x, 1.15, FZ2, pc, { CanCollide = false })
		end
	end
	for z = FZ1 + STEP, FZ2 - 1, STEP do
		mpart(design, "FencePost", 0.14, 2.3, 0.14, FX1, 1.15, z, pc, { CanCollide = false })
		mpart(design, "FencePost", 0.14, 2.3, 0.14, FX2, 1.15, z, pc, { CanCollide = false })
	end
	local rc = Color3.fromRGB(154, 163, 173)
	for _, ry in ipairs({ 0.95, 1.85 }) do
		tiled(design, "FenceRail", FX2 - FX1, 0.07, 0.06, 0, ry, FZ1, rc, { CanCollide = false })
		tiled(design, "FenceRail", (-16) - FX1, 0.07, 0.06, (FX1 - 16) / 2, ry, FZ2, rc, { CanCollide = false })
		tiled(design, "FenceRail", FX2 - 16, 0.07, 0.06, (FX2 + 16) / 2, ry, FZ2, rc, { CanCollide = false })
		tiled(design, "FenceRail", 0.06, 0.07, FZ2 - FZ1, FX1, ry, (FZ1 + FZ2) / 2, rc, { CanCollide = false })
		tiled(design, "FenceRail", 0.06, 0.07, FZ2 - FZ1, FX2, ry, (FZ1 + FZ2) / 2, rc, { CanCollide = false })
	end
end)
-- Drehendes Rundsicht-Radar auf dem Tower (Client animiert)
sysInit("Radar", function()
	local radar = Instance.new("Model"); radar.Name = "Radar"; radar.Parent = design
	local ped = mpart(radar, "Ped", 0.7, 1.4, 0.7, -127.2, 31.0, 250, Color3.fromRGB(138, 146, 158), { CanCollide = false })
	radar.PrimaryPart = ped
	local dish = mpart(radar, "Dish", 4.6, 1.0, 0.14, -127.2, 32.2, 250, Color3.fromRGB(232, 236, 240), { CanCollide = false })
	dish.CFrame = dish.CFrame * CFrame.Angles(-0.35, 0, 0)
end)
-- Gemalte Stand-Nummern auf dem Vorfeld
for i, px in ipairs({ -130, -40, 40, 130, 200 }) do
	local sp = mpart(design, "StandNum", 4.6, 0.12, 4.6, px, 0.32, 190, Color3.fromRGB(58, 63, 70), { CanCollide = false })
	local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Top; sg.CanvasSize = Vector2.new(200, 200); sg.Parent = sp
	local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
	tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = Color3.fromRGB(255, 215, 94); tl.Text = tostring(i); tl.Parent = sg
end
-- ILS: Localizer-Antennenreihen hinter der Anflugbefeuerung + Gleitpfad-Mast
sysInit("ILS", function()
	local rcol = Color3.fromRGB(194, 59, 46)
	for _, ax in ipairs({ -980, 980 }) do
		for k = 0, 14 do
			mpart(design, "ILSel", 0.14, 2.4, 0.14, ax, 1.2, -15.4 + k * 2.2, rcol, { CanCollide = false })
		end
		mpart(design, "ILSbeam", 0.18, 0.14, 33, ax, 2.35, 0, COL.white, { CanCollide = false })
	end
	mpart(design, "GPmast", 0.4, 12, 0.4, -560, 6, 36, rcol)
	mpart(design, "GPant", 2.6, 0.5, 0.3, -559, 8.6, 36, COL.white, { CanCollide = false })
	mpart(design, "GPant2", 2.6, 0.5, 0.3, -559, 5.4, 36, COL.white, { CanCollide = false })
end)

---------------------------------------------------------------- Spawn im Terminal
local spawnLoc = Instance.new("SpawnLocation")
spawnLoc.Name = "Spawn"
spawnLoc.Size = Vector3.new(24, 1, 24) -- Platz fuer mehrere Spieler
spawnLoc.CFrame = CFrame.new(-30 * M, 0.5, 268 * M)
spawnLoc.Anchored = true
spawnLoc.Neutral = true
spawnLoc.Transparency = 1
spawnLoc.Parent = airport

print("[Airport] Flughafen aufgebaut. Skalierung: 1 m = " .. M .. " Studs.")
