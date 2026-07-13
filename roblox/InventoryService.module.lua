-- InventoryService · Der Server besitzt den Spielerzustand.
-- Credits/XP/Unlocks/INVENTAR, DataStore-Schema v2 (Migration von v1: altes
-- Save ohne Inventar laedt als leeres Inventar), leaderstats, alle Remotes,
-- Job-Tokens gegen EarnCredits-Spam, Kosmetik als Server-"Accessory" (Weld an
-- den Kopf, bei Respawn/Rejoin wieder da), Boarding-Paesse + Mitarbeiter-Ausweis.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ShopData = require(RS:WaitForChild("ShopData"))

local Inv = {}

local earnEv = Instance.new("RemoteEvent"); earnEv.Name = "EarnCredits"; earnEv.Parent = RS
local buyEv = Instance.new("RemoteEvent"); buyEv.Name = "BuyItem"; buyEv.Parent = RS
local syncEv = Instance.new("RemoteEvent"); syncEv.Name = "SyncState"; syncEv.Parent = RS
local achEv = Instance.new("RemoteEvent"); achEv.Name = "UnlockAch"; achEv.Parent = RS
local claimEv = Instance.new("RemoteEvent"); claimEv.Name = "ClaimVehicle"; claimEv.Parent = RS
local jobEv = Instance.new("RemoteEvent"); jobEv.Name = "StartJob"; jobEv.Parent = RS

-- Obergrenzen pro gemeldetem Auftrag; Jobs brauchen zusaetzlich ein gueltiges Token
local CAPS = {
	checkin = 150, security = 200, ramp = 450, fuel = 350,
	marshal = 550, flight = 2600, xp = 0, misc = 120,
}
local MIN_EARN = -300
-- Job-Tokens: max. Aufgaben pro Schicht + Mindestabstand zwischen Meldungen
local JOBS = {
	checkin = { max = 12, gap = 2.5 },
	security = { max = 12, gap = 1.5 },
	ramp = { max = 16, gap = 1.2 },
	fuel = { max = 6, gap = 4 },
	marshal = { max = 8, gap = 2 },
	flight = { max = 3, gap = 30 },
}
local TOKEN_TTL = 1800
local STAFF_XP = 100 -- Mitarbeiter-Ausweis ab Level 2

local flights = nil
local store = nil
pcall(function()
	store = game:GetService("DataStoreService"):GetDataStore("AirportJobSim_v1")
end)

local state = {} -- [pl] = { credits, xp, unlocks, inventory = {id=count}, loaded }
local tokens = {} -- [pl] = { job, started, lastAccept, tasks, lastStart }

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
		warn("[InventoryService] " .. what .. " fehlgeschlagen (Versuch " .. attempt .. "): " .. tostring(err))
		task.wait(attempt)
	end
	return false
end

local function fullSync(pl)
	local st = state[pl]
	if not st then return end
	local unlockList = {}
	for id in pairs(st.unlocks) do table.insert(unlockList, id) end
	syncEv:FireClient(pl, st.credits, st.xp, unlockList, st.inventory)
end

---------------------------------------------------------------- Inventar
function Inv.count(pl, itemId)
	local st = state[pl]
	return st and (st.inventory[itemId] or 0) or 0
end

function Inv.addItem(pl, itemId, n)
	local st = state[pl]
	if not st then return end
	st.inventory[itemId] = (st.inventory[itemId] or 0) + (n or 1)
end

function Inv.consumeItem(pl, itemId)
	local st = state[pl]
	if not st or (st.inventory[itemId] or 0) <= 0 then return false end
	st.inventory[itemId] = st.inventory[itemId] - 1
	if st.inventory[itemId] <= 0 then st.inventory[itemId] = nil end
	fullSync(pl)
	return true
end

local function hasStaff(pl)
	local st = state[pl]
	return st ~= nil and ((st.inventory.staff_id or 0) > 0 or st.xp >= STAFF_XP)
end

local function maybeGrantStaff(pl)
	local st = state[pl]
	if st and st.xp >= STAFF_XP and (st.inventory.staff_id or 0) == 0 then
		st.inventory.staff_id = 1
		syncEv:FireClient(pl, st.credits, st.xp, nil, st.inventory)
	end
end

---------------------------------------------------------------- Kosmetik (Server-Accessoires)
local COSMETICS = {
	glasses = {
		{ Vector3.new(1.15, 0.3, 0.16), CFrame.new(0, 0.12, -0.62), Color3.fromRGB(20, 22, 26) },
	},
	phones = {
		{ Vector3.new(0.28, 0.55, 0.45), CFrame.new(-0.75, 0, 0), Color3.fromRGB(194, 59, 46) },
		{ Vector3.new(0.28, 0.55, 0.45), CFrame.new(0.75, 0, 0), Color3.fromRGB(194, 59, 46) },
		{ Vector3.new(1.6, 0.2, 0.35), CFrame.new(0, 0.72, 0), Color3.fromRGB(20, 22, 26) },
	},
}

local function equipCosmetic(pl, kind)
	local spec = COSMETICS[kind]
	local ch = pl.Character
	local head = ch and ch:FindFirstChild("Head")
	if not spec or not head or ch:FindFirstChild("Acc_" .. kind) then return end
	local mdl = Instance.new("Model"); mdl.Name = "Acc_" .. kind
	for _, d in ipairs(spec) do
		local p = Instance.new("Part")
		p.Size = d[1]; p.Color = d[3]
		p.CanCollide = false; p.Massless = true; p.Anchored = false
		p.CFrame = head.CFrame * d[2]
		local w = Instance.new("WeldConstraint"); w.Part0 = head; w.Part1 = p; w.Parent = p
		p.Parent = mdl
	end
	mdl.Parent = ch
end

local function equipOwned(pl)
	local st = state[pl]
	if not st then return end
	for kind in pairs(COSMETICS) do
		if (st.inventory[kind] or 0) > 0 then equipCosmetic(pl, kind) end
	end
end

---------------------------------------------------------------- Laden / Speichern (v2 + Migration)
Players.PlayerAdded:Connect(function(pl)
	local st = { credits = 0, xp = 0, unlocks = {}, inventory = {}, loaded = store == nil }
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
				-- v2: Inventar · v1 (kein v-Feld): leeres Inventar, KEIN Fehler
				if data.v == 2 and type(data.inv) == "table" then
					for id, n in pairs(data.inv) do
						if type(id) == "string" and tonumber(n) then st.inventory[id] = math.floor(tonumber(n)) end
					end
				end
			end
		end)
	end
	if not pl:IsDescendantOf(Players) then return end
	local ls = Instance.new("Folder"); ls.Name = "leaderstats"
	local cv = Instance.new("IntValue"); cv.Name = "Credits"; cv.Value = st.credits; cv.Parent = ls
	local lv = Instance.new("IntValue"); lv.Name = "Level"; lv.Value = level(st.xp); lv.Parent = ls
	ls.Parent = pl
	maybeGrantStaff(pl)
	fullSync(pl)
	pl.CharacterAdded:Connect(function(ch)
		ch:WaitForChild("Head", 10)
		equipOwned(pl)
	end)
	if pl.Character then equipOwned(pl) end
end)

syncEv.OnServerEvent:Connect(fullSync)

local function save(pl)
	local st = state[pl]
	if not st or not store then return end
	if not st.loaded then
		warn("[InventoryService] Speichern übersprungen für " .. pl.Name .. " — Laden war fehlgeschlagen")
		return
	end
	local unlockList = {}
	for id in pairs(st.unlocks) do table.insert(unlockList, id) end
	withRetry("Speichern", function()
		store:SetAsync("p" .. pl.UserId, { v = 2, c = st.credits, x = st.xp, u = unlockList, inv = st.inventory })
	end)
end

---------------------------------------------------------------- Job-Tokens + EarnCredits
jobEv.OnServerEvent:Connect(function(pl, job)
	if not state[pl] or type(job) ~= "string" or not JOBS[job] then return end
	local tk = tokens[pl]
	local now = os.clock()
	if tk and now - (tk.lastStart or 0) < 8 then return end -- Start-Spam
	tokens[pl] = { job = job, started = now, lastAccept = 0, tasks = 0, lastStart = now }
end)

earnEv.OnServerEvent:Connect(function(pl, reason, credits, xp)
	local st = state[pl]
	if not st then return end
	reason = type(reason) == "string" and reason or "misc"
	local cap = CAPS[reason] or CAPS.misc
	credits = tonumber(credits) or 0
	xp = tonumber(xp) or 0
	if credits ~= credits then credits = 0 end -- NaN rutscht durch math.clamp
	if xp ~= xp then xp = 0 end
	-- Jobs nur mit gueltigem Token, mit Mindestabstand und Aufgaben-Limit
	local cfg = JOBS[reason]
	if cfg then
		local tk = tokens[pl]
		local now = os.clock()
		if not tk or tk.job ~= reason or now - tk.started > TOKEN_TTL then
			warn("[InventoryService] EarnCredits ohne gültiges Job-Token von " .. pl.Name .. " (" .. reason .. ") — verworfen")
			return
		end
		if now - tk.lastAccept < cfg.gap or tk.tasks >= cfg.max then
			warn("[InventoryService] EarnCredits-Spam von " .. pl.Name .. " (" .. reason .. ") — verworfen")
			return
		end
		tk.lastAccept = now
		tk.tasks = tk.tasks + 1
	end
	credits = math.clamp(credits, MIN_EARN, cap)
	xp = math.clamp(xp, 0, 200)
	st.credits = math.max(0, st.credits + math.floor(credits))
	st.xp = st.xp + math.floor(xp)
	maybeGrantStaff(pl)
	pushLeaderstats(pl)
	syncEv:FireClient(pl, st.credits, st.xp, nil, st.inventory)
end)

---------------------------------------------------------------- Kaufen (schreibt jetzt ins Inventar)
buyEv.OnServerEvent:Connect(function(pl, shopIdx, itemIdx)
	local st = state[pl]
	if not st then return end
	local s = ShopData[tonumber(shopIdx) or 0]
	local it = s and s.items[tonumber(itemIdx) or 0]
	if not it then return end
	local price, eff = it[2], it[3]
	-- Kosmetik, die man schon besitzt, wird nicht doppelt berechnet
	if COSMETICS[eff] and (st.inventory[eff] or 0) > 0 then
		buyEv:FireClient(pl, true, shopIdx, itemIdx, st.credits)
		equipCosmetic(pl, eff)
		return
	end
	if st.credits < price then
		buyEv:FireClient(pl, false, shopIdx, itemIdx, st.credits)
		return
	end
	st.credits = st.credits - price
	if type(eff) == "string" then
		if eff:sub(1, 5) == "pass_" then
			Inv.addItem(pl, eff)
		elseif COSMETICS[eff] then
			Inv.addItem(pl, eff)
			equipCosmetic(pl, eff)
		end
	end
	pushLeaderstats(pl)
	buyEv:FireClient(pl, true, shopIdx, itemIdx, st.credits)
	fullSync(pl)
end)

achEv.OnServerEvent:Connect(function(pl, id)
	local st = state[pl]
	if not (st and type(id) == "string" and #id <= 40) then return end
	local n = 0
	for _ in pairs(st.unlocks) do n = n + 1 end
	if n >= 64 then return end
	st.unlocks[id] = true
end)

---------------------------------------------------------------- Fahrzeug-Claims
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
	tokens[pl] = nil
end)

game:BindToClose(function()
	for _, pl in ipairs(Players:GetPlayers()) do
		save(pl)
	end
end)

---------------------------------------------------------------- Admin-Zugriffe (nur vom AdminService gerufen, serverseitig)
function Inv.adminGive(pl, credits, xp)
	local st = state[pl]
	if not st then return end
	st.credits = math.max(0, st.credits + math.floor(credits or 0))
	st.xp = math.max(0, st.xp + math.floor(xp or 0))
	maybeGrantStaff(pl)
	pushLeaderstats(pl)
	fullSync(pl)
end

function Inv.adminGrant(pl, itemId)
	local st = state[pl]
	if not st then return end
	if (st.inventory[itemId] or 0) == 0 then
		Inv.addItem(pl, itemId)
	end
	if COSMETICS[itemId] then equipCosmetic(pl, itemId) end
	fullSync(pl)
end

---------------------------------------------------------------- Provider fuer den ZoneService
function Inv.zoneProvider()
	return {
		hasStaff = hasStaff,
		hasPass = function(pl, code)
			return Inv.count(pl, "pass_" .. code) > 0
		end,
		consumePass = function(pl, code)
			Inv.consumeItem(pl, "pass_" .. code)
		end,
		anyPassGate = function(pl)
			local st = state[pl]
			if not st or not flights then return nil end
			for id, n in pairs(st.inventory) do
				if n > 0 and id:sub(1, 5) == "pass_" then
					local g = flights.gateOf(id:sub(6))
					if g then return g end
				end
			end
			return nil
		end,
		exemptFlight = function(pl)
			local tk = tokens[pl]
			return tk ~= nil and tk.job == "flight" and os.clock() - tk.started < TOKEN_TTL
		end,
	}
end

function Inv.init(flightService)
	flights = flightService
	print("[InventoryService] bereit — Inventar (Schema v2), Job-Tokens, DataStore " .. (store and "aktiv" or "NICHT verfügbar (Studio ohne API-Zugriff?)"))
end

return Inv
