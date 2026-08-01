-- ServerScriptService/Systems/HackEffects.lua
--!strict
-- GHOSTNET :: Was in der Welt passiert, wenn ein Hack klappt.
--
-- Das Attribut "OnSuccess" am Part ist ein Schluessel in diese Tabelle.
-- Ein neues Verhalten = ein neuer Eintrag hier. Der HackService kennt
-- keinen einzigen Objekttyp.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

type HackTarget = Types.HackTarget

local HackEffects = {}

--==========================================================================
-- Hilfsfunktionen
--==========================================================================

local function setLights(part: BasePart, enabled: boolean)
	for _, d in part:GetDescendants() do
		if d:IsA("Light") then
			d.Enabled = enabled
		end
	end
end

local function pulseLight(part: BasePart, color: Color3, duration: number)
	local existing = part:FindFirstChildOfClass("PointLight")
	local created = existing == nil

	local l: PointLight
	if existing then
		l = existing
	else
		l = Instance.new("PointLight")
		l.Parent = part
	end
	local oldColor, oldBright, oldRange = l.Color, l.Brightness, l.Range
	l.Color = color
	l.Brightness = 6
	l.Range = 18
	l.Enabled = true

	TweenService:Create(l, TweenInfo.new(duration, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
	task.delay(duration, function()
		if created then
			l:Destroy()
		else
			l.Color, l.Brightness, l.Range = oldColor, oldBright, oldRange
		end
	end)
end

-- Faerbt einen Part fuer die Dauer der Stoerung um und stellt danach
-- den Originalzustand wieder her.
local function recolorFor(part: BasePart, color: Color3, duration: number)
	local originalColor = part.Color
	TweenService:Create(part, TweenInfo.new(0.3), { Color = color }):Play()
	task.delay(duration, function()
		if part.Parent then
			TweenService:Create(part, TweenInfo.new(0.6), { Color = originalColor }):Play()
		end
	end)
end

--==========================================================================
-- Effekte
--==========================================================================

type EffectFn = (target: HackTarget, player: Player, duration: number) -> ()

local Effects: { [string]: EffectFn } = {}

-- Standard, wenn ein Part keinen bekannten OnSuccess-Wert hat.
Effects.Offline = function(target, _player, duration)
	local part = target.Part
	setLights(part, false)
	recolorFor(part, Config.Theme.Ice, duration)
	task.delay(duration, function()
		if part.Parent then
			setLights(part, true)
		end
	end)
end

Effects.CameraOffline = function(target, _player, duration)
	local part = target.Part
	setLights(part, false)
	recolorFor(part, Config.Theme.Ice, duration)

	-- Kamera senkt den Kopf, solange sie tot ist.
	local original = part.CFrame
	TweenService:Create(part, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		CFrame = original * CFrame.Angles(math.rad(-55), 0, 0),
	}):Play()

	task.delay(duration, function()
		if part.Parent then
			setLights(part, true)
			TweenService:Create(part, TweenInfo.new(1.0, Enum.EasingStyle.Quad), { CFrame = original }):Play()
		end
	end)
end

Effects.DoorOpen = function(target, _player, duration)
	local part = target.Part
	local original = part.CFrame
	local drop = part.Size.Y + 0.4

	part.CanCollide = false
	pulseLight(part, Config.Theme.Cyan, 0.8)
	TweenService:Create(part, TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		CFrame = original * CFrame.new(0, -drop, 0),
	}):Play()

	task.delay(duration, function()
		if not part.Parent then
			return
		end
		local close = TweenService:Create(part, TweenInfo.new(0.9, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			CFrame = original,
		})
		close:Play()
		close.Completed:Connect(function()
			if part.Parent then
				part.CanCollide = true
			end
		end)
	end)
end

Effects.AtmPayout = function(target, _player, duration)
	local part = target.Part
	pulseLight(part, Config.Theme.Amber, 1.2)
	recolorFor(part, Config.Theme.Amber, math.min(duration, 3))

	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Config.Theme.Amber)
	sparks.Lifetime = NumberRange.new(0.4, 0.9)
	sparks.Rate = 90
	sparks.Speed = NumberRange.new(6, 12)
	sparks.SpreadAngle = Vector2.new(35, 35)
	sparks.Size = NumberSequence.new(0.18)
	sparks.Parent = part

	task.delay(1.1, function()
		sparks.Enabled = false
		task.delay(1.2, function()
			sparks:Destroy()
		end)
	end)
end

--==========================================================================
-- Aufruf durch den HackService
--==========================================================================

function HackEffects.Apply(target: HackTarget, player: Player)
	local fn = Effects[target.OnSuccess]
	if not fn then
		warn(("[GHOSTNET] Unbekannter OnSuccess-Effekt '%s' an %s - benutze 'Offline'."):format(
			target.OnSuccess,
			target.Part:GetFullName()
		))
		fn = Effects.Offline
	end

	local duration = math.max(1, target.DownTime)
	local call = table.pack(pcall(fn, target, player, duration))
	if not call[1] then
		warn(("[GHOSTNET] Effekt '%s' ist fehlgeschlagen: %s"):format(target.OnSuccess, tostring(call[2])))
	end
end

function HackEffects.Has(name: string): boolean
	return Effects[name] ~= nil
end

return HackEffects
