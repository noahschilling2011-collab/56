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

---------------------------------------------------------------- Deko-Jets
local function makeJet(name, color, x, z, yawDeg)
	local m = Instance.new("Model"); m.Name = name
	local root = mpart(m, "Root", 1, 1, 1, 0, 0, 0, color, { Transparency = 1, CanCollide = false })
	m.PrimaryPart = root
	-- Zylinderachse liegt in Roblox auf X -> Laenge in X, dann um 90 Grad drehen
	local fus = mpart(m, "Fus", 26, 3.8, 3.8, 0, 3.2, 0, COL.cream)
	fus.Shape = Enum.PartType.Cylinder
	fus.CFrame = CFrame.new(0, 3.2 * M, 0) * CFrame.Angles(0, math.rad(90), 0)
	local nose = mpart(m, "Nose", 3.8, 3.8, 3.8, 0, 3.2, -13, COL.cream); nose.Shape = Enum.PartType.Ball
	mpart(m, "Tailc", 1.6, 1.6, 5, 0, 3.9, 15.5, COL.cream)
	mpart(m, "Wing", 24, 0.35, 4.5, 0, 2.9, 0.5, color)
	mpart(m, "HStab", 9, 0.25, 2.6, 0, 4.4, 17, color)
	mpart(m, "VStab", 0.3, 5.5, 3.4, 0, 6.5, 17.5, color)
	for _, sx in ipairs({ -1, 1 }) do
		local e = mpart(m, "Eng", 2.1, 2.1, 3.2, sx * 6.5, 1.9, -1.5, Color3.fromRGB(154, 160, 168))
	end
	for _, g in ipairs({ { 0, -10 }, { -2.5, 1 }, { 2.5, 1 } }) do
		mpart(m, "Gear", 0.4, 1.6, 0.4, g[1], 0.8, g[2], Color3.fromRGB(40, 40, 40))
	end
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

---------------------------------------------------------------- Spieler-Propellerflugzeug
local plane = Instance.new("Model"); plane.Name = "PlayerPlane"; plane.Parent = airport
local proot = mpart(plane, "Root", 1, 1, 1, 0, 0, 0, COL.cream, { Transparency = 1, CanCollide = false })
plane.PrimaryPart = proot
local function pp(name, sx, sy, sz, x, y, z, color, props)
	return mpart(plane, name, sx, sy, sz, x, y, z, color, props)
end
pp("Fus", 1.3, 1.3, 5.6, 0, 1.35, 0.3, COL.cream)
pp("Cowl", 1.2, 1.2, 1.1, 0, 1.35, -2.9, COL.red)
pp("Tailcone", 0.7, 0.7, 2.2, 0, 1.5, 4.0, COL.cream, { CanCollide = false })
pp("Canopy", 0.9, 0.62, 1.5, 0, 2.05, -0.7, COL.glass, { Transparency = 0.45, CanCollide = false })
pp("Prop1", 0.16, 2.3, 0.1, 0, 1.35, -3.5, COL.dark, { CanCollide = false })
pp("Prop2", 2.3, 0.16, 0.1, 0, 1.35, -3.5, COL.dark, { CanCollide = false })
pp("Wing", 10.4, 0.16, 1.6, 0, 1.9, -0.4, COL.cream)
pp("WingStripe", 10.4, 0.06, 0.3, 0, 2.0, -1.1, COL.red, { CanCollide = false })
pp("AilL", 1.9, 0.1, 0.5, -4.2, 1.9, 0.55, COL.red, { CanCollide = false })
pp("AilR", 1.9, 0.1, 0.5, 4.2, 1.9, 0.55, COL.red, { CanCollide = false })
pp("HStab", 3.6, 0.12, 1.0, 0, 1.7, 4.7, COL.cream, { CanCollide = false })
pp("Elev", 3.6, 0.09, 0.5, 0, 1.7, 5.4, COL.red, { CanCollide = false })
pp("VStab", 0.12, 1.8, 1.2, 0, 2.6, 4.7, COL.cream, { CanCollide = false })
pp("Rud", 0.1, 1.6, 0.6, 0, 2.7, 5.6, COL.red, { CanCollide = false })
for _, g in ipairs({ { "GearN", 0, -2.4 }, { "GearL", -1.3, 0.3 }, { "GearR", 1.3, 0.3 } }) do
	pp(g[1], 0.14, 0.9, 0.14, g[2], 0.7, g[3], COL.dark, { CanCollide = false })
	pp(g[1] .. "W", 0.6, 0.22, 0.6, g[2], 0.28, g[3], Color3.fromRGB(22, 24, 28), { CanCollide = false })
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
