--[[
	Run ONCE (Play → Stop → Delete this script).

	Turns OFF Blender prop replacement and brings back the original
	shop / trainer / dock / mine / colosseum visuals.
]]

-- 1) Disable the placer so it won't re-hide things next Play
local sss = game:GetService("ServerScriptService")
for _, name in ipairs({ "PlaceBlenderProps", "FixColors", "Test1", "Test" }) do
	local s = sss:FindFirstChild(name, true)
	if s and s:IsA("BaseScript") then
		s.Enabled = false
		print("[Restore] disabled", s:GetFullName())
	end
end

-- 2) Remove placed Blender clones from the world
local placed = workspace:FindFirstChild("BlenderPropsPlaced")
if placed then
	placed:Destroy()
	print("[Restore] removed BlenderPropsPlaced")
end

-- 3) Un-hide legacy builds (shop, trainer, docks, mine, colosseum)
local function restore(inst: Instance)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			-- Only unhide things we blanked (fully invisible)
			if d.Transparency >= 0.99 then
				d.Transparency = 0
				d.CanCollide = true
				d.CanQuery = true
			end
		end
	end
end

for _, name in ipairs({ "RobuxShop", "StatTrainerStall", "Colosseum", "FishingSpot", "GoldMine" }) do
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst.Name == name then
			restore(inst)
			print("[Restore] restored", inst:GetFullName())
		end
	end
end

-- Fishing spots + mine may be unnamed — restore any fully-invisible model with those prompts
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("ProximityPrompt") then
		local host = d:FindFirstAncestorOfClass("Model")
		if host then
			restore(host)
		end
	end
end

print("[Restore] DONE — Stop Play, Save to Roblox, delete this script.")
print("[Restore] Keep ServerStorage.BlenderProps if you want them later; they won't show.")
