--!strict
--[[
	3D Robux shop: vehicles (speed / fly) and visual weapons.
	Game pass IDs live in BrainrotData.MONETIZED_SHOP.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local PlotSystem = require(script.Parent:WaitForChild("PlotSystem"))

local ShopSystem = {}

local function hint(player: Player, text: string)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local ev = remotes and remotes:FindFirstChild("ShowHint")
	if ev and ev:IsA("RemoteEvent") then
		ev:FireClient(player, text)
	end
end

local function catalog(): { any }
	return BrainrotData.MONETIZED_SHOP or {}
end

local function defById(id: string): any
	for _, item in ipairs(catalog()) do
		if item.Id == id then
			return item
		end
	end
	return nil
end

local function defByPass(passId: number): any
	for _, item in ipairs(catalog()) do
		if (item.GamePassId or 0) == passId and passId > 0 then
			return item
		end
	end
	return nil
end

local function passIdOf(item: any): number
	local attrName = "ShopPass_" .. tostring(item.Id)
	local attr = workspace:GetAttribute(attrName)
	if type(attr) == "number" and attr > 0 then
		return attr
	end
	return tonumber(item.GamePassId) or 0
end

local function playerOwns(player: Player, item: any): boolean
	if PlayerData.OwnsShopItem(player, item.Id) then
		return true
	end
	local passId = passIdOf(item)
	if passId > 0 then
		local ok, owned = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		if ok and owned then
			PlayerData.GrantShopItem(player, item.Id)
			return true
		end
	end
	return false
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.CanCollide = false
	p.Massless = true
	p.Anchored = true
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function makeDisplay(itemId: string, parent: Instance, at: CFrame)
	if itemId == "skateboard" then
		local deck = part(parent, "Deck", Vector3.new(2.4, 0.12, 0.7), at, Color3.fromRGB(40, 40, 48), Enum.Material.SmoothPlastic)
		part(parent, "Grip", Vector3.new(2.2, 0.04, 0.6), at * CFrame.new(0, 0.08, 0), Color3.fromRGB(220, 60, 80), Enum.Material.Fabric)
		for _, x in ipairs({ -0.85, 0.85 }) do
			for _, z in ipairs({ -0.22, 0.22 }) do
				part(parent, "Wheel", Vector3.new(0.22, 0.22, 0.22), at * CFrame.new(x, -0.18, z), Color3.fromRGB(30, 30, 30), Enum.Material.SmoothPlastic)
			end
		end
		return deck
	elseif itemId == "magic_carpet" then
		return part(parent, "Rug", Vector3.new(3.2, 0.12, 2.0), at, Color3.fromRGB(170, 40, 70), Enum.Material.Fabric)
	elseif itemId == "airplane" then
		local body = part(parent, "Fuselage", Vector3.new(3.2, 0.7, 0.7), at, Color3.fromRGB(230, 230, 240), Enum.Material.SmoothPlastic)
		part(parent, "Wing", Vector3.new(0.5, 0.12, 3.6), at, Color3.fromRGB(50, 90, 180), Enum.Material.SmoothPlastic)
		part(parent, "Tail", Vector3.new(0.7, 0.9, 0.12), at * CFrame.new(-1.4, 0.5, 0), Color3.fromRGB(50, 90, 180), Enum.Material.SmoothPlastic)
		part(parent, "Nose", Vector3.new(0.5, 0.5, 0.5), at * CFrame.new(1.7, 0, 0), Color3.fromRGB(220, 80, 70), Enum.Material.SmoothPlastic)
		return body
	elseif itemId == "sword" then
		part(parent, "Blade", Vector3.new(0.18, 2.4, 0.08), at * CFrame.new(0, 0.6, 0), Color3.fromRGB(210, 220, 230), Enum.Material.Metal)
		return part(parent, "Hilt", Vector3.new(0.22, 0.7, 0.22), at * CFrame.new(0, -0.7, 0), Color3.fromRGB(90, 60, 40), Enum.Material.Wood)
	elseif itemId == "mace" then
		part(parent, "Head", Vector3.new(0.9, 0.9, 0.9), at * CFrame.new(0, 1.1, 0), Color3.fromRGB(120, 120, 130), Enum.Material.Metal)
		return part(parent, "Shaft", Vector3.new(0.22, 2.2, 0.22), at, Color3.fromRGB(90, 60, 40), Enum.Material.Wood)
	else
		part(parent, "Head", Vector3.new(1.1, 0.7, 0.12), at * CFrame.new(0.2, 1.0, 0), Color3.fromRGB(140, 140, 150), Enum.Material.Metal)
		return part(parent, "Haft", Vector3.new(0.2, 2.2, 0.2), at, Color3.fromRGB(90, 60, 40), Enum.Material.Wood)
	end
end

local function makeTool(item: any): Tool
	local tool = Instance.new("Tool")
	tool.Name = item.Name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ShopItemId", item.Id)
	tool:SetAttribute("SpeedMult", item.SpeedMult or 1)
	tool:SetAttribute("Fly", item.Fly == true)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 1, 0.4)
	handle.Transparency = if item.Kind == "vehicle" then 1 else 0
	handle.CanCollide = false
	handle.Massless = true
	handle.Color = Color3.fromRGB(80, 55, 35)
	handle.Parent = tool

	if item.Kind == "vehicle" then
		makeDisplay(item.Id, tool, handle.CFrame * CFrame.new(0, -2.2, 0))
		for _, p in ipairs(tool:GetChildren()) do
			if p:IsA("BasePart") and p ~= handle then
				p.Anchored = false
				p.Massless = true
				p.CanCollide = false
				p.CFrame = handle.CFrame * CFrame.new(0, if item.Id == "airplane" then 1.2 else -2.4, 0)
				weld(handle, p)
			end
		end
		if item.Id == "skateboard" then
			tool.Grip = CFrame.new(0, 2.2, 0) * CFrame.Angles(0, 0, math.pi / 2)
		elseif item.Id == "magic_carpet" then
			tool.Grip = CFrame.new(0, 2.6, 0)
		else
			tool.Grip = CFrame.new(0, -1.4, 1.4) * CFrame.Angles(0, math.pi / 2, 0)
		end
	else
		makeDisplay(item.Id, tool, handle.CFrame)
		for _, p in ipairs(tool:GetChildren()) do
			if p:IsA("BasePart") and p ~= handle then
				p.Anchored = false
				p.Massless = true
				p.CanCollide = false
				weld(handle, p)
			end
		end
		tool.Grip = CFrame.new(0, -0.8, 0)
		local last = 0
		tool.Activated:Connect(function()
			if os.clock() - last < 0.45 then
				return
			end
			last = os.clock()
			local base = tool.Grip
			for i = 1, 6 do
				tool.Grip = base * CFrame.Angles(math.rad(-80 * (i / 6)), 0, 0)
				task.wait(0.02)
			end
			tool.Grip = base
		end)
	end
	return tool
end

local function stripItemTools(player: Player)
	local function wipe(container: Instance?)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("ShopItemId") ~= nil then
				child:Destroy()
			end
		end
	end
	wipe(player:FindFirstChildOfClass("Backpack"))
	wipe(player.Character)
end

local function giveOwnedTools(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	stripItemTools(player)
	for _, item in ipairs(catalog()) do
		if playerOwns(player, item) then
			makeTool(item).Parent = backpack
		end
	end
end

local function refreshSpeed(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local best = 1
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") then
			local m = child:GetAttribute("SpeedMult")
			if type(m) == "number" and m > best then
				best = m
			end
		end
	end
	char:SetAttribute("ShopSpeedMult", best)
	PlayerData.ApplyStats(player)
end

local function hookCharacter(player: Player, char: Model)
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("ShopItemId") ~= nil then
			task.defer(function()
				refreshSpeed(player)
			end)
		end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			task.defer(function()
				refreshSpeed(player)
			end)
		end
	end)
	task.delay(0.4, function()
		if player.Parent then
			giveOwnedTools(player)
			PlayerData.ApplyStats(player)
		end
	end)
	task.delay(1.2, function()
		if player.Parent then
			PlayerData.ApplyStats(player)
		end
	end)
end

local function onPlayer(player: Player)
	for _, item in ipairs(catalog()) do
		playerOwns(player, item)
	end
	player.CharacterAdded:Connect(function(char)
		hookCharacter(player, char)
	end)
	if player.Character then
		hookCharacter(player, player.Character)
	end
end

local function promptBuy(player: Player, item: any)
	if playerOwns(player, item) then
		giveOwnedTools(player)
		hint(player, "You already own " .. item.Name .. " — check your backpack.")
		return
	end
	local passId = passIdOf(item)
	if passId > 0 then
		MarketplaceService:PromptGamePassPurchase(player, passId)
		return
	end
	if RunService:IsStudio() then
		PlayerData.GrantShopItem(player, item.Id)
		giveOwnedTools(player)
		hint(player, item.Name .. " granted in Studio. Paste a GamePassId for live Robux sales.")
		return
	end
	hint(player, "Create a Game Pass for " .. item.Name .. " and paste GamePassId in BrainrotData.")
end

function ShopSystem.Setup()
	local spot = PlotSystem.PlazaSpots.Shop
	local cx, cz = 68, 28
	if spot then
		cx, cz = spot.X, spot.Y
	end

	local stall = Instance.new("Model")
	stall.Name = "RobuxShop"

	local gy = 16
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(cx, 500, cz), Vector3.new(0, -1000, 0), params)
	if hit then
		gy = hit.Position.Y
	end

	local function anchored(name: string, size: Vector3, pos: Vector3, color: Color3, mat: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Position = pos
		p.Anchored = true
		p.Color = color
		p.Material = mat
		p.Parent = stall
		return p
	end

	local floor = anchored("Floor", Vector3.new(22, 0.6, 12), Vector3.new(cx, gy + 0.3, cz), Color3.fromRGB(70, 50, 36), Enum.Material.WoodPlanks)
	stall.PrimaryPart = floor
	anchored("Awning", Vector3.new(22, 0.4, 12), Vector3.new(cx, gy + 8.2, cz), Color3.fromRGB(180, 40, 50), Enum.Material.Fabric)
	anchored("PostL", Vector3.new(0.5, 8, 0.5), Vector3.new(cx - 10, gy + 4.3, cz - 5), Color3.fromRGB(90, 65, 40), Enum.Material.Wood)
	anchored("PostR", Vector3.new(0.5, 8, 0.5), Vector3.new(cx + 10, gy + 4.3, cz - 5), Color3.fromRGB(90, 65, 40), Enum.Material.Wood)
	anchored("PostLB", Vector3.new(0.5, 8, 0.5), Vector3.new(cx - 10, gy + 4.3, cz + 5), Color3.fromRGB(90, 65, 40), Enum.Material.Wood)
	anchored("PostRB", Vector3.new(0.5, 8, 0.5), Vector3.new(cx + 10, gy + 4.3, cz + 5), Color3.fromRGB(90, 65, 40), Enum.Material.Wood)

	local sign = anchored("Sign", Vector3.new(10, 2.4, 0.4), Vector3.new(cx, gy + 10.2, cz), Color3.fromRGB(28, 22, 18), Enum.Material.Wood)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.Parent = sign
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 1, 0)
	title.BackgroundTransparency = 1
	title.Text = "ROBUX SHOP\nRides & Weapons"
	title.TextScaled = true
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.fromRGB(255, 220, 90)
	title.Parent = gui
	local back = gui:Clone()
	back.Face = Enum.NormalId.Back
	back.Parent = sign

	for i, item in ipairs(catalog()) do
		local col = ((i - 1) % 3) - 1
		local row = if i <= 3 then -1 else 1
		local px = cx + col * 6.2
		local pz = cz + row * 3.2
		local stand = anchored("Stand_" .. item.Id, Vector3.new(2.4, 1.1, 2.4), Vector3.new(px, gy + 0.95, pz), Color3.fromRGB(50, 40, 32), Enum.Material.Wood)
		local displayAt = CFrame.new(px, gy + 2.6, pz)
		makeDisplay(item.Id, stall, displayAt)
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 160, 0, 54)
		bb.StudsOffset = Vector3.new(0, 2.4, 0)
		bb.AlwaysOnTop = false
		bb.Parent = stand
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = item.Name .. "\n" .. tostring(item.Desc) .. "\n" .. tostring(item.Robux) .. " R$"
		lbl.Font = Enum.Font.GothamBold
		lbl.TextScaled = true
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.TextStrokeTransparency = 0.3
		lbl.Parent = bb
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Buy / Take"
		prompt.ObjectText = item.Name
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = stand
		local captured = item
		prompt.Triggered:Connect(function(plr: Player)
			promptBuy(plr, captured)
		end)
	end

	stall.Parent = workspace
	print("[ShopSystem] Robux shop at " .. tostring(Vector3.new(cx, gy, cz)))

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local item = defByPass(passId)
		if not item then
			return
		end
		PlayerData.GrantShopItem(player, item.Id)
		giveOwnedTools(player)
		hint(player, "You bought " .. item.Name .. "!")
	end)

	Players.PlayerAdded:Connect(onPlayer)
	for _, existing in ipairs(Players:GetPlayers()) do
		task.defer(onPlayer, existing)
	end
end

return ShopSystem
