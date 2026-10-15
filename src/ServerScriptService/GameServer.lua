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
local FishingSystem = require(Systems:WaitForChild("FishingSystem"))
local WanderSystem = require(Systems:WaitForChild("WanderSystem"))
local SoundSystem = require(Systems:WaitForChild("SoundSystem"))
local WeatherSystem = require(Systems:WaitForChild("WeatherSystem"))
local AchievementSystem = require(Systems:WaitForChild("AchievementSystem"))
local LeaderboardSystem = require(Systems:WaitForChild("LeaderboardSystem"))
local WorldDesign = require(Systems:WaitForChild("WorldDesign"))
local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))

-- // RemoteEvents --------------------------------------------------------------
-- Idempotent: reuse a Remotes folder saved in the place file instead of
-- stacking a duplicate on every server start.
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

for _, name in ipairs({ "QuestUpdate", "CollectionUpdate", "ShowHint", "UpdateShowcase", "AssignWorker", "CollectStation", "WorkUpdate", "OpenFusion", "OpenArena", "FusionResult", "BattleUpdate", "FuseBrainrots", "StartBattle", "SubmitMoves", "ForfeitBattle", "StartExpedition", "ExpeditionUpdate", "ClaimDailyEgg", "DailyUpdate", "BuyEggSlot", "EggUpdate", "CollectPassive", "PassiveUpdate", "UnlockTheme", "BuyDecoration", "CustomizeUpdate", "UnlockZone", "CastLine", "ReelIn", "FishingUpdate", "WildCaught", "BuyUpgrade",
		"PlaySound", "WeatherUpdate", "AchievementUnlocked", "LeaderboardUpdate" }) do
	if not remotes:FindFirstChild(name) then
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = remotes
	end
end

local function pushCollection(player: Player)
	local data = PlayerData.Get(player)
	if data then
		remotes:WaitForChild("CollectionUpdate"):FireClient(player, {
			Brainrots = data.Brainrots,
			Showcase = data.Showcase,
			Coins = data.Coins,
			Working = PlayerData.GetWorkingIds(player),
			Upgrades = data.Upgrades or { Speed = 0, Jump = 0, Reach = 0, Luck = 0 },
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
		-- 3D fusion celebration at player position
		task.spawn(function()
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and instance then
				local def = BrainrotData.GetBrainrot(instance.BrainrotId)
				if def then
					local resultModel = PlotSystem.BuildDisplayModel(def, true, instance.Variant)
					local fusionPos = (hrp :: BasePart).Position + Vector3.new(0, 5, 0)
					-- Create dummy input models for the animation
					local dummies = {}
					VisualEffects.PlayFusion(dummies, fusionPos, resultModel, function() end)
				end
			end
		end)
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
		-- Leaderboard + achievements
		LeaderboardSystem.RecordWin(player)
		SoundSystem.PlayForPlayer(player, "BattleWin")
		local newAch = AchievementSystem.RecordProgress(player, "battles_won", 1)
		for _, achId in ipairs(newAch) do
			local def = AchievementSystem.DEFS[achId]
			if def then
				remotes:WaitForChild("AchievementUnlocked"):FireClient(player, {
					Name = def.Name, Desc = def.Desc,
				})
			end
		end
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
	local quest, questId = QuestSystem.GetActiveQuest(player)
	if quest then
		-- Diagnostic (2026-10-14): line 484 threw "attempt to call a nil value".
		-- FindFirstChild + explicit checks so the output names the culprit.
		local showHint = remotes and remotes:FindFirstChild("ShowHint")
		if showHint and showHint:IsA("RemoteEvent") then
			showHint:FireClient(player, tostring(quest.Name) .. ": " .. tostring(quest.Description))
		else
			warn(("[GameServer] QuestBoard: ShowHint remote missing (remotes=%s, showHint=%s, questId=%s)"):format(
				typeof(remotes), showHint and showHint.ClassName or "nil", tostring(questId)))
		end
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
local PORTAL_SPACING = 18
local PORTAL_START_X = 100
local PORTAL_Z = 155 -- south of plots (plots end at Z~132), clear of colosseum
for i, zoneId in ipairs(BrainrotData.ZONE_ORDER) do
	local portal = VisualEffects.BuildZonePortal(zoneId)
	local x = PORTAL_START_X + (i - 1) * PORTAL_SPACING
	pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		local r = workspace:Raycast(Vector3.new(x, 500, PORTAL_Z), Vector3.new(0, -1000, 0), params)
		if r then
			portal:PivotTo(CFrame.new(Vector3.new(x, r.Position.Y, PORTAL_Z)))
		else
			portal:PivotTo(CFrame.new(Vector3.new(x, 16, PORTAL_Z)))
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

-- Shared gold mine: ONE mine in the world, 100 studs east of plots.
-- Anyone can harvest it (per-player cooldown).
local sharedMine = VisualEffects.BuildGoldMine(1)
do
	local mx, mz = 227, 98 -- 100 studs east of plot center (127, 98)
	local my = 16
	pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		local r = workspace:Raycast(Vector3.new(mx, 500, mz), Vector3.new(0, -1000, 0), params)
		if r then my = r.Position.Y end
	end)
	sharedMine:PivotTo(CFrame.new(Vector3.new(mx, my + 1, mz)))
	sharedMine.Parent = workspace
end

local mineCooldown: { [number]: number } = {} -- [userId] = last harvest time
local MINE_COOLDOWN_SECS = 60
local MINE_REWARD = 25

local minePrompt = Instance.new("ProximityPrompt")
minePrompt.ActionText = "Mine Gold"
minePrompt.ObjectText = "Shared Gold Mine"
minePrompt.HoldDuration = 2
minePrompt.MaxActivationDistance = 12
minePrompt.RequiresLineOfSight = false
minePrompt.Parent = sharedMine.PrimaryPart or sharedMine:FindFirstChildWhichIsA("BasePart")
minePrompt.Triggered:Connect(function(player: Player)
	local now = os.time()
	local last = mineCooldown[player.UserId] or 0
	if now - last < MINE_COOLDOWN_SECS then
		local waitSecs = MINE_COOLDOWN_SECS - (now - last)
		remotes:WaitForChild("ShowHint"):FireClient(player,
			"Mine is exhausted! Come back in " .. waitSecs .. "s.")
		return
	end
	mineCooldown[player.UserId] = now
	local data = PlayerData.Get(player)
	if not data then return end
	PlayerData.AddCoins(player, MINE_REWARD)
	DailyQuestSystem.RecordProgress(player, "coins_earned", MINE_REWARD)
	pushCollection(player)
	PlayerData.Save(player)
	remotes:WaitForChild("ShowHint"):FireClient(player,
		"+ " .. MINE_REWARD .. " coins from the gold mine!")
end)

-- Fishing docks near water.
local fishingSpots = {}
for i, spotInfo in ipairs({
	{ X = 100, Z = 120, Name = "Riverside Dock" },
	{ X = 160, Z = 130, Name = "Lakeside Pier" },
}) do
	local dock = VisualEffects.BuildFishingSpot()
	pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		local r = workspace:Raycast(
			Vector3.new(spotInfo.X, 500, spotInfo.Z),
			Vector3.new(0, -1000, 0),
			params
		)
		if r then
			dock:PivotTo(CFrame.new(Vector3.new(spotInfo.X, r.Position.Y, spotInfo.Z)))
		else
			dock:PivotTo(CFrame.new(Vector3.new(spotInfo.X, 16, spotInfo.Z)))
		end
	end)
	dock.Parent = workspace
	table.insert(fishingSpots, { Id = "dock" .. i, Model = dock, Name = spotInfo.Name })
end

-- // Fishing ------------------------------------------------------------------
local function pushFishingState(player: Player, state: string, reward: any?)
	remotes:WaitForChild("FishingUpdate"):FireClient(player, {
		State = state,
		Reward = reward,
	})
end

-- Track fishing gear per player for bite/catch animation
local playerFishingGear: { [number]: any } = {}

remotes:WaitForChild("CastLine").OnServerEvent:Connect(function(player: Player, spotId: any)
	if type(spotId) ~= "string" then return end
	local biteDelay = FishingSystem.Cast(player, spotId)
	if biteDelay then
		-- Visual: rod + bobber with line
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local fromPos = (hrp :: BasePart).Position + Vector3.new(0, 3, 0)
			local dockPos = fromPos + Vector3.new(0, 0, 10)
			for _, spot in ipairs(fishingSpots) do
				if spot.Id == spotId then
					local water = spot.Model:FindFirstChild("Water")
					if water and water:IsA("BasePart") then
						dockPos = (water :: BasePart).Position + Vector3.new(0, 1, 0)
					end
					break
				end
			end
			local gear = VisualEffects.CastBobber(player, fromPos, dockPos)
			playerFishingGear[player.UserId] = gear
		end
		pushFishingState(player, "Waiting")
		-- Schedule bite notification
		task.delay(biteDelay, function()
			local state = FishingSystem.CheckBite(player)
			if state == "Bite" then
				local gear = playerFishingGear[player.UserId]
				if gear and gear.Bobber then
					VisualEffects.PlayBite(gear.Bobber)
				end
				pushFishingState(player, "Bite")
			end
		end)
		-- Expire bite after 3s
		task.delay(biteDelay + 3.5, function()
			local state = FishingSystem.GetState(player)
			if state == "Missed" then
				pushFishingState(player, "Missed")
				local gear = playerFishingGear[player.UserId]
				if gear then
					if gear.Bobber and gear.Bobber.Parent then gear.Bobber:Destroy() end
					if gear.Stripe and gear.Stripe.Parent then gear.Stripe:Destroy() end
					if gear.Rod and gear.Rod.Parent then gear.Rod:Destroy() end
				end
				playerFishingGear[player.UserId] = nil
				FishingSystem.Cancel(player)
			end
		end)
	end
end)

remotes:WaitForChild("ReelIn").OnServerEvent:Connect(function(player: Player, quality: any)
	local q = tonumber(quality) or 0.5
	local reward = FishingSystem.Reel(player, q)
	-- Cleanup gear, play catch
	local gear = playerFishingGear[player.UserId]
	if gear and gear.Bobber and gear.Bobber.Parent then
		local bobberPos = gear.Bobber.Position
		if reward and reward.Kind ~= "Miss" then
			VisualEffects.PlayCatch(bobberPos, reward.Kind)
			-- Spawn 3D fish model for fish/brainrot catches
			if reward.Kind == "Fish" or reward.Kind == "Brainrot" then
				local fish = VisualEffects.BuildFish(reward.Kind == "Brainrot")
				fish:PivotTo(CFrame.new(bobberPos + Vector3.new(0, 1, 0)))
				fish.Parent = workspace
				-- Fish jumps and flops
				task.spawn(function()
					for i = 1, 15 do
						if not fish or not fish.Parent then break end
						local t = i / 15
						fish:PivotTo(CFrame.new(
							bobberPos + Vector3.new(0, 1 + math.sin(t * math.pi) * 4, 0)
						) * CFrame.Angles(0, 0, math.sin(t * 20) * 0.5))
						task.wait(0.05)
					end
					task.wait(1)
					if fish and fish.Parent then fish:Destroy() end
				end)
			end
		end
		gear.Bobber:Destroy()
		if gear.Stripe and gear.Stripe.Parent then gear.Stripe:Destroy() end
		if gear.Rod and gear.Rod.Parent then gear.Rod:Destroy() end
	end
	playerFishingGear[player.UserId] = nil
	if reward then
		pushFishingState(player, "None", reward)
		pushCollection(player)
		if reward.Kind == "Brainrot" then
			PlotSystem.RefreshPlot(player)
		end
	end
end)

-- Cancel fishing if player leaves
Players.PlayerRemoving:Connect(function(player: Player)
	FishingSystem.Cancel(player)
	local gear = playerFishingGear[player.UserId]
	if gear then
		if gear.Bobber and gear.Bobber.Parent then gear.Bobber:Destroy() end
		if gear.Rod and gear.Rod.Parent then gear.Rod:Destroy() end
	end
	playerFishingGear[player.UserId] = nil
end)

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

-- // Wandering Brainrots ---------------------------------------------------------------
-- Wild spawns with rarity-tuned timers. Each player sees their own.
local wanderModels: { [number]: { [string]: Model } } = {} -- [userId][wanderId] = model
local wanderBeams: { [number]: { [string]: Model } } = {} -- legendary beams

local function spawnWildVisual(player: Player, wanderId: string)
	local wander = WanderSystem.GetWanderer(player, wanderId)
	if not wander then return end
	local def = BrainrotData.GetBrainrot(wander.BrainrotId)
	if not def then return end

	-- Build model
	local model = PlotSystem.BuildDisplayModel(def, false, nil)
	-- Normalize size: wilds should fit in a ~2.5 stud box (smaller than player).
	-- Uses max dimension so long/wide models (dolphin) get caught too.
	pcall(function()
		local _, bbSize = model:GetBoundingBox()
		if bbSize then
			local maxDim = math.max(bbSize.X, bbSize.Y, bbSize.Z)
			if maxDim > 0 then
				local targetMax = 3.0
				local s = targetMax / maxDim
				-- Only adjust if meaningfully off (avoid jitter).
				if math.abs(s - 1) > 0.15 then
					s = math.clamp(s, 0.3, 1.5)
					model:ScaleTo(s)
				end
			end
		end
	end)
	VisualEffects.AddWildAura(model, wander.Rarity)

	-- Ground position via raycast
	local spawnPos = wander.SpawnPos
	pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		local r = workspace:Raycast(
			Vector3.new(spawnPos.X, 500, spawnPos.Z),
			Vector3.new(0, -1000, 0),
			params
		)
		if r then
			spawnPos = r.Position + Vector3.new(0, 2, 0)
		else
			spawnPos = Vector3.new(spawnPos.X, 18, spawnPos.Z)
		end
	end)
	model:PivotTo(CFrame.new(spawnPos))
	model.Parent = workspace

	-- Make catchable via invisible hitbox (size scales with Reach upgrade)
	local reachTier = PlayerData.GetUpgradeTier(player, "Reach")
	local hitboxSize = 6
	if reachTier > 0 then
		hitboxSize = PlayerData.UPGRADE_DEFS.Reach.Values[reachTier]
	end
	local hitbox = Instance.new("Part")
	hitbox.Name = "WildHitbox"
	hitbox.Size = Vector3.new(hitboxSize, hitboxSize, hitboxSize)
	hitbox.Transparency = 1
	hitbox.CanCollide = false
	hitbox.Anchored = true
	hitbox.Position = spawnPos
	hitbox.Parent = model
	hitbox:SetAttribute("WanderId", wanderId)
	hitbox:SetAttribute("OwnerId", player.UserId)

	hitbox.Touched:Connect(function(hit: BasePart)
		local char = hit and hit.Parent
		local p = char and Players:GetPlayerFromCharacter(char)
		if p and p.UserId == player.UserId then
			-- Catch!
			local result = WanderSystem.Catch(p, wanderId)
			if result and result.Success then
				VisualEffects.PlayWildCatch(spawnPos, wander.Rarity)
				SoundSystem.PlayForPlayer(p, "Catch" .. wander.Rarity)
				-- Achievements
				local newAch = AchievementSystem.RecordProgress(p, "wild_caught", 1)
				if wander.Rarity == "Rare" then
					for _, id in ipairs(AchievementSystem.RecordProgress(p, "rare_caught", 1)) do
						table.insert(newAch, id)
					end
				elseif wander.Rarity == "Epic" then
					for _, id in ipairs(AchievementSystem.RecordProgress(p, "epic_caught", 1)) do
						table.insert(newAch, id)
					end
				elseif wander.Rarity == "Legendary" then
					for _, id in ipairs(AchievementSystem.RecordProgress(p, "legendary_caught", 1)) do
						table.insert(newAch, id)
					end
				end
				if result.Shiny then
					for _, id in ipairs(AchievementSystem.RecordProgress(p, "shinies", 1)) do
						table.insert(newAch, id)
					end
				end
				for _, achId in ipairs(newAch) do
					local def = AchievementSystem.DEFS[achId]
					if def then
						remotes:WaitForChild("AchievementUnlocked"):FireClient(p, {
							Name = def.Name, Desc = def.Desc,
						})
						SoundSystem.PlayForPlayer(p, "Achievement")
					end
				end
				remotes:WaitForChild("WildCaught"):FireClient(p, result)
				remotes:WaitForChild("ShowHint"):FireClient(p,
					"Caught: " .. result.BrainrotName .. " (" .. result.Rarity .. ")!" ..
					(if result.Shiny then " ✨ SHINY!" else ""))
				pushCollection(p)
				PlotSystem.RefreshPlot(p)
				QuestSystem.CheckObjective(p, "brainrots")
			end
			-- Cleanup
			if wanderModels[player.UserId] then
				wanderModels[player.UserId][wanderId] = nil
			end
			if model and model.Parent then
				model:Destroy()
			end
			-- Remove beam if legendary
			if wanderBeams[player.UserId] and wanderBeams[player.UserId][wanderId] then
				local beam = wanderBeams[player.UserId][wanderId]
				if beam and beam.Parent then beam:Destroy() end
				wanderBeams[player.UserId][wanderId] = nil
			end
		end
	end)

	-- Track
	if not wanderModels[player.UserId] then
		wanderModels[player.UserId] = {}
	end
	wanderModels[player.UserId][wanderId] = model
	wander.Model = model

	-- Legendary beam + announcement
	if wander.Rarity == "Legendary" then
		local beam = VisualEffects.BuildLegendaryBeam(spawnPos)
		beam.Parent = workspace
		if not wanderBeams[player.UserId] then
			wanderBeams[player.UserId] = {}
		end
		wanderBeams[player.UserId][wanderId] = beam
		remotes:WaitForChild("ShowHint"):FireClient(player,
			"🌟 LEGENDARY BRAINROT SPOTTED! Follow the golden beam! (3 min)")
	end

	-- Wandering AI: random walk + flee from player
	task.spawn(function()
		local cfg = wander.Config
		local currentPos = spawnPos
		local targetPos = currentPos
		local fleeing = false
		while model and model.Parent do
			-- Check if player is near (flee)
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local playerPos = hrp and (hrp :: BasePart).Position
			if playerPos and cfg.FleeRadius > 0 then
				local dist = (currentPos - playerPos).Magnitude
				if dist < cfg.FleeRadius then
					-- Flee away from player
					local fleeDir = (currentPos - playerPos).Unit
					targetPos = currentPos + fleeDir * 20
					fleeing = true
				else
					fleeing = false
				end
			end
			-- Pick new random target if reached or every 5s
			if (currentPos - targetPos).Magnitude < 3 or math.random() < 0.2 then
				if not fleeing then
					targetPos = currentPos + Vector3.new(
						(math.random() - 0.5) * 40,
						0,
						(math.random() - 0.5) * 40
					)
				end
			end
			-- Move toward target with walk bob
			local dir = (targetPos - currentPos)
			dir = Vector3.new(dir.X, 0, dir.Z)
			if dir.Magnitude > 0.5 then
				dir = dir.Unit
				local speed = cfg.WalkSpeed * (if fleeing then 1.5 else 1)
				currentPos += dir * speed * 0.2
				-- Bob while walking
				local bobY = math.abs(math.sin(os.clock() * 8)) * 0.4
				-- Face movement direction (face is on +Z, so flip 180° from default -Z forward).
				local cf = CFrame.new(currentPos + Vector3.new(0, bobY, 0), currentPos + dir * 5)
				model:PivotTo(cf * CFrame.Angles(0, math.pi, 0))
				-- Move hitbox with model
				if hitbox and hitbox.Parent then
					hitbox.Position = currentPos + Vector3.new(0, 1, 0)
				end
			end
			task.wait(0.2)
		end
	end)
end

-- Spawn timers per rarity (staggered)
-- Tracks last spawn time per player per rarity
local lastSpawn: { [number]: { [string]: number } } = {}
task.spawn(function()
	while true do
		task.wait(15) -- check every 15s
		local now = os.time()
		print("[WildSpawn] Tick — players online:", #Players:GetPlayers())
		for _, player in ipairs(Players:GetPlayers()) do
			local userId = player.UserId
			if not lastSpawn[userId] then
				lastSpawn[userId] = {}
			end
			-- Check each rarity's timer
			for _, rarity in ipairs({ "Common", "Rare", "Epic", "Legendary" }) do
				local cfg = WanderSystem.GetRarityConfig(rarity)
				if cfg then
					local last = lastSpawn[userId][rarity] or 0
					-- Random interval within the rarity's range
					local interval = math.random(cfg.RespawnSecs[1], cfg.RespawnSecs[2])
					if now - last >= interval then
						-- Roll: only spawn if this rarity wins the weight roll
						-- (prevents every timer firing at once)
						local roll = math.random() * 100
						local totalWeight = 60 + 25 + 12 + 3
						local weight = cfg.Weight / totalWeight * 100
						-- Scale by how overdue we are (guaranteed eventually)
						local overdue = (now - last) / interval
						if roll < weight * overdue then
							-- Force this rarity by temporarily overriding
							-- (SpawnWild rolls internally, so we retry until we get it or give up)
							-- Lucky Charm boost
							local luckTier = PlayerData.GetUpgradeTier(player, 'Luck')
							local luckMult = 1
							if luckTier > 0 then
								luckMult = PlayerData.UPGRADE_DEFS.Luck.Values[luckTier]
							end
							for attempt = 1, 5 do
								local wanderId = WanderSystem.SpawnWild(player, PlotSystem, luckMult)
								if wanderId then
									local wander = WanderSystem.GetWanderer(player, wanderId)
									if wander and wander.Rarity == rarity then
										print("[WildSpawn] Spawning", rarity, wanderId, "for", player.Name)
										spawnWildVisual(player, wanderId)
										print("[WildSpawn] Visual done for", wanderId)
										lastSpawn[userId][rarity] = now
										break
									else
										-- Wrong rarity, remove and retry
										WanderSystem.Remove(player, wanderId)
									end
								else
									print("[WildSpawn] SpawnWild nil (cap?) for", player.Name)
									break -- at cap
								end
							end
						end
					end
				end
			end
		end
		-- Cleanup despawns
		local despawned = WanderSystem.TickDespawn()
		for _, item in ipairs(despawned) do
			local userId = item.UserId
			local wanderId = item.WanderId
			if wanderModels[userId] and wanderModels[userId][wanderId] then
				local model = wanderModels[userId][wanderId]
				if model and model.Parent then
					model:Destroy()
				end
				wanderModels[userId][wanderId] = nil
			end
			if wanderBeams[userId] and wanderBeams[userId][wanderId] then
				local beam = wanderBeams[userId][wanderId]
				if beam and beam.Parent then
					beam:Destroy()
				end
				wanderBeams[userId][wanderId] = nil
			end
		end
	end
end)

-- Stat upgrade purchase
remotes:WaitForChild("BuyUpgrade").OnServerEvent:Connect(function(player: Player, stat: any)
	local statName = tostring(stat)
	local success, msg = PlayerData.BuyUpgrade(player, statName)
	if success then
		PlayerData.ApplyStats(player)
		pushCollection(player) -- refresh coin display
	end
	remotes:WaitForChild("ShowHint"):FireClient(player, msg)
end)

-- Leaderboard request
remotes:WaitForChild("LeaderboardUpdate").OnServerEvent:Connect(function(player: Player)
	local top = LeaderboardSystem.GetTop(10)
	local myStats = LeaderboardSystem.GetPlayerRank(player)
	remotes:WaitForChild("LeaderboardUpdate"):FireClient(player, {
		Top = top,
		MyWins = myStats.Wins,
	})
end)

-- Apply stats on spawn
Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function()
		task.wait(0.5) -- let character load
		PlayerData.ApplyStats(player)
	end)
end)

-- Cleanup on leave
Players.PlayerRemoving:Connect(function(player: Player)
	WanderSystem.ClearPlayer(player)
	if wanderModels[player.UserId] then
		for _, model in pairs(wanderModels[player.UserId]) do
			if model and model.Parent then model:Destroy() end
		end
		wanderModels[player.UserId] = nil
	end
	if wanderBeams[player.UserId] then
		for _, beam in pairs(wanderBeams[player.UserId]) do
			if beam and beam.Parent then beam:Destroy() end
		end
		wanderBeams[player.UserId] = nil
	end
end)

-- // Weather system ---------------------------------------------------------------
local function applyWeatherVisuals(weather: string)
	local lighting = game:GetService("Lighting")
	if weather == "Rain" then
		lighting.ClockTime = 14
		lighting.Brightness = 1.5
		-- Rain particles handled client-side via WeatherUpdate
	elseif weather == "Storm" then
		lighting.ClockTime = 16
		lighting.Brightness = 1
	elseif weather == "Fog" then
		lighting.FogEnd = 200
		lighting.FogStart = 50
	else -- Clear
		lighting.FogEnd = 100000
		lighting.FogStart = 0
		lighting.Brightness = 2
	end
	-- Notify all clients
	remotes:WaitForChild("WeatherUpdate"):FireAllClients(WeatherSystem.GetInfo())
end

-- Weather tick (check every 30s)
task.spawn(function()
	while true do
		task.wait(30)
		local newWeather = WeatherSystem.Tick()
		if newWeather then
			applyWeatherVisuals(newWeather)
			remotes:WaitForChild("ShowHint"):FireAllClients(
				if newWeather == "Rain" then "🌧️ Rain! Water-types more common!"
				elseif newWeather == "Storm" then "⛈️ Storm! Electric-types more common!"
				elseif newWeather == "Fog" then "🌫️ Fog rolling in... Ghost-types more common!"
				else "☀️ Clear skies!"
			)
		end
	end
end)

-- World beauty pass: plaza, paths, landscaping, ambient life, lighting.
pcall(function()
	WorldDesign.Setup()
end)

-- Day/night cycle: 10-minute full cycle for atmosphere.
task.spawn(function()
	local Lighting = game:GetService("Lighting")
	local cycleMinutes = 10
	while true do
		for minute = 0, cycleMinutes * 60 do
			-- 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset
			local t = (minute / (cycleMinutes * 60)) % 1
			Lighting.ClockTime = t * 24
			-- Adjust ambient for night
			if t < 0.22 or t > 0.78 then
				-- Night: darker, bluer
				Lighting.Ambient = Color3.fromRGB(40, 40, 70)
				Lighting.OutdoorAmbient = Color3.fromRGB(30, 30, 60)
			elseif t < 0.28 or t > 0.72 then
				-- Dawn/dusk: warm
				Lighting.Ambient = Color3.fromRGB(80, 60, 60)
				Lighting.OutdoorAmbient = Color3.fromRGB(90, 70, 70)
			else
				-- Day: bright
				Lighting.Ambient = Color3.fromRGB(90, 90, 90)
				Lighting.OutdoorAmbient = Color3.fromRGB(100, 100, 100)
			end
			task.wait(1)
		end
	end
end)

print("[Brainrot Arena] Server online — milestone 1 prototype.")

-- Admin: chat "/wipebrainrots" to clear your caught brainrots (testing).
game:GetService("Players").PlayerAdded:Connect(function(player: Player)
	player.Chatted:Connect(function(msg: string)
		if msg:lower() == "/wipebrainrots" then
			local data = PlayerData.Get(player)
			if data then
				data.Brainrots = {}
				data.Showcase = {}
				PlayerData.Save(player)
				pushCollection(player)
				PlotSystem.RefreshPlot(player)
				remotes:WaitForChild("ShowHint"):FireClient(player, "Brainrot inventory wiped!")
				print("[Admin] Wiped brainrots for " .. player.Name)
			end
		elseif msg:lower() == "/listmodels" then
			print("[Admin] === Brainrot pack contents ===")
			local rs = game:GetService("ReplicatedStorage")
			for _, root in ipairs({ workspace, rs }) do
				for _, d in ipairs(root:GetDescendants()) do
					if (d:IsA("Folder") or d:IsA("Model"))
						and string.find(string.lower(d.Name), "brainrot", 1, true) then
						print("FOUND: " .. d:GetFullName() .. " (" .. d.ClassName .. ")")
						local n = 0
						for _, k in ipairs(d:GetChildren()) do
							n += 1
							if n <= 200 then
								print("  " .. k.ClassName .. ": " .. k.Name)
							end
						end
						print("  ... total children: " .. n)
					end
				end
			end
			print("[Admin] === End of list ===")
			remotes:WaitForChild("ShowHint"):FireClient(player, "Model list printed to Output (Window -> Output)")
		elseif msg:lower() == "/clearmodels" then
			local rs = game:GetService("ReplicatedStorage")
			local mf = rs:FindFirstChild("BrainrotModels")
			if mf then
				for _, c in ipairs(mf:GetChildren()) do
					c:Destroy()
				end
				print("[Admin] Cleared BrainrotModels.")
				remotes:WaitForChild("ShowHint"):FireClient(player, "BrainrotModels cleared. Re-Play to re-import.")
			end
		end
	end)
end)
