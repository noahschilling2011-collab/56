-- ServerScriptService/World/TestTargets.server.lua
--!strict
-- GHOSTNET :: Drei Testobjekte fuer Phase 1.
--
-- Wichtig fuer das Gesamtbild: In diesem Skript steht KEINE Hack-Logik.
-- Es baut Parts und setzt Attribute. Genau so entstehen spaeter auch alle
-- echten Ziele in der Stadt - per Hand im Studio oder per Generator.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local FOLDER_NAME = "GhostNet_TestTargets"

if workspace:FindFirstChild(FOLDER_NAME) then
	return -- schon gebaut (z.B. nach einem Studio-Reload)
end

local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = workspace

type PartProps = {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material?,
	Transparency: number?,
	CanCollide: boolean?,
	Parent: Instance?,
}

local function makePart(props: PartProps): Part
	local p = Instance.new("Part")
	p.Name = props.Name
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Transparency = props.Transparency or 0
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = props.Parent or folder
	return p
end

-- Macht aus einem beliebigen Part ein Hack-Ziel. Nur Attribute, sonst nichts.
local function makeHackable(part: BasePart, attributes: { [string]: any })
	for key, value in attributes do
		part:SetAttribute(key, value)
	end
	part:SetAttribute("Offline", false)
	CollectionService:AddTag(part, Config.HackableTag)
end

local function accentLight(part: BasePart, color: Color3, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 2
	light.Range = range
	light.Parent = part
end

--==========================================================================
-- 1) UEBERWACHUNGSKAMERA  -  Schwierigkeit 2
--==========================================================================
do
	local base = Vector3.new(-24, 0, -26)

	makePart({
		Name = "KameraMast",
		Size = Vector3.new(0.8, 12, 0.8),
		CFrame = CFrame.new(base + Vector3.new(0, 6, 0)),
		Color = Color3.fromRGB(38, 44, 54),
		Material = Enum.Material.Metal,
	})

	makePart({
		Name = "KameraArm",
		Size = Vector3.new(3.4, 0.5, 0.5),
		CFrame = CFrame.new(base + Vector3.new(1.7, 11.6, 0)),
		Color = Color3.fromRGB(38, 44, 54),
		Material = Enum.Material.Metal,
	})

	local head = makePart({
		Name = "Ueberwachungskamera",
		Size = Vector3.new(1.6, 1.6, 3.2),
		CFrame = CFrame.new(base + Vector3.new(3.4, 11.2, 0)) * CFrame.Angles(math.rad(-15), 0, 0),
		Color = Color3.fromRGB(24, 30, 38),
		Material = Enum.Material.Metal,
	})
	accentLight(head, Config.Theme.Magenta, 14)

	makeHackable(head, {
		DisplayName = "CAM-07 // Kreuzung Nord",
		Difficulty = 2,
		HackType = "NodeBreach",
		RequiredLevel = 1,
		OnSuccess = "CameraOffline",
		DownTime = 30,
	})
end

--==========================================================================
-- 2) SICHERHEITSTUER  -  Schwierigkeit 4
--==========================================================================
do
	local base = Vector3.new(0, 0, -38)

	makePart({
		Name = "WandLinks",
		Size = Vector3.new(10, 12, 1.2),
		CFrame = CFrame.new(base + Vector3.new(-8, 6, 0)),
		Color = Color3.fromRGB(30, 34, 42),
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "WandRechts",
		Size = Vector3.new(10, 12, 1.2),
		CFrame = CFrame.new(base + Vector3.new(8, 6, 0)),
		Color = Color3.fromRGB(30, 34, 42),
		Material = Enum.Material.Concrete,
	})
	makePart({
		Name = "Sturz",
		Size = Vector3.new(6, 2, 1.2),
		CFrame = CFrame.new(base + Vector3.new(0, 11, 0)),
		Color = Color3.fromRGB(30, 34, 42),
		Material = Enum.Material.Concrete,
	})

	local door = makePart({
		Name = "Sicherheitstuer",
		Size = Vector3.new(6, 10, 0.8),
		CFrame = CFrame.new(base + Vector3.new(0, 5, 0)),
		Color = Color3.fromRGB(20, 26, 34),
		Material = Enum.Material.Metal,
	})
	accentLight(door, Config.Theme.Cyan, 12)

	makeHackable(door, {
		DisplayName = "SEC-DOOR // Lagerhalle B",
		Difficulty = 4,
		HackType = "NodeBreach",
		RequiredLevel = 1,
		OnSuccess = "DoorOpen",
		DownTime = 12,
	})
end

--==========================================================================
-- 3) GELDAUTOMAT  -  Schwierigkeit 6
--==========================================================================
do
	local base = Vector3.new(24, 0, -26)

	makePart({
		Name = "AutomatSockel",
		Size = Vector3.new(5, 1, 3),
		CFrame = CFrame.new(base + Vector3.new(0, 0.5, 0)),
		Color = Color3.fromRGB(26, 30, 38),
		Material = Enum.Material.Concrete,
	})

	local atm = makePart({
		Name = "Geldautomat",
		Size = Vector3.new(4.4, 7, 2.4),
		CFrame = CFrame.new(base + Vector3.new(0, 4.5, 0)),
		Color = Color3.fromRGB(34, 40, 50),
		Material = Enum.Material.Metal,
	})

	makePart({
		Name = "AutomatDisplay",
		Size = Vector3.new(3, 2.2, 0.2),
		CFrame = CFrame.new(base + Vector3.new(0, 5.6, 1.25)),
		Color = Config.Theme.Cyan,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	accentLight(atm, Config.Theme.Cyan, 16)

	makeHackable(atm, {
		DisplayName = "ATM // Nakamura Bank",
		Difficulty = 6,
		HackType = "NodeBreach",
		RequiredLevel = 1,
		OnSuccess = "AtmPayout",
		Cooldown = 300,
		DownTime = 20,
	})
end

print("[GHOSTNET] Testobjekte gebaut: Kamera (D2), Sicherheitstuer (D4), Geldautomat (D6).")
