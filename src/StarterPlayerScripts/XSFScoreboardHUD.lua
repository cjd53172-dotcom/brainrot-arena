--[[
	XSFScoreboardHUD — small left-side translucent scoreboard.

	Shows Name / Kills / Deaths from each player's leaderstats,
	plus match clock (10:00) and kill limit (25).
	Toggle with M (or D-Pad Down on controller). Always starts visible.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local MAX_ROWS = 10
local connections = {}

local gui = Instance.new("ScreenGui")
gui.Name = "XSFScoreboardHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 0.5)
panel.Position = UDim2.new(0, 14, 0.5, 0)
panel.Size = UDim2.fromOffset(220, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
panel.BackgroundTransparency = 0.55
panel.BorderSizePixel = 0
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.PaddingLeft = UDim.new(0, 10)
pad.PaddingRight = UDim.new(0, 10)
pad.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 2)
layout.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.LayoutOrder = 0
title.Size = UDim2.new(1, 0, 0, 18)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextColor3 = Color3.fromRGB(230, 230, 235)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "SCORE  ·  M"
title.Parent = panel

local clock = Instance.new("TextLabel")
clock.Name = "Clock"
clock.LayoutOrder = 1
clock.Size = UDim2.new(1, 0, 0, 14)
clock.BackgroundTransparency = 1
clock.Font = Enum.Font.GothamMedium
clock.TextSize = 11
clock.TextColor3 = Color3.fromRGB(180, 200, 140)
clock.TextXAlignment = Enum.TextXAlignment.Left
clock.Text = "10:00  ·  first to 25"
clock.Parent = panel

local header = Instance.new("TextLabel")
header.Name = "Header"
header.LayoutOrder = 2
header.Size = UDim2.new(1, 0, 0, 14)
header.BackgroundTransparency = 1
header.Font = Enum.Font.GothamMedium
header.TextSize = 11
header.TextColor3 = Color3.fromRGB(160, 165, 175)
header.TextXAlignment = Enum.TextXAlignment.Left
header.Text = "NAME                  K   D"
header.Parent = panel

local function clearConns()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	connections = {}
end

local function makeRow(order)
	local row = Instance.new("TextLabel")
	row.Name = "Row" .. tostring(order)
	row.LayoutOrder = order + 2
	row.Size = UDim2.new(1, 0, 0, 16)
	row.BackgroundTransparency = 1
	row.Font = Enum.Font.Gotham
	row.TextSize = 12
	row.TextColor3 = Color3.fromRGB(235, 235, 240)
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.Text = ""
	row.Parent = panel
	return row
end

local rows = {}
for i = 1, MAX_ROWS do
	rows[i] = makeRow(i)
end

local function playerName(player)
	if player.DisplayName and player.DisplayName ~= "" then
		return player.DisplayName
	end
	return player.Name
end

local function trimName(name)
	if #name <= 14 then
		return name
	end
	return string.sub(name, 1, 13) .. "…"
end

local function refresh()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local ls = player:FindFirstChild("leaderstats")
		local k = ls and ls:FindFirstChild("Kills")
		local d = ls and ls:FindFirstChild("Deaths")
		table.insert(list, {
			Player = player,
			Name = playerName(player),
			Kills = (k and tonumber(k.Value)) or 0,
			Deaths = (d and tonumber(d.Value)) or 0,
		})
	end
	table.sort(list, function(a, b)
		if a.Kills == b.Kills then
			return a.Deaths < b.Deaths
		end
		return a.Kills > b.Kills
	end)

	for i = 1, MAX_ROWS do
		local entry = list[i]
		local label = rows[i]
		if entry then
			local mine = entry.Player == localPlayer
			label.TextColor3 = if mine then Color3.fromRGB(120, 210, 255) else Color3.fromRGB(235, 235, 240)
			label.Font = if mine then Enum.Font.GothamBold else Enum.Font.Gotham
			label.Text = string.format(
				"%-14s  %2d  %2d",
				trimName(entry.Name),
				entry.Kills,
				entry.Deaths
			)
			label.Visible = true
		else
			label.Text = ""
			label.Visible = false
		end
	end
end

local function watchPlayer(player)
	local function hookStats(ls)
		if not ls then
			return
		end
		table.insert(connections, ls.ChildAdded:Connect(function()
			refresh()
		end))
		for _, child in ipairs(ls:GetChildren()) do
			if child:IsA("IntValue") or child:IsA("NumberValue") then
				table.insert(connections, child.Changed:Connect(refresh))
			end
		end
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		hookStats(ls)
	end
	table.insert(connections, player.ChildAdded:Connect(function(child)
		if child.Name == "leaderstats" then
			hookStats(child)
			refresh()
		end
	end))
end

local function rebindAll()
	clearConns()
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(function(player)
		watchPlayer(player)
		refresh()
	end))
	table.insert(connections, Players.PlayerRemoving:Connect(function()
		task.defer(refresh)
	end))
	refresh()
end

rebindAll()

local visible = true
local function setVisible(on)
	visible = on
	panel.Visible = on
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.M or input.KeyCode == Enum.KeyCode.DPadDown then
		setVisible(not visible)
	end
end)

local function formatTime(sec)
	sec = math.max(0, math.floor(sec))
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%d:%02d", m, s)
end

task.spawn(function()
	local match = ReplicatedStorage:WaitForChild("XSFMatch", 30)
	if not match then
		return
	end
	local secondsLeft = match:WaitForChild("SecondsLeft", 5)
	local killLimit = match:FindFirstChild("KillLimit")
	local status = match:FindFirstChild("Status")
	local winner = match:FindFirstChild("Winner")
	local limit = (killLimit and killLimit.Value) or 25

	local function updateClock()
		if status and status.Value == "over" then
			local w = (winner and winner.Value ~= "" and winner.Value) or "—"
			clock.Text = "OVER  ·  " .. w
			clock.TextColor3 = Color3.fromRGB(255, 200, 100)
			return
		end
		local left = (secondsLeft and secondsLeft.Value) or 0
		clock.Text = formatTime(left) .. "  ·  first to " .. tostring(limit)
		if left <= 30 then
			clock.TextColor3 = Color3.fromRGB(255, 140, 120)
		else
			clock.TextColor3 = Color3.fromRGB(180, 200, 140)
		end
	end

	if secondsLeft then
		secondsLeft.Changed:Connect(updateClock)
	end
	if status then
		status.Changed:Connect(updateClock)
	end
	updateClock()
end)

print("[XSFScoreboardHUD] left scoreboard ready (toggle M)")
