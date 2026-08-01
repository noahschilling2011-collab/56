-- ReplicatedStorage/Shared/UITheme.lua
--!strict
-- GHOSTNET :: Bausteine fuer das Fake-OS-Aussehen.
-- Damit HackUI und HUD nicht dreimal dieselben Farben und Rahmen bauen.

local TweenService = game:GetService("TweenService")
local Config = require(script.Parent.Config)

local UITheme = {}

UITheme.Color = Config.Theme
UITheme.Font = Enum.Font.Code

UITheme.Tween = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
}

--== Grundbausteine ========================================================

function UITheme.Frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = UITheme.Color.Panel
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	return f
end

function UITheme.Label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = UITheme.Font
	l.TextColor3 = UITheme.Color.Text
	l.TextSize = 14
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.RichText = true
	for k, v in props do
		(l :: any)[k] = v
	end
	return l
end

function UITheme.Button(props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = UITheme.Color.PanelLight
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Font = UITheme.Font
	b.TextColor3 = UITheme.Color.Text
	b.TextSize = 14
	b.Text = ""
	for k, v in props do
		(b :: any)[k] = v
	end
	return b
end

-- 1px-Rahmen im Terminal-Look.
function UITheme.Stroke(parent: GuiObject, color: Color3?, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or UITheme.Color.Line
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function UITheme.Corner(parent: GuiObject, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 3)
	c.Parent = parent
	return c
end

function UITheme.Padding(parent: GuiObject, px: number): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
	return p
end

--== Scanlines =============================================================
-- Prozedural aus duennen Frames gebaut, weil hier keine Textur-Asset-ID
-- hochgeladen werden kann. Optisch identisch, kostet ein paar Instanzen.
-- Liegt oben drauf und schluckt keine Klicks.

function UITheme.Scanlines(parent: GuiObject, spacing: number?): Frame
	local gap = spacing or 4
	local holder = UITheme.Frame({
		Name = "Scanlines",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		ClipsDescendants = true,
	})

	local lines = math.clamp(math.floor(parent.AbsoluteSize.Y / gap), 20, 220)
	for i = 0, lines do
		local line = UITheme.Frame({
			Name = "L",
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.new(0, 0, 0, i * gap),
			ZIndex = 50,
		})
		line.Parent = holder
	end

	-- langsam wandernder Helligkeitsstreifen
	local sweep = UITheme.Frame({
		Name = "Sweep",
		BackgroundColor3 = UITheme.Color.Cyan,
		BackgroundTransparency = 0.96,
		Size = UDim2.new(1, 0, 0, 90),
		Position = UDim2.new(0, 0, 0, -90),
		ZIndex = 51,
	})
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	grad.Parent = sweep
	sweep.Parent = holder

	task.spawn(function()
		while sweep.Parent do
			sweep.Position = UDim2.new(0, 0, 0, -90)
			local t = TweenService:Create(sweep, TweenInfo.new(3.2, Enum.EasingStyle.Linear), {
				Position = UDim2.new(0, 0, 1, 0),
			})
			t:Play()
			t.Completed:Wait()
			task.wait(2.4)
		end
	end)

	holder.Parent = parent
	return holder
end

--== Terminal-Tippanimation ================================================
-- Gibt eine Funktion zurueck, die eine Zeile Text zeichenweise ausgibt.
-- cancelled() darf true liefern, dann bricht die Ausgabe sofort ab.

function UITheme.TypeInto(label: TextLabel, text: string, cps: number?, cancelled: (() -> boolean)?)
	local speed = cps or 90
	local total = #text
	label.Text = ""
	local shown = 0
	local acc = 0
	while shown < total do
		if cancelled and cancelled() then
			label.Text = text
			return
		end
		acc += task.wait() * speed
		local step = math.floor(acc)
		if step >= 1 then
			acc -= step
			shown = math.min(total, shown + step)
			label.Text = string.sub(text, 1, shown)
		end
	end
	label.Text = text
end

--== Kleine Helfer =========================================================

function UITheme.Flash(obj: GuiObject, color: Color3)
	local original = obj.BackgroundColor3
	obj.BackgroundColor3 = color
	TweenService:Create(obj, UITheme.Tween.Slow, { BackgroundColor3 = original }):Play()
end

function UITheme.Screen(name: string, displayOrder: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = displayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	return gui
end

return UITheme
