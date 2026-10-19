--[[
	Studio fix: unstuck spawn, shrink Blender props, place them apart.

	1. ServerScriptService → + → Script
	2. Paste this whole file
	3. Play once → Stop
	4. File → Save to Roblox
	5. Delete this Script
]]

local ServerStorage = game:GetService("ServerStorage")

local folder = workspace:FindFirstChild("BlenderProps") or ServerStorage:FindFirstChild("BlenderProps")
if not folder then
	warn("[BlenderProps] No BlenderProps folder in Workspace or ServerStorage")
	return
end

-- Keep them in Workspace so you can see them, but get them off spawn first.
folder.Parent = workspace

local TARGETS: { [string]: number } = {
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

local function anchorAll(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = true
		end
	end
end

local function fitToMax(model: Model, maxSize: number)
	anchorAll(model)
	-- ScaleTo needs a PrimaryPart on some Studio builds — set one if missing.
	if not model.PrimaryPart then
		local part = model:FindFirstChildWhichIsA("BasePart", true)
		if part then
			model.PrimaryPart = part
		end
	end
	local ok, size = pcall(function()
		local _, s = model:GetBoundingBox()
		return s
	end)
	if not ok or typeof(size) ~= "Vector3" then
		warn("[BlenderProps] could not measure " .. model.Name)
		return
	end
	local longest = math.max(size.X, size.Y, size.Z)
	if longest <= 0.01 then
		return
	end
	if longest > maxSize then
		local factor = maxSize / longest
		local scaleOk = pcall(function()
			model:ScaleTo(model:GetScale() * factor)
		end)
		if not scaleOk then
			-- Fallback: scale MeshPart sizes / FileMesh if ScaleTo fails
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Size = d.Size * factor
					d.Position = d.Position * factor
				end
			end
			warn("[BlenderProps] ScaleTo failed for " .. model.Name .. "; used part fallback")
		end
		print("[BlenderProps] scaled " .. model.Name .. " x" .. string.format("%.3f", factor))
	end
end

local function sitOnTerrain(model: Model, x: number, z: number)
	anchorAll(model)
	model:PivotTo(CFrame.new(x, 200, z)) -- lift high first so we don't nest inside terrain/stack
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	local hit = workspace:Raycast(Vector3.new(x, 800, z), Vector3.new(0, -2000, 0), params)
	local gy = if hit then hit.Position.Y else 0
	model:PivotTo(CFrame.new(x, gy + 50, z))
	local boxCF, boxSize = model:GetBoundingBox()
	local bottomY = boxCF.Position.Y - boxSize.Y * 0.5
	model:TranslateBy(Vector3.new(0, gy - bottomY + 0.1, 0))
end

local WORLD_DX, WORLD_DZ = 127, 98
local ARENA_X, ARENA_Z = WORLD_DX - 300, WORLD_DZ - 260
local PLAZA_Z, PLAZA_GAP, PLAZA_X0 = 28, 24, 68

-- Spread far from typical spawn; match game plaza / arena layout.
local spots: { [string]: { number } } = {
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

-- 1) Park everything far away immediately so spawn is clear
for _, child in ipairs(folder:GetChildren()) do
	if child:IsA("Model") then
		anchorAll(child)
		child:PivotTo(CFrame.new(0, 500, -500))
	end
end
print("[BlenderProps] cleared spawn pile")

-- 2) Scale + place
local placed = 0
for name, xz in pairs(spots) do
	local model = folder:FindFirstChild(name)
	if model and model:IsA("Model") then
		fitToMax(model, TARGETS[name] or 20)
		sitOnTerrain(model, xz[1], xz[2])
		placed += 1
		print("[BlenderProps] placed " .. name)
	else
		warn("[BlenderProps] missing " .. name .. " (check exact name in Explorer)")
	end
end

-- Any leftover unnamed imports (e.g. "Scene") — hide in ServerStorage
for _, child in ipairs(folder:GetChildren()) do
	if child:IsA("Model") and not spots[child.Name] then
		child.Parent = ServerStorage
		warn("[BlenderProps] moved leftover " .. child.Name .. " to ServerStorage")
	end
end

print("[BlenderProps] done — placed " .. tostring(placed) .. ". Stop ▶, Save to Roblox, delete this Script.")
