-- ClientToast: всплывающие уведомления вверху экрана (только клиент)
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Toast = {}
local holder

local function ensure()
	if holder and holder.Parent then return holder end

	local gui = Instance.new("ScreenGui")
	gui.Name = "Toasts"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(440, 240)
	holder.Position = UDim2.new(0.5, -220, 0, 64)
	holder.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	return holder
end

local order = 0

function Toast.show(text, color, duration)
	local h = ensure()
	order += 1

	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Size = UDim2.new(1, 0, 0, 0)
	l.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	l.BackgroundTransparency = 0.2
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 17
	l.TextWrapped = true
	l.Text = text
	l.Parent = h

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = l
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	pad.Parent = l

	task.delay(duration or 4, function()
		if not l.Parent then return end
		local tw = TweenService:Create(l, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 })
		tw:Play()
		tw.Completed:Wait()
		l:Destroy()
	end)
end

return Toast
