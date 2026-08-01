-- ServerScriptService/GhostNetServer.server.lua
--!strict
-- GHOSTNET :: Server-Bootstrap. Startet die Systeme in fester Reihenfolge.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
-- Das Requiren legt die Remote-Objekte an, bevor irgendein Client sie sucht.
require(ReplicatedStorage.Shared.Remotes)

local Systems = script.Parent:WaitForChild("Systems")

local EconomyService = require(Systems.EconomyService)
local HackTargets = require(Systems.HackTargets)
local HackService = require(Systems.HackService)

EconomyService.Init()
HackTargets.Init()
HackService.Init()

print(("[GHOSTNET] Server hochgefahren - Version %s"):format(Config.Version))
