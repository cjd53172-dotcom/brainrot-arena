--!strict
--[[
	ShooterRotation — one plaza portal that cycles shooter minigames
	(Laser Tag, Orb Blitz, …) so they never run at the same time.

	Set Workspace.ShooterSeparatePortals = true to spawn one portal per game
	instead of cycling (fallback).
]]

local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))
local VisualEffects = require(script.Parent:WaitForChild("VisualEffects"))
local PlotSystem = require(script.Parent:WaitForChild("PlotSystem"))
local LeaderboardSystem = require(script.Parent:WaitForChild("LeaderboardSystem"))

local ShooterRotation = {}

local function hint(player: Player, text: string)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local ev = remotes and remotes:FindFirstChild("ShowHint")
	if ev and ev:IsA("RemoteEvent") then
		ev:FireClient(player, text)
	end
end

local function resolvePlaceId(gameDef: any): number
	local attrName = gameDef.Attribute
	if type(attrName) == "string" then
		local attr = workspace:GetAttribute(attrName)
		if type(attr) == "number" and attr > 0 then
			return attr
		end
	end
	return tonumber(gameDef.PlaceId) or 0
end

function ShooterRotation.GetActiveIndex(gamesCount: number, cycleMinutes: number): number
	if gamesCount <= 1 then
		return 1
	end
	local mins = math.max(1, cycleMinutes)
	local slot = math.floor(os.time() / (mins * 60))
	return (slot % gamesCount) + 1
end

function ShooterRotation.MinutesUntilSwitch(cycleMinutes: number): number
	local mins = math.max(1, cycleMinutes)
	local period = mins * 60
	local left = period - (os.time() % period)
	return math.max(1, math.ceil(left / 60))
end

local function paintPortal(portal: Model, gameDef: any, cycleMinutes: number, rotating: boolean)
	local color = gameDef.Color or Color3.fromRGB(40, 220, 70)
	local surface = portal:FindFirstChild("PortalSurface", true)
	if surface and surface:IsA("BasePart") then
		surface.Color = color
		local pe = surface:FindFirstChildOfClass("ParticleEmitter")
		if pe then
			pe.Color = ColorSequence.new(color)
		end
	end
	local label = portal:FindFirstChild("GateSignLabel", true)
	if label and label:IsA("TextLabel") then
		if rotating then
			local left = ShooterRotation.MinutesUntilSwitch(cycleMinutes)
			label.Text = "SHOOTER\n" .. tostring(gameDef.Name) .. "\n(switches in " .. tostring(left) .. "m)"
		else
			label.Text = "MINIGAME\n" .. tostring(gameDef.Name)
		end
		label.TextColor3 = color
	end
	local prompt = portal:FindFirstChild("PlacePrompt", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.ObjectText = tostring(gameDef.Name)
	end
	portal:SetAttribute("ActiveShooterId", gameDef.Id)
	portal:SetAttribute("ActiveShooterName", gameDef.Name)
end

local function attachKillBoard(portal: Model, gameDef: any)
	local existing = portal:FindFirstChild("ShooterKillBoard")
	if existing then
		existing:Destroy()
	end
	local existingH = portal:FindFirstChild("ShooterKillHeader")
	if existingH then
		existingH:Destroy()
	end

	local pivot = portal:GetPivot()
	local frame = Instance.new("Part")
	frame.Name = "ShooterKillBoard"
	frame.Size = Vector3.new(26, 26, 0.8)
	frame.Anchored = true
	frame.CanCollide = true
	frame.Color = Color3.fromRGB(12, 20, 28)
	frame.Material = Enum.Material.SmoothPlastic
	frame.CFrame = pivot * CFrame.new(28, 15, 0)
	frame.Parent = portal

	local header = Instance.new("Part")
	header.Name = "ShooterKillHeader"
	header.Size = Vector3.new(26, 4, 0.8)
	header.Anchored = true
	header.CanCollide = false
	header.Color = Color3.fromRGB(30, 40, 55)
	header.Material = Enum.Material.SmoothPlastic
	header.CFrame = pivot * CFrame.new(28, 30.2, 0)
	header.Parent = portal

	local listLabels: { TextLabel } = {}
	local titleLabels: { TextLabel } = {}
	local function face(part: BasePart, title: boolean, normal: Enum.NormalId): TextLabel
		local gui = Instance.new("SurfaceGui")
		gui.Face = normal
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.LightInfluence = 0
		gui.Brightness = 1.25
		gui.MaxDistance = 180
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -20, 1, -20)
		label.Position = UDim2.new(0, 10, 0, 10)
		label.BackgroundTransparency = 1
		label.Text = if title then tostring(gameDef.BoardTitle or "KILLS") else "Play to post kills.\nKills save across visits."
		label.Font = if title then Enum.Font.GothamBlack else Enum.Font.GothamBold
		label.TextScaled = false
		label.TextSize = if title then 48 else 44
		label.LineHeight = 1.15
		label.TextColor3 = Color3.fromRGB(220, 240, 255)
		label.TextStrokeTransparency = 0.15
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.TextWrapped = false
		label.TextYAlignment = if title then Enum.TextYAlignment.Center else Enum.TextYAlignment.Top
		label.Parent = gui
		return label
	end
	table.insert(titleLabels, face(header, true, Enum.NormalId.Front))
	table.insert(titleLabels, face(header, true, Enum.NormalId.Back))
	table.insert(listLabels, face(frame, false, Enum.NormalId.Front))
	table.insert(listLabels, face(frame, false, Enum.NormalId.Back))

	local function paint()
		local store = gameDef.KillStore or "LaserTagKills_v1"
		local top = LeaderboardSystem.GetMinigameTop(store, 15)
		local title = tostring(gameDef.BoardTitle or "KILLS")
		for _, label in ipairs(titleLabels) do
			label.Text = title
		end
		local text = "Play to post kills.\nKills save across visits."
		if #top > 0 then
			local lines = {}
			for i, row in ipairs(top) do
				table.insert(lines, string.format("%d.  %s   —   %d", i, tostring(row.Name), tonumber(row.Kills) or 0))
			end
			text = table.concat(lines, "\n")
		end
		for _, label in ipairs(listLabels) do
			label.Text = text
		end
	end
	paint()
	task.spawn(function()
		while frame.Parent do
			task.wait(15)
			paint()
		end
	end)
end

local function makePortal(gameDef: any, x: number, z: number, scale: number?): Model
	local portal = VisualEffects.BuildPlacePortal(tostring(gameDef.Name), gameDef.Color or Color3.fromRGB(40, 220, 70))
	if scale and scale ~= 1 then
		portal:ScaleTo(scale)
	end
	PlotSystem.SitOnTerrain(portal, x, z)
	portal:PivotTo(portal:GetPivot() * CFrame.Angles(0, math.pi, 0))
	portal.Parent = workspace
	return portal
end

local function wireHop(portal: Model, getGame: () -> any)
	local lastHop: { [number]: number } = {}
	local function hop(player: Player)
		local now = os.clock()
		if lastHop[player.UserId] and now - lastHop[player.UserId] < 4 then
			return
		end
		lastHop[player.UserId] = now
		local gameDef = getGame()
		local dest = resolvePlaceId(gameDef)
		if dest <= 0 then
			hint(player, tostring(gameDef.Name) .. " isn't linked yet. Publish it as a Place, then set PlaceId (or Workspace." .. tostring(gameDef.Attribute) .. ").")
			return
		end
		if dest == game.PlaceId then
			hint(player, "That minigame is this same place — publish it as a second Place.")
			return
		end
		hint(player, "Entering " .. tostring(gameDef.Name) .. "...")
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData({
			ReturnPlaceId = game.PlaceId,
			From = "BrainrotArena",
			Minigame = gameDef.Id,
		})
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(dest, { player }, options)
		end)
		if not ok then
			hint(player, "Teleport needs a published place. Studio Play cannot jump templates. " .. tostring(err))
		end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PlacePrompt"
	prompt.ActionText = "Enter"
	prompt.ObjectText = "Shooter"
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 22
	prompt.RequiresLineOfSight = false
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = portal:FindFirstChild("PortalSurface") or portal:FindFirstChildWhichIsA("BasePart")
	prompt.Triggered:Connect(hop)
end

function ShooterRotation.Setup()
	local cfg = BrainrotData.SHOOTER_ROTATION
	if type(cfg) ~= "table" or type(cfg.Games) ~= "table" or #cfg.Games == 0 then
		print("[ShooterRotation] no SHOOTER_ROTATION config — skip")
		return
	end

	local separate = workspace:GetAttribute("ShooterSeparatePortals") == true or cfg.SeparatePortals == true
	local cycleMinutes = tonumber(cfg.CycleMinutes) or 20
	local portalX = (cfg.SharedPortal and cfg.SharedPortal.X) or 44
	local portalZ = (cfg.SharedPortal and cfg.SharedPortal.Z) or 28

	if separate then
		-- Fallback: one portal per shooter game (no overlap of sessions — different places).
		for i, gameDef in ipairs(cfg.Games) do
			local x = portalX + (i - 1) * 28
			local portal = makePortal(gameDef, x, portalZ, 2)
			wireHop(portal, function()
				return gameDef
			end)
			paintPortal(portal, gameDef, cycleMinutes, false)
			attachKillBoard(portal, gameDef)
			print("[ShooterRotation] separate portal", gameDef.Id, "at", x, portalZ)
		end
		return
	end

	-- Single cycling portal
	local portal = makePortal(cfg.Games[1], portalX, portalZ, 2)
	local function activeGame()
		local idx = ShooterRotation.GetActiveIndex(#cfg.Games, cycleMinutes)
		return cfg.Games[idx], idx
	end

	wireHop(portal, function()
		local g = activeGame()
		return g
	end)

	local function refresh()
		local g = activeGame()
		paintPortal(portal, g, cycleMinutes, true)
		attachKillBoard(portal, g)
		print("[ShooterRotation] active =", g.Id, "next switch in", ShooterRotation.MinutesUntilSwitch(cycleMinutes), "m")
	end
	refresh()
	task.spawn(function()
		while portal.Parent do
			task.wait(30)
			refresh()
		end
	end)
end

return ShooterRotation
