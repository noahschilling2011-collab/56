-- AirportEconomy · Server-Oekonomie (Phase 3)
-- leaderstats (Credits, Level), validierte Job-Belohnungen, Shop-Kaeufe gegen
-- ShopData, DataStore-Persistenz (Credits, XP, Unlocks) mit pcall + Retry.
-- Der Client meldet nur Abschluesse; gerechnet und gespeichert wird hier.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ShopData = require(RS:WaitForChild("ShopData"))

local earnEv = Instance.new("RemoteEvent"); earnEv.Name = "EarnCredits"; earnEv.Parent = RS
local buyEv = Instance.new("RemoteEvent"); buyEv.Name = "BuyItem"; buyEv.Parent = RS
local syncEv = Instance.new("RemoteEvent"); syncEv.Name = "SyncState"; syncEv.Parent = RS
local achEv = Instance.new("RemoteEvent"); achEv.Name = "UnlockAch"; achEv.Parent = RS

-- plausible Obergrenzen pro gemeldetem Auftrag (Credits); XP pro Meldung max. 200
local CAPS = {
	checkin = 150, security = 200, ramp = 450, fuel = 350,
	marshal = 550, flight = 2600, xp = 0, misc = 120,
}
local MIN_EARN = -300

local store = nil
pcall(function()
	store = game:GetService("DataStoreService"):GetDataStore("AirportJobSim_v1")
end)

local state = {} -- [Player] = { credits, xp, unlocks = {id=true} }

local function level(xp)
	return math.floor(xp / 100) + 1
end

local function pushLeaderstats(pl)
	local st = state[pl]
	local ls = pl:FindFirstChild("leaderstats")
	if not st or not ls then return end
	ls.Credits.Value = st.credits
	ls.Level.Value = level(st.xp)
end

local function withRetry(what, fn)
	for attempt = 1, 3 do
		local ok, err = pcall(fn)
		if ok then return true end
		warn("[AirportEconomy] " .. what .. " fehlgeschlagen (Versuch " .. attempt .. "): " .. tostring(err))
		task.wait(attempt)
	end
	return false
end

Players.PlayerAdded:Connect(function(pl)
	local st = { credits = 0, xp = 0, unlocks = {} }
	state[pl] = st
	if store then
		withRetry("Laden", function()
			local data = store:GetAsync("p" .. pl.UserId)
			if type(data) == "table" then
				st.credits = tonumber(data.c) or 0
				st.xp = tonumber(data.x) or 0
				if type(data.u) == "table" then
					for _, id in ipairs(data.u) do st.unlocks[tostring(id)] = true end
				end
			end
		end)
	end
	local ls = Instance.new("Folder"); ls.Name = "leaderstats"
	local cv = Instance.new("IntValue"); cv.Name = "Credits"; cv.Value = st.credits; cv.Parent = ls
	local lv = Instance.new("IntValue"); lv.Name = "Level"; lv.Value = level(st.xp); lv.Parent = ls
	ls.Parent = pl
	local unlockList = {}
	for id in pairs(st.unlocks) do table.insert(unlockList, id) end
	syncEv:FireClient(pl, st.credits, st.xp, unlockList)
end)

earnEv.OnServerEvent:Connect(function(pl, reason, credits, xp)
	local st = state[pl]
	if not st then return end
	reason = type(reason) == "string" and reason or "misc"
	local cap = CAPS[reason] or CAPS.misc
	credits = math.clamp(tonumber(credits) or 0, MIN_EARN, cap)
	xp = math.clamp(tonumber(xp) or 0, 0, 200)
	st.credits = math.max(0, st.credits + math.floor(credits))
	st.xp = st.xp + math.floor(xp)
	pushLeaderstats(pl)
	syncEv:FireClient(pl, st.credits, st.xp)
end)

buyEv.OnServerEvent:Connect(function(pl, shopIdx, itemIdx)
	local st = state[pl]
	if not st then return end
	local s = ShopData[tonumber(shopIdx) or 0]
	local it = s and s.items[tonumber(itemIdx) or 0]
	if not it then return end
	local price = it[2]
	if st.credits < price then
		buyEv:FireClient(pl, false, shopIdx, itemIdx, st.credits)
		return
	end
	st.credits = st.credits - price
	pushLeaderstats(pl)
	buyEv:FireClient(pl, true, shopIdx, itemIdx, st.credits)
end)

achEv.OnServerEvent:Connect(function(pl, id)
	local st = state[pl]
	if st and type(id) == "string" and #id <= 40 then
		st.unlocks[id] = true
	end
end)

local function save(pl)
	local st = state[pl]
	if not st or not store then return end
	local unlockList = {}
	for id in pairs(st.unlocks) do table.insert(unlockList, id) end
	withRetry("Speichern", function()
		store:SetAsync("p" .. pl.UserId, { c = st.credits, x = st.xp, u = unlockList })
	end)
end

Players.PlayerRemoving:Connect(function(pl)
	save(pl)
	state[pl] = nil
end)

game:BindToClose(function()
	for _, pl in ipairs(Players:GetPlayers()) do
		save(pl)
	end
end)

print("[AirportEconomy] bereit — leaderstats, EarnCredits/BuyItem, DataStore " .. (store and "aktiv" or "NICHT verfügbar (Studio ohne API-Zugriff?)"))
