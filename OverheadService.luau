-- OverheadService: подпись над головой: род и поколение, ник, возраст, рост, скорость
local Overhead = {}

local function label(parent, size, color, font, order)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, size + 4)
	l.Text = ""
	l.TextSize = size
	l.TextColor3 = color
	l.Font = font
	l.TextStrokeTransparency = 0.4
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

-- создаЄт подпись, возвращает таблицу дл€ Overhead.update
function Overhead.attach(character)
	local head = character:FindFirstChild("Head")
	if not head then return nil end

	local old = head:FindFirstChild("OverheadInfo")
	if old then old:Destroy() end

	local gui = Instance.new("BillboardGui")
	gui.Name = "OverheadInfo"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(300, 3 * 22 + 6)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 160

	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = frame

	local o = {
		gui = gui,
		head = head,
		lineage = label(frame, 15, Color3.new(1, 1, 1), Enum.Font.GothamBold, 1),
		nick = label(frame, 18, Color3.new(1, 1, 1), Enum.Font.GothamBold, 2),
		stats = label(frame, 14, Color3.fromRGB(215, 215, 215), Enum.Font.GothamMedium, 3),
	}
	gui.Parent = head
	return o
end

-- d = { Lineage, LineageColor, Generation, Nick, Age, Height, Speed }
function Overhead.update(o, d)
	if not o or not o.gui.Parent then return end
	o.lineage.Text = string.format("%s Х поколение %d", d.Lineage, d.Generation)
	o.lineage.TextColor3 = d.LineageColor
	o.nick.Text = d.Nick
	o.stats.Text = string.format("¬озраст %d  Х  –ост %.1f  Х  —корость %d", d.Age, d.Height, math.floor(d.Speed + 0.5))
	o.gui.StudsOffsetWorldSpace = Vector3.new(0, o.head.Size.Y * 0.5 + 1.4, 0)
end

return Overhead
