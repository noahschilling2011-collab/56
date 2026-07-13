-- AdminService · Admin-Rechte fuer den Spielbesitzer.
-- WER ist Admin? (1) Der Creator des Spiels (dein Account), (2) jeder im
-- Studio (zum Testen), (3) UserIds aus ADMIN_IDS unten (Freunde eintragen!).
-- Alle Befehle werden SERVERSEITIG geprueft — ein normaler Spieler, der das
-- Remote feuert, bekommt nur eine Warnung im Output.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local Admin = {}

-- Hier zusaetzliche Admins eintragen, z. B. [123456789] = true,
local ADMIN_IDS = {
}

local adminEv = Instance.new("RemoteEvent"); adminEv.Name = "AdminCmd"; adminEv.Parent = RS

local god = {} -- [pl] = true: Zonen-Bypass aktiv (Schalter im Panel, Standard AUS)
local inv, flights
local M = 3.4

-- Teleport-Ziele in Metern (y = Bodenhoehe)
local TELEPORTS = {
	terminal = { -30, 0.5, 268 },
	vorfeld = { 32, 0.5, 210 },
	gate1 = { -130, 0.5, 200 },
	keller = { -25, -4.6, 255 },
	tunnel = { -90, -4.6, 290 },
	galerie = { 35, 4.9, 280 },
	parkhaus = { -125, 0.5, 330 },
	runway = { -700, 0.5, 8 },
	tower = { -138, 0.5, 250 },
}

-- Zonen-Bypass: NUR wenn der Admin ihn im Panel eingeschaltet hat.
-- So erlebt auch der Besitzer Security/Gates ganz normal (Standard: AUS).
function Admin.isExempt(pl)
	return god[pl] == true and Admin.isAdmin(pl)
end

function Admin.isAdmin(pl)
	if RunService:IsStudio() then return true end
	if ADMIN_IDS[pl.UserId] then return true end
	return game.CreatorType == Enum.CreatorType.User and pl.UserId == game.CreatorId
end

adminEv.OnServerEvent:Connect(function(pl, cmd, arg)
	if not Admin.isAdmin(pl) then
		warn("[AdminService] " .. pl.Name .. " hat ohne Admin-Rechte '" .. tostring(cmd) .. "' versucht — ignoriert.")
		return
	end
	if cmd == "hello" then
		adminEv:FireClient(pl, "ok")
	elseif cmd == "god" then
		god[pl] = not god[pl] or nil
		adminEv:FireClient(pl, "god", god[pl] == true)
	elseif cmd == "credits" then
		inv.adminGive(pl, math.clamp(tonumber(arg) or 1000, -100000, 100000), 0)
	elseif cmd == "xp" then
		inv.adminGive(pl, 0, math.clamp(tonumber(arg) or 500, 0, 100000))
	elseif cmd == "staff" then
		inv.adminGrant(pl, "staff_id")
	elseif cmd == "passes" then
		for _, f in ipairs(flights.getFlights()) do
			inv.adminGrant(pl, "pass_" .. f.code)
		end
	elseif cmd == "cosmetics" then
		inv.adminGrant(pl, "glasses")
		inv.adminGrant(pl, "phones")
	elseif cmd == "boarding" then
		flights.forceGateBoarding(math.clamp(tonumber(arg) or 1, 1, 5))
	elseif cmd == "tp" then
		local t = TELEPORTS[tostring(arg)]
		local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
		if t and root then
			root.CFrame = CFrame.new(t[1] * M, t[2] * M + 4, t[3] * M)
		end
	end
end)

game:GetService("Players").PlayerRemoving:Connect(function(pl)
	god[pl] = nil
end)

function Admin.init(inventoryService, flightService)
	inv = inventoryService
	flights = flightService
	M = workspace:GetAttribute("MetersToStuds") or M
	print("[AdminService] bereit — Admin: Creator, Studio, ADMIN_IDS (" .. (game.CreatorType == Enum.CreatorType.User and ("CreatorId " .. game.CreatorId) or "Gruppenspiel") .. ")")
end

return Admin
