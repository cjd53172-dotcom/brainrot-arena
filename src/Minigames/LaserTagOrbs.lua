--!strict
--[[
	Paste this Script into ServerScriptService of the Laser Tag PLACE
	(alongside ReturnToArena — not the Brainrot Arena hub).

	Each life you get 3 throw orbs. Throw one (click / tap with the tool
	equipped) and you teleport to where it lands.

	After pasting: File → Publish to Roblox → overwrite THIS laser tag place only.
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

print("[LaserTagOrbs] script running in " .. tostring(script:GetFullName()))

local ORBS_PER_LIFE = 3
local THROW_SPEED = 92
local THROW_UP = 22
local MAX_FLIGHT = 4
local LAND_LIFT = 3.2

local function setAmmoLabel(tool: Tool, ammo: number)
	tool.Name = "Teleport Orb (" .. tostring(ammo) .. ")"
	tool.ToolTip = tostring(ammo) .. " left this life"
end

local function landCFrame(hitPos: Vector3, hitNormal: Vector3?): CFrame
	local up = if hitNormal and hitNormal.Magnitude > 0.2 then hitNormal.Unit else Vector3.yAxis
	if up.Y < 0.35 then
		up = Vector3.yAxis
	end
	local pos = hitPos + up * LAND_LIFT
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local roof = workspace:Raycast(pos, Vector3.new(0, 6, 0), params)
	if roof then
		pos = Vector3.new(pos.X, roof.Position.Y - 2.5, pos.Z)
	end
	return CFrame.new(pos)
end

local function teleportTo(player: Player, pos: Vector3, normal: Vector3?)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (hrp and hrp:IsA("BasePart") and hum and hum.Health > 0) then
		return
	end
	local look = (hrp :: BasePart).CFrame.LookVector
	local cf = landCFrame(pos, normal)
	;(hrp :: BasePart).CFrame = CFrame.new(cf.Position, cf.Position + Vector3.new(look.X, 0, look.Z))
end

local function throwOrb(player: Player, tool: Tool)
	local ammo = tool:GetAttribute("Ammo")
	if type(ammo) ~= "number" or ammo <= 0 then
		return
	end
	local last = tool:GetAttribute("LastThrow")
	if type(last) == "number" and os.clock() - last < 0.45 then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end
	tool:SetAttribute("LastThrow", os.clock())
	tool:SetAttribute("Ammo", ammo - 1)
	setAmmoLabel(tool, ammo - 1)

	local origin = (hrp :: BasePart).CFrame
	local dir = origin.LookVector
	local spawnAt = origin.Position + dir * 3 + Vector3.new(0, 1.4, 0)

	local orb = Instance.new("Part")
	orb.Name = "TeleportOrb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(1.35, 1.35, 1.35)
	orb.Color = Color3.fromRGB(80, 220, 255)
	orb.Material = Enum.Material.Neon
	orb.CanCollide = true
	orb.Massless = false
	orb.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.2, 0.1, 1, 1)
	orb.CFrame = CFrame.new(spawnAt)
	orb.AssemblyLinearVelocity = dir * THROW_SPEED + Vector3.new(0, THROW_UP, 0)
	orb.Parent = workspace

	local light = Instance.new("PointLight")
	light.Brightness = 2.5
	light.Range = 12
	light.Color = Color3.fromRGB(90, 230, 255)
	light.Parent = orb

	local landed = false
	local function finish(hitPos: Vector3, normal: Vector3?)
		if landed then
			return
		end
		landed = true
		teleportTo(player, hitPos, normal)
		if orb.Parent then
			orb:Destroy()
		end
	end

	orb.Touched:Connect(function(hit: BasePart)
		if landed or not hit then
			return
		end
		if hit:IsDescendantOf(char) then
			return
		end
		if hit:IsA("Terrain") or hit.CanCollide == true then
			finish(orb.Position, hit.CFrame.YVector)
		end
	end)

	Debris:AddItem(orb, MAX_FLIGHT + 0.2)
	task.delay(MAX_FLIGHT, function()
		if landed or not orb.Parent then
			return
		end
		if orb.Position.Y < -20 then
			orb:Destroy()
			return
		end
		finish(orb.Position, Vector3.yAxis)
	end)

	if ammo - 1 <= 0 then
		task.defer(function()
			if tool.Parent then
				tool:Destroy()
			end
		end)
	end
end

local function giveOrbs(player: Player, char: Model)
	local old = char:FindFirstChild("Teleport Orb")
	if old then
		old:Destroy()
	end
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") and string.find(child.Name, "Teleport Orb", 1, true) then
			child:Destroy()
		end
	end
	local pack = player:FindFirstChildOfClass("Backpack")
	if pack then
		for _, child in ipairs(pack:GetChildren()) do
			if child:IsA("Tool") and string.find(child.Name, "Teleport Orb", 1, true) then
				child:Destroy()
			end
		end
	end

	local tool = Instance.new("Tool")
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("Ammo", ORBS_PER_LIFE)
	setAmmoLabel(tool, ORBS_PER_LIFE)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Shape = Enum.PartType.Ball
	handle.Size = Vector3.new(1.2, 1.2, 1.2)
	handle.Color = Color3.fromRGB(80, 220, 255)
	handle.Material = Enum.Material.Neon
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local light = Instance.new("PointLight")
	light.Brightness = 1.4
	light.Range = 8
	light.Color = Color3.fromRGB(90, 230, 255)
	light.Parent = handle

	tool.Activated:Connect(function()
		throwOrb(player, tool)
	end)
	tool.Parent = pack or char
end

local function hookPlayer(player: Player)
	player.CharacterAdded:Connect(function(char)
		task.wait(0.4)
		if player.Parent and char.Parent then
			giveOrbs(player, char)
		end
	end)
	if player.Character then
		giveOrbs(player, player.Character)
	end
end

Players.PlayerAdded:Connect(hookPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	hookPlayer(p)
end
