--!strict
--[[
	Paste this Script into ServerScriptService of the Orb Blitz PLACE
	(alongside OrbBlitzReturn — not the Brainrot Arena hub).

	Deathmatch with throwable explosive orbs (distinct from Laser Tag's
	teleport orbs). Each life you get 4 blast orbs. Throw one; on impact it
	explodes and damages nearby players. Kills are credited via Humanoid
	creator tags so OrbBlitzReturn can post them to the plaza board.

	After pasting: File → Publish to Roblox → overwrite THIS Orb Blitz place only.
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

print("[OrbBlitz] script running in " .. tostring(script:GetFullName()))

local ORBS_PER_LIFE = 4
local THROW_SPEED = 88
local THROW_UP = 18
local MAX_FLIGHT = 3.5
local BLAST_RADIUS = 14
local BLAST_DAMAGE = 55
local SELF_SAFE = 0.35 -- seconds after throw before self-damage counts

local function setAmmoLabel(tool: Tool, ammo: number)
	tool.Name = "Blast Orb (" .. tostring(ammo) .. ")"
	tool.ToolTip = tostring(ammo) .. " left this life"
end

local function explodeAt(owner: Player, pos: Vector3, thrownAt: number)
	local blast = Instance.new("Part")
	blast.Name = "OrbBlast"
	blast.Shape = Enum.PartType.Ball
	blast.Size = Vector3.new(2, 2, 2)
	blast.Anchored = true
	blast.CanCollide = false
	blast.Material = Enum.Material.Neon
	blast.Color = Color3.fromRGB(255, 140, 40)
	blast.Transparency = 0.2
	blast.CFrame = CFrame.new(pos)
	blast.Parent = workspace

	local light = Instance.new("PointLight")
	light.Brightness = 4
	light.Range = BLAST_RADIUS
	light.Color = Color3.fromRGB(255, 160, 50)
	light.Parent = blast

	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/fire_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 180, 60), Color3.fromRGB(255, 60, 20))
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	pe.Lifetime = NumberRange.new(0.25, 0.55)
	pe.Speed = NumberRange.new(8, 22)
	pe.Rate = 0
	pe.Parent = blast
	pe:Emit(40)

	task.spawn(function()
		for i = 1, 6 do
			blast.Size = Vector3.new(2, 2, 2) * (1 + i * 1.6)
			blast.Transparency = 0.2 + i * 0.12
			task.wait(0.03)
		end
		if blast.Parent then
			blast:Destroy()
		end
	end)
	Debris:AddItem(blast, 1.2)

	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (hrp and hrp:IsA("BasePart") and hum and hum.Health > 0) then
			continue
		end
		if player == owner and now - thrownAt < SELF_SAFE then
			continue
		end
		local dist = ((hrp :: BasePart).Position - pos).Magnitude
		if dist > BLAST_RADIUS then
			continue
		end
		local falloff = 1 - (dist / BLAST_RADIUS) * 0.55
		local dmg = math.floor(BLAST_DAMAGE * falloff)
		if dmg <= 0 then
			continue
		end
		-- Standard creator tag so OrbBlitzReturn / leaderstats can credit the kill.
		local tag = Instance.new("ObjectValue")
		tag.Name = "creator"
		tag.Value = owner
		tag.Parent = hum
		Debris:AddItem(tag, 2)
		hum:TakeDamage(dmg)
	end
end

local function throwOrb(player: Player, tool: Tool)
	local ammo = tool:GetAttribute("Ammo")
	if type(ammo) ~= "number" or ammo <= 0 then
		return
	end
	local last = tool:GetAttribute("LastThrow")
	if type(last) == "number" and os.clock() - last < 0.4 then
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

	local thrownAt = os.clock()
	local origin = (hrp :: BasePart).CFrame
	local dir = origin.LookVector
	local spawnAt = origin.Position + dir * 3 + Vector3.new(0, 1.4, 0)

	local orb = Instance.new("Part")
	orb.Name = "BlastOrb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(1.4, 1.4, 1.4)
	orb.Color = Color3.fromRGB(255, 110, 30)
	orb.Material = Enum.Material.Neon
	orb.CanCollide = true
	orb.Massless = false
	orb.CustomPhysicalProperties = PhysicalProperties.new(0.45, 0.2, 0.15, 1, 1)
	orb.CFrame = CFrame.new(spawnAt)
	orb.AssemblyLinearVelocity = dir * THROW_SPEED + Vector3.new(0, THROW_UP, 0)
	orb.Parent = workspace

	local light = Instance.new("PointLight")
	light.Brightness = 2.2
	light.Range = 10
	light.Color = Color3.fromRGB(255, 140, 40)
	light.Parent = orb

	local landed = false
	local function finish(hitPos: Vector3)
		if landed then
			return
		end
		landed = true
		if orb.Parent then
			orb:Destroy()
		end
		explodeAt(player, hitPos, thrownAt)
	end

	orb.Touched:Connect(function(hit: BasePart)
		if landed or not hit then
			return
		end
		if hit:IsDescendantOf(char) then
			return
		end
		if hit:IsA("Terrain") or hit.CanCollide == true then
			finish(orb.Position)
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
		finish(orb.Position)
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
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") and string.find(child.Name, "Blast Orb", 1, true) then
			child:Destroy()
		end
	end
	local pack = player:FindFirstChildOfClass("Backpack")
	if pack then
		for _, child in ipairs(pack:GetChildren()) do
			if child:IsA("Tool") and string.find(child.Name, "Blast Orb", 1, true) then
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
	handle.Size = Vector3.new(1.25, 1.25, 1.25)
	handle.Color = Color3.fromRGB(255, 110, 30)
	handle.Material = Enum.Material.Neon
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local light = Instance.new("PointLight")
	light.Brightness = 1.5
	light.Range = 8
	light.Color = Color3.fromRGB(255, 140, 40)
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
