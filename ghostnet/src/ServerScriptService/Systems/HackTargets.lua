-- ServerScriptService/Systems/HackTargets.lua
--!strict
-- GHOSTNET :: Registry aller hackbaren Objekte.
--
-- Ein Hack-Ziel ist NUR ein BasePart mit dem Tag "GhostNetHackable".
-- Alle Eigenschaften kommen aus Attributen, fehlende aus Config.TargetDefaults.
-- Ein neues Ziel = neuer Part + Tag. Kein Code.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

type HackTarget = Types.HackTarget

local HackTargets = {}

local registry: { [string]: HackTarget } = {}
local byPart: { [BasePart]: HackTarget } = {}
local idCounter = 0

-- cooldowns[player][targetId] = os.clock()-Zeitpunkt, ab dem wieder erlaubt
local cooldowns: { [Player]: { [string]: number } } = {}

--==========================================================================
-- Attribute lesen
--==========================================================================

local function attrNumber(part: BasePart, name: string, default: number): number
	local v = part:GetAttribute(name)
	if typeof(v) == "number" then
		return v
	end
	return default
end

local function attrString(part: BasePart, name: string, default: string): string
	local v = part:GetAttribute(name)
	if typeof(v) == "string" and v ~= "" then
		return v
	end
	return default
end

local function readTarget(part: BasePart, id: string): HackTarget
	local d = Config.TargetDefaults

	local difficulty = math.clamp(math.floor(attrNumber(part, "Difficulty", d.Difficulty)), 1, 10)

	local reward = attrNumber(part, "Reward", d.Reward)
	if reward < 0 then
		reward = Config.GetReward(difficulty)
	end

	local traceGain = attrNumber(part, "TraceGain", d.TraceGain)
	if traceGain < 0 then
		traceGain = difficulty * Config.Trace.GainPerDifficulty
	end

	local cooldown = attrNumber(part, "Cooldown", d.Cooldown)
	if cooldown < 0 then
		cooldown = Config.Cooldown.Default
	end

	local displayName = attrString(part, "DisplayName", d.DisplayName)
	if displayName == "" then
		displayName = part.Name
	end

	local existing = registry[id]
	return {
		Id = id,
		Part = part,
		DisplayName = displayName,
		Difficulty = difficulty,
		HackType = attrString(part, "HackType", d.HackType),
		Reward = math.floor(reward),
		TraceGain = traceGain,
		Cooldown = cooldown,
		RequiredLevel = math.max(1, math.floor(attrNumber(part, "RequiredLevel", d.RequiredLevel))),
		OnSuccess = attrString(part, "OnSuccess", d.OnSuccess),
		DownTime = attrNumber(part, "DownTime", d.DownTime),
		DownUntil = existing and existing.DownUntil or 0,
	}
end

--==========================================================================
-- Registrierung
--==========================================================================

local function register(inst: Instance)
	if not inst:IsA("BasePart") then
		warn(("[GHOSTNET] '%s' hat den Hackable-Tag, ist aber kein BasePart."):format(inst:GetFullName()))
		return
	end
	local part = inst :: BasePart
	if byPart[part] then
		return
	end

	-- Stabile Id: bereits vergebene wiederverwenden, sonst neu.
	local id = part:GetAttribute("TargetId")
	if typeof(id) ~= "string" or id == "" or registry[id :: string] then
		idCounter += 1
		id = ("T%04d"):format(idCounter)
		part:SetAttribute("TargetId", id)
	end

	local target = readTarget(part, id :: string)
	registry[id :: string] = target
	byPart[part] = target

	-- Live-Tuning im Studio: Attribut aendern -> sofort uebernommen.
	part.AttributeChanged:Connect(function(attribute: string)
		if attribute == "TargetId" then
			return
		end
		local current = byPart[part]
		if current then
			local refreshed = readTarget(part, current.Id)
			registry[current.Id] = refreshed
			byPart[part] = refreshed
		end
	end)
end

local function unregister(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local part = inst :: BasePart
	local target = byPart[part]
	if target then
		registry[target.Id] = nil
		byPart[part] = nil
	end
end

function HackTargets.Init()
	for _, inst in CollectionService:GetTagged(Config.HackableTag) do
		register(inst)
	end
	CollectionService:GetInstanceAddedSignal(Config.HackableTag):Connect(register)
	CollectionService:GetInstanceRemovedSignal(Config.HackableTag):Connect(unregister)

	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player] = nil
	end)

	print(("[GHOSTNET] HackTargets: %d Ziele registriert."):format(HackTargets.Count()))
end

function HackTargets.Count(): number
	local n = 0
	for _ in registry do
		n += 1
	end
	return n
end

function HackTargets.Get(id: string): HackTarget?
	return registry[id]
end

function HackTargets.All(): { [string]: HackTarget }
	return registry
end

--==========================================================================
-- Distanz
--==========================================================================

-- Abstand zur Oberflaeche des Parts, nicht zum Mittelpunkt. Sonst waeren
-- grosse Objekte (Tueren, Werbetafeln) unfair weit weg.
function HackTargets.DistanceTo(target: HackTarget, position: Vector3): number
	local part = target.Part
	if not part.Parent then
		return math.huge
	end
	local rel = part.CFrame:PointToObjectSpace(position)
	local half = part.Size * 0.5
	local clamped = Vector3.new(
		math.clamp(rel.X, -half.X, half.X),
		math.clamp(rel.Y, -half.Y, half.Y),
		math.clamp(rel.Z, -half.Z, half.Z)
	)
	return (rel - clamped).Magnitude
end

-- Liefert Distanz oder nil, wenn der Spieler gerade keinen lebenden Character hat.
function HackTargets.DistanceFromPlayer(target: HackTarget, player: Player): number?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return HackTargets.DistanceTo(target, root.Position)
end

--==========================================================================
-- Cooldowns (Phase 1 im Speicher, Phase 2 im Profil)
--==========================================================================

function HackTargets.CooldownLeft(player: Player, id: string): number
	local perPlayer = cooldowns[player]
	if not perPlayer then
		return 0
	end
	local until_ = perPlayer[id]
	if not until_ then
		return 0
	end
	return math.max(0, until_ - os.clock())
end

function HackTargets.SetCooldown(player: Player, id: string, seconds: number)
	local perPlayer = cooldowns[player]
	if not perPlayer then
		perPlayer = {}
		cooldowns[player] = perPlayer
	end
	perPlayer[id] = os.clock() + seconds
end

--==========================================================================
-- "Down"-Zustand (Kamera aus, Tuer offen, ...)
--==========================================================================

function HackTargets.IsDown(target: HackTarget): boolean
	return target.DownUntil > os.clock()
end

function HackTargets.MarkDown(target: HackTarget, seconds: number)
	target.DownUntil = os.clock() + seconds
	target.Part:SetAttribute("Offline", true)
	task.delay(seconds, function()
		if target.DownUntil <= os.clock() and target.Part.Parent then
			target.Part:SetAttribute("Offline", false)
		end
	end)
end

return HackTargets
