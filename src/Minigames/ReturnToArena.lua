--!strict
--[[
	Paste this Script into ServerScriptService of the Laser Tag PLACE
	(the second place in the Brainrot Arena experience — not the hub).

	Players arrive from the plaza portal with ReturnPlaceId in teleport data.
	A return gate appears so they can walk back to the arena.
]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local returnPlaceByUser: { [number]: number } = {}

local function hubIdFor(player: Player): number
	return returnPlaceByUser[player.UserId] or 0
end

Players.PlayerAdded:Connect(function(player: Player)
	local join = player:GetJoinData()
	local data = join and join.TeleportData
	if type(data) == "table" and type(data.ReturnPlaceId) == "number" and data.ReturnPlaceId > 0 then
		returnPlaceByUser[player.UserId] = data.ReturnPlaceId
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	returnPlaceByUser[player.UserId] = nil
end)

local gate = Instance.new("Part")
gate.Name = "ReturnToArena"
gate.Size = Vector3.new(8, 12, 2)
gate.Anchored = true
gate.CanCollide = false
gate.Color = Color3.fromRGB(255, 180, 40)
gate.Material = Enum.Material.Neon
gate.Position = Vector3.new(0, 8, 0)
gate.Parent = workspace

local prompt = Instance.new("ProximityPrompt")
prompt.ActionText = "Return"
prompt.ObjectText = "Brainrot Arena"
prompt.HoldDuration = 0
prompt.MaxActivationDistance = 16
prompt.RequiresLineOfSight = false
prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.Parent = gate

local function goHome(player: Player)
	local placeId = hubIdFor(player)
	if placeId <= 0 then
		return
	end
	pcall(function()
		TeleportService:TeleportAsync(placeId, { player })
	end)
end

prompt.Triggered:Connect(goHome)
gate.Touched:Connect(function(hit: BasePart)
	local char = hit and hit.Parent
	local player = char and Players:GetPlayerFromCharacter(char)
	if player then
		goHome(player)
	end
end)
