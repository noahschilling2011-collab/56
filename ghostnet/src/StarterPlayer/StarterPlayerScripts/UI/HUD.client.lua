-- StarterPlayer/StarterPlayerScripts/UI/HUD.client.lua
--!strict
-- GHOSTNET :: Dauerhaftes HUD - Wallet, Ziel-Prompt, Meldungen.
--
-- Der HUD trifft KEINE Entscheidungen. Er zeigt an, was der Server sagt,
-- und schickt beim Druck auf [E] eine Bitte los. Ob sie erlaubt ist,
-- entscheidet ausschliesslich der Server.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local C = UITheme.Color

--==========================================================================
-- Zustand
--==========================================================================

local wallet = { Banked = 0, Unsold = 0, Tier = 1 }
local rig = table.clone(Config.Rig.StartLevels)
local hackOpen = false
local cooldownUntil: { [string]: number } = {}
local currentTargetId: string? = nil

--==========================================================================
-- Aufbau
--==========================================================================

local gui = UITheme.Screen("GhostNetHUD", 10)
gui.Parent = playerGui

--== Wallet oben rechts ====================================================

local walletPanel = UITheme.Frame({
	Name = "Wallet",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 18),
	Size = UDim2.fromOffset(226, 58),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.08,
	Parent = gui,
})
UITheme.Corner(walletPanel, 4)
UITheme.Stroke(walletPanel, C.Line)
UITheme.Padding(walletPanel, 10)

UITheme.Label({
	Name = "Title",
	Text = "WALLET",
	TextColor3 = C.TextDim,
	TextSize = 11,
	Size = UDim2.new(1, 0, 0, 12),
	Parent = walletPanel,
})

local walletValue = UITheme.Label({
	Name = "Value",
	Text = "0 CRY",
	TextColor3 = C.Cyan,
	TextSize = 20,
	Position = UDim2.new(0, 0, 0, 14),
	Size = UDim2.new(1, 0, 0, 24),
	Parent = walletPanel,
})

local walletSub = UITheme.Label({
	Name = "Sub",
	Text = "unverkauft // TIER 1",
	TextColor3 = C.TextDim,
	TextSize = 11,
	Position = UDim2.new(0, 0, 1, -12),
	Size = UDim2.new(1, 0, 0, 12),
	Parent = walletPanel,
})

--== Ziel-Prompt unten Mitte ===============================================

local prompt = UITheme.Button({
	Name = "TargetPrompt",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -46),
	Size = UDim2.fromOffset(360, 76),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.06,
	Visible = false,
	Parent = gui,
})
UITheme.Corner(prompt, 4)
local promptStroke = UITheme.Stroke(prompt, C.CyanDim)
UITheme.Padding(prompt, 12)

local promptName = UITheme.Label({
	Name = "Name",
	Text = "",
	TextColor3 = C.Cyan,
	TextSize = 16,
	Size = UDim2.new(1, 0, 0, 18),
	Parent = prompt,
})

local promptInfo = UITheme.Label({
	Name = "Info",
	Text = "",
	TextColor3 = C.TextDim,
	TextSize = 12,
	Position = UDim2.new(0, 0, 0, 22),
	Size = UDim2.new(1, 0, 0, 14),
	Parent = prompt,
})

local promptAction = UITheme.Label({
	Name = "Action",
	Text = "[E]  BREACH",
	TextColor3 = C.Text,
	TextSize = 14,
	Position = UDim2.new(0, 0, 1, -18),
	Size = UDim2.new(1, 0, 0, 16),
	Parent = prompt,
})

--== Meldungen =============================================================

local toastHolder = UITheme.Frame({
	Name = "Toasts",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -132),
	Size = UDim2.fromOffset(420, 130),
	BackgroundTransparency = 1,
	Parent = gui,
})
local toastLayout = Instance.new("UIListLayout")
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Padding = UDim.new(0, 4)
toastLayout.Parent = toastHolder

local toastOrder = 0

local function toast(text: string, color: Color3)
	toastOrder += 1
	local item = UITheme.Frame({
		Name = "Toast",
		Size = UDim2.fromOffset(420, 26),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		LayoutOrder = toastOrder,
		Parent = toastHolder,
	})
	UITheme.Corner(item, 3)
	UITheme.Stroke(item, color)

	local label = UITheme.Label({
		Text = text,
		TextColor3 = color,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = item,
	})

	task.delay(3.2, function()
		if not item.Parent then
			return
		end
		TweenService:Create(item, UITheme.Tween.Normal, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, UITheme.Tween.Normal, { TextTransparency = 1 }):Play()
		task.wait(0.3)
		item:Destroy()
	end)
end

--== Weltmarkierung des naechsten Ziels ====================================

local highlight = Instance.new("Highlight")
highlight.FillColor = C.Cyan
highlight.FillTransparency = 0.86
highlight.OutlineColor = C.Cyan
highlight.OutlineTransparency = 0.15
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Enabled = false
highlight.Parent = gui

--==========================================================================
-- Anzeige aktualisieren
--==========================================================================

local function refreshWallet()
	walletValue.Text = ("%d CRY"):format(wallet.Unsold)
	walletSub.Text = ("unverkauft // TIER %d // BANK %d"):format(wallet.Tier, wallet.Banked)
end

-- Gleiche Rechnung wie auf dem Server: Abstand zur Oberflaeche, nicht zum
-- Mittelpunkt. Sonst zeigt der HUD etwas anderes an, als der Server erlaubt.
local function surfaceDistance(part: BasePart, position: Vector3): number
	local rel = part.CFrame:PointToObjectSpace(position)
	local half = part.Size * 0.5
	local clamped = Vector3.new(
		math.clamp(rel.X, -half.X, half.X),
		math.clamp(rel.Y, -half.Y, half.Y),
		math.clamp(rel.Z, -half.Z, half.Z)
	)
	return (rel - clamped).Magnitude
end

local function cooldownLeft(id: string): number
	local until_ = cooldownUntil[id]
	if not until_ then
		return 0
	end
	return math.max(0, until_ - os.clock())
end

local function hidePrompt()
	if prompt.Visible then
		prompt.Visible = false
	end
	currentTargetId = nil
	highlight.Enabled = false
	highlight.Adornee = nil
end

local function scan()
	if hackOpen then
		hidePrompt()
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		hidePrompt()
		return
	end

	local range = Config.GetRange(rig.NetCard)
	local best: BasePart? = nil
	local bestDist = math.huge

	for _, inst in CollectionService:GetTagged(Config.HackableTag) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			local d = surfaceDistance(inst, root.Position)
			if d <= range and d < bestDist then
				best, bestDist = inst, d
			end
		end
	end

	if not best then
		hidePrompt()
		return
	end

	local id = best:GetAttribute("TargetId")
	if typeof(id) ~= "string" then
		hidePrompt() -- Server hat den Part noch nicht registriert
		return
	end

	currentTargetId = id
	prompt.Visible = true
	highlight.Adornee = best
	highlight.Enabled = true

	local name = best:GetAttribute("DisplayName")
	promptName.Text = if typeof(name) == "string" and name ~= "" then name else best.Name

	local difficulty = best:GetAttribute("Difficulty")
	local reward = best:GetAttribute("Reward")
	local diffNum = if typeof(difficulty) == "number" then difficulty else 1
	local rewardNum = if typeof(reward) == "number" and reward >= 0 then reward else Config.GetReward(diffNum)

	promptInfo.Text = ("SCHWIERIGKEIT %d/10   //   %d CRY   //   %.0fm"):format(diffNum, rewardNum, bestDist)

	local offline = best:GetAttribute("Offline") == true
	local cd = cooldownLeft(id)

	if offline then
		promptAction.Text = "ZIEL BEREITS OFFLINE"
		promptAction.TextColor3 = C.TextDim
		highlight.OutlineColor = C.Line
		promptStroke.Color = C.Line
	elseif cd > 0 then
		promptAction.Text = ("GESPERRT // %ds"):format(math.ceil(cd))
		promptAction.TextColor3 = C.Amber
		highlight.OutlineColor = C.Amber
		promptStroke.Color = C.Amber
	else
		promptAction.Text = "[E]  BREACH"
		promptAction.TextColor3 = C.Text
		highlight.OutlineColor = C.Cyan
		promptStroke.Color = C.CyanDim
	end
end

--==========================================================================
-- Eingabe
--==========================================================================

local function requestHack()
	if hackOpen or not currentTargetId then
		return
	end
	Remotes.HackRequestStart:FireServer({ TargetId = currentTargetId })
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.E then
		requestHack()
	end
end)

prompt.Activated:Connect(requestHack) -- Touch/Klick

--==========================================================================
-- Server-Meldungen
--==========================================================================

Remotes.EconomySync.OnClientEvent:Connect(function(snapshot: any)
	if typeof(snapshot) ~= "table" then
		return
	end
	wallet.Banked = snapshot.Banked or 0
	wallet.Unsold = snapshot.Unsold or 0
	wallet.Tier = snapshot.Tier or 1
	if typeof(snapshot.Rig) == "table" then
		rig = snapshot.Rig
	end
	refreshWallet()
end)

Remotes.HackSessionStarted.OnClientEvent:Connect(function()
	hackOpen = true
	hidePrompt()
end)

Remotes.HackResolved.OnClientEvent:Connect(function(data: any)
	hackOpen = false
	if typeof(data) ~= "table" then
		return
	end

	if typeof(data.TargetId) == "string" and typeof(data.Cooldown) == "number" and data.Cooldown > 0 then
		cooldownUntil[data.TargetId] = os.clock() + data.Cooldown
	end

	if data.Success then
		toast(("BREACH ERFOLGREICH   +%d CRY   TRACE +%.0f"):format(data.Reward or 0, data.TraceDelta or 0), C.Cyan)
	else
		local reasons = {
			TIMEOUT = "ZEIT ABGELAUFEN",
			NO_ATTEMPTS = "RIG UEBERLASTET - KEINE VERSUCHE MEHR",
			OUT_OF_RANGE = "VERBINDUNG ABGERISSEN - ZU WEIT WEG",
			ABORTED = "ABGEBROCHEN",
			TARGET_GONE = "ZIEL VERSCHWUNDEN",
		}
		local text = reasons[data.Reason] or "BREACH FEHLGESCHLAGEN"
		toast(("%s   TRACE +%.0f"):format(text, data.TraceDelta or 0), C.Magenta)
	end
end)

Remotes.HackDenied.OnClientEvent:Connect(function(data: any)
	if typeof(data) ~= "table" then
		return
	end
	local seconds = tonumber(data.Seconds) or 0

	if data.Reason == "COOLDOWN" then
		if typeof(data.TargetId) == "string" then
			cooldownUntil[data.TargetId] = os.clock() + seconds
		end
		toast(("ZIEL NOCH GESPERRT // %ds"):format(math.ceil(seconds)), C.Amber)
	elseif data.Reason == "LEVEL" then
		toast(("RIG ZU SCHWACH // TIER %d NOETIG"):format(seconds), C.Amber)
	elseif data.Reason == "RANGE" then
		toast("AUSSER REICHWEITE - NAEHER RAN", C.Amber)
	elseif data.Reason == "OFFLINE" then
		toast("ZIEL IST BEREITS OFFLINE", C.TextDim)
	else
		toast("ZUGRIFF VERWEIGERT", C.Magenta)
	end
end)

--==========================================================================
-- Schleife
--==========================================================================

refreshWallet()

local accumulator = 0
RunService.RenderStepped:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.15 then
		return
	end
	accumulator = 0
	scan()
end)

UITheme.Scanlines(walletPanel, 4)
