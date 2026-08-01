-- ReplicatedStorage/Shared/Config.lua
--!strict
-- GHOSTNET :: Zentrale Balancing-Datei.
-- Regel: Jede Zahl, die man zum Austarieren anfassen will, steht HIER und
-- nirgendwo sonst. Server und Client lesen dieselbe Datei.

local Config = {}

Config.Version = "0.1.0"

-- CollectionService-Tag, der einen Part zu einem Hack-Ziel macht.
Config.HackableTag = "GhostNetHackable"

--==========================================================================
-- 1. REICHWEITE (Netzwerkkarte)
--==========================================================================
Config.Range = {
	Base = 18, -- Studs auf NetCard 1
	PerNetCard = 6, -- pro weiterer Stufe
	Tolerance = 4, -- Lag-Puffer bei der Serverpruefung
}

function Config.GetRange(netCardLevel: number): number
	return Config.Range.Base + Config.Range.PerNetCard * (netCardLevel - 1)
end

--==========================================================================
-- 2. ZEIT (CPU)
--==========================================================================
Config.Time = {
	Base = 25, -- Sekunden auf CPU 1
	PerCPU = 4, -- pro weiterer Stufe
	PerDifficulty = 3, -- Zuschlag pro Schwierigkeitsgrad
}

function Config.GetTimeLimit(cpuLevel: number, difficulty: number): number
	return Config.Time.Base + Config.Time.PerCPU * (cpuLevel - 1) + Config.Time.PerDifficulty * difficulty
end

--==========================================================================
-- 3. VERSUCHE (RAM)
--==========================================================================
Config.Attempts = {
	Base = 3, -- auf RAM 1
	PerRAM = 1,
	Cap = 7,
}

function Config.GetAttempts(ramLevel: number): number
	return math.min(Config.Attempts.Cap, Config.Attempts.Base + Config.Attempts.PerRAM * (ramLevel - 1))
end

--==========================================================================
-- 4. TRACE (Kuehlung)  -- angewendet ab Phase 2, Zahl wird schon berechnet
--==========================================================================
Config.Trace = {
	GainPerDifficulty = 4.0, -- Default, wenn der Part kein TraceGain-Attribut hat
	CoolingReduction = 0.08, -- -8% Trace-Gewinn pro Kuehlungsstufe
	AbortFactor = 0.5, -- Abbruch kostet halben Trace, damit er kein Free-Retry ist
	FailFactor = 0.75, -- Fehlschlag kostet 75% Trace
}

function Config.GetTraceGain(baseGain: number, coolingLevel: number): number
	local reduction = 1 - Config.Trace.CoolingReduction * (coolingLevel - 1)
	return baseGain * math.max(0.2, reduction)
end

--==========================================================================
-- 5. BELOHNUNG
--==========================================================================
Config.Reward = {
	Base = 40,
	Exponent = 1.35,
}

function Config.GetReward(difficulty: number): number
	return math.floor(Config.Reward.Base * difficulty ^ Config.Reward.Exponent)
end

--==========================================================================
-- 6. COOLDOWN
--==========================================================================
Config.Cooldown = {
	Default = 90, -- Sekunden, pro Spieler und Ziel
	AfterFail = 20, -- kuerzer nach einem Fehlschlag, damit man es nochmal darf
}

--==========================================================================
-- 7. RIG
--==========================================================================
Config.Rig = {
	MaxLevel = 5,
	Components = { "CPU", "RAM", "Cooling", "NetCard" },
	StartLevels = { CPU = 1, RAM = 1, Cooling = 1, NetCard = 1 },
}

--==========================================================================
-- 8. DEFAULTS FUER HACK-ZIELE
-- Ein Part braucht KEIN einziges Attribut. Alles, was fehlt, kommt von hier.
--==========================================================================
Config.TargetDefaults = {
	Difficulty = 1,
	HackType = "NodeBreach",
	Reward = -1, -- -1 = aus Difficulty berechnen
	TraceGain = -1, -- -1 = aus Difficulty berechnen
	Cooldown = -1, -- -1 = Config.Cooldown.Default
	RequiredLevel = 1,
	OnSuccess = "Offline",
	DisplayName = "", -- "" = Instanzname benutzen
	DownTime = 30, -- wie lange der Welteffekt haelt
}

--==========================================================================
-- 9. RATE-LIMITS (Token-Bucket pro Spieler und Remote)
--==========================================================================
Config.RateLimits = {
	HackRequestStart = { Rate = 2, Burst = 3 },
	HackInput = { Rate = 12, Burst = 20 },
	HackAbort = { Rate = 4, Burst = 6 },
}

--==========================================================================
-- 10. NODE-BREACH
--==========================================================================
Config.NodeBreach = {
	-- Pro Schwierigkeitsband: Gittergroesse, Anzahl Relays, Anteil sichtbares
	-- ICE und Anteil verstecktes ICE (nur DAS kostet Versuche).
	Tiers = {
		{ MaxDifficulty = 2, Width = 5, Height = 5, Relays = 1, Ice = 0.15, MaskedIce = 0.06 },
		{ MaxDifficulty = 4, Width = 6, Height = 6, Relays = 2, Ice = 0.20, MaskedIce = 0.09 },
		{ MaxDifficulty = 6, Width = 6, Height = 6, Relays = 3, Ice = 0.25, MaskedIce = 0.12 },
		{ MaxDifficulty = 8, Width = 7, Height = 7, Relays = 3, Ice = 0.30, MaskedIce = 0.15 },
		{ MaxDifficulty = 10, Width = 8, Height = 8, Relays = 4, Ice = 0.32, MaskedIce = 0.18 },
	},
	PathSearchTries = 12, -- so viele Pfade werden erzeugt, der passendste gewinnt
	PathLengthBonus = 2, -- Wunschlaenge = Width + Height + Bonus
}

--==========================================================================
-- SESSION / LAUFZEIT
--==========================================================================
Config.Session = {
	TickRate = 0.25, -- Sekunden zwischen Ablauf- und Distanzpruefung
	GraceAfterStart = 0.5, -- kurze Schonfrist, bevor die Distanz geprueft wird
}

--==========================================================================
-- UI-FARBEN (Fake-OS)
--==========================================================================
Config.Theme = {
	Background = Color3.fromRGB(6, 8, 11),
	Panel = Color3.fromRGB(13, 17, 23),
	PanelLight = Color3.fromRGB(22, 28, 37),
	Line = Color3.fromRGB(38, 48, 62),
	Cyan = Color3.fromRGB(0, 229, 255),
	CyanDim = Color3.fromRGB(0, 120, 140),
	Magenta = Color3.fromRGB(255, 45, 149),
	Amber = Color3.fromRGB(255, 176, 0),
	Text = Color3.fromRGB(198, 214, 226),
	TextDim = Color3.fromRGB(96, 116, 134),
	Ice = Color3.fromRGB(64, 78, 96),
}

table.freeze(Config.Theme)

return Config
