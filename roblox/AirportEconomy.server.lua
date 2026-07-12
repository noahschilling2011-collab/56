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
local claimEv = Instance.new("RemoteEvent"); claimEv.Name = "ClaimVehicle"; claimEv.Parent = RS

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

local function fullSync(pl)
	local st = state[pl]
	if not st then return end
	local unlockList = {}
	for id in pairs(st.unlocks) do table.insert(unlockList, id) end
	syncEv:FireClient(pl, st.credits, st.xp, unlockList)
end

Players.PlayerAdded:Connect(function(pl)
	-- loaded verhindert, dass ein fehlgeschlagenes Laden beim Verlassen Nullen
	-- ueber den echten Spielstand speichert (save() prueft das Flag)
	local st = { credits = 0, xp = 0, unlocks = {}, loaded = store == nil }
	state[pl] = st
	if store then
		st.loaded = withRetry("Laden", function()
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
	-- Spieler kann waehrend GetAsync/Retries schon weg sein
	if not pl:IsDescendantOf(Players) then return end
	local ls = Instance.new("Folder"); ls.Name = "leaderstats"
	local cv = Instance.new("IntValue"); cv.Name = "Credits"; cv.Value = st.credits; cv.Parent = ls
	local lv = Instance.new("IntValue"); lv.Name = "Level"; lv.Value = level(st.xp); lv.Parent = ls
	ls.Parent = pl
	fullSync(pl)
end)

-- Client meldet sich, sobald sein Handler steht -> initialer Stand geht nie verloren
syncEv.OnServerEvent:Connect(fullSync)

earnEv.OnServerEvent:Connect(function(pl, reason, credits, xp)
	local st = state[pl]
	if not st then return end
	reason = type(reason) == "string" and reason or "misc"
	local cap = CAPS[reason] or CAPS.misc
	credits = tonumber(credits) or 0
	xp = tonumber(xp) or 0
	if credits ~= credits then credits = 0 end -- NaN rutscht durch math.clamp!
	if xp ~= xp then xp = 0 end
	credits = math.clamp(credits, MIN_EARN, cap)
	xp = math.clamp(xp, 0, 200)
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
	if not (st and type(id) == "string" and #id <= 40) then return end
	local n = 0
	for _ in pairs(st.unlocks) do n = n + 1 end
	if n >= 64 then return end -- weit ueber der echten Erfolgs-Liste, blockt Muell-Fluten
	st.unlocks[id] = true
end)

local function save(pl)
	local st = state[pl]
	if not st or not store then return end
	if not st.loaded then
		warn("[AirportEconomy] Speichern uebersprungen fuer " .. pl.Name .. " — Laden war fehlgeschlagen (kein Ueberschreiben mit Defaults)")
		return
	end
	local unlockList = {}
	for id in pairs(st.unlocks) do table.insert(unlockList, id) end
	withRetry("Speichern", function()
		store:SetAsync("p" .. pl.UserId, { c = st.credits, x = st.xp, u = unlockList })
	end)
end

-- Fahrzeug-Belegung (Multiplayer): pro Fahrzeugname genau ein Fahrer
local claims = {}
claimEv.OnServerEvent:Connect(function(pl, veh, want)
	if type(veh) ~= "string" or #veh > 30 then return end
	if want then
		local holder = claims[veh]
		if holder == nil or holder == pl or not holder:IsDescendantOf(Players) then
			claims[veh] = pl
			claimEv:FireClient(pl, veh, true)
		else
			claimEv:FireClient(pl, veh, false)
		end
	elseif claims[veh] == pl then
		claims[veh] = nil
	end
end)

Players.PlayerRemoving:Connect(function(pl)
	for veh, holder in pairs(claims) do
		if holder == pl then claims[veh] = nil end
	end
	save(pl)
	state[pl] = nil
end)

game:BindToClose(function()
	for _, pl in ipairs(Players:GetPlayers()) do
		save(pl)
	end
end)

print("[AirportEconomy] bereit — leaderstats, EarnCredits/BuyItem, DataStore " .. (store and "aktiv" or "NICHT verfügbar (Studio ohne API-Zugriff?)"))
