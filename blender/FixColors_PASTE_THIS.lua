--[[
	DELETE your old Test / Test1 scripts first.

	1. Click ServerScriptService (NOT the Systems folder)
	2. + → Script → rename to FixColors
	3. Replace ALL text with this file
	4. View → Output (so you can see messages)
	5. Press Play — watch Output for "COLORS OK"
]]

task.wait(3) -- wait for PlaceBlenderProps / GameLoader

local ServerStorage = game:GetService("ServerStorage")

local roots = {
	workspace:FindFirstChild("BlenderPropsPlaced"),
	workspace:FindFirstChild("BlenderProps"),
	ServerStorage:FindFirstChild("BlenderProps"),
}

print("[FixColors] starting…")
for i, root in ipairs(roots) do
	print("[FixColors] root", i, root and root:GetFullName() or "nil")
end

local rules = {
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
	{ "Bit", Color3.fromRGB(160, 164, 172), Enum.Material.Metal },
	{ "Rock", Color3.fromRGB(108, 102, 96), Enum.Material.Slate },
	{ "Stone", Color3.fromRGB(120, 114, 108), Enum.Material.Concrete },
	{ "Wall", Color3.fromRGB(150, 142, 132), Enum.Material.Marble },
	{ "Arch", Color3.fromRGB(160, 152, 142), Enum.Material.Marble },
	{ "Cornice", Color3.fromRGB(90, 86, 80), Enum.Material.Cobblestone },
	{ "Floor", Color3.fromRGB(196, 154, 96), Enum.Material.Sand },
	{ "Pedestal", Color3.fromRGB(220, 212, 196), Enum.Material.Marble },
	{ "Plinth", Color3.fromRGB(120, 114, 108), Enum.Material.Concrete },
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
	{ "Rail", Color3.fromRGB(196, 170, 120), Enum.Material.Fabric },
	{ "Wrap", Color3.fromRGB(100, 30, 30), Enum.Material.Fabric },
	{ "Carpet", Color3.fromRGB(160, 40, 50), Enum.Material.Fabric },
	{ "Wheel", Color3.fromRGB(40, 40, 44), Enum.Material.Metal },
	{ "Foundation", Color3.fromRGB(64, 60, 56), Enum.Material.Slate },
}

local painted = 0
for _, root in ipairs(roots) do
	if root then
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				-- Strip import leftovers that force white
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
				for _, r in ipairs(rules) do
					if string.find(d.Name, r[1], 1, true) then
						d.Color = r[2]
						d.Material = r[3]
						matched = true
						break
					end
				end
				if not matched then
					d.Color = Color3.fromRGB(130, 120, 110)
					d.Material = Enum.Material.SmoothPlastic
				end
				painted += 1
			end
		end
	end
end

print("[FixColors] COLORS OK — painted", painted, "parts")
if painted == 0 then
	warn("[FixColors] painted 0 parts. Is BlenderProps in ServerStorage? Did PlaceBlenderProps run?")
end
