--!strict
--[[
	GameServer (Script -> ServerScriptService)
	Boots the game: creates RemoteEvents, sets up systems, spawns orb
	pickups and the quest board, and wires player join/leave.

	EXPLORER LAYOUT THIS SCRIPT EXPECTS:
	ServerScriptService
	├── GameServer            <- this script
	└── Systems (Folder)
	    ├── PlayerData        (ModuleScript)
	    ├── QuestSystem       (ModuleScript)
	    └── PlotSystem        (ModuleScript)
	ReplicatedStorage
	└── BrainrotData          (ModuleScript)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Systems = script.Parent:WaitForChild("Systems")
local PlayerData = require(Systems:WaitForChild("PlayerData"))
local QuestSystem = require(Systems:WaitForChild("QuestSystem"))
local PlotSystem = require(Systems:WaitForChild("PlotSystem"))
local BattleSystem = require(Systems:WaitForChild("BattleSystem"))
local ExpeditionSystem = require(Systems:WaitForChild("ExpeditionSystem"))
local DailyQuestSystem = require(Systems:WaitForChild("DailyQuestSystem"))
local EggSystem = require(Systems:WaitForChild("EggSystem"))
local VisualEffects = require(Systems:WaitForChild("VisualEffects"))
local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))

-- // RemoteEvents --------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

for _, name in ipairs({ "QuestUpdate", "CollectionUpdate", "ShowHint", "UpdateShowcase", "AssignWorker", "CollectStation", "WorkUpdate", "OpenFusion", "OpenArena", "FusionResult", "BattleUpdate", "FuseBrainrots", "StartBattle", "SubmitMoves", "ForfeitBattle", "StartExpedition", "ExpeditionUpdate", "ClaimDailyEgg", "DailyUpdate", "BuyEggSlot", "EggUpdate", "CollectPassive", "PassiveUpdate", "UnlockTheme", "BuyDecoration", "CustomizeUpdate", "UnlockZone" }) do
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
end

local function pushCollection(player: Player)
	local data = PlayerData.Get(player)
	if data then
		remotes:WaitForChild("CollectionUpdate"):FireClient(player, {
			Brainrots = data.Brainrots,
			Showcase = data.Showcase,
			Coins = data.Coins,
			Working = PlayerData.GetWorkingIds(player),
		})
	end
end

-- Showcase curation: the client sends its desired instance-ID list;
-- the server validates ownership and the cap before applying.
remotes:WaitForChild("UpdateShowcase").OnServerEvent:Connect(function(player: Player, instanceIds: any)
	if PlayerData.SetShowcase(player, instanceIds) then
		PlotSystem.RefreshPlot(player)
		pushCollection(player)
	end
end)

-- // Work system ------------------------------------------------------------------
local function pushWorkState(player: Player)
	local view = PlayerData.GetWorkView(player)
	if view then
		remotes:WaitForChild("WorkUpdate"):FireClient(player, view)
	end
end

-- AssignWorker(instanceId, workId): workId nil/"" unassigns.
remotes:WaitForChild("AssignWorker").OnServerEvent:Connect(function(player: Player, instanceId: any, workId: any)
	if type(instanceId) ~= "string" then
		return
	end
	if type(workId) == "string" and workId ~= "" then
		PlayerData.AssignJob(player, instanceId, workId)
	else
		PlayerData.UnassignJob(player, instanceId)
	end
	PlotSystem.RefreshPlot(player)   -- a worker leaves the showcase
	PlotSystem.RefreshWorkers(player)
	pushWorkState(player)
	pushCollection(player)
	QuestSystem.CheckObjective(player, "workers")
end)

remotes:WaitForChild("CollectStation").OnServerEvent:Connect(function(player: Player, workId: any)
	if type(workId) ~= "string" then
		return
	end
	local granted = PlayerData.CollectStation(player, workId)
	if granted > 0 then
		local data = PlayerData.Get(player)
		if data then
			data.LifetimeMaterials = (data.LifetimeMaterials or 0) + granted
		end
		QuestSystem.CheckObjective(player, "materials")
		DailyQuestSystem.RecordProgress(player, "workstation_collect", granted)
		pushDailyState(player)
	end
	pushWorkState(player)
	pushCollection(player)
end)

-- // Fusion ----------------------------------------------------------------------
remotes:WaitForChild("FuseBrainrots").OnServerEvent:Connect(function(player: Player, instanceIds: any)
	local data = PlayerData.Get(player)
	if not data or type(instanceIds) ~= "table" or #instanceIds ~= 3 then
		return
	end
	-- Validate: 3 owned, same BrainrotId, none shiny, none working.
	local seen: { [string]: boolean } = {}
	local firstId: string? = nil
	for _, id in ipairs(instanceIds) do
		if type(id) ~= "string" or seen[id] then
			return
		end
		seen[id] = true
		local inst = PlayerData.GetInstance(player, id)
		if not inst or inst.Shiny then
			return
		end
		if data.Jobs[id] then
			return -- unassign workers before fusing them
		end
		if not firstId then
			firstId = inst.BrainrotId
		elseif inst.BrainrotId ~= firstId then
			return
		end
	end
	local def = BrainrotData.GetById(firstId :: string)
	if not def then
		return
	end
	local rarity = def.Rarity

	if rarity == "Legendary" then
		-- 3 Legendaries -> a guaranteed SHINY (any brainrot). No material cost, but coin fee.
		local coinFee = BrainrotData.FUSION_COIN_COST.Legendary or 1000
		if not PlayerData.SpendCoins(player, coinFee) then
			remotes:WaitForChild("ShowHint"):FireClient(player, "Not enough coins! Need " .. tostring(coinFee) .. ".")
			return
		end
		local resultId = BrainrotData.GetRandomIdOfRarity(BrainrotData.RollRewardRarity())
		if not resultId then
			return
		end
		PlayerData.RemoveBrainrotInstances(player, instanceIds)
		local instance, err = PlayerData.TryAddBrainrot(player, resultId, true, BrainrotData.RollVariant())
		data.Fusions = (data.Fusions or 0) + 1
		DailyQuestSystem.RecordProgress(player, "fuse", 1)
		pushDailyState(player)
		PlotSystem.RefreshPlot(player)
		remotes:WaitForChild("FusionResult"):FireClient(player, {
			Kind = "Fusion",
			BrainrotId = instance and instance.BrainrotId or nil,
			Variant = instance and instance.Variant or nil,
			Shiny = true,
			InventoryFull = err == "full",
			Coins = 0,
		})
	else
		local resultRarity = BrainrotData.GetFusionResultRarity(rarity)
		local resultId = resultRarity and BrainrotData.GetRandomIdOfRarity(resultRarity) or nil
		if not resultId then
			return
		end
		-- Material cost follows the sacrificed brainrot's effective type.
		local workId = BrainrotData.GetWorkIdForType(BrainrotData.GetEffectiveType(def, nil))
		local cost = BrainrotData.FUSION_MATERIAL_COST[rarity] or 15
		local coinFee = BrainrotData.FUSION_COIN_COST[rarity] or 100
		if not PlayerData.SpendCoins(player, coinFee) then
			remotes:WaitForChild("ShowHint"):FireClient(player, "Not enough coins! Need " .. tostring(coinFee) .. ".")
			return
		end
		if not workId or not PlayerData.SpendMaterials(player, { [workId] = cost }) then
			-- Refund coins if materials fail (fee taken first).
			PlayerData.AddCoins(player, coinFee)
			remotes:WaitForChild("ShowHint"):FireClient(player, "Not enough materials for fusion!")
			return
		end
		PlayerData.RemoveBrainrotInstances(player, instanceIds)
		local shiny = math.random() < BrainrotData.SHINY_CHANCE
		local variant = BrainrotData.RollVariant()
		local instance, err = PlayerData.TryAddBrainrot(player, resultId, shiny, variant)
		data.Fusions = (data.Fusions or 0) + 1
		DailyQuestSystem.RecordProgress(player, "fuse", 1)
		pushDailyState(player)
		PlotSystem.RefreshPlot(player)
		remotes:WaitForChild("FusionResult"):FireClient(player, {
			Kind = "Fusion",
			BrainrotId = instance and instance.BrainrotId or nil,
			Variant = instance and instance.Variant or nil,
			Shiny = instance and instance.Shiny or false,
			InventoryFull = err == "full",
			Coins = 0,
		})
	end
	pushCollection(player)
	pushWorkState(player)
	QuestSystem.CheckObjective(player, "fusions")
	QuestSystem.CheckObjective(player, "brainrots")
	PlayerData.Save(player)
end)

-- // Battles ---------------------------------------------------------------------
local function battleReward(player: Player, rival: any)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	if rival.RewardCoins then
		PlayerData.AddCoins(player, rival.RewardCoins)
		DailyQuestSystem.RecordProgress(player, "battle_win", 1)
		pushDailyState(player)
	end
	local grantedId: string? = nil
	if rival.RewardRarity then
		grantedId = BrainrotData.GetRandomIdOfRarity(rival.RewardRarity)
		if grantedId then
			local shiny = math.random() < BrainrotData.SHINY_CHANCE
			PlayerData.TryAddBrainrot(player, grantedId, shiny, BrainrotData.RollVariant())
		end
	end
	PlayerData.RecordRivalWin(player, rival.Id)
	PlotSystem.RefreshPlot(player)
	pushCollection(player)
	QuestSystem.CheckObjective(player, "rival", rival.Id)
	PlayerData.Save(player)
end

remotes:WaitForChild("StartBattle").OnServerEvent:Connect(function(player: Player, rivalId: any, teamIds: any)
	if type(rivalId) ~= "string" then
		return
	end
	local battle, err = BattleSystem.StartBattle(player, rivalId, teamIds)
	if not battle then
		remotes:WaitForChild("ShowHint"):FireClient(player, "Can't start battle: " .. tostring(err))
		return
	end
	-- Spawn the 3D fighters in the arena.
	PlotSystem.SpawnBattleModels(player, battle.pTeam, battle.eTeam)
	remotes:WaitForChild("BattleUpdate"):FireClient(player, {
		Phase = "Start",
		State = BattleSystem.GetClientState(player),
	})
end)

remotes:WaitForChild("SubmitMoves").OnServerEvent:Connect(function(player: Player, moveIndices: any)
	local result, err = BattleSystem.SubmitMoves(player, moveIndices)
	if not result then
		return
	end
	-- Animate the turn in the 3D arena (non-blocking; the UI log arrives instantly).
	task.spawn(function()
		PlotSystem.PlayBattleTurn(player, result.events)
		if result.winner then
			PlotSystem.PlayVictory(player, result.winner)
		end
	end)
	local payload: any = {
		Phase = "Turn",
		Events = result.events,
		State = BattleSystem.GetClientState(player),
	}
	if result.winner == "player" then
		local battle = BattleSystem.GetBattle(player)
		local rival = battle and BrainrotData.GetRival(battle.rivalId) or nil
		if rival then
			battleReward(player, rival)
		end
		payload.Rewards = {
			Coins = rival and rival.RewardCoins or 0,
			RewardRarity = rival and rival.RewardRarity or nil,
		}
		BattleSystem.ClearBattle(player)
		task.delay(4, function()
			PlotSystem.ClearBattleModels(player)
		end)
	elseif result.winner == "enemy" then
		BattleSystem.ClearBattle(player)
		task.delay(4, function()
			PlotSystem.ClearBattleModels(player)
		end)
	end
	remotes:WaitForChild("BattleUpdate"):FireClient(player, payload)
end)

remotes:WaitForChild("ForfeitBattle").OnServerEvent:Connect(function(player: Player)
	local battle = BattleSystem.Forfeit(player)
	if battle then
		remotes:WaitForChild("BattleUpdate"):FireClient(player, {
			Phase = "End",
			State = BattleSystem.GetClientState(player),
		})
		BattleSystem.ClearBattle(player)
		task.delay(2, function()
			PlotSystem.ClearBattleModels(player)
		end)
	end
end)

-- // World setup ----------------------------------------------------------------
PlotSystem.Setup()

-- Fusion Lab + Arena prompts.
if PlotSystem.FusionPrompt then
	PlotSystem.FusionPrompt.Triggered:Connect(function(player: Player)
		remotes:WaitForChild("OpenFusion"):FireClient(player)
	end)
end
if PlotSystem.ArenaPrompt then
	PlotSystem.ArenaPrompt.Triggered:Connect(function(player: Player)
		remotes:WaitForChild("OpenArena"):FireClient(player, {
			Rivals = BrainrotData.RIVALS,
			Beaten = (function()
				local d = PlayerData.Get(player)
				return d and d.RivalsBeaten or {}
			end)(),
		})
	end)
end

-- Glowing orb pickups for the "First Steps" quest.
-- Orbs spawn around the gameplay area (plots center 127, 98).
local ORB_CX, ORB_CZ = 127, 98
local ORB_POSITIONS = {
	Vector3.new(ORB_CX + 25, 3, ORB_CZ + 10),
	Vector3.new(ORB_CX - 30, 3, ORB_CZ + 15),
	Vector3.new(ORB_CX + 20, 3, ORB_CZ - 25),
	Vector3.new(ORB_CX - 15, 3, ORB_CZ - 30),
	Vector3.new(ORB_CX, 3, ORB_CZ - 55), -- near arena
	Vector3.new(ORB_CX + 70, 3, ORB_CZ), -- near fusion lab
	Vector3.new(ORB_CX + 10, 3, ORB_CZ + 45), -- near obby start
	Vector3.new(ORB_CX - 45, 3, ORB_CZ - 10),
}
local ORB_RESPAWN_SECONDS = 30

local orbsFolder = Instance.new("Folder")
orbsFolder.Name = "Orbs"
orbsFolder.Parent = workspace

local function spawnOrb(pos: Vector3)
	local orb = Instance.new("Part")
	orb.Name = "BrainrotOrb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(2, 2, 2)
	orb.Position = pos
	orb.Anchored = true
	orb.CanCollide = false
	orb.Material = Enum.Material.Neon
	orb.Color = Color3.fromRGB(255, 200, 60)
	-- Lift to terrain surface so orbs aren't buried.
	pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		local r = workspace:Raycast(Vector3.new(pos.X, 500, pos.Z), Vector3.new(0, -1000, 0), params)
		if r then
			orb.Position = Vector3.new(pos.X, r.Position.Y + 3, pos.Z)
		end
	end)
	orb.Parent = orbsFolder

	local debounce = false
	orb.Touched:Connect(function(hit: BasePart)
		if debounce then
			return
		end
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		local data = PlayerData.Get(player)
		if not data then
			return
		end

		debounce = true
		QuestSystem.AddProgress(player, 1)

		-- Brainrot Cache: every 5 orbs earns a random brainrot + coins.
		-- This is the core repeatable grind loop of the game.
		data.OrbProgress = (data.OrbProgress or 0) + 1
		DailyQuestSystem.RecordProgress(player, "orbs", 1)
		if data.OrbProgress >= 5 then
			data.OrbProgress = 0
			local rarity = BrainrotData.RollRewardRarity()
			local rewardId = BrainrotData.GetRandomIdOfRarity(rarity)
			if rewardId then
				local shiny = math.random() < BrainrotData.SHINY_CHANCE
				local variant = BrainrotData.RollVariant()
				local instance, err = PlayerData.TryAddBrainrot(player, rewardId, shiny, variant)
				if instance then
					PlotSystem.RefreshPlot(player)
				elseif err == "full" then
					PlayerData.AddCoins(player, 150)
				end
				remotes:WaitForChild("FusionResult"):FireClient(player, {
					Kind = "Cache",
					BrainrotId = instance and instance.BrainrotId or nil,
					Variant = instance and instance.Variant or nil,
					Shiny = instance and instance.Shiny or false,
					InventoryFull = err == "full",
					Coins = 25,
				})
			end
			PlayerData.AddCoins(player, 25)
			pushCollection(player)
			QuestSystem.CheckObjective(player, "brainrots")
			PlayerData.Save(player)
		end

		orb.Transparency = 1
		orb.CanTouch = false
		task.wait(ORB_RESPAWN_SECONDS)
		orb.Transparency = 0
		orb.CanTouch = true
		debounce = false
	end)
end

for _, pos in ipairs(ORB_POSITIONS) do
	spawnOrb(pos)
end

-- Quest board near spawn: reminds the player what to do.
local board = Instance.new("Part")
board.Name = "QuestBoard"
board.Size = Vector3.new(6, 5, 0.6)
board.Position = Vector3.new(127, 16, 60) -- near plots (gameplay center 127, 98)
board.Anchored = true
board.Color = Color3.fromRGB(150, 110, 70)
pcall(function()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local r = workspace:Raycast(Vector3.new(127, 500, 60), Vector3.new(0, -1000, 0), params)
	if r then
		board.Position = Vector3.new(127, r.Position.Y + 3.5, 60)
	end
end)
board.Material = Enum.Material.Wood
board.Parent = workspace

local boardGui = Instance.new("SurfaceGui")
boardGui.Face = Enum.NormalId.Front
boardGui.Parent = board
local boardLabel = Instance.new("TextLabel")
boardLabel.Size = UDim2.new(1, 0, 1, 0)
boardLabel.BackgroundTransparency = 1
boardLabel.Text = "QUEST BOARD\nTouch the glowing orbs!"
boardLabel.TextScaled = true
boardLabel.Font = Enum.Font.GothamBold
boardLabel.TextColor3 = Color3.new(1, 1, 1)
boardLabel.TextStrokeTransparency = 0.6
boardLabel.Parent = boardGui

local prompt = Instance.new("ProximityPrompt")
prompt.ActionText = "Read Board"
prompt.ObjectText = "Quest Board"
prompt.HoldDuration = 0
prompt.MaxActivationDistance = 12
prompt.Parent = board

prompt.Triggered:Connect(function(player: Player)
	local quest, _ = QuestSystem.GetActiveQuest(player)
	if quest then
		remotes:WaitForChild("ShowHint"):FireClient(player, quest.Name .. ": " .. quest.Description)
	else
		remotes:WaitForChild("ShowHint"):FireClient(player, "No active quests. More adventures coming soon!")
	end
end)

-- Expedition board: physical gateway to the expedition system.
local expBoard = Instance.new("Part")
expBoard.Name = "ExpeditionBoard"
expBoard.Size = Vector3.new(6, 5, 0.6)
expBoard.Anchored = true
expBoard.Color = Color3.fromRGB(60, 120, 60)
expBoard.Material = Enum.Material.Wood
pcall(function()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local r = workspace:Raycast(Vector3.new(135, 500, 60), Vector3.new(0, -1000, 0), params)
	if r then
		expBoard.Position = Vector3.new(135, r.Position.Y + 3.5, 60)
	else
		expBoard.Position = Vector3.new(135, 16, 60)
	end
end)
expBoard.Parent = workspace

local expGui = Instance.new("SurfaceGui")
expGui.Face = Enum.NormalId.Front
expGui.Parent = expBoard
local expLabel = Instance.new("TextLabel")
expLabel.Size = UDim2.new(1, 0, 1, 0)
expLabel.BackgroundTransparency = 1
expLabel.Text = "EXPEDITION BOARD\nSend brainrots to gather!"
expLabel.TextScaled = true
expLabel.Font = Enum.Font.GothamBold
expLabel.TextColor3 = Color3.new(1, 1, 1)
expLabel.TextStrokeTransparency = 0.6
expLabel.Parent = expGui

local expPrompt = Instance.new("ProximityPrompt")
expPrompt.ActionText = "Open"
expPrompt.ObjectText = "Expedition Board"
expPrompt.HoldDuration = 0
expPrompt.MaxActivationDistance = 12
expPrompt.Parent = expBoard

expPrompt.Triggered:Connect(function(player: Player)
	-- Tell client to open expedition panel
	remotes:WaitForChild("ExpeditionUpdate"):FireClient(player, ExpeditionSystem.GetStatus(player))
	remotes:WaitForChild("ShowHint"):FireClient(player, "Open the Explore menu to send expeditions!")
end)

-- Zone portals: physical entrances to expedition zones.
-- Placed in a row near the expedition board. Walking through discovers the zone.
local PORTAL_SPACING = 15
local PORTAL_START_X = 150
for i, zoneId in ipairs(BrainrotData.ZONE_ORDER) do
	local portal = VisualEffects.BuildZonePortal(zoneId)
	local x = PORTAL_START_X + (i - 1) * PORTAL_SPACING
	pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		local r = workspace:Raycast(Vector3.new(x, 500, 80), Vector3.new(0, -1000, 0), params)
		if r then
			portal:PivotTo(CFrame.new(Vector3.new(x, r.Position.Y, 80)))
		else
			portal:PivotTo(CFrame.new(Vector3.new(x, 16, 80)))
		end
	end)
	portal.Parent = workspace

	-- Discovery trigger: touching the portal unlocks the zone
	local surface = portal:FindFirstChild("PortalSurface")
	if surface and surface:IsA("BasePart") then
		(surface :: BasePart).Touched:Connect(function(hit: BasePart)
			local char = hit and hit.Parent
			local player = char and game:GetService("Players"):GetPlayerFromCharacter(char)
			if player then
				if ExpeditionSystem.UnlockZone(player, zoneId) then
					pushExpeditionState(player)
				end
			end
		end)
	end
end

-- // Player wiring ----------------------------------------------------------------
local function sendInitialState(player: Player)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	local quest, questId = QuestSystem.GetActiveQuest(player)
	if quest then
		remotes:WaitForChild("QuestUpdate"):FireClient(player, {
			Type = "Progress",
			QuestId = questId,
			Name = quest.Name,
			Progress = data.QuestProgress,
			Goal = quest.Goal,
		})
	end
	remotes:WaitForChild("CollectionUpdate"):FireClient(player, {
		Brainrots = data.Brainrots,
		Showcase = data.Showcase,
		Coins = data.Coins,
		Working = PlayerData.GetWorkingIds(player),
	})
end

-- // Expeditions ------------------------------------------------------------------
local function pushExpeditionState(player: Player)
	local status = ExpeditionSystem.GetStatus(player)
	remotes:WaitForChild("ExpeditionUpdate"):FireClient(player, status)
end

remotes:WaitForChild("StartExpedition").OnServerEvent:Connect(function(player: Player, zoneId: any, teamIds: any)
	if type(zoneId) ~= "string" or type(teamIds) ~= "table" then return end
	local ok, msg = ExpeditionSystem.StartExpedition(player, zoneId, teamIds)
	if ok then
		pushExpeditionState(player)
		pushCollection(player)
		-- Departure animation: team walks off toward the zone
		task.spawn(function()
			local plot = PlotSystem.GetPlot(player)
			if plot then
				local base = plot:FindFirstChild("Base")
				if base and base:IsA("BasePart") then
					local bp = (base :: BasePart).Position
					local models = {}
					for i, instanceId in ipairs(teamIds) do
						local inst = PlayerData.GetInstance(player, instanceId)
						local def = inst and BrainrotData.GetBrainrot(inst.BrainrotId)
						if def then
							local m = PlotSystem.BuildDisplayModel(def, inst.Shiny == true, inst.Variant)
							m:PivotTo(CFrame.new(bp + Vector3.new((i - 2) * 4, 3, 0)))
							m.Parent = workspace
							table.insert(models, m)
						end
					end
					-- Walk toward expedition board direction (east)
					VisualEffects.PlayDeparture(models, Vector3.new(1, 0, 0.3))
				end
			end
		end)
	else
		remotes:WaitForChild("ShowHint"):FireClient(player, msg or "Could not start expedition")
	end
end)

remotes:WaitForChild("UnlockZone").OnServerEvent:Connect(function(player: Player, zoneId: any)
	if type(zoneId) ~= "string" then return end
	if ExpeditionSystem.UnlockZone(player, zoneId) then
		pushExpeditionState(player)
		remotes:WaitForChild("ShowHint"):FireClient(player, "Discovered: " .. (BrainrotData.ZONES[zoneId] and BrainrotData.ZONES[zoneId].Name or zoneId))
	end
end)

-- // Daily Quests ------------------------------------------------------------------
local function pushDailyState(player: Player)
	local status = DailyQuestSystem.GetStatus(player)
	remotes:WaitForChild("DailyUpdate"):FireClient(player, status)
end

-- Forward-declared (defined in Eggs section below, used by ClaimDailyEgg).
local pushEggStateFn: ((Player) -> ())?

remotes:WaitForChild("ClaimDailyEgg").OnServerEvent:Connect(function(player: Player, tier: any)
	if type(tier) ~= "string" then return end
	local ok, msg = DailyQuestSystem.ClaimEgg(player, tier)
	if ok then
		pushDailyState(player)
		if pushEggStateFn then pushEggStateFn(player) end
		PlotSystem.RefreshEggs(player)
		remotes:WaitForChild("ShowHint"):FireClient(player, "Mystery egg added to incubator!")
	else
		remotes:WaitForChild("ShowHint"):FireClient(player, msg or "Could not claim egg")
	end
end)

-- // Eggs ------------------------------------------------------------------
local function pushEggState(player: Player)
	local status = EggSystem.GetStatus(player)
	remotes:WaitForChild("EggUpdate"):FireClient(player, status)
end
pushEggStateFn = pushEggState

remotes:WaitForChild("BuyEggSlot").OnServerEvent:Connect(function(player: Player)
	local ok, msg = EggSystem.BuySlot(player)
	if ok then
		pushEggState(player)
		pushCollection(player)
		remotes:WaitForChild("ShowHint"):FireClient(player, "Incubator slot added!")
	else
		remotes:WaitForChild("ShowHint"):FireClient(player, msg or "Could not buy slot")
	end
end)

-- // Passive Income ------------------------------------------------------------------
remotes:WaitForChild("CollectPassive").OnServerEvent:Connect(function(player: Player)
	local amount = PlayerData.CollectPassive(player)
	if amount > 0 then
		pushCollection(player)
		remotes:WaitForChild("PassiveUpdate"):FireClient(player, { Banked = 0, Collected = amount })
		remotes:WaitForChild("ShowHint"):FireClient(player, "+" .. tostring(amount) .. " coins from gold mine!")
		DailyQuestSystem.RecordProgress(player, "coins_earned", amount)
	end
end)

-- // Customization ------------------------------------------------------------------
local function pushCustomizeState(player: Player)
	local data = PlayerData.Get(player)
	if not data then return end
	remotes:WaitForChild("CustomizeUpdate"):FireClient(player, {
		Theme = data.PlotTheme,
		UnlockedThemes = data.UnlockedThemes,
		Decorations = data.Decorations,
		GoldMineLevel = data.GoldMineLevel,
	})
end

remotes:WaitForChild("UnlockTheme").OnServerEvent:Connect(function(player: Player, themeId: any)
	if type(themeId) ~= "string" then return end
	local ok, msg = PlayerData.UnlockTheme(player, themeId)
	if ok then
		pushCustomizeState(player)
		pushCollection(player)
		PlotSystem.RefreshPlot(player) -- apply theme visual
		remotes:WaitForChild("ShowHint"):FireClient(player, "Plot theme unlocked!")
	else
		remotes:WaitForChild("ShowHint"):FireClient(player, msg or "Could not unlock theme")
	end
end)

remotes:WaitForChild("BuyDecoration").OnServerEvent:Connect(function(player: Player, decoId: any)
	if type(decoId) ~= "string" then return end
	local ok, msg = PlayerData.BuyDecoration(player, decoId)
	if ok then
		pushCustomizeState(player)
		pushCollection(player)
		PlotSystem.RefreshPlot(player) -- show decoration
		remotes:WaitForChild("ShowHint"):FireClient(player, "Decoration placed!")
	else
		remotes:WaitForChild("ShowHint"):FireClient(player, msg or "Could not buy decoration")
	end
end)

local function onPlayerAdded(player: Player)
	PlayerData.Load(player)
	PlayerData.ResetStationClocks(player) -- workers rest while you're away
	PlotSystem.AssignPlot(player)
	PlotSystem.RefreshPlot(player)
	PlotSystem.RefreshWorkers(player)
	-- Teleport to plot on every spawn (world is big; spawn may be far away).
	player.CharacterAdded:Connect(function()
		task.wait(0.3)
		PlotSystem.TeleportToPlot(player)
	end)
	-- Also teleport now if character already exists.
	if player.Character then
		task.defer(function()
			PlotSystem.TeleportToPlot(player)
		end)
	end
	-- Defer so the client's UI exists before we fire at it.
	task.defer(function()
		sendInitialState(player)
		pushWorkState(player)
		DailyQuestSystem.EnsureToday(player)
		pushDailyState(player)
		pushExpeditionState(player)
		pushEggState(player)
		pushCustomizeState(player)
		PlotSystem.RefreshEggs(player)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player: Player)
	BattleSystem.ClearBattle(player)
	PlayerData.Release(player)
	PlotSystem.ReleasePlot(player)
end)

game:BindToClose(function()
	for _, p in ipairs(Players:GetPlayers()) do
		PlayerData.Save(p)
	end
end)

-- Production tick: advance every online player's stations every 30s.
-- Also: expeditions (check completions), eggs (incubation), passive income.
local tickCount = 0
task.spawn(function()
	while true do
		task.wait(30)
		tickCount += 1
		for _, p in ipairs(Players:GetPlayers()) do
			local data = PlayerData.Get(p)
			if not data then continue end
			-- Workstations
			if next(data.Jobs) ~= nil then
				pushWorkState(p)
			end
			-- Expeditions: check for completions
			local results = ExpeditionSystem.TickExpeditions(p)
			if #results > 0 then
				pushExpeditionState(p)
				pushCollection(p)
				for _, r in ipairs(results) do
					remotes:WaitForChild("ShowHint"):FireClient(p,
						"Expedition complete! Materials scattered on your plot!")
					DailyQuestSystem.RecordProgress(p, "expedition_complete", 1)
					-- Spawn 3D material pickups on plot (collect by touching)
					PlotSystem.SpawnMaterialPickups(p, r.Materials)
				end
				pushDailyState(p)
			elseif next(data.Expeditions) ~= nil then
				pushExpeditionState(p) -- update countdown timers
			end
			-- Eggs: 0.5 minutes of incubation per 30s tick
			local hatched = EggSystem.TickIncubation(p, 0.5)
			if #hatched > 0 then
				pushEggState(p)
				pushCollection(p)
				PlotSystem.RefreshEggs(p)
				for _, h in ipairs(hatched) do
					remotes:WaitForChild("ShowHint"):FireClient(p,
						"Egg hatched: " .. h.BrainrotName .. " (" .. h.Rarity .. ")!")
					-- Play 3D hatching animation
					local def = BrainrotData.GetBrainrot(h.BrainrotId)
					-- Note: eggId not in hatch result, refresh eggs instead
				end
				pushDailyState(p)
			elseif next(data.Eggs) ~= nil then
				pushEggState(p) -- update progress bars
			end
			-- Passive income: bank coins
			local gained = PlayerData.TickPassiveIncome(p)
			if gained > 0 then
				remotes:WaitForChild("PassiveUpdate"):FireClient(p, {
					Banked = math.floor(data.PassiveBanked or 0),
				})
			end
		end
	end
end)

print("[Brainrot Arena] Server online — milestone 1 prototype.")
