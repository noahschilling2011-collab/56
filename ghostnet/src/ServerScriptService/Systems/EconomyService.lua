-- ServerScriptService/Systems/EconomyService.lua
--!strict
-- GHOSTNET :: Einzige Stelle, an der sich Crypto und Rig-Werte aendern.
--
-- Phase 1 haelt den Zustand nur im Serverspeicher. In Phase 2 setzt der
-- SaveService das Profil davor, in Phase 3 kommen Shop, Verkauf und
-- Upgrades dazu. Die Schnittstelle nach aussen bleibt dieselbe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

type RigLevels = Types.RigLevels

type Wallet = {
	Banked: number, -- sicher
	Unsold: number, -- heiss, geht beim Bust verloren (Phase 2)
	Rig: RigLevels,
}

local EconomyService = {}

local wallets: { [Player]: Wallet } = {}

local function newWallet(): Wallet
	local start = Config.Rig.StartLevels
	return {
		Banked = 0,
		Unsold = 0,
		Rig = { CPU = start.CPU, RAM = start.RAM, Cooling = start.Cooling, NetCard = start.NetCard },
	}
end

local function get(player: Player): Wallet
	local w = wallets[player]
	if not w then
		w = newWallet()
		wallets[player] = w
	end
	return w
end

--==========================================================================
-- Lesen
--==========================================================================

function EconomyService.GetRig(player: Player): RigLevels
	return get(player).Rig
end

-- Tier ist abgeleitet, nicht gekauft: das SCHWAECHSTE Bauteil zaehlt.
-- Man kann sich also nicht mit einer einzelnen Komponente in eine hoehere
-- Zone schummeln.
function EconomyService.GetTier(player: Player): number
	local rig = get(player).Rig
	return math.min(rig.CPU, rig.RAM, rig.Cooling, rig.NetCard)
end

function EconomyService.GetRange(player: Player): number
	return Config.GetRange(get(player).Rig.NetCard)
end

function EconomyService.Snapshot(player: Player): { [string]: any }
	local w = get(player)
	return {
		Banked = w.Banked,
		Unsold = w.Unsold,
		Rig = table.clone(w.Rig),
		Tier = EconomyService.GetTier(player),
	}
end

--==========================================================================
-- Schreiben
--==========================================================================

function EconomyService.Sync(player: Player)
	if not player.Parent then
		return
	end
	Remotes.EconomySync:FireClient(player, EconomyService.Snapshot(player))
end

-- Belohnung aus einem Hack landet im heissen Wallet, nicht auf der Bank.
function EconomyService.AwardUnsold(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local w = get(player)
	w.Unsold += math.floor(amount)
	EconomyService.Sync(player)
end

-- Wird beim Bust in Phase 2 gebraucht.
function EconomyService.WipeUnsold(player: Player): number
	local w = get(player)
	local lost = w.Unsold
	w.Unsold = 0
	EconomyService.Sync(player)
	return lost
end

function EconomyService.Init()
	Players.PlayerAdded:Connect(function(player)
		wallets[player] = newWallet()
		EconomyService.Sync(player)
	end)

	for _, player in Players:GetPlayers() do
		if not wallets[player] then
			wallets[player] = newWallet()
			EconomyService.Sync(player)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		wallets[player] = nil
	end)
end

return EconomyService
