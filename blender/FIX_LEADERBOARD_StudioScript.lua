--[[
	One-shot: make arena leaderboard readable again.
	Paste into a Script under ServerScriptService → Play once → Stop → Delete.
]]

task.wait(2)

local function darkenBoard(part: BasePart)
	part.Color = Color3.fromRGB(18, 14, 12)
	part.Material = Enum.Material.Slate
	-- Move any gold slab that sits in front of the text to behind it
	if part.Name == "ChampionTrim" then
		local board = part.Parent and part.Parent:FindFirstChild("ChampionBoard")
		if board and board:IsA("BasePart") then
			part.Size = Vector3.new(math.max(part.Size.X, board.Size.X + 2), part.Size.Y, 0.35)
			part.Position = Vector3.new(board.Position.X, part.Position.Y, board.Position.Z - 0.85)
			part.CanCollide = false
		end
	end
end

for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("BasePart") then
		if d.Name == "ChampionBoard" or d.Name == "ChampionHeader" then
			darkenBoard(d)
			print("[LB] darkened", d.Name)
		elseif d.Name == "ChampionTrim" then
			darkenBoard(d)
			print("[LB] moved trim behind board")
		elseif d.Name == "Sign" and d.Parent and d.Parent.Name == "Plaza" then
			-- Arena approach sign should stay dark wood
			if d.Color.R > 0.6 and d.Color.G > 0.5 then
				d.Color = Color3.fromRGB(36, 24, 16)
				d.Material = Enum.Material.Wood
				print("[LB] fixed arena Sign color")
			end
		end
	end
	if d:IsA("TextLabel") and (d.Name == "RankText" or d.Name == "TitleText") then
		d.TextColor3 = Color3.fromRGB(255, 244, 210)
		d.TextStrokeTransparency = 0.05
		d.TextStrokeColor3 = Color3.new(0, 0, 0)
		local gui = d.Parent
		if gui and gui:IsA("SurfaceGui") then
			gui.LightInfluence = 0
			gui.Brightness = 1.35
		end
	end
end

print("[LB] leaderboard contrast fixed — Stop, Save, delete this script")
