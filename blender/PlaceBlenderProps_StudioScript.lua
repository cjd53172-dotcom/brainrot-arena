--[[
	LEAVE this Script in ServerScriptService (not inside Systems).
	Replaces old part-built props with your Blender models.

	Requires: ServerStorage.BlenderProps (drag folder there in Edit mode, Save).
]]

task.wait(4) -- after GameLoader builds plaza / shop / docks / mine

local ServerStorage = game:GetService("ServerStorage")

local TARGETS = {
	Arena = 90,
	PlayerPlot = 52,
	GoldMine = 20,
	FishingDock = 24,
	VendorStall = 14,
	TrainerStall = 14,
	SignPost = 8,
	FishingSign = 8,
	Sword = 5,
	Mace = 6,
	Axe = 6,
	Skateboard = 4,
	MagicCarpet = 6,
	MiniPlane = 8,
}

-- Match live game spots (PlotSystem / GameServer)
local WORLD_DX, WORLD_DZ = 127, 98
local ARENA_X, ARENA_Z = WORLD_DX - 300, WORLD_DZ - 260
local PLAZA_Z, PLAZA_GAP, PLAZA_X0 = 28, 24, 68
local SPOTS = {
	Arena = { ARENA_X, ARENA_Z },
	VendorStall = { PLAZA_X0, PLAZA_Z }, -- RobuxShop
	TrainerStall = { PLAZA_X0 + PLAZA_GAP * 2, PLAZA_Z }, -- StatTrainerStall
	FishingDock = { 70, 20 },
	FishingSign = { 68, 8 },
	GoldMine = { 227, 98 }, -- shared mine
	SignPost = { PLAZA_X0 + PLAZA_GAP, PLAZA_Z + 18 },
	-- cosmetics near shop
	Sword = { PLAZA_X0 - 10, PLAZA_Z + 10 },
	Mace = { PLAZA_X0 - 7, PLAZA_Z + 10 },
	Axe = { PLAZA_X0 - 4, PLAZA_Z + 10 },
	Skateboard = { PLAZA_X0 + 8, PLAZA_Z + 10 },
	MagicCarpet = { PLAZA_X0 + 12, PLAZA_Z + 10 },
	MiniPlane = { PLAZA_X0 + 16, PLAZA_Z + 10 },
	-- keep plot template far away
	PlayerPlot = { WORLD_DX + 160, WORLD_DZ + 160 },
}

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
	{ "Awning", Color3.fromRGB(200, 48, 48), Enum.Material.Fabric },
	{ "Wheel", Color3.fromRGB(40, 40, 44), Enum.Material.Metal },
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

local function paint(m)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			if d:IsA("MeshPart") then
				pcall(function()
					(d :: MeshPart).TextureID = ""
				end)
			end
			local sa = d:FindFirstChildOfClass("SurfaceAppearance")
			if sa then
				sa:Destroy()
			end
			local matched = false
			for _, r in ipairs(COLOR_RULES) do
				if string.find(d.Name, r[1], 1, true) then
					d.Color = r[2]
					d.Material = r[3]
					matched = true
					break
				end
			end
			if not matched and d.Color == Color3.new(1, 1, 1) then
				d.Color = Color3.fromRGB(130, 120, 110)
			end
		end
	end
end

local function anyPart(model: Model): BasePart?
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function movePrompts(fromModel: Instance?, toModel: Model)
	if not fromModel then
		return
	end
	local dest = anyPart(toModel)
	if not dest then
		return
	end
	for _, d in ipairs(fromModel:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			d.Parent = dest
		end
	end
	-- Keep NPC under new stall if present
	for _, child in ipairs(fromModel:GetChildren()) do
		if child:IsA("Model") and (child.Name == "Shopkeeper" or child.Name == "Trainer") then
			child.Parent = toModel
			local hrp = child:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				local pivot = toModel:GetPivot()
				child:PivotTo(pivot * CFrame.new(0, 3, -1))
			end
		end
	end
end

local function hideLegacy(name: string)
	local inst = workspace:FindFirstChild(name, true)
	if inst then
		-- Keep in game for prompt rescue, but invisible / non-colliding
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Transparency = 1
				d.CanCollide = false
				d.CanQuery = false
			end
		end
		if inst:IsA("BasePart") then
			inst.Transparency = 1
			inst.CanCollide = false
		end
		print("[PlaceBlenderProps] hid legacy", name)
	end
end

local templates = ServerStorage:FindFirstChild("BlenderProps")
if not templates then
	local world = workspace:FindFirstChild("BlenderProps")
	if world then
		world.Parent = ServerStorage
		templates = world
	else
		warn("[PlaceBlenderProps] No BlenderProps in ServerStorage")
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

local models: { [string]: Model } = {}
for name, xz in pairs(SPOTS) do
	local src = templates:FindFirstChild(name)
	if src and src:IsA("Model") then
		local clone = src:Clone()
		clone.Name = name
		clone.Parent = placed
		fit(clone, TARGETS[name] or 16)
		sit(clone, xz[1], xz[2], placed)
		paint(clone)
		models[name] = clone
		print("[PlaceBlenderProps] placed", name)
	end
end

-- Move gameplay prompts from old builds onto Blender models
if models.VendorStall then
	local shop = workspace:FindFirstChild("RobuxShop", true)
	movePrompts(shop, models.VendorStall)
	hideLegacy("RobuxShop")
end
if models.TrainerStall then
	local trainer = workspace:FindFirstChild("StatTrainerStall", true)
	movePrompts(trainer, models.TrainerStall)
	hideLegacy("StatTrainerStall")
end
if models.GoldMine then
	-- Shared mine is often unnamed model; find by Mine Gold prompt
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.ActionText == "Mine Gold" then
			local host = d:FindFirstAncestorOfClass("Model")
			d.Parent = anyPart(models.GoldMine) or d.Parent
			if host and host.Name ~= "GoldMine" then
				hideLegacy(host.Name)
				-- also hide parts of unnamed mine
				for _, p in ipairs(host:GetDescendants()) do
					if p:IsA("BasePart") then
						p.Transparency = 1
						p.CanCollide = false
					end
				end
			end
			break
		end
	end
end
if models.FishingDock then
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and (d.Name == "FishPrompt" or d.ActionText == "Cast Line") then
			local host = d:FindFirstAncestorOfClass("Model")
			if host and host.Name == "FishingSpot" then
				d.Parent = anyPart(models.FishingDock) or d.Parent
				for _, p in ipairs(host:GetDescendants()) do
					if p:IsA("BasePart") then
						p.Transparency = 1
						p.CanCollide = false
					end
				end
			end
		end
	end
end
if models.Arena then
	local colo = workspace:FindFirstChild("Colosseum", true)
	if colo then
		for _, p in ipairs(colo:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Transparency = 1
				p.CanCollide = false
			end
		end
		print("[PlaceBlenderProps] hid legacy Colosseum")
	end
end

print("[PlaceBlenderProps] replacement done")
