--[[
	LEAVE in ServerScriptService OR run once then delete.

	Roblox Import 3D often drops Blender colors → white / grey MeshParts.
	This paints MeshParts from their names (Gold, Wood, Rock, etc.).
]]

local function paint(part: BasePart, color: Color3, material: Enum.Material)
	part.Color = color
	part.Material = material
	-- Clear blank textures that force white
	if part:IsA("MeshPart") then
		pcall(function()
			(part :: MeshPart).TextureID = ""
		end)
	end
end

local RULES: { { string | Color3 | Enum.Material } } = {
	-- order matters: first match wins
	{ "Flame", Color3.fromRGB(255, 140, 40), Enum.Material.Neon },
	{ "Lantern", Color3.fromRGB(255, 186, 80), Enum.Material.Neon },
	{ "Lamp", Color3.fromRGB(255, 196, 110), Enum.Material.Neon },
	{ "Gem", Color3.fromRGB(80, 170, 255), Enum.Material.Neon },
	{ "Gold", Color3.fromRGB(228, 184, 72), Enum.Material.Metal },
	{ "SignGold", Color3.fromRGB(228, 184, 72), Enum.Material.Metal },
	{ "BannerTrim", Color3.fromRGB(228, 184, 72), Enum.Material.Metal },
	{ "PostCap", Color3.fromRGB(228, 184, 72), Enum.Material.Metal },
	{ "Ring", Color3.fromRGB(228, 184, 72), Enum.Material.Metal },
	{ "Water", Color3.fromRGB(42, 120, 168), Enum.Material.Glass },
	{ "Banner", Color3.fromRGB(180, 40, 48), Enum.Material.Fabric },
	{ "Cloth", Color3.fromRGB(180, 40, 48), Enum.Material.Fabric },
	{ "Awning", Color3.fromRGB(200, 48, 48), Enum.Material.Fabric },
	{ "Stripe", Color3.fromRGB(228, 184, 72), Enum.Material.Metal },
	{ "Steel", Color3.fromRGB(180, 186, 196), Enum.Material.Metal },
	{ "Metal", Color3.fromRGB(140, 144, 150), Enum.Material.Metal },
	{ "Blade", Color3.fromRGB(190, 196, 205), Enum.Material.Metal },
	{ "Bit", Color3.fromRGB(160, 164, 172), Enum.Material.Metal },
	{ "Flange", Color3.fromRGB(130, 134, 140), Enum.Material.Metal },
	{ "Spike", Color3.fromRGB(130, 134, 140), Enum.Material.Metal },
	{ "Head", Color3.fromRGB(130, 134, 140), Enum.Material.Metal },
	{ "Rock", Color3.fromRGB(108, 102, 96), Enum.Material.Slate },
	{ "Stone", Color3.fromRGB(120, 114, 108), Enum.Material.Concrete },
	{ "Wall", Color3.fromRGB(150, 142, 132), Enum.Material.Marble },
	{ "Arch", Color3.fromRGB(160, 152, 142), Enum.Material.Marble },
	{ "Cornice", Color3.fromRGB(90, 86, 80), Enum.Material.Cobblestone },
	{ "Floor", Color3.fromRGB(196, 154, 96), Enum.Material.Sand },
	{ "Sand", Color3.fromRGB(196, 154, 96), Enum.Material.Sand },
	{ "Pedestal", Color3.fromRGB(220, 212, 196), Enum.Material.Marble },
	{ "Plinth", Color3.fromRGB(120, 114, 108), Enum.Material.Concrete },
	{ "Marble", Color3.fromRGB(220, 212, 196), Enum.Material.Marble },
	{ "Grass", Color3.fromRGB(72, 140, 64), Enum.Material.Grass },
	{ "Lawn", Color3.fromRGB(72, 140, 64), Enum.Material.Grass },
	{ "Plank", Color3.fromRGB(158, 108, 58), Enum.Material.WoodPlanks },
	{ "Deck", Color3.fromRGB(158, 108, 58), Enum.Material.WoodPlanks },
	{ "Wood", Color3.fromRGB(110, 72, 40), Enum.Material.Wood },
	{ "Haft", Color3.fromRGB(110, 72, 40), Enum.Material.Wood },
	{ "Grip", Color3.fromRGB(70, 42, 24), Enum.Material.Wood },
	{ "Piling", Color3.fromRGB(70, 42, 24), Enum.Material.Wood },
	{ "Post", Color3.fromRGB(78, 50, 30), Enum.Material.Wood },
	{ "Sign", Color3.fromRGB(36, 24, 16), Enum.Material.Wood },
	{ "Rope", Color3.fromRGB(196, 170, 120), Enum.Material.Fabric },
	{ "Rail", Color3.fromRGB(196, 170, 120), Enum.Material.Fabric },
	{ "Wrap", Color3.fromRGB(100, 30, 30), Enum.Material.Fabric },
	{ "Carpet", Color3.fromRGB(160, 40, 50), Enum.Material.Fabric },
	{ "Wheel", Color3.fromRGB(40, 40, 44), Enum.Material.Metal },
	{ "Tire", Color3.fromRGB(40, 40, 44), Enum.Material.SmoothPlastic },
	{ "Torch", Color3.fromRGB(70, 46, 28), Enum.Material.Wood },
	{ "Foundation", Color3.fromRGB(64, 60, 56), Enum.Material.Slate },
	{ "Curb", Color3.fromRGB(120, 114, 108), Enum.Material.Concrete },
}

local function colorPart(part: BasePart)
	local n = part.Name
	for _, rule in ipairs(RULES) do
		local needle = rule[1] :: string
		if string.find(n, needle, 1, true) then
			paint(part, rule[2] :: Color3, rule[3] :: Enum.Material)
			return
		end
	end
	-- default warm wood so nothing stays pure white
	if part.Color == Color3.new(1, 1, 1) or part.Color == Color3.fromRGB(163, 162, 165) then
		paint(part, Color3.fromRGB(130, 120, 110), Enum.Material.SmoothPlastic)
	end
end

local roots = {
	workspace:FindFirstChild("BlenderPropsPlaced"),
	workspace:FindFirstChild("BlenderProps"),
	game:GetService("ServerStorage"):FindFirstChild("BlenderProps"),
}

local painted = 0
for _, root in ipairs(roots) do
	if root then
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				colorPart(d)
				painted += 1
			end
		end
		print("[FixColors] painted under", root:GetFullName())
	end
end
print("[FixColors] done — parts touched:", painted)
