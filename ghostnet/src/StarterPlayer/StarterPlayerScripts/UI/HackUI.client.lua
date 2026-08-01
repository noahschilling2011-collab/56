-- StarterPlayer/StarterPlayerScripts/UI/HackUI.client.lua
--!strict
-- GHOSTNET :: Das Fake-Betriebssystem waehrend eines Hacks.
--
-- Dieses Skript kennt die Loesung nicht und rechnet nichts aus. Es zeigt,
-- was der Server geschickt hat, und meldet Klicks zurueck. Der komplette
-- Raetselzustand liegt auf dem Server.
--
-- Alles hier ist Fiktion: ein stilisiertes Minispiel, keine Darstellung
-- realer Technik.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local C = UITheme.Color

-- Zelltypen, identisch zu NodeBreach.lua
local OPEN, ICE, RELAY, START, EXIT = 0, 1, 2, 3, 4

local GLYPH = { [OPEN] = "\u{00B7}", [ICE] = "#", [RELAY] = "R", [START] = "S", [EXIT] = "E" }

--==========================================================================
-- Sitzungszustand (nur Anzeige)
--==========================================================================

local session: {
	Id: string,
	Deadline: number,
	TimeLimit: number,
	Width: number,
	Height: number,
	Cells: { number },
	Path: { number },
	RelaysLeft: number,
	AttemptsLeft: number,
	Attempts: number,
	NextStep: number,
	LastAck: number,
	LastSend: number,
	Closing: boolean,
}? = nil

local cellButtons: { [number]: TextButton } = {}
local connectors: { Frame } = {}
local logLines: { TextLabel } = {}
local typingToken = 0

--==========================================================================
-- Aufbau
--==========================================================================

local gui = UITheme.Screen("GhostNetHackUI", 20)
gui.Enabled = false
gui.Parent = playerGui

local backdrop = UITheme.Frame({
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	Parent = gui,
})

local window = UITheme.Frame({
	Name = "Window",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0.92, 0, 0.86, 0),
	BackgroundColor3 = C.Background,
	ClipsDescendants = true,
	Parent = backdrop,
})
UITheme.Corner(window, 5)
UITheme.Stroke(window, C.CyanDim)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(820, 580)
sizeConstraint.MinSize = Vector2.new(320, 300)
sizeConstraint.Parent = window

--== Titelleiste ===========================================================

local titleBar = UITheme.Frame({
	Name = "TitleBar",
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = C.Panel,
	Parent = window,
})

local titleText = UITheme.Label({
	Name = "Title",
	Text = "GHOSTNET // NODE-BREACH",
	TextColor3 = C.Cyan,
	TextSize = 14,
	Position = UDim2.new(0, 12, 0, 0),
	Size = UDim2.new(0.5, 0, 1, 0),
	Parent = titleBar,
})

local targetText = UITheme.Label({
	Name = "Target",
	Text = "",
	TextColor3 = C.TextDim,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Right,
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.new(0.5, -96, 1, 0),
	Parent = titleBar,
})

local abortButton = UITheme.Button({
	Name = "Abort",
	Text = "ABBRUCH [ESC]",
	TextSize = 11,
	TextColor3 = C.Magenta,
	BackgroundColor3 = C.PanelLight,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -8, 0.5, 0),
	Size = UDim2.fromOffset(86, 20),
	Parent = titleBar,
})
UITheme.Corner(abortButton, 3)
UITheme.Stroke(abortButton, C.Magenta)

--== Linke Spalte: Terminal + Status =======================================

local sidebar = UITheme.Frame({
	Name = "Sidebar",
	Position = UDim2.new(0, 0, 0, 30),
	Size = UDim2.new(0, 220, 1, -38),
	BackgroundColor3 = C.Background,
	Parent = window,
})
UITheme.Padding(sidebar, 12)

local statusBox = UITheme.Frame({
	Name = "Status",
	Size = UDim2.new(1, 0, 0, 74),
	BackgroundColor3 = C.Panel,
	Parent = sidebar,
})
UITheme.Corner(statusBox, 3)
UITheme.Stroke(statusBox, C.Line)
UITheme.Padding(statusBox, 8)

local relayLabel = UITheme.Label({
	Name = "Relays",
	Text = "RELAYS   -",
	TextSize = 12,
	Size = UDim2.new(1, 0, 0, 16),
	Parent = statusBox,
})

local attemptsLabel = UITheme.Label({
	Name = "AttemptsText",
	Text = "RAM",
	TextSize = 12,
	TextColor3 = C.TextDim,
	Position = UDim2.new(0, 0, 0, 20),
	Size = UDim2.new(1, 0, 0, 14),
	Parent = statusBox,
})

local chipHolder = UITheme.Frame({
	Name = "Chips",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 0, 0, 38),
	Size = UDim2.new(1, 0, 0, 12),
	Parent = statusBox,
})
local chipLayout = Instance.new("UIListLayout")
chipLayout.FillDirection = Enum.FillDirection.Horizontal
chipLayout.Padding = UDim.new(0, 4)
chipLayout.Parent = chipHolder

local terminal = UITheme.Frame({
	Name = "Terminal",
	Position = UDim2.new(0, 0, 0, 84),
	Size = UDim2.new(1, 0, 1, -84),
	BackgroundColor3 = C.Panel,
	ClipsDescendants = true,
	Parent = sidebar,
})
UITheme.Corner(terminal, 3)
UITheme.Stroke(terminal, C.Line)
UITheme.Padding(terminal, 8)

local termLayout = Instance.new("UIListLayout")
termLayout.SortOrder = Enum.SortOrder.LayoutOrder
termLayout.Padding = UDim.new(0, 2)
termLayout.Parent = terminal

--== Rechte Spalte: Gitter =================================================

local gridArea = UITheme.Frame({
	Name = "GridArea",
	Position = UDim2.new(0, 220, 0, 30),
	Size = UDim2.new(1, -220, 1, -38),
	BackgroundTransparency = 1,
	Parent = window,
})

local grid = UITheme.Frame({
	Name = "Grid",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.86, 0.86),
	BackgroundTransparency = 1,
	Parent = gridArea,
})
local gridAspect = Instance.new("UIAspectRatioConstraint")
gridAspect.AspectRatio = 1
gridAspect.Parent = grid

--== Timer-Balken ==========================================================

local timerTrack = UITheme.Frame({
	Name = "TimerTrack",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 8),
	BackgroundColor3 = C.PanelLight,
	Parent = window,
})

local timerFill = UITheme.Frame({
	Name = "TimerFill",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.Cyan,
	Parent = timerTrack,
})

local timerText = UITheme.Label({
	Name = "TimerText",
	Text = "",
	TextSize = 11,
	TextColor3 = C.Background,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 3,
	Parent = timerTrack,
})

--== Ergebnis-Overlay ======================================================

local resultOverlay = UITheme.Frame({
	Name = "Result",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.Background,
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 60,
	Parent = window,
})

local resultTitle = UITheme.Label({
	Name = "ResultTitle",
	Text = "",
	TextSize = 34,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.46),
	Size = UDim2.new(1, 0, 0, 40),
	ZIndex = 61,
	Parent = resultOverlay,
})

local resultSub = UITheme.Label({
	Name = "ResultSub",
	Text = "",
	TextSize = 14,
	TextColor3 = C.TextDim,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.56),
	Size = UDim2.new(1, 0, 0, 20),
	ZIndex = 61,
	Parent = resultOverlay,
})

UITheme.Scanlines(window, 4)

--==========================================================================
-- Terminal
--==========================================================================

local function pushLog(text: string, color: Color3?, instant: boolean?)
	local line = UITheme.Label({
		Text = "",
		TextSize = 11,
		TextColor3 = color or C.TextDim,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 13),
		LayoutOrder = #logLines + 1,
		Parent = terminal,
	})
	table.insert(logLines, line)

	while #logLines > 16 do
		local old = table.remove(logLines, 1)
		if old then
			old:Destroy()
		end
	end

	if instant then
		line.Text = text
	else
		local token = typingToken
		task.spawn(function()
			UITheme.TypeInto(line, text, 130, function()
				return typingToken ~= token or line.Parent == nil
			end)
		end)
	end
end

local function clearLog()
	typingToken += 1
	for _, line in logLines do
		line:Destroy()
	end
	table.clear(logLines)
end

--==========================================================================
-- Gitter zeichnen
--==========================================================================

local function clearGrid()
	for _, b in cellButtons do
		b:Destroy()
	end
	table.clear(cellButtons)
	for _, c in connectors do
		c:Destroy()
	end
	table.clear(connectors)
end

local function cellCenter(idx: number, w: number, h: number): (number, number)
	local x = (idx - 1) % w + 1
	local y = math.floor((idx - 1) / w) + 1
	return (x - 0.5) / w, (y - 0.5) / h
end

local sendInput: (number) -> ()

local function buildGrid()
	local s = session
	if not s then
		return
	end
	clearGrid()

	local w, h = s.Width, s.Height
	for idx = 1, w * h do
		local cx, cy = cellCenter(idx, w, h)
		local btn = UITheme.Button({
			Name = ("N%d"):format(idx),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(cx, cy),
			Size = UDim2.fromScale(0.78 / w, 0.78 / h),
			BackgroundColor3 = C.PanelLight,
			Text = "",
			TextSize = 13,
			ZIndex = 2,
			Parent = grid,
		})
		UITheme.Corner(btn, 3)
		UITheme.Stroke(btn, C.Line)
		btn.Activated:Connect(function()
			sendInput(idx)
		end)
		cellButtons[idx] = btn
	end
end

local function redrawGrid()
	local s = session
	if not s then
		return
	end

	local inPath: { [number]: boolean } = {}
	for _, idx in s.Path do
		inPath[idx] = true
	end
	local head = s.Path[#s.Path]

	for idx, btn in cellButtons do
		local cell = s.Cells[idx]
		local stroke = btn:FindFirstChildOfClass("UIStroke")

		btn.Text = GLYPH[cell] or ""
		btn.TextColor3 = C.TextDim
		btn.BackgroundColor3 = C.PanelLight
		btn.BackgroundTransparency = 0
		if stroke then
			stroke.Color = C.Line
			stroke.Thickness = 1
		end

		if cell == ICE then
			btn.BackgroundColor3 = C.Background
			btn.TextColor3 = C.Ice
			if stroke then
				stroke.Color = C.Ice
			end
		elseif cell == RELAY then
			btn.TextColor3 = C.Amber
			if stroke then
				stroke.Color = C.Amber
			end
		elseif cell == EXIT then
			btn.TextColor3 = C.Magenta
			if stroke then
				stroke.Color = C.Magenta
			end
		elseif cell == START then
			btn.TextColor3 = C.Cyan
		end

		if inPath[idx] then
			btn.BackgroundColor3 = C.CyanDim
			btn.TextColor3 = C.Background
			if stroke then
				stroke.Color = C.Cyan
			end
		end

		if idx == head then
			btn.BackgroundColor3 = C.Cyan
			btn.TextColor3 = C.Background
			if stroke then
				stroke.Color = C.Cyan
				stroke.Thickness = 2
			end
		end
	end

	-- Verbindungslinien zwischen den Pfadknoten
	for _, c in connectors do
		c:Destroy()
	end
	table.clear(connectors)

	for i = 1, #s.Path - 1 do
		local ax, ay = cellCenter(s.Path[i], s.Width, s.Height)
		local bx, by = cellCenter(s.Path[i + 1], s.Width, s.Height)
		local horizontal = math.abs(ax - bx) > math.abs(ay - by)
		local link = UITheme.Frame({
			Name = "Link",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale((ax + bx) * 0.5, (ay + by) * 0.5),
			Size = if horizontal
				then UDim2.new(0.34 / s.Width, 0, 0, 3)
				else UDim2.new(0, 3, 0.34 / s.Height, 0),
			BackgroundColor3 = C.Cyan,
			ZIndex = 1,
			Parent = grid,
		})
		table.insert(connectors, link)
	end
end

local function redrawChips()
	local s = session
	if not s then
		return
	end
	for _, child in chipHolder:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i = 1, s.Attempts do
		local chip = UITheme.Frame({
			Name = "Chip",
			Size = UDim2.fromOffset(16, 8),
			BackgroundColor3 = if i <= s.AttemptsLeft then C.Cyan else C.Line,
			LayoutOrder = i,
			Parent = chipHolder,
		})
		UITheme.Corner(chip, 2)
	end
	attemptsLabel.Text = ("RAM   %d / %d VERSUCHE"):format(s.AttemptsLeft, s.Attempts)
	relayLabel.Text = ("RELAYS   %d OFFEN"):format(s.RelaysLeft)
	relayLabel.TextColor3 = if s.RelaysLeft > 0 then C.Amber else C.Cyan
end

--==========================================================================
-- Eingabe an den Server
--==========================================================================

-- Eigene Drossel knapp unter dem Server-Limit. Damit kann der Client sein
-- eigenes Rate-Limit gar nicht erst reissen und aus dem Takt geraten.
local MIN_SEND_INTERVAL = 0.09

sendInput = function(node: number)
	local s = session
	if not s or s.Closing then
		return
	end
	local now = os.clock()
	if now - s.LastSend < MIN_SEND_INTERVAL then
		return
	end
	s.LastSend = now

	local btn = cellButtons[node]
	if btn then
		UITheme.Flash(btn, C.Text)
	end

	Remotes.HackInput:FireServer({
		SessionId = s.Id,
		Step = s.NextStep,
		Payload = { Node = node },
	})
	s.NextStep += 1
end

--==========================================================================
-- Oeffnen / Schliessen
--==========================================================================

local function open()
	gui.Enabled = true
	backdrop.BackgroundTransparency = 1
	window.Size = UDim2.new(0.92, 0, 0.3, 0)
	resultOverlay.Visible = false
	resultOverlay.BackgroundTransparency = 1

	TweenService:Create(backdrop, UITheme.Tween.Normal, { BackgroundTransparency = 0.35 }):Play()
	TweenService:Create(window, UITheme.Tween.Slow, { Size = UDim2.new(0.92, 0, 0.86, 0) }):Play()
end

local function close()
	local s = session
	if s then
		s.Closing = true
	end
	TweenService:Create(backdrop, UITheme.Tween.Normal, { BackgroundTransparency = 1 }):Play()
	local shrink = TweenService:Create(window, UITheme.Tween.Normal, { Size = UDim2.new(0.92, 0, 0.3, 0) })
	shrink:Play()
	shrink.Completed:Connect(function()
		gui.Enabled = false
		clearGrid()
		clearLog()
		session = nil
	end)
end

local function abort()
	local s = session
	if not s or s.Closing then
		return
	end
	Remotes.HackAbort:FireServer({ SessionId = s.Id })
end

abortButton.Activated:Connect(abort)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape and gui.Enabled then
		abort()
	end
end)

--==========================================================================
-- Server-Meldungen
--==========================================================================

Remotes.HackSessionStarted.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" or typeof(data.Public) ~= "table" then
		return
	end
	local public = data.Public

	session = {
		Id = data.SessionId,
		Deadline = data.Deadline,
		TimeLimit = data.TimeLimit,
		Width = public.Width,
		Height = public.Height,
		Cells = public.Cells,
		Path = { public.Start },
		RelaysLeft = public.Relays,
		AttemptsLeft = data.Attempts,
		Attempts = data.Attempts,
		NextStep = 1,
		LastAck = 0,
		LastSend = 0,
		Closing = false,
	}

	titleText.Text = ("GHOSTNET // %s"):format(data.Label or "BREACH")
	targetText.Text = ("%s   [D%d]"):format(data.Target and data.Target.Name or "?", data.Target and data.Target.Difficulty or 0)

	clearLog()
	buildGrid()
	redrawGrid()
	redrawChips()
	open()

	pushLog("> uplink hergestellt", C.Cyan)
	task.delay(0.35, function()
		if session and session.Id == data.SessionId then
			pushLog(("> ziel: %s"):format(string.lower(data.Target and data.Target.Name or "unbekannt")))
		end
	end)
	task.delay(0.8, function()
		if session and session.Id == data.SessionId then
			pushLog("> route vom start zum exit legen", C.Text)
		end
	end)
	task.delay(1.2, function()
		if session and session.Id == data.SessionId then
			pushLog("> alle relays (R) mitnehmen", C.Amber)
		end
	end)
	task.delay(1.6, function()
		if session and session.Id == data.SessionId then
			pushLog("> warnung: getarntes ice im gitter", C.Magenta)
		end
	end)
end)

local REASON_TEXT: { [string]: { Text: string, Color: Color3 } } = {
	OK = { Text = "> knoten uebernommen", Color = C.Cyan },
	SOLVED = { Text = "> exit erreicht", Color = C.Cyan },
	BACKTRACK = { Text = "> route zurueckgenommen", Color = C.TextDim },
	NOT_ADJACENT = { Text = "> kein direkter link", Color = C.TextDim },
	REVISIT = { Text = "> knoten bereits im pfad", Color = C.TextDim },
	ALREADY_HERE = { Text = "> du bist hier", Color = C.TextDim },
	ICE = { Text = "> ice blockiert", Color = C.Ice },
	RELAYS_MISSING = { Text = "> exit gesperrt - relays fehlen", Color = C.Amber },
	MASKED_ICE = { Text = "> GETARNTES ICE - rig ueberlastet", Color = C.Magenta },
	BAD_PAYLOAD = { Text = "> eingabe verworfen", Color = C.Magenta },
}

Remotes.HackFeedback.OnClientEvent:Connect(function(data: any)
	local s = session
	if not s or typeof(data) ~= "table" or data.SessionId ~= s.Id then
		return
	end

	-- Schritt-Zaehler am Server ausrichten, falls er je auseinanderlaufen sollte.
	if typeof(data.Step) == "number" then
		s.LastAck = data.Step
		s.NextStep = math.max(s.NextStep, data.Step + 1)
	end

	if typeof(data.AttemptsLeft) == "number" then
		s.AttemptsLeft = data.AttemptsLeft
	end

	local fb = data.Feedback
	if typeof(fb) == "table" then
		if typeof(fb.Path) == "table" then
			s.Path = fb.Path
		end
		if typeof(fb.RelaysLeft) == "number" then
			s.RelaysLeft = fb.RelaysLeft
		end
		-- Getarntes ICE, das gerade aufgeflogen ist.
		if typeof(fb.Reveal) == "number" then
			s.Cells[fb.Reveal] = ICE
			local btn = cellButtons[fb.Reveal]
			if btn then
				UITheme.Flash(btn, C.Magenta)
			end
		end
	end

	local info = REASON_TEXT[data.Reason]
	if info then
		pushLog(info.Text, info.Color, true)
	end

	redrawGrid()
	redrawChips()
end)

local RESOLVE_TEXT: { [string]: string } = {
	SOLVED = "zugriff gewaehrt",
	TIMEOUT = "verbindung zeitueberschreitung",
	NO_ATTEMPTS = "rig ueberlastet",
	OUT_OF_RANGE = "signal verloren",
	ABORTED = "abbruch durch benutzer",
	TARGET_GONE = "ziel nicht mehr erreichbar",
}

Remotes.HackResolved.OnClientEvent:Connect(function(data: any)
	local s = session
	if not s or typeof(data) ~= "table" or data.SessionId ~= s.Id then
		return
	end
	s.Closing = true

	resultOverlay.Visible = true
	TweenService:Create(resultOverlay, UITheme.Tween.Normal, { BackgroundTransparency = 0.12 }):Play()

	if data.Success then
		resultTitle.Text = "BREACH OK"
		resultTitle.TextColor3 = C.Cyan
		resultSub.Text = ("+%d CRY   //   TRACE +%.0f"):format(data.Reward or 0, data.TraceDelta or 0)
		resultSub.TextColor3 = C.Text
	else
		resultTitle.Text = "BREACH FEHLGESCHLAGEN"
		resultTitle.TextColor3 = C.Magenta
		resultSub.Text = ("%s   //   TRACE +%.0f"):format(RESOLVE_TEXT[data.Reason] or "abbruch", data.TraceDelta or 0)
		resultSub.TextColor3 = C.TextDim
	end

	task.delay(1.7, close)
end)

--==========================================================================
-- Timer
--==========================================================================

RunService.RenderStepped:Connect(function()
	local s = session
	if not s or not gui.Enabled then
		return
	end

	local remaining = math.max(0, s.Deadline - workspace:GetServerTimeNow())
	local fraction = if s.TimeLimit > 0 then math.clamp(remaining / s.TimeLimit, 0, 1) else 0

	timerFill.Size = UDim2.fromScale(fraction, 1)
	timerText.Text = ("%.1fs"):format(remaining)

	if s.Closing then
		timerFill.BackgroundColor3 = C.Line
	elseif fraction < 0.25 then
		-- letzte Sekunden: pulsierendes Warnmagenta
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 12)
		timerFill.BackgroundColor3 = C.Magenta:Lerp(C.Amber, pulse)
	else
		timerFill.BackgroundColor3 = C.Cyan
	end
end)

--==========================================================================
-- Notbremse: Sollte eine Eingabe nie beantwortet werden, setzen wir den
-- Schrittzaehler zurueck, damit die Session nicht stumm haengen bleibt.
--==========================================================================

task.spawn(function()
	while true do
		task.wait(2.5)
		local s = session
		if s and not s.Closing and s.NextStep > s.LastAck + 1 and os.clock() - s.LastSend > 2.5 then
			s.NextStep = s.LastAck + 1
			pushLog("> resync", C.TextDim, true)
		end
	end
end)
