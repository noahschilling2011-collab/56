-- ServerScriptService/Systems/RateLimiter.lua
--!strict
-- GHOSTNET :: Token-Bucket pro Spieler und Remote.
-- Jeder Remote-Handler fragt als ALLERERSTES hier nach.

local Players = game:GetService("Players")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

type Bucket = { Tokens: number, Last: number, Rate: number, Burst: number }

local RateLimiter = {}

local buckets: { [Player]: { [string]: Bucket } } = {}
-- Wer dauerhaft gegen Limits laeuft, wird geloggt statt still verschluckt.
local offences: { [Player]: number } = {}

local function getBucket(player: Player, key: string): Bucket?
	local limit = (Config.RateLimits :: any)[key]
	if not limit then
		warn(("[GHOSTNET] Kein Rate-Limit fuer '%s' konfiguriert - Aufruf wird verworfen."):format(key))
		return nil
	end

	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end

	local b = perPlayer[key]
	if not b then
		b = { Tokens = limit.Burst, Last = os.clock(), Rate = limit.Rate, Burst = limit.Burst }
		perPlayer[key] = b
	end
	return b
end

-- true  = Aufruf darf verarbeitet werden
-- false = Aufruf wird verworfen
function RateLimiter.Check(player: Player, key: string): boolean
	if not player.Parent then
		return false
	end

	local b = getBucket(player, key)
	if not b then
		return false
	end

	local now = os.clock()
	b.Tokens = math.min(b.Burst, b.Tokens + (now - b.Last) * b.Rate)
	b.Last = now

	if b.Tokens < 1 then
		local n = (offences[player] or 0) + 1
		offences[player] = n
		if n == 25 or n % 250 == 0 then
			warn(("[GHOSTNET] %s ueberschreitet Rate-Limit '%s' (%d Verstoesse)"):format(player.Name, key, n))
		end
		return false
	end

	b.Tokens -= 1
	return true
end

function RateLimiter.Clear(player: Player)
	buckets[player] = nil
	offences[player] = nil
end

Players.PlayerRemoving:Connect(RateLimiter.Clear)

return RateLimiter
