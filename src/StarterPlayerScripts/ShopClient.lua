--!strict
--[[
	Flight for the Mini Plane shop item. Equip the plane, then WASD / thumbstick
	to move, Space / jump to climb, Left Control to dive.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local flyConn: RBXScriptConnection? = nil

local function stopFly()
	if flyConn then
		flyConn:Disconnect()
		flyConn = nil
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.AutoRotate = true
	end
end

local function startFly(tool: Tool)
	stopFly()
	flyConn = RunService.RenderStepped:Connect(function()
		local char = player.Character
		if not char or tool.Parent ~= char then
			stopFly()
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")
		if not (hum and root and root:IsA("BasePart")) then
			return
		end
		local hrp = root :: BasePart
		local speed = hum.WalkSpeed
		if speed < 8 then
			speed = 48
		end
		local move = hum.MoveDirection
		local up = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			up = 1
		elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			up = -1
		end
		local vel = move * speed + Vector3.new(0, up * speed, 0)
		if move.Magnitude < 0.05 and up == 0 then
			vel = Vector3.new(0, hrp.AssemblyLinearVelocity.Y * 0.85, 0)
		end
		hrp.AssemblyLinearVelocity = vel
	end)
end

local function watchChar(char: Model)
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("Fly") == true then
			startFly(child)
		end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("Fly") == true then
			stopFly()
		end
	end)
	local held = char:FindFirstChildOfClass("Tool")
	if held and held:GetAttribute("Fly") == true then
		startFly(held)
	end
end

player.CharacterAdded:Connect(watchChar)
if player.Character then
	watchChar(player.Character)
end
