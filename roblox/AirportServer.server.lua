--[[
	FLUGHAFEN-JOB-SIMULATOR · Server
	Baut den kompletten Flughafen beim Start auf (keine externen Assets).
	Masseinheit: 1 m = 2 Studs (Skalierungsfaktor M).
	Norden = -Z, Osten = +X. Runway 09/27 entlang der X-Achse.

	Die gesamte Spiellogik (Jobs, Flugphysik, HUD) laeuft im LocalScript
	"AirportClient" in StarterPlayerScripts — ausgelegt auf Solo-Play.
]]

local M = 2 -- Meter -> Studs

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

-- Alte Version entfernen (bei Re-Run in Studio)
local old = Workspace:FindFirstChild("Airport")
if old then old:Destroy() end

local airport = Instance.new("Folder")
airport.Name = "Airport"
airport.Parent = Workspace

-- Atmosphaere / Fog
Lighting.ClockTime = 13
Lighting.FogColor = Color3.fromRGB(168, 207, 232)
Lighting.FogStart = 1400 * M
Lighting.FogEnd = 2800 * M
Lighting.Brightness = 2

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

---------------------------------------------------------------- Boden
-- Roblox kappt Part-Groessen bei 2048 Studs pro Achse -> grosse Flaechen kacheln!
-- Kachel-Helfer: teilt sx/sz in Stuecke von maximal 1000 m (= 2000 Studs)
local function tiled(parent, name, sx, sy, sz, x, y, z, color, props)
	local MAXM = 1000
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
tiled(airport, "Taxiway", RWY_L + 40, 0.35, 16, 0, 0.02, 80, COL.taxi)
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
mpart(airport, "Apron", 320, 0.35, 95, 45, 0.02, 182, COL.apron, { Material = Enum.Material.Concrete })
for _, px in ipairs({ -40, 40, 130 }) do
	mpart(airport, "Stand", 0.6, 0.1, 22, px, 0.3, 176, COL.yellow, { CanCollide = false })
	mpart(airport, "Stand", 14, 0.1, 0.6, px, 0.3, 165, COL.yellow, { CanCollide = false })
end

---------------------------------------------------------------- Deko-Jets: Airbus A380 (Doppeldecker, 4 Triebwerke)
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
			mpart(m, "Pylon", 0.4, 1.5, 2.6, sx * e[1], 2.8, e[2] + 1.2, COL.cream, { CanCollide = false })
		end
	end
	-- Leitwerk
	local fin = mpart(m, "Fin", 0.5, 9.5, 5.5, 0, 9.0, 19.8, color, { CanCollide = false })
	fin.CFrame = CFrame.new(0, 9.0 * M, 19.8 * M) * CFrame.Angles(-0.32, 0, 0)
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
makeJet("JetA", COL.blue, -40, 165, 0)   -- LH 452 · BLAU
makeJet("JetB", COL.orange, 40, 165, 0)  -- EW 771 · ORANGE
local trafficJet = makeJet("TrafficJet", Color3.fromRGB(153, 153, 153), 0, -4000, 0) -- Deko-Verkehr (Client animiert)

---------------------------------------------------------------- Terminal (x -70..75, z 232..302)
local T = { x1 = -70, x2 = 75, z1 = 232, z2 = 302, h = 11 }
local term = Instance.new("Model"); term.Name = "Terminal"; term.Parent = airport
mpart(term, "Floor", T.x2 - T.x1, 0.5, T.z2 - T.z1, (T.x1 + T.x2) / 2, 0.15, (T.z1 + T.z2) / 2, Color3.fromRGB(185, 190, 199))
mpart(term, "Roof", T.x2 - T.x1 + 4, 0.7, T.z2 - T.z1 + 4, (T.x1 + T.x2) / 2, T.h, (T.z1 + T.z2) / 2, Color3.fromRGB(138, 146, 158))
local function wallSeg(nm, x1, x2, z, color, transp)
	mpart(term, nm, x2 - x1, T.h, 0.6, (x1 + x2) / 2, T.h / 2, z, color,
		transp and { Transparency = 0.6, Material = Enum.Material.Glass } or nil)
end
-- Glasfront Nord (zum Vorfeld), Tuer bei x 28..36
wallSeg("GlassW", T.x1, 28, T.z1, COL.glass, true)
wallSeg("GlassE", 36, T.x2, T.z1, COL.glass, true)
-- Suedwand mit Eingang bei x -8..0
wallSeg("BackW", T.x1, -8, T.z2, COL.wall)
wallSeg("BackE", 0, T.x2, T.z2, COL.wall)
mpart(term, "SideW", 0.6, T.h, T.z2 - T.z1, T.x1, T.h / 2, (T.z1 + T.z2) / 2, COL.wall)
mpart(term, "SideE", 0.6, T.h, T.z2 - T.z1, T.x2, T.h / 2, (T.z1 + T.z2) / 2, COL.wall)
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
-- Gate-Sitzreihen
for r = 0, 3 do
	for c = 0, 9 do
		mpart(term, "Seat", 1.6, 0.9, 1.4, 18 + c * 3.2, 0.45, 244 + r * 4.5, Color3.fromRGB(61, 90, 128))
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
boardLine("FLUG    ZIEL          ZEIT   STATUS", 55, Color3.fromRGB(127, 150, 173), 22)
local FLIGHTS = {
	{ "LH 452", "MÜNCHEN", "14:20", "OPEN" },
	{ "AB 118", "BERLIN", "14:35", "BOARDING" },
	{ "EW 771", "WIEN", "14:50", "OPEN" },
	{ "FR 903", "PARIS", "15:05", "CLOSED" },
	{ "KL 233", "AMSTERDAM", "15:20", "OPEN" },
	{ "SK 660", "OSLO", "15:40", "CLOSED" },
}
-- Umlaut-sichere Spaltenbreite (utf8.len statt Byte-Laenge)
local function pad(s, n)
	local len = utf8.len(s) or #s
	return s .. string.rep(" ", math.max(0, n - len))
end
for i, f in ipairs(FLIGHTS) do
	local col = f[4] == "OPEN" and Color3.fromRGB(84, 208, 106) or f[4] == "BOARDING" and Color3.fromRGB(255, 215, 94) or Color3.fromRGB(255, 99, 99)
	boardLine(pad(f[1], 8) .. pad(f[2], 14) .. f[3], 60 + i * 38, Color3.fromRGB(232, 238, 247), 22)
	local st = boardLine(f[4], 60 + i * 38, col, 22)
	st.Position = UDim2.new(0, 470, 0, 60 + i * 38)
end

---------------------------------------------------------------- Gepaeckband Terminal -> Vorfeld
local belt = Instance.new("Model"); belt.Name = "Belt"; belt.Parent = airport
mpart(belt, "BeltBody", 3, 0.9, 64, -20, 0.45, 226, COL.dark)
mpart(belt, "BeltTop", 3.4, 0.2, 64.4, -20, 0.95, 226, Color3.fromRGB(28, 30, 36))
mpart(belt, "BeltEndT", 3.6, 1.6, 1.2, -20, 0.8, 257, Color3.fromRGB(96, 103, 116))
mpart(belt, "BeltEndA", 3.6, 1.6, 1.2, -20, 0.8, 195, Color3.fromRGB(96, 103, 116))

---------------------------------------------------------------- Gepaeckwagen
local cart = Instance.new("Model"); cart.Name = "Cart"; cart.Parent = airport
local croot = mpart(cart, "Root", 1, 1, 1, 0, 0, 0, COL.dark, { Transparency = 1, CanCollide = false })
cart.PrimaryPart = croot
mpart(cart, "Chassis", 2.4, 0.5, 5.2, 0, 0.65, 0, Color3.fromRGB(42, 109, 181))
mpart(cart, "Cab", 2.2, 1.5, 1.6, 0, 1.6, 1.6, Color3.fromRGB(42, 109, 181))
mpart(cart, "Windshield", 2, 0.7, 0.15, 0, 2.0, 0.85, COL.glass, { Transparency = 0.5, CanCollide = false })
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
pp("GlassBand", 1.17, 0.5, 1.7, 0, 1.95, -0.15, COL.glass, { Transparency = 0.45, CanCollide = false })
pp("Windshield", 1.1, 0.62, 0.12, 0, 1.95, -1.15, COL.glass, { Transparency = 0.45, CanCollide = false })
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
mpart(tower, "CabGlass", 9.4, 2.4, 9.4, -130, 28.4, 250, COL.glass, { Transparency = 0.5, CanCollide = false })
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
marker("MarkerPlane", 124, 172, Color3.fromRGB(143, 232, 159))

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
mpart(deco2, "RedLine", 300, 0.1, 0.35, 45, 0.3, 141, Color3.fromRGB(176, 48, 48), { CanCollide = false })
for i, px in ipairs({ -40, 40, 130 }) do
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
gse("FuelTruck", -72, 190, 0.5, function(m)
	mpart(m, "Body", 2.4, 1.1, 6.4, 0, 1.0, 0, Color3.fromRGB(217, 210, 196))
	mpart(m, "Tank", 2.0, 2.0, 4.6, 0, 1.9, 0.6, Color3.fromRGB(202, 194, 178))
	mpart(m, "Cab", 2.2, 1.3, 1.6, 0, 1.1, -3.1, Color3.fromRGB(143, 47, 36))
end)
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
gse("Kiosk", 62, 282, 0, function(m)
	mpart(m, "Body", 7, 2.6, 4, 0, 1.3, 0, Color3.fromRGB(106, 74, 54))
	mpart(m, "Roof", 7.4, 0.3, 4.4, 0, 2.75, 0, Color3.fromRGB(74, 52, 38))
	mpart(m, "Theke", 6, 1.0, 0.7, 0, 0.5, -2.0, Color3.fromRGB(138, 95, 69))
	local ks = mpart(m, "Schild", 5, 1, 0.12, 0, 2.2, -2.06, Color3.fromRGB(58, 42, 30), { CanCollide = false })
	local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(500, 100); sg.Parent = ks
	local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
	tl.Font = Enum.Font.GothamBold; tl.TextScaled = true; tl.TextColor3 = Color3.fromRGB(255, 215, 94); tl.Text = "CAFÉ · SNACKS"; tl.Parent = sg
end)
for _, p in ipairs({ { -62, 240 }, { -62, 290 }, { 8, 238 }, { 70, 250 }, { 12, 296 } }) do
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
local carCols = { Color3.fromRGB(184, 184, 184), Color3.fromRGB(47, 58, 74), Color3.fromRGB(143, 47, 36), Color3.fromRGB(58, 111, 176), Color3.fromRGB(63, 63, 63) }
for x = -54.5, 40, 7 do
	if math.random() > 0.3 then
		mpart(deco2, "Car", 2.2, 0.9, 4.4, x, 0.6, 309.5, carCols[math.random(#carCols)])
		mpart(deco2, "CarCab", 1.9, 0.7, 2.2, x, 1.35, 309.9, Color3.fromRGB(34, 40, 49), { CanCollide = false })
	end
end
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
do
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
end

---------------------------------------------------------------- Spawn im Terminal
local spawnLoc = Instance.new("SpawnLocation")
spawnLoc.Name = "Spawn"
spawnLoc.Size = Vector3.new(6, 1, 6)
spawnLoc.CFrame = CFrame.new(-30 * M, 0.5, 268 * M)
spawnLoc.Anchored = true
spawnLoc.Neutral = true
spawnLoc.Transparency = 1
spawnLoc.Parent = airport

print("[Airport] Flughafen aufgebaut. Skalierung: 1 m = " .. M .. " Studs.")
