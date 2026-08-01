-- ReplicatedStorage/Shared/Types.lua
--!strict
-- GHOSTNET :: Gemeinsame Luau-Typen fuer Server und Client.

export type RigLevels = {
	CPU: number,
	RAM: number,
	Cooling: number,
	NetCard: number,
}

-- Ein registriertes Hack-Ziel in der Welt.
export type HackTarget = {
	Id: string,
	Part: BasePart,
	DisplayName: string,
	Difficulty: number,
	HackType: string,
	Reward: number,
	TraceGain: number,
	Cooldown: number,
	RequiredLevel: number,
	OnSuccess: string,
	DownTime: number,
	DownUntil: number, -- 0 = einsatzbereit
}

-- Was der Client ueber ein Node-Breach-Gitter erfahren darf.
-- Verstecktes ICE ist hier als OPEN (0) getarnt.
export type NodeBreachPublic = {
	Width: number,
	Height: number,
	Cells: { number }, -- 0 Open, 1 Ice, 2 Relay, 3 Start, 4 Exit
	Start: number,
	Exit: number,
	Relays: number,
}

-- Serverseitiger Rätselzustand. Verlaesst den Server NIE.
export type NodeBreachState = {
	Width: number,
	Height: number,
	Cells: { number }, -- inkl. 5 = MaskedIce
	Start: number,
	Exit: number,
	RelayTotal: number,
	RelaysVisited: number,
	Path: { number },
	InPath: { [number]: boolean },
	Revealed: { [number]: boolean },
	Solution: { number }, -- fuer den Auto-Solver in Phase 3
}

-- Ergebnis einer einzelnen Spielereingabe, vom Minispiel zurueckgegeben.
export type InputResult = {
	Ok: boolean,
	Reason: string,
	CostsAttempt: boolean,
	Solved: boolean,
	Feedback: { [string]: any },
}

-- Eine laufende Hack-Session auf dem Server.
export type Session = {
	Id: string,
	Player: Player,
	TargetId: string,
	HackType: string,
	Difficulty: number,
	Range: number,
	ExpectedStep: number,
	AttemptsLeft: number,
	Deadline: number, -- workspace:GetServerTimeNow()
	StartedAt: number,
	State: any, -- minispielspezifisch
	Resolved: boolean,
}

return {}
