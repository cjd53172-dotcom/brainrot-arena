--[[
	PASTE THIS INTO ROBLOX STUDIO COMMAND BAR (bottom of Studio), then press Enter.

	Requires: Workspace.BlenderProps with your imported models inside.
	Places each prop on terrain at the same world spots the game uses.
]]

local folder = workspace:FindFirstChild("BlenderProps")
if not folder then
	warn("[BlenderProps] Folder Workspace.BlenderProps not found")
	return
end

local function anchorAll(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = true
		end
	end
end

local function sitOnTerrain(model: Model, x: number, z: number)
	anchorAll(model)
	model:PivotTo(CFrame.new(x, 0, z))
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), params)
	local gy = if hit then hit.Position.Y else 0
	local boxCF, boxSize = model:GetBoundingBox()
	local bottomY = boxCF.Position.Y - boxSize.Y * 0.5
	model:TranslateBy(Vector3.new(0, gy - bottomY + 0.05, 0))
end

-- Same layout constants as PlotSystem / GameServer
local WORLD_DX, WORLD_DZ = 127, 98
local ARENA_X, ARENA_Z = WORLD_DX - 300, WORLD_DZ - 260
local PLAZA_Z, PLAZA_GAP, PLAZA_X0 = 28, 24, 68

local spots: { [string]: { number } } = {
	Arena = { ARENA_X, ARENA_Z },
	VendorStall = { PLAZA_X0, PLAZA_Z },
	TrainerStall = { PLAZA_X0 + PLAZA_GAP * 2, PLAZA_Z },
	FishingDock = { 70, 20 },
	FishingSign = { 68, 10 },
	GoldMine = { WORLD_DX - 45, WORLD_DZ - 35 },
	SignPost = { PLAZA_X0 + PLAZA_GAP, PLAZA_Z + 16 },
	PlayerPlot = { WORLD_DX + 90, WORLD_DZ + 100 },
	Sword = { PLAZA_X0 - 12, PLAZA_Z + 8 },
	Mace = { PLAZA_X0 - 8, PLAZA_Z + 8 },
	Axe = { PLAZA_X0 - 4, PLAZA_Z + 8 },
	Skateboard = { PLAZA_X0 + 10, PLAZA_Z + 10 },
	MagicCarpet = { PLAZA_X0 + 16, PLAZA_Z + 10 },
	MiniPlane = { PLAZA_X0 + 22, PLAZA_Z + 10 },
}

local placed = 0
for name, xz in pairs(spots) do
	local model = folder:FindFirstChild(name)
	if model and model:IsA("Model") then
		sitOnTerrain(model, xz[1], xz[2])
		placed += 1
		print("[BlenderProps] placed " .. name .. " at", xz[1], xz[2])
	else
		warn("[BlenderProps] missing model: " .. name)
	end
end

print("[BlenderProps] done — placed " .. tostring(placed) .. " models. File → Save to Roblox")
