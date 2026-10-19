--[[
	LEAVE THIS SCRIPT IN ServerScriptService (do not delete).
	GameLoader won't overwrite it.

	Edit mode (not Play):
	  1. Find Workspace.BlenderProps
	  2. Drag that folder onto ServerStorage
	  3. File → Save to Roblox
	Then Press Play — props appear scaled and spread out.
]]

local ServerStorage = game:GetService("ServerStorage")

local TARGETS = {
	Arena = 100,
	PlayerPlot = 56,
	GoldMine = 22,
	FishingDock = 28,
	VendorStall = 16,
	TrainerStall = 16,
	SignPost = 12,
	FishingSign = 12,
	Sword = 6,
	Mace = 7,
	Axe = 7,
	Skateboard = 5,
	MagicCarpet = 8,
	MiniPlane = 10,
}

local WORLD_DX, WORLD_DZ = 127, 98
local ARENA_X, ARENA_Z = WORLD_DX - 300, WORLD_DZ - 260
local PLAZA_Z, PLAZA_GAP, PLAZA_X0 = 28, 24, 68

local SPOTS = {
	Arena = { ARENA_X, ARENA_Z },
	VendorStall = { PLAZA_X0, PLAZA_Z },
	TrainerStall = { PLAZA_X0 + PLAZA_GAP * 2, PLAZA_Z },
	FishingDock = { 70, 20 },
	FishingSign = { 68, 8 },
	GoldMine = { WORLD_DX - 45, WORLD_DZ - 35 },
	SignPost = { PLAZA_X0 + PLAZA_GAP, PLAZA_Z + 20 },
	PlayerPlot = { WORLD_DX + 120, WORLD_DZ + 120 },
	Sword = { PLAZA_X0 - 14, PLAZA_Z + 12 },
	Mace = { PLAZA_X0 - 10, PLAZA_Z + 12 },
	Axe = { PLAZA_X0 - 6, PLAZA_Z + 12 },
	Skateboard = { PLAZA_X0 + 10, PLAZA_Z + 14 },
	MagicCarpet = { PLAZA_X0 + 16, PLAZA_Z + 14 },
	MiniPlane = { PLAZA_X0 + 22, PLAZA_Z + 14 },
}

local function anchor(m)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = true
		end
	end
	if not m.PrimaryPart then
		local p = m:FindFirstChildWhichIsA("BasePart", true)
		if p then
			m.PrimaryPart = p
		end
	end
end

local function fit(m, maxSize)
	anchor(m)
	local ok, size = pcall(function()
		local _, s = m:GetBoundingBox()
		return s
	end)
	if ok and typeof(size) == "Vector3" then
		local longest = math.max(size.X, size.Y, size.Z)
		if longest > maxSize then
			pcall(function()
				m:ScaleTo(m:GetScale() * (maxSize / longest))
			end)
		end
	end
end

local function sit(m, x, z, ignore)
	anchor(m)
	m:PivotTo(CFrame.new(x, 200, z))
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ignore }
	local hit = workspace:Raycast(Vector3.new(x, 800, z), Vector3.new(0, -2000, 0), params)
	local gy = if hit then hit.Position.Y else 0
	local boxCF, boxSize = m:GetBoundingBox()
	m:TranslateBy(Vector3.new(0, gy - (boxCF.Position.Y - boxSize.Y * 0.5) + 0.1, 0))
end

task.wait(2) -- let GameLoader / PlotSystem finish first

local templates = ServerStorage:FindFirstChild("BlenderProps")
if not templates then
	local world = workspace:FindFirstChild("BlenderProps")
	if world then
		world.Parent = ServerStorage
		templates = world
		print("[PlaceBlenderProps] moved Workspace.BlenderProps → ServerStorage")
	else
		warn("[PlaceBlenderProps] No BlenderProps folder. In EDIT mode: import FBX, put folder in ServerStorage, Save.")
		return
	end
end

local old = workspace:FindFirstChild("BlenderPropsPlaced")
if old then
	old:Destroy()
end
local placed = Instance.new("Folder")
placed.Name = "BlenderPropsPlaced"
placed.Parent = workspace

local COLOR_RULES = {
	{ "Flame", Color3.fromRGB(255, 140, 40), Enum.Material.Neon },
	{ "Lantern", Color3.fromRGB(255, 186, 80), Enum.Material.Neon },
	{ "Lamp", Color3.fromRGB(255, 196, 110), Enum.Material.Neon },
	{ "Gem", Color3.fromRGB(80, 170, 255), Enum.Material.Neon },
	{ "Gold", Color3.fromRGB(228, 184, 72), Enum.Material.Metal },
	{ "Banner", Color3.fromRGB(180, 40, 48), Enum.Material.Fabric },
	{ "Water", Color3.fromRGB(42, 120, 168), Enum.Material.Glass },
	{ "Steel", Color3.fromRGB(180, 186, 196), Enum.Material.Metal },
	{ "Metal", Color3.fromRGB(140, 144, 150), Enum.Material.Metal },
	{ "Blade", Color3.fromRGB(190, 196, 205), Enum.Material.Metal },
	{ "Rock", Color3.fromRGB(108, 102, 96), Enum.Material.Slate },
	{ "Stone", Color3.fromRGB(120, 114, 108), Enum.Material.Concrete },
	{ "Wall", Color3.fromRGB(150, 142, 132), Enum.Material.Marble },
	{ "Arch", Color3.fromRGB(160, 152, 142), Enum.Material.Marble },
	{ "Floor", Color3.fromRGB(196, 154, 96), Enum.Material.Sand },
	{ "Pedestal", Color3.fromRGB(220, 212, 196), Enum.Material.Marble },
	{ "Grass", Color3.fromRGB(72, 140, 64), Enum.Material.Grass },
	{ "Lawn", Color3.fromRGB(72, 140, 64), Enum.Material.Grass },
	{ "Plank", Color3.fromRGB(158, 108, 58), Enum.Material.WoodPlanks },
	{ "Deck", Color3.fromRGB(158, 108, 58), Enum.Material.WoodPlanks },
	{ "Wood", Color3.fromRGB(110, 72, 40), Enum.Material.Wood },
	{ "Haft", Color3.fromRGB(110, 72, 40), Enum.Material.Wood },
	{ "Piling", Color3.fromRGB(70, 42, 24), Enum.Material.Wood },
	{ "Post", Color3.fromRGB(78, 50, 30), Enum.Material.Wood },
	{ "Sign", Color3.fromRGB(36, 24, 16), Enum.Material.Wood },
	{ "Rope", Color3.fromRGB(196, 170, 120), Enum.Material.Fabric },
	{ "Wrap", Color3.fromRGB(100, 30, 30), Enum.Material.Fabric },
	{ "Wheel", Color3.fromRGB(40, 40, 44), Enum.Material.Metal },
}

local function paintClone(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			for _, rule in ipairs(COLOR_RULES) do
				if string.find(d.Name, rule[1], 1, true) then
					d.Color = rule[2]
					d.Material = rule[3]
					break
				end
			end
			if d.Color == Color3.new(1, 1, 1) then
				d.Color = Color3.fromRGB(130, 120, 110)
				d.Material = Enum.Material.SmoothPlastic
			end
		end
	end
end

local n = 0
for name, xz in pairs(SPOTS) do
	local src = templates:FindFirstChild(name)
	if src and src:IsA("Model") then
		local clone = src:Clone()
		clone.Parent = placed
		fit(clone, TARGETS[name] or 20)
		sit(clone, xz[1], xz[2], placed)
		paintClone(clone)
		n += 1
		print("[PlaceBlenderProps] placed", name)
	else
		warn("[PlaceBlenderProps] missing", name)
	end
end
print("[PlaceBlenderProps] done:", n)
