--!strict
--[[
	GameServer (Script -> ServerScriptService)
	Boots the game: creates RemoteEvents, sets up systems, spawns orb
	pickups and the quest board, and wires player join/leave.
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

-- Shiny rate (0-1). 0.004 = about 1 in 250. Lower = rarer. (Applies to everything that
-- rolls BrainrotData.SHINY_CHANCE; if wild catches are still too shiny, WanderSystem has its own roll.)
local SHINY_CHANCE = 0.004
do
	local brainrotDataAny: any = BrainrotData
	local okShiny = pcall(function()
		brainrotDataAny.SHINY_CHANCE = SHINY_CHANCE
	end)
	print("[GameServer] Shiny chance set to " .. tostring(SHINY_CHANCE) .. " (ok: " .. tostring(okShiny) .. ")")
end

-- // RemoteEvents System Cache Engine -------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local REMOTE_LIST = { 
	"QuestUpdate", "CollectionUpdate", "ShowHint", "UpdateShowcase", "AssignWorker", 
	"CollectStation", "WorkUpdate", "OpenFusion", "OpenArena", "FusionResult", 
	"BattleUpdate", "FuseBrainrots", "StartBattle", "SubmitMoves", "ForfeitBattle", 
	"StartExpedition", "ExpeditionUpdate", "ClaimDailyEgg", "DailyUpdate", "BuyEggSlot", 
	"EggUpdate", "CollectPassive", "PassiveUpdate", "UnlockTheme", "BuyDecoration", 
	"CustomizeUpdate", "UnlockZone", "CastLine", "ReelIn", "FishingUpdate", "WildCaught", 
	"BuyUpgrade", "PlaySound", "WeatherUpdate", "AchievementUnlocked", "LeaderboardUpdate", "OpenStats", "SellBrainrots" 
}

local CachedRemotes: { [string]: RemoteEvent } = {}

for _, name in ipairs(REMOTE_LIST) do
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = remotes
	end
	CachedRemotes[name] = r :: RemoteEvent
end

local JanitorConnections: { [string]: RBXScriptConnection } = {}

-- Forward-declare helper functions
local pushCollection: (Player) -> ()
local pushWorkState: (Player) -> ()
local pushDailyState: (Player) -> ()
local pushExpeditionState: (Player) -> ()
local pushEggState: (Player) -> ()

pushCollection = function(player: Player)
	local data = PlayerData.Get(player)
	if data then
		local collectionUpdateEvent = CachedRemotes["CollectionUpdate"]
		if collectionUpdateEvent then
			collectionUpdateEvent:FireClient(player, {
				Brainrots = data.Brainrots,
				Showcase = data.Showcase,
				Coins = data.Coins,
				Working = PlayerData.GetWorkingIds(player),
				Upgrades = data.Upgrades or { Speed = 0, Jump = 0, Reach = 0, Luck = 0 },
			})
		end
	end
end

-- Showcase processing rule validation array limits
local updateShowcaseRemote = CachedRemotes["UpdateShowcase"]
if updateShowcaseRemote then
	updateShowcaseRemote.OnServerEvent:Connect(function(player: Player, instanceIds: any)
		if type(instanceIds) ~= "table" then return end
		if PlayerData.SetShowcase(player, instanceIds) then
			PlotSystem.RefreshPlot(player)
			pushCollection(player)
		else
			warn("[Showcase] SetShowcase rejected the list from " .. player.Name .. " (" .. tostring(#instanceIds) .. " entries)")
			pushCollection(player) -- put the player's screen back in step with the server
		end
	end)
end


-- Puts your newest brainrot on a free pedestal automatically. Also drops showcase
-- entries whose brainrot no longer exists in BrainrotData (they only vanish from the
-- pedestal list; they stay in your inventory), which frees up their slots.
local function autoShowcase(player: Player, skipAdd: boolean?)
	local data = PlayerData.Get(player)
	if not data or not data.Brainrots then return end

	local function defFor(inst: any): any
		if not inst then return nil end
		return BrainrotData.GetById(inst.BrainrotId) or BrainrotData.GetBrainrot(inst.BrainrotId)
	end

	local list: { string } = {}
	local shown: { [string]: boolean } = {}
	for _, id in ipairs(data.Showcase or {}) do
		if defFor(PlayerData.GetInstance(player, id)) then
			table.insert(list, id)
			shown[id] = true
		end
	end

	local working: any = PlayerData.GetWorkingIds(player) or {}
	if not skipAdd and #list < BrainrotData.SHOWCASE_LIMIT then
		for i = #data.Brainrots, 1, -1 do
			local inst = data.Brainrots[i]
			if inst and not shown[inst.InstanceId] and not working[inst.InstanceId] and defFor(inst) then
				table.insert(list, inst.InstanceId)
				break
			end
		end
	end

	PlayerData.SetShowcase(player, list)
end

-- // Selling brainrots ----------------------------------------------------------------
-- Coins you get for selling one brainrot, by rarity (shiny = x5). Keep in step with the
-- SELL_PRICE table at the top of ClientUI (that one is only used to show the price).
local SELL_PRICE: { [string]: number } = {
	Common = 25,
	Rare = 100,
	Epic = 400,
	Legendary = 2000,
}

local sellRemote = CachedRemotes["SellBrainrots"]
if sellRemote then
	sellRemote.OnServerEvent:Connect(function(player: Player, ids: any)
		if type(ids) ~= "table" or #ids == 0 or #ids > 100 then return end
		local data = PlayerData.Get(player)
		if not data then return end
		local hintEvent = CachedRemotes["ShowHint"]

		local working: any = PlayerData.GetWorkingIds(player) or {}
		local seen: { [string]: boolean } = {}
		local toSell: { string } = {}
		local total = 0
		for _, id in ipairs(ids) do
			if type(id) == "string" and not seen[id] then
				seen[id] = true
				local inst = PlayerData.GetInstance(player, id)
				if inst and not working[id] then
					local def = BrainrotData.GetById(inst.BrainrotId) or BrainrotData.GetBrainrot(inst.BrainrotId)
					local price = if def then (SELL_PRICE[def.Rarity] or 10) else 10 -- unknown/old brainrots: 10
					if inst.Shiny then
						price *= 5
					end
					total += price
					table.insert(toSell, id)
				end
			end
		end

		if #toSell == 0 then
			if hintEvent then hintEvent:FireClient(player, "Nothing to sell (brainrots at work can't be sold).") end
			return
		end

		PlayerData.RemoveBrainrotInstances(player, toSell)
		PlayerData.AddCoins(player, total)
		autoShowcase(player, true) -- drops sold ones from the pedestal list without adding others
		pushCollection(player)
		PlotSystem.RefreshPlot(player)
		PlayerData.Save(player)
		if hintEvent then
			hintEvent:FireClient(player, ("Sold %d brainrot%s for %d coins!"):format(#toSell, if #toSell == 1 then "" else "s", total))
		end
	end)
end

-- // Coin display fix -------------------------------------------------------------
-- Modules like the coin obby add coins without telling your screen, so the counter looked
-- stuck. Any coin change now schedules a quick refresh of that player's UI.
local coinsDirty: { [Player]: boolean } = {}
do
	local playerDataAny: any = PlayerData
	local originalAddCoins = playerDataAny.AddCoins
	playerDataAny.AddCoins = function(player: Player, ...)
		local result = originalAddCoins(player, ...)
		coinsDirty[player] = true
		return result
	end
	task.spawn(function()
		while true do
			task.wait(0.3)
			for plr in pairs(coinsDirty) do
				coinsDirty[plr] = nil
				if plr.Parent then
					pushCollection(plr)
				end
			end
		end
	end)
end

-- // Baseball bat (players can hit each other) -------------------------------------------
local BAT_DAMAGE = 14
local BAT_COOLDOWN = 0.7 -- seconds between swings
local BAT_RANGE = 8 -- studs in front of you
local BAT_KNOCKBACK = 60
local BAT_PVP_EVERYWHERE = false -- false = bats only hurt players standing in the Arena

local function inArena(pos: Vector3): boolean
	if BAT_PVP_EVERYWHERE then
		return true
	end
	local arena = workspace:FindFirstChild("Arena", true)
	if not arena or not arena:IsA("Model") then
		return false
	end
	local cf, size = arena:GetBoundingBox()
	local rel = cf:PointToObjectSpace(pos)
	return math.abs(rel.X) <= size.X / 2 + 10 and math.abs(rel.Z) <= size.Z / 2 + 10 and math.abs(rel.Y) <= size.Y / 2 + 40
end

local function makeBat(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Baseball Bat"
	tool.ToolTip = "Click to swing!"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	local baseGrip = CFrame.new(0, -1.4, 0)
	tool.Grip = baseGrip

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.6, 3.6, 0.6)
	handle.Color = Color3.fromRGB(176, 124, 70)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local head = Instance.new("Part")
	head.Name = "BatHead"
	head.Size = Vector3.new(0.95, 1.5, 0.95)
	head.Color = Color3.fromRGB(150, 100, 55)
	head.Material = Enum.Material.Wood
	head.CanCollide = false
	head.Massless = true
	head.CFrame = handle.CFrame * CFrame.new(0, 1.1, 0)
	head.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = head

	local lastSwing = 0
	tool.Activated:Connect(function()
		local char = tool.Parent
		if not char or not char:IsA("Model") then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local rootInst = char:FindFirstChild("HumanoidRootPart")
		local attacker = Players:GetPlayerFromCharacter(char)
		if not hum or hum.Health <= 0 or not rootInst or not attacker then return end
		local now = os.clock()
		if now - lastSwing < BAT_COOLDOWN then return end
		lastSwing = now
		local root = rootInst :: BasePart

		-- swing animation (spin the grip forward and back)
		task.spawn(function()
			for i = 1, 6 do
				tool.Grip = baseGrip * CFrame.Angles(math.rad(-20 * i), 0, 0)
				task.wait(0.02)
			end
			for i = 5, 0, -1 do
				tool.Grip = baseGrip * CFrame.Angles(math.rad(-20 * i), 0, 0)
				task.wait(0.02)
			end
		end)

		local boxCF = root.CFrame * CFrame.new(0, 0, -BAT_RANGE / 2)
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char }
		local parts = workspace:GetPartBoundsInBox(boxCF, Vector3.new(8, 7, BAT_RANGE), params)

		local hitModels: { [Model]: boolean } = {}
		for _, part in ipairs(parts) do
			local model = part:FindFirstAncestorOfClass("Model")
			if model and not hitModels[model] then
				local victim = Players:GetPlayerFromCharacter(model)
				local vHum = model:FindFirstChildOfClass("Humanoid")
				local vRootInst = model:FindFirstChild("HumanoidRootPart")
				if victim and victim ~= attacker and vHum and vRootInst and vHum.Health > 0 then
					hitModels[model] = true
					local vRoot = vRootInst :: BasePart
					if inArena(root.Position) and inArena(vRoot.Position) then
						vHum:TakeDamage(BAT_DAMAGE)
						local flat = (vRoot.Position - root.Position) * Vector3.new(1, 0, 1)
						local dir = if flat.Magnitude > 0 then flat.Unit else root.CFrame.LookVector
						vRoot.AssemblyLinearVelocity = dir * BAT_KNOCKBACK + Vector3.new(0, 30, 0)
						if vHum.Health <= 0 then
							local hintEvent = CachedRemotes["ShowHint"]
							if hintEvent then
								hintEvent:FireClient(attacker, "You knocked out " .. victim.DisplayName .. "!")
							end
						end
					else
						local hintEvent = CachedRemotes["ShowHint"]
						if hintEvent then
							hintEvent:FireClient(attacker, "Bats only work inside the Arena!")
						end
					end
				end
			end
		end
	end)

	return tool
end

local function giveBat(player: Player)
	local function give()
		local backpack = player:FindFirstChildOfClass("Backpack")
		local char = player.Character
		if not backpack then return end
		if backpack:FindFirstChild("Baseball Bat") or (char and char:FindFirstChild("Baseball Bat")) then return end
		makeBat().Parent = backpack
	end
	player.CharacterAdded:Connect(function()
		task.wait(1)
		give()
	end)
	if player.Character then
		task.defer(give)
	end
end
Players.PlayerAdded:Connect(giveBat)
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	giveBat(existingPlayer)
end

-- // Work system ------------------------------------------------------------------
pushWorkState = function(player: Player)
	local view = PlayerData.GetWorkView(player)
	if view then
		local workUpdateEvent = CachedRemotes["WorkUpdate"]
		if workUpdateEvent then
			workUpdateEvent:FireClient(player, view)
		end
	end
end

local assignWorkerRemote = CachedRemotes["AssignWorker"]
if assignWorkerRemote then
	assignWorkerRemote.OnServerEvent:Connect(function(player: Player, instanceId: any, workId: any)
		if type(instanceId) ~= "string" then return end

		if type(workId) == "string" and workId ~= "" then
			PlayerData.AssignJob(player, instanceId, workId)
		else
			PlayerData.UnassignJob(player, instanceId)
		end

		PlotSystem.RefreshPlot(player)
		PlotSystem.RefreshWorkers(player)
		pushWorkState(player)
		pushCollection(player)
		QuestSystem.CheckObjective(player, "workers")
	end)
end

pushDailyState = function(player: Player)
	local status = DailyQuestSystem.GetStatus(player)
	local dailyUpdateEvent = CachedRemotes["DailyUpdate"]
	if dailyUpdateEvent then
		dailyUpdateEvent:FireClient(player, status)
	end
end

local collectStationRemote = CachedRemotes["CollectStation"]
if collectStationRemote then
	collectStationRemote.OnServerEvent:Connect(function(player: Player, workId: any)
		if type(workId) ~= "string" then return end

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
end

-- // Fusion ----------------------------------------------------------------------
local fuseBrainrotsRemote = CachedRemotes["FuseBrainrots"]
if fuseBrainrotsRemote then
	fuseBrainrotsRemote.OnServerEvent:Connect(function(player: Player, instanceIds: any)
		local data = PlayerData.Get(player)
		if not data or type(instanceIds) ~= "table" or #instanceIds ~= 3 then return end

		-- Anti-Duplication Security Array Match Validation Check
		if instanceIds[1] == instanceIds[2] or instanceIds[1] == instanceIds[3] or instanceIds[2] == instanceIds[3] then
			warn("Exploit Blocked: Duplicated unique instance index array passed from player: " .. player.Name)
			return
		end

		local seen: { [string]: boolean } = {}
		local firstId: string? = nil
		for _, id in ipairs(instanceIds) do
			if type(id) ~= "string" or seen[id] then return end
			seen[id] = true

			local inst = PlayerData.GetInstance(player, id)
			if not inst or inst.Shiny then return end
			if data.Jobs[id] then return end

			if not firstId then
				firstId = inst.BrainrotId
			elseif inst.BrainrotId ~= firstId then
				return
			end
		end

		local def = BrainrotData.GetById(firstId :: string) or BrainrotData.GetBrainrot(firstId :: string)
		if not def then return end
		local rarity = def.Rarity

		if rarity == "Legendary" then
			local coinFee = BrainrotData.FUSION_COIN_COST.Legendary or 1000
			if not PlayerData.SpendCoins(player, coinFee) then
				local hintEvent = CachedRemotes["ShowHint"]
				if hintEvent then
					hintEvent:FireClient(player, "Not enough coins! Need " .. tostring(coinFee) .. ".")
				end
				return
			end

			local resultId = BrainrotData.GetRandomIdOfRarity(BrainrotData.RollRewardRarity())
			if not resultId then return end

			-- Instantly fetch character position coordinates prior to operational yielding loops
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local staticPosition = hrp and (hrp :: BasePart).Position or Vector3.new(0, 0, 0)

			PlayerData.RemoveBrainrotInstances(player, instanceIds)
			local instance, err = PlayerData.TryAddBrainrot(player, resultId, true, BrainrotData.RollVariant())

			data.Fusions = (data.Fusions or 0) + 1
			DailyQuestSystem.RecordProgress(player, "fuse", 1)
			pushDailyState(player)
			autoShowcase(player)
			PlotSystem.RefreshPlot(player)

			local fusionResultEvent = CachedRemotes["FusionResult"]
			if fusionResultEvent then
				fusionResultEvent:FireClient(player, {
					Kind = "Fusion",
					BrainrotId = instance and instance.BrainrotId or nil,
					Variant = instance and instance.Variant or nil,
					Shiny = true,
					InventoryFull = err == "full",
					Coins = 0,
				})
			end

			task.spawn(function()
				if instance and staticPosition.Magnitude > 0 then
					local displayDef = BrainrotData.GetBrainrot(instance.BrainrotId)
					if displayDef then
						local resultModel = PlotSystem.BuildDisplayModel(displayDef, true, instance.Variant)
						local fusionPos = staticPosition + Vector3.new(0, 5, 0)
						local dummies = {}
						VisualEffects.PlayFusion(dummies, fusionPos, resultModel, function() end)
					end
				end
			end)
		else
			local resultRarity = BrainrotData.GetFusionResultRarity(rarity)
			local resultId = resultRarity and BrainrotData.GetRandomIdOfRarity(resultRarity) or nil
			if not resultId then return end

			-- Material extraction processing rules calculation loop
			local workId = BrainrotData.GetWorkIdForType(BrainrotData.GetEffectiveType(def, nil))
			local cost = BrainrotData.FUSION_MATERIAL_COST[rarity] or 15
			local coinFee = BrainrotData.FUSION_COIN_COST[rarity] or 100

			if not PlayerData.SpendCoins(player, coinFee) then
				local hintEvent = CachedRemotes["ShowHint"]
				if hintEvent then
					hintEvent:FireClient(player, "Not enough coins! Need " .. tostring(coinFee) .. ".")
				end
				return
			end

			if not workId or not PlayerData.SpendMaterials(player, { [workId] = cost }) then
				-- Safe Transactional Rollback: Refund currency if material balance check fails
				PlayerData.AddCoins(player, coinFee)
				local hintEvent = CachedRemotes["ShowHint"]
				if hintEvent then
					hintEvent:FireClient(player, "Not enough materials for fusion!")
				end
				return
			end

			PlayerData.RemoveBrainrotInstances(player, instanceIds)
			local shiny = math.random() < BrainrotData.SHINY_CHANCE
			local variant = BrainrotData.RollVariant()
			local instance, err = PlayerData.TryAddBrainrot(player, resultId, shiny, variant)

			data.Fusions = (data.Fusions or 0) + 1
			DailyQuestSystem.RecordProgress(player, "fuse", 1)
			pushDailyState(player)
			autoShowcase(player)
			PlotSystem.RefreshPlot(player)

			local fusionResultEvent = CachedRemotes["FusionResult"]
			if fusionResultEvent then
				fusionResultEvent:FireClient(player, {
					Kind = "Fusion",
					BrainrotId = instance and instance.BrainrotId or nil,
					Variant = instance and instance.Variant or nil,
					Shiny = instance and instance.Shiny or false,
					InventoryFull = err == "full",
					Coins = 0,
				})
			end
		end
		pushCollection(player)
		pushWorkState(player)
		QuestSystem.CheckObjective(player, "fusions")
		QuestSystem.CheckObjective(player, "brainrots")
		PlayerData.Save(player)
	end)
end

-- // Battles System Processing Array Engine --------------------------------------
local function battleReward(player: Player, rival: any)
	local data = PlayerData.Get(player)
	if not data then return end

	if rival.RewardCoins then
		PlayerData.AddCoins(player, rival.RewardCoins)
		DailyQuestSystem.RecordProgress(player, "battle_win", 1)
		pushDailyState(player)
	end

	if rival.RewardRarity then
		local grantedId = BrainrotData.GetRandomIdOfRarity(rival.RewardRarity)
		if grantedId then
			local shiny = math.random() < BrainrotData.SHINY_CHANCE
			PlayerData.TryAddBrainrot(player, grantedId, shiny, BrainrotData.RollVariant())
		end
	end

	PlayerData.RecordRivalWin(player, rival.Id)
	autoShowcase(player)
	PlotSystem.RefreshPlot(player)
	pushCollection(player)
	QuestSystem.CheckObjective(player, "rival", rival.Id)
	QuestSystem.CheckObjective(player, "battle", rival.Id)
	QuestSystem.CheckObjective(player, "battles")
	PlayerData.Save(player)
end

local startBattleRemote = CachedRemotes["StartBattle"]
if startBattleRemote then
	startBattleRemote.OnServerEvent:Connect(function(player: Player, rivalId: any, teamIds: any)
		if type(rivalId) ~= "string" or type(teamIds) ~= "table" or #teamIds ~= 3 then return end

		local battle, err = BattleSystem.StartBattle(player, rivalId, teamIds)
		if not battle then
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then
				hintEvent:FireClient(player, "Can't start battle: " .. tostring(err))
			end
			return
		end

		PlotSystem.SpawnBattleModels(player, battle.pTeam, battle.eTeam)
		local battleUpdateEvent = CachedRemotes["BattleUpdate"]
		if battleUpdateEvent then
			battleUpdateEvent:FireClient(player, {
				Phase = "Start",
				Events = battle.openingEvents or {},
				State = BattleSystem.GetClientState(player),
			})
		end
	end)
end

local submitMovesRemote = CachedRemotes["SubmitMoves"]
if submitMovesRemote then
	submitMovesRemote.OnServerEvent:Connect(function(player: Player, moveIndices: any)
		if type(moveIndices) ~= "table" then return end

		local result, err = BattleSystem.SubmitMoves(player, moveIndices)
		if not result then return end

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
			LeaderboardSystem.RecordWin(player)
			SoundSystem.PlayForPlayer(player, "BattleWin")
			task.defer(function()
				local top = LeaderboardSystem.GetTop(10)
				local lines = { "ARENA CHAMPIONS" }
				if #top == 0 then
					table.insert(lines, "Win a battle to take the throne.")
				else
					for i, entry in ipairs(top) do
						table.insert(lines, tostring(i) .. ". " .. tostring(entry.Name) .. "  —  " .. tostring(entry.Wins))
					end
				end
				PlotSystem.SetArenaBoardText(table.concat(lines, "\n"))
			end)

			local newAch = AchievementSystem.RecordProgress(player, "battles_won", 1)
			for _, achId in ipairs(newAch) do
				local def = AchievementSystem.DEFS[achId]
				if def then
					local achEvent = CachedRemotes["AchievementUnlocked"]
					if achEvent then
						achEvent:FireClient(player, { Name = def.Name, Desc = def.Desc })
					end
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

			-- Hardened Context Lock: Hold structural cleanup inside thread timeline loop
			task.delay(4, function()
				PlotSystem.ClearBattleModels(player)
				BattleSystem.ClearBattle(player)
			end)
		elseif result.winner == "enemy" then
			task.delay(4, function()
				PlotSystem.ClearBattleModels(player)
				BattleSystem.ClearBattle(player)
			end)
		end

		local battleUpdateEvent = CachedRemotes["BattleUpdate"]
		if battleUpdateEvent then
			battleUpdateEvent:FireClient(player, payload)
		end
	end)
end

local forfeitBattleRemote = CachedRemotes["ForfeitBattle"]
if forfeitBattleRemote then
	forfeitBattleRemote.OnServerEvent:Connect(function(player: Player)
		local battle = BattleSystem.Forfeit(player)
		if battle then
			local battleUpdateEvent = CachedRemotes["BattleUpdate"]
			if battleUpdateEvent then
				battleUpdateEvent:FireClient(player, {
					Phase = "End",
					State = BattleSystem.GetClientState(player),
				})
			end
			task.delay(2, function()
				PlotSystem.ClearBattleModels(player)
				BattleSystem.ClearBattle(player)
			end)
		end
	end)
end

-- // World setup ----------------------------------------------------------------
PlotSystem.Setup()

if PlotSystem.FusionPrompt then
	PlotSystem.FusionPrompt.Triggered:Connect(function(player: Player)
		local openFusionEvent = CachedRemotes["OpenFusion"]
		if openFusionEvent then
			openFusionEvent:FireClient(player)
		end
	end)
end
if PlotSystem.ArenaPrompt then
	PlotSystem.ArenaPrompt.Triggered:Connect(function(player: Player)
		local openArenaEvent = CachedRemotes["OpenArena"]
		if openArenaEvent then
			openArenaEvent:FireClient(player, {
				Rivals = BrainrotData.RIVALS,
				Beaten = (function()
					local d = PlayerData.Get(player)
					return d and d.RivalsBeaten or {}
				end)(),
			})
		end
	end)
end
if PlotSystem.ArenaBoardPrompt then
	PlotSystem.ArenaBoardPrompt.Triggered:Connect(function(player: Player)
		local top = LeaderboardSystem.GetTop(10)
		local lines = { "ARENA CHAMPIONS" }
		if #top == 0 then
			table.insert(lines, "Win a battle to take the throne.")
		else
			for i, entry in ipairs(top) do
				table.insert(lines, tostring(i) .. ". " .. tostring(entry.Name) .. "  —  " .. tostring(entry.Wins))
			end
		end
		PlotSystem.SetArenaBoardText(table.concat(lines, "\n"))
		local hintEvent = CachedRemotes["ShowHint"]
		if hintEvent then
			hintEvent:FireClient(player, "Champions are listed on this board.")
		end
	end)
end

-- // Quest board setup module ----------------------------------------------------
local board = Instance.new("Part")
board.Name = "QuestBoard"
board.Size = Vector3.new(6, 5, 0.6)
board.Anchored = true
board.Color = Color3.fromRGB(150, 110, 70)
board.Material = Enum.Material.Wood

do
	local targetY = 16
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { workspace.Terrain }

	-- Robust initialization step: Fallback structural looping checks for terrain data sync
	for attempt = 1, 3 do
		local castResult = workspace:Raycast(Vector3.new(127, 500, 60), Vector3.new(0, -1000, 0), raycastParams)
		if castResult then
			targetY = castResult.Position.Y + 3.5
			break
		end
		if not game:IsLoaded() then task.wait(0.1) end
	end
	board.Position = Vector3.new(127, targetY, 60)
end
board.Parent = workspace
print("[GameServer] Quest board placed at " .. tostring(board.Position))

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
prompt.RequiresLineOfSight = false
prompt.Parent = board

prompt.Triggered:Connect(function(player: Player)
	local quest, questId = QuestSystem.GetActiveQuest(player)
	local hintEvent = CachedRemotes["ShowHint"]
	if not hintEvent then return end

	if quest then
		hintEvent:FireClient(player, tostring(quest.Name) .. ": " .. tostring(quest.Description))
	else
		hintEvent:FireClient(player, "No active quests. More adventures coming soon!")
	end
end)

-- // Stat trainer stall (Speed / Jump / Reach / Luck) ----------------
do
	local stall = Instance.new("Model")
	stall.Name = "StatTrainerStall"

	local groundY = 16
	local upParams = RaycastParams.new()
	upParams.FilterType = Enum.RaycastFilterType.Include
	upParams.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(141, 500, 60), Vector3.new(0, -1000, 0), upParams)
	if hit then
		groundY = hit.Position.Y
	end
	local cx, cz = 141, 68

	local function stallPart(name: string, size: Vector3, pos: Vector3, color: Color3, mat: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Position = pos
		p.Anchored = true
		p.Color = color
		p.Material = mat
		p.Parent = stall
		return p
	end

	stallPart("Floor", Vector3.new(10, 0.6, 8), Vector3.new(cx, groundY + 0.3, cz), Color3.fromRGB(90, 70, 45), Enum.Material.WoodPlanks)
	local counter = stallPart("Counter", Vector3.new(8, 1.2, 2.2), Vector3.new(cx, groundY + 1.5, cz + 1.4), Color3.fromRGB(120, 85, 50), Enum.Material.Wood)
	stallPart("Canopy", Vector3.new(10, 0.3, 8), Vector3.new(cx, groundY + 6.4, cz), Color3.fromRGB(180, 40, 40), Enum.Material.Fabric)
	stallPart("PoleL", Vector3.new(0.4, 6, 0.4), Vector3.new(cx - 4.5, groundY + 3.4, cz - 3.4), Color3.fromRGB(80, 60, 40), Enum.Material.Wood)
	stallPart("PoleR", Vector3.new(0.4, 6, 0.4), Vector3.new(cx + 4.5, groundY + 3.4, cz - 3.4), Color3.fromRGB(80, 60, 40), Enum.Material.Wood)
	stallPart("PoleBL", Vector3.new(0.4, 6, 0.4), Vector3.new(cx - 4.5, groundY + 3.4, cz + 3.4), Color3.fromRGB(80, 60, 40), Enum.Material.Wood)
	stallPart("PoleBR", Vector3.new(0.4, 6, 0.4), Vector3.new(cx + 4.5, groundY + 3.4, cz + 3.4), Color3.fromRGB(80, 60, 40), Enum.Material.Wood)

	-- Shopkeep
	local torso = stallPart("Torso", Vector3.new(2, 2.2, 1.1), Vector3.new(cx, groundY + 3.4, cz - 0.6), Color3.fromRGB(35, 70, 150), Enum.Material.Fabric)
	stallPart("Head", Vector3.new(1.5, 1.5, 1.5), Vector3.new(cx, groundY + 5.1, cz - 0.6), Color3.fromRGB(240, 200, 160), Enum.Material.SmoothPlastic)
	stallPart("Hat", Vector3.new(1.7, 0.5, 1.7), Vector3.new(cx, groundY + 5.95, cz - 0.6), Color3.fromRGB(30, 30, 40), Enum.Material.SmoothPlastic)
	stallPart("ArmL", Vector3.new(0.7, 2, 0.7), Vector3.new(cx - 1.4, groundY + 3.3, cz - 0.6), Color3.fromRGB(240, 200, 160), Enum.Material.SmoothPlastic)
	stallPart("ArmR", Vector3.new(0.7, 2, 0.7), Vector3.new(cx + 1.4, groundY + 3.3, cz - 0.6), Color3.fromRGB(240, 200, 160), Enum.Material.SmoothPlastic)

	local sign = stallPart("Sign", Vector3.new(7, 1.8, 0.3), Vector3.new(cx, groundY + 7.5, cz), Color3.fromRGB(40, 30, 20), Enum.Material.Wood)
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.Parent = sign
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.new(1, 0, 1, 0)
	signLabel.BackgroundTransparency = 1
	signLabel.Text = "STAT TRAINER\nSpeed · Jump · Reach · Luck"
	signLabel.TextScaled = true
	signLabel.Font = Enum.Font.GothamBold
	signLabel.TextColor3 = Color3.fromRGB(255, 220, 90)
	signLabel.Parent = signGui

	for i, label in ipairs({ "SPD", "JMP", "RCH", "LCK" }) do
		local bottle = stallPart("Stock" .. i, Vector3.new(0.6, 0.9, 0.6), Vector3.new(cx - 2.4 + (i - 1) * 1.6, groundY + 2.55, cz + 1.4), Color3.fromRGB(255, 190, 70), Enum.Material.Neon)
		bottle.CanCollide = false
	end

	stall.PrimaryPart = counter
	stall.Parent = workspace
	print("[GameServer] Stat trainer stall placed at " .. tostring(counter.Position))

	local upPrompt = Instance.new("ProximityPrompt")
	upPrompt.ActionText = "Shop Upgrades"
	upPrompt.ObjectText = "Stat Trainer"
	upPrompt.HoldDuration = 0
	upPrompt.MaxActivationDistance = 14
	upPrompt.RequiresLineOfSight = false
	upPrompt.Parent = counter

	upPrompt.Triggered:Connect(function(player: Player)
		pushCollection(player)
		local openStats = CachedRemotes["OpenStats"]
		if openStats then
			openStats:FireClient(player)
		end
	end)
end

-- // Expedition board system module ----------------------------------------------
local expBoard = Instance.new("Part")
expBoard.Name = "ExpeditionBoard"
expBoard.Size = Vector3.new(6, 5, 0.6)
expBoard.Anchored = true
expBoard.Color = Color3.fromRGB(60, 120, 60)
expBoard.Material = Enum.Material.Wood

local expButton = Instance.new("Part")
expButton.Name = "ExpeditionButton"
expButton.Size = Vector3.new(1.8, 1.8, 0.6)
expButton.Anchored = true
expButton.Material = Enum.Material.Neon
expButton.Color = Color3.fromRGB(80, 220, 90)

do
	local targetY = 16
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { workspace.Terrain }

	for attempt = 1, 3 do
		local castResult = workspace:Raycast(Vector3.new(135, 500, 60), Vector3.new(0, -1000, 0), raycastParams)
		if castResult then
			targetY = castResult.Position.Y + 3.5
			break
		end
		if not game:IsLoaded() then task.wait(0.1) end
	end
	expBoard.Position = Vector3.new(135, targetY, 60)
	expButton.Position = expBoard.Position + Vector3.new(0, -1.6, 1.1)
end
expBoard.Parent = workspace
expButton.Parent = workspace

local expGui = Instance.new("SurfaceGui")
expGui.Face = Enum.NormalId.Front
expGui.Parent = expBoard

local expLabel = Instance.new("TextLabel")
expLabel.Size = UDim2.new(1, 0, 1, 0)
expLabel.BackgroundTransparency = 1
expLabel.Text = "EXPEDITION BOARD\nPress the green button!"
expLabel.TextScaled = true
expLabel.Font = Enum.Font.GothamBold
expLabel.TextColor3 = Color3.new(1, 1, 1)
expLabel.TextStrokeTransparency = 0.6
expLabel.Parent = expGui

local expPrompt = Instance.new("ProximityPrompt")
expPrompt.ActionText = "Send Expeditions"
expPrompt.ObjectText = "Expedition Board"
expPrompt.HoldDuration = 0
expPrompt.MaxActivationDistance = 14
expPrompt.RequiresLineOfSight = false
expPrompt.Parent = expButton

pushExpeditionState = function(player: Player)
	local status = ExpeditionSystem.GetStatus(player)
	local updateEvent = CachedRemotes["ExpeditionUpdate"]
	if updateEvent then
		updateEvent:FireClient(player, status)
	end
end

local function openExpeditionBoard(player: Player)
	local status = ExpeditionSystem.GetStatus(player)
	if type(status) ~= "table" then
		status = {}
	end
	status.OpenPanel = true
	local updateEvent = CachedRemotes["ExpeditionUpdate"]
	if updateEvent then
		updateEvent:FireClient(player, status)
	end
end

expPrompt.Triggered:Connect(openExpeditionBoard)
local expClick = Instance.new("ClickDetector")
expClick.MaxActivationDistance = 16
expClick.Parent = expButton
expClick.MouseClick:Connect(openExpeditionBoard)

-- // Zone portals creation configuration maps ------------------------------------
local PORTAL_SPACING = 18
local PORTAL_START_X = 100
local PORTAL_Z = 155

-- Portals are spread in a ring around the world instead of one short row.
-- If a spot isn't dry/flat land it tries nearby, and finally falls back to the old row.
local PORTAL_RING_CENTER = Vector3.new(127, 0, 98) -- middle of your plots
local PORTAL_RING_RADIUS = 300 -- studs from the center; raise for a bigger world

local function findPortalSpot(angle: number): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	for _, mult in ipairs({ 1, 0.9, 1.1, 0.8, 1.2, 0.7, 1.3 }) do
		for _, da in ipairs({ 0, 0.08, -0.08, 0.16, -0.16 }) do
			local x = PORTAL_RING_CENTER.X + math.cos(angle + da) * PORTAL_RING_RADIUS * mult
			local z = PORTAL_RING_CENTER.Z + math.sin(angle + da) * PORTAL_RING_RADIUS * mult
			local hit = workspace:Raycast(Vector3.new(x, 1000, z), Vector3.new(0, -2000, 0), params)
			if hit and hit.Material ~= Enum.Material.Water and hit.Normal.Y > 0.85 then
				return Vector3.new(x, hit.Position.Y, z)
			end
		end
	end
	return nil
end

local portalZoneCount = #BrainrotData.ZONE_ORDER

for i, zoneId in ipairs(BrainrotData.ZONE_ORDER) do
	local portal = VisualEffects.BuildZonePortal(zoneId)
	local spot: Vector3? = nil
	if zoneId == "crystal_caves" then
		-- Keep this portal off the arena hill (arena lives west/south of the plots).
		spot = findPortalSpot(0.55)
		if not spot then
			spot = Vector3.new(360, 0, 240)
		end
	else
		spot = findPortalSpot(((i - 1) / math.max(1, portalZoneCount)) * math.pi * 2)
	end
	local x = if spot then spot.X else PORTAL_START_X + (i - 1) * PORTAL_SPACING
	local z = if spot then spot.Z else PORTAL_Z
	print("[GameServer] Portal " .. tostring(zoneId) .. " placed at " .. tostring(Vector3.new(x, 0, z)))

	local targetY = 16
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { workspace.Terrain }

	local castResult = workspace:Raycast(Vector3.new(x, 1000, z), Vector3.new(0, -2000, 0), raycastParams)
	if castResult then targetY = castResult.Position.Y end

	portal:PivotTo(CFrame.new(Vector3.new(x, targetY, z)))
	portal.Parent = workspace

	local zoneDef = BrainrotData.ZONES[zoneId]
	local zoneColor = (zoneDef and zoneDef.Color) or Color3.fromRGB(150, 150, 150)
	local zoneName = (zoneDef and zoneDef.Name) or zoneId

	local trigger = Instance.new("Part")
	trigger.Name = "PortalTrigger"
	trigger.Size = Vector3.new(10, 12, 8)
	trigger.Transparency = 1
	trigger.Anchored = true
	trigger.CanCollide = false
	trigger.CanQuery = false
	trigger.CFrame = portal:GetPivot()
	trigger.Parent = portal

	local lastTouch: { [number]: number } = {}
	local isLockActive = false

	trigger.Touched:Connect(function(hit: BasePart)
		if isLockActive then return end

		local char = hit and hit.Parent
		local p = char and Players:GetPlayerFromCharacter(char)
		if not p then return end

		local now = os.clock()
		if lastTouch[p.UserId] and now - lastTouch[p.UserId] < 3 then return end

		isLockActive = true
		lastTouch[p.UserId] = now

		if ExpeditionSystem.UnlockZone(p, zoneId) then
			pushExpeditionState(p)
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then
				hintEvent:FireClient(p, "✨ Discovered: " .. zoneName .. "! Send brainrots there from 🗺 Explore.")
			end
			VisualEffects.PlayZoneDiscover(trigger.Position + Vector3.new(0, 4, 0), zoneColor)
		end
		isLockActive = false
	end)
end

-- // Shared gold mine placement system setup -------------------------------------
local sharedMine = VisualEffects.BuildGoldMine(1)
do
	local mx, mz = 227, 98
	local my = 16
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { workspace.Terrain }

	local castResult = workspace:Raycast(Vector3.new(mx, 500, mz), Vector3.new(0, -1000, 0), raycastParams)
	if castResult then my = castResult.Position.Y end

	sharedMine:PivotTo(CFrame.new(Vector3.new(mx, my + 1, mz)))
	sharedMine.Parent = workspace
end

local mineCooldown: { [number]: number } = {}
local MINE_COOLDOWN_SECS = 60
local MINE_REWARD = 25

local minePrompt = Instance.new("ProximityPrompt")
minePrompt.ActionText = "Mine Gold"
minePrompt.ObjectText = "Shared Gold Mine"
minePrompt.HoldDuration = 2
minePrompt.MaxActivationDistance = 12
minePrompt.RequiresLineOfSight = false
minePrompt.RequiresLineOfSight = false
minePrompt.Parent = sharedMine.PrimaryPart or sharedMine:FindFirstChildWhichIsA("BasePart")

minePrompt.Triggered:Connect(function(player: Player)
	local now = os.time()
	local last = mineCooldown[player.UserId] or 0
	if now - last < MINE_COOLDOWN_SECS then
		local waitSecs = MINE_COOLDOWN_SECS - (now - last)
		local hintEvent = CachedRemotes["ShowHint"]
		if hintEvent then
			hintEvent:FireClient(player, "Mine is exhausted! Come back in " .. tostring(waitSecs) .. "s.")
		end
		return
	end

	mineCooldown[player.UserId] = now
	local data = PlayerData.Get(player)
	if not data then return end

	PlayerData.AddCoins(player, MINE_REWARD)
	DailyQuestSystem.RecordProgress(player, "coins_earned", MINE_REWARD)
	pushCollection(player)
	PlayerData.Save(player)

	local hintEvent = CachedRemotes["ShowHint"]
	if hintEvent then
		hintEvent:FireClient(player, "+ " .. tostring(MINE_REWARD) .. " coins from the gold mine!")
	end
end)

-- // Fishing docks creation system module ----------------------------------------
local fishingSpots = {}
do
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local function hitAt(x: number, z: number): RaycastResult?
		return workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), params)
	end
	local shores: { any } = {}
	-- Search around the plaza / white pad where the river sits in the pretty map.
	for x = 40, 240, 10 do
		for z = -20, 160, 10 do
			local h = hitAt(x, z)
			if h and h.Material == Enum.Material.Water then
				for _, d in ipairs({ Vector3.new(12, 0, 0), Vector3.new(-12, 0, 0), Vector3.new(0, 0, 12), Vector3.new(0, 0, -12) }) do
					local land = hitAt(x + d.X, z + d.Z)
					if land and land.Material ~= Enum.Material.Water and land.Normal.Y > 0.6 then
						table.insert(shores, {
							X = land.Position.X,
							Z = land.Position.Z,
							Y = land.Position.Y,
							Yaw = math.atan2(-d.X, -d.Z),
							Dist = (x - 127) * (x - 127) + (z - 60) * (z - 60),
						})
					end
				end
			end
		end
	end
	table.sort(shores, function(a, b)
		return a.Dist < b.Dist
	end)
	local chosen: { any } = {}
	for _, s in ipairs(shores) do
		local ok = true
		for _, c in ipairs(chosen) do
			local dx, dz = s.X - c.X, s.Z - c.Z
			if dx * dx + dz * dz < 22 * 22 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(chosen, s)
		end
		if #chosen >= 2 then
			break
		end
	end
	if #chosen == 0 then
		chosen = {
			{ X = 110, Z = 48, Y = 14, Yaw = 0 },
			{ X = 118, Z = 40, Y = 14, Yaw = math.pi / 2 },
		}
	end
	local names = { "Riverside Dock", "Lakeside Pier" }
	for i, s in ipairs(chosen) do
		local dock = VisualEffects.BuildFishingSpot()
		dock:PivotTo(CFrame.new(s.X, s.Y, s.Z) * CFrame.Angles(0, s.Yaw or 0, 0))
		dock.Parent = workspace
		table.insert(fishingSpots, { Id = "dock" .. i, Model = dock, Name = names[i] or ("Dock " .. i) })
		print("[GameServer] Fishing dock " .. tostring(i) .. " at " .. tostring(Vector3.new(s.X, s.Y, s.Z)))
	end
end

-- // Fishing System Core Logic Pipeline -------------------------------------------
local function pushFishingState(player: Player, state: string, reward: any?)
	local fishingUpdateEvent = CachedRemotes["FishingUpdate"]
	if fishingUpdateEvent then
		fishingUpdateEvent:FireClient(player, {
			State = state,
			Reward = reward,
		})
	end
end

local playerFishingGear: { [number]: any } = {}

local castLineRemote = CachedRemotes["CastLine"]
if castLineRemote then
	castLineRemote.OnServerEvent:Connect(function(player: Player, spotId: any)
		if type(spotId) ~= "string" then return end

		local biteDelay = FishingSystem.Cast(player, spotId)
		if biteDelay then
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
end

local reelInRemote = CachedRemotes["ReelIn"]
if reelInRemote then
	reelInRemote.OnServerEvent:Connect(function(player: Player, quality: any)
		-- Hardened Anti-Cheat State Check: Extract and clear registration instantly
		local gear = playerFishingGear[player.UserId]
		playerFishingGear[player.UserId] = nil

		local q = tonumber(quality) or 0.5
		local reward = FishingSystem.Reel(player, q)

		if gear and gear.Bobber and gear.Bobber.Parent then
			local bobberPos = gear.Bobber.Position
			if reward and reward.Kind ~= "Miss" then
				VisualEffects.PlayCatch(bobberPos, reward.Kind)
				if reward.Kind == "Fish" or reward.Kind == "Brainrot" then
					local fish = VisualEffects.BuildFish(reward.Kind == "Brainrot")
					fish:PivotTo(CFrame.new(bobberPos + Vector3.new(0, 1, 0)))
					fish.Parent = workspace

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

		if reward then
			pushFishingState(player, "None", reward)
			pushCollection(player)
			if reward.Kind == "Brainrot" then
				autoShowcase(player)
				PlotSystem.RefreshPlot(player)
				pushCollection(player)
			end
		end
	end)
end

JanitorConnections.PlayerRemovingFishing = Players.PlayerRemoving:Connect(function(player: Player)
	FishingSystem.Cancel(player)
	local gear = playerFishingGear[player.UserId]
	if gear then
		if gear.Bobber and gear.Bobber.Parent then gear.Bobber:Destroy() end
		if gear.Rod and gear.Rod.Parent then gear.Rod:Destroy() end
	end
	playerFishingGear[player.UserId] = nil
end)

-- // Expeditions system module ---------------------------------------------------
local startExpeditionRemote = CachedRemotes["StartExpedition"]
if startExpeditionRemote then
	startExpeditionRemote.OnServerEvent:Connect(function(player: Player, zoneId: any, teamIds: any)
		if type(zoneId) ~= "string" or type(teamIds) ~= "table" then return end

		-- Verification for duplicate expedition data payloads
		local seenIds: { [string]: boolean } = {}
		for _, id in ipairs(teamIds) do
			if type(id) ~= "string" or seenIds[id] then return end
			seenIds[id] = true
		end

		local ok, msg = ExpeditionSystem.StartExpedition(player, zoneId, teamIds)
		if ok then
			pushExpeditionState(player)
			pushCollection(player)
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
						VisualEffects.PlayDeparture(models, Vector3.new(1, 0, 0.3))
					end
				end
			end)
		else
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then
				hintEvent:FireClient(player, msg or "Could not start expedition")
			end
		end
	end)
end

local unlockZoneRemote = CachedRemotes["UnlockZone"]
if unlockZoneRemote then
	unlockZoneRemote.OnServerEvent:Connect(function(player: Player, zoneId: any)
		if type(zoneId) ~= "string" then return end
		if ExpeditionSystem.UnlockZone(player, zoneId) then
			pushExpeditionState(player)
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then
				local nameString = BrainrotData.ZONES[zoneId] and BrainrotData.ZONES[zoneId].Name or zoneId
				hintEvent:FireClient(player, "Discovered: " .. tostring(nameString))
			end
		end
	end)
end

-- // Daily Quests & Eggs -----------------------------------------------------------
pushEggState = function(player: Player)
	local status = EggSystem.GetStatus(player)
	local eggUpdateEvent = CachedRemotes["EggUpdate"]
	if eggUpdateEvent then
		eggUpdateEvent:FireClient(player, status)
	end
end

local claimDailyEggRemote = CachedRemotes["ClaimDailyEgg"]
if claimDailyEggRemote then
	claimDailyEggRemote.OnServerEvent:Connect(function(player: Player, tier: any)
		if type(tier) ~= "string" then return end
		local ok, msg = DailyQuestSystem.ClaimEgg(player, tier)
		if ok then
			pushDailyState(player)
			pushEggState(player)
			PlotSystem.RefreshEggs(player)
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then
				hintEvent:FireClient(player, "Mystery egg added to incubator!")
			end
		else
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then
				hintEvent:FireClient(player, msg or "Could not claim egg")
			end
		end
	end)
end

local buyEggSlotRemote = CachedRemotes["BuyEggSlot"]
if buyEggSlotRemote then
	buyEggSlotRemote.OnServerEvent:Connect(function(player: Player)
		local ok, msg = EggSystem.BuySlot(player)
		if ok then
			pushEggState(player)
			pushCollection(player)
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then hintEvent:FireClient(player, "Incubator slot added!") end
		else
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then hintEvent:FireClient(player, msg or "Could not buy slot") end
		end
	end)
end

-- // Passive Income ------------------------------------------------------------------
-- Brainrots on your pedestals earn gold for you. Coins per MINUTE per brainrot, by rarity
-- (shiny doubles it). Edit these numbers to tune the economy.
local BRAINROT_GOLD_PER_MIN: { [string]: number } = {
	Common = 2,
	Rare = 5,
	Epic = 12,
	Legendary = 40,
}

local function brainrotGoldPerMin(player: Player, data: any): number
	local total = 0
	for _, id in ipairs(data.Showcase or {}) do
		local inst = PlayerData.GetInstance(player, id)
		local def = inst and (BrainrotData.GetById(inst.BrainrotId) or BrainrotData.GetBrainrot(inst.BrainrotId))
		if def then
			local rate = BRAINROT_GOLD_PER_MIN[def.Rarity] or 1
			if inst.Shiny then
				rate *= 2
			end
			total += rate
		end
	end
	return total
end

local collectPassiveRemote = CachedRemotes["CollectPassive"]
if collectPassiveRemote then
	collectPassiveRemote.OnServerEvent:Connect(function(player: Player)
		local amount = PlayerData.CollectPassive(player)
		if amount > 0 then
			pushCollection(player)
			local passiveUpdateEvent = CachedRemotes["PassiveUpdate"]
			local hintEvent = CachedRemotes["ShowHint"]

			if passiveUpdateEvent then passiveUpdateEvent:FireClient(player, { Banked = 0, Collected = amount }) end
			if hintEvent then hintEvent:FireClient(player, "+" .. tostring(amount) .. " coins from gold mine!") end

			DailyQuestSystem.RecordProgress(player, "coins_earned", amount)
		end
	end)
end

-- // Customization ------------------------------------------------------------------
local function pushCustomizeState(player: Player)
	local data = PlayerData.Get(player)
	if not data then return end
	local customizeUpdateEvent = CachedRemotes["CustomizeUpdate"]
	if customizeUpdateEvent then
		customizeUpdateEvent:FireClient(player, {
			Theme = data.PlotTheme,
			UnlockedThemes = data.UnlockedThemes,
			Decorations = data.Decorations,
			GoldMineLevel = data.GoldMineLevel,
		})
	end
end

local unlockThemeRemote = CachedRemotes["UnlockTheme"]
if unlockThemeRemote then
	unlockThemeRemote.OnServerEvent:Connect(function(player: Player, themeId: any)
		if type(themeId) ~= "string" then return end
		local ok, msg = PlayerData.UnlockTheme(player, themeId)
		if ok then
			pushCustomizeState(player)
			pushCollection(player)
			PlotSystem.RefreshPlot(player)
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then hintEvent:FireClient(player, "Plot theme unlocked!") end
		else
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then hintEvent:FireClient(player, msg or "Could not unlock theme") end
		end
	end)
end

local buyDecorationRemote = CachedRemotes["BuyDecoration"]
if buyDecorationRemote then
	buyDecorationRemote.OnServerEvent:Connect(function(player: Player, decoId: any)
		if type(decoId) ~= "string" then return end
		local ok, msg = PlayerData.BuyDecoration(player, decoId)
		if ok then
			pushCustomizeState(player)
			pushCollection(player)
			PlotSystem.RefreshPlot(player)
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then hintEvent:FireClient(player, "Decoration placed!") end
		else
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then hintEvent:FireClient(player, msg or "Could not buy decoration") end
		end
	end)
end

local function sendInitialState(player: Player)
	local data = PlayerData.Get(player)
	if not data then return end

	local quest, questId = QuestSystem.GetActiveQuest(player)
	if quest then
		local questUpdateEvent = CachedRemotes["QuestUpdate"]
		if questUpdateEvent then
			questUpdateEvent:FireClient(player, {
				Type = "Progress",
				QuestId = questId,
				Name = quest.Name,
				Progress = data.QuestProgress,
				Goal = quest.Goal,
			})
		end
	end

	local collectionUpdateEvent = CachedRemotes["CollectionUpdate"]
	if collectionUpdateEvent then
		collectionUpdateEvent:FireClient(player, {
			Brainrots = data.Brainrots,
			Showcase = data.Showcase,
			Coins = data.Coins,
			Working = PlayerData.GetWorkingIds(player),
		})
	end
end

local function onPlayerAdded(player: Player)
	PlayerData.Load(player)
	PlayerData.ResetStationClocks(player)
	PlotSystem.AssignPlot(player)
	PlotSystem.RefreshPlot(player)
	PlotSystem.RefreshWorkers(player)

	player.CharacterAdded:Connect(function()
		task.wait(0.3)
		-- Safety Thread-Verification Check: Prevent disconnected memory execution
		if not player or not player.Parent then return end
		PlotSystem.TeleportToPlot(player)
	end)

	if player.Character then
		task.defer(function()
			if player and player.Parent then PlotSystem.TeleportToPlot(player) end
		end)
	end

	task.defer(function()
		if not player or not player.Parent then return end
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

JanitorConnections.PlayerJoinServerEvent = Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

JanitorConnections.PlayerLeaveServerEvent = Players.PlayerRemoving:Connect(function(player: Player)
	BattleSystem.ClearBattle(player)
	PlayerData.Release(player)
	PlotSystem.ReleasePlot(player)
end)

game:BindToClose(function()
	for _, p in ipairs(Players:GetPlayers()) do
		PlayerData.Save(p)
	end
end)

-- // Production Cycle Optimization Routine Loop ----------------------------------
task.spawn(function()
	while true do
		task.wait(30)
		for _, p in ipairs(Players:GetPlayers()) do
			-- Distribute intensive server calculations uniformly into concurrent microthreads
			task.spawn(function()
				local data = PlayerData.Get(p)
				if not data or not p.Parent then return end

				if next(data.Jobs) ~= nil then
					pushWorkState(p)
				end

				local results = ExpeditionSystem.TickExpeditions(p)
				if #results > 0 then
					pushExpeditionState(p)
					pushCollection(p)
					for _, r in ipairs(results) do
						local hintEvent = CachedRemotes["ShowHint"]
						if hintEvent then
							hintEvent:FireClient(p, "Expedition complete! Materials scattered on your plot!")
						end
						DailyQuestSystem.RecordProgress(p, "expedition_complete", 1)
						PlotSystem.SpawnMaterialPickups(p, r.Materials)
					end
					pushDailyState(p)
				elseif next(data.Expeditions) ~= nil then
					pushExpeditionState(p)
				end

				local hatched = EggSystem.TickIncubation(p, 0.5)
				if #hatched > 0 then
					pushEggState(p)
					pushCollection(p)
					PlotSystem.RefreshEggs(p)
					for _, h in ipairs(hatched) do
						local hintEvent = CachedRemotes["ShowHint"]
						if hintEvent then
							hintEvent:FireClient(p, "Egg hatched: " .. h.BrainrotName .. " (" .. h.Rarity .. ")!")
						end
					end
					pushDailyState(p)
				elseif next(data.Eggs) ~= nil then
					pushEggState(p)
				end

				local gained = PlayerData.TickPassiveIncome(p)

				-- Brainrot income. This loop runs every 30 seconds (half a minute).
				local perMin = brainrotGoldPerMin(p, data)
				local brainrotGold = perMin * 0.5
				if brainrotGold > 0 then
					local banked = data.PassiveBanked or 0
					-- Bank holds up to 2 hours of brainrot income (never shrinks what's already banked).
					data.PassiveBanked = math.max(banked, math.min(banked + brainrotGold, perMin * 120))
					gained += brainrotGold
				end

				if gained > 0 then
					local passiveUpdateEvent = CachedRemotes["PassiveUpdate"]
					if passiveUpdateEvent then
						passiveUpdateEvent:FireClient(p, {
							Banked = math.floor(data.PassiveBanked or 0),
							BrainrotRate = perMin,
						})
					end
				end
			end)
		end
	end
end)

-- // Wandering Brainrots System Module ------------------------------------------------
local wanderModels: { [number]: { [string]: Model } } = {}
local wanderBeams: { [number]: { [string]: Model } } = {}

-- How far from the player a wild brainrot can appear, by rarity: { min studs, max studs }.
-- Raise these numbers for a bigger world, lower them for a smaller one.
local WILD_SPAWN_RADIUS: { [string]: { number } } = {
	Common = { 60, 220 },
	Rare = { 120, 380 },
	Epic = { 180, 550 },
	Legendary = { 300, 850 },
}

-- Picks a random dry, fairly flat spot on the terrain around the player.
-- Falls back to the position WanderSystem chose if nothing suitable is found.
local function findWildSpawn(player: Player, rarity: string, fallback: Vector3): Vector3
	local range = WILD_SPAWN_RADIUS[rarity] or WILD_SPAWN_RADIUS.Common
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local center = if hrp then (hrp :: BasePart).Position else fallback
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	for _ = 1, 20 do
		local angle = math.random() * math.pi * 2
		local dist = range[1] + math.random() * (range[2] - range[1])
		local x = center.X + math.cos(angle) * dist
		local z = center.Z + math.sin(angle) * dist
		local hit = workspace:Raycast(Vector3.new(x, 1000, z), Vector3.new(0, -2000, 0), params)
		if hit and hit.Material ~= Enum.Material.Water and hit.Normal.Y > 0.75 then
			return Vector3.new(x, hit.Position.Y, z)
		end
	end
	return fallback
end

-- Finds solid ground under (x, z). Ignores the creature itself, characters, other
-- wild creatures, beams, and anything with CanCollide off (decor, effects).
local function wildGroundY(x: number, z: number, ignore: Instance): number?
	local exclude: { Instance } = { ignore }
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(exclude, plr.Character) end
	end
	for _, byId in pairs(wanderModels) do
		for _, m in pairs(byId) do table.insert(exclude, m) end
	end
	for _, byId in pairs(wanderBeams) do
		for _, b in pairs(byId) do table.insert(exclude, b) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	local hit = workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -600, 0), params)
	return hit and hit.Position.Y or nil
end

local function spawnWildVisual(player: Player, wanderId: string)
	local wander = WanderSystem.GetWanderer(player, wanderId)
	if not wander then return end
	local def = BrainrotData.GetBrainrot(wander.BrainrotId)
	if not def then return end

	local model = PlotSystem.BuildDisplayModel(def, false, nil)

	local function measureWild()
		local ok, cf, sz = pcall(function() return model:GetBoundingBox() end)
		if ok and sz then
			return cf, sz
		end
		return nil, nil
	end

	local function manualWildScale(s: number)
		local bbCF = measureWild()
		if not bbCF then return end
		local center = (bbCF :: CFrame).Position

		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local part = d :: BasePart
				local rel: Vector3 = part.Position - center
				pcall(function()
					part.Size = part.Size * s
					part.CFrame = CFrame.new(center + rel * s) * (part.CFrame - part.CFrame.Position)
				end)

				for _, m in ipairs(part:GetChildren()) do
					if m:IsA("SpecialMesh") then
						pcall(function() (m :: SpecialMesh).Scale = (m :: SpecialMesh).Scale * s end)
					elseif m:IsA("DataModelMesh") then
						pcall(function() (m :: DataModelMesh).Scale = (m :: DataModelMesh).Scale * s end)
					end
				end
			end
		end
	end

	-- Native scaling loop optimization matrix
	for _ = 1, 3 do
		local _, bbSize = measureWild()
		if not bbSize then break end

		local maxDim = math.max(bbSize.X, bbSize.Y, bbSize.Z)
		if maxDim <= 0 then break end

		local s = 4.0 / maxDim
		if math.abs(s - 1) <= 0.15 then break end
		s = math.clamp(s, 0.04, 1)

		pcall(function() model:ScaleTo(s) end)
		local _, afterSize = measureWild()
		local afterMax = afterSize and math.max(afterSize.X, afterSize.Y, afterSize.Z) or maxDim

		if math.abs(afterMax - maxDim) < (maxDim * 0.05) then
			manualWildScale(s)
		end
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			d:Destroy()
		end
	end
	VisualEffects.AddWildAura(model, wander.Rarity, BrainrotData.GetDisplayName(def, nil, false))
	PlotSystem.UprightModel(model)

	-- How far the model's pivot sits above its lowest point, so feet land on the ground
	local bottomOffset = 2
	do
		local okBB, bbCF, bbSize = pcall(function() return model:GetBoundingBox() end)
		if okBB and bbCF and bbSize then
			bottomOffset = model:GetPivot().Position.Y - ((bbCF :: CFrame).Position.Y - (bbSize :: Vector3).Y / 2)
		end
	end

	local spawnPos = findWildSpawn(player, wander.Rarity, wander.SpawnPos)
	local spawnGround = wildGroundY(spawnPos.X, spawnPos.Z, model)
	spawnPos = Vector3.new(spawnPos.X, (spawnGround or 60) + bottomOffset + 0.2, spawnPos.Z)

	local currentPivot = model:GetPivot()
	model:PivotTo(currentPivot + (spawnPos - currentPivot.Position))
	model:SetAttribute("WildOwner", player.UserId) -- other players' screens hide it (see ClientUI)
	model.Parent = workspace
	PlotSystem.FitInWorld(model, 4)
	do
		local okBB, bbCF, bbSize = pcall(function()
			return model:GetBoundingBox()
		end)
		if okBB and bbCF and bbSize then
			bottomOffset = model:GetPivot().Position.Y - ((bbCF :: CFrame).Position.Y - (bbSize :: Vector3).Y / 2)
		end
		local spawnGround2 = wildGroundY(spawnPos.X, spawnPos.Z, model)
		local grounded = Vector3.new(spawnPos.X, (spawnGround2 or 60) + bottomOffset + 0.2, spawnPos.Z)
		model:PivotTo(model:GetPivot() + (grounded - model:GetPivot().Position))
	end

	local reachTier = PlayerData.GetUpgradeTier(player, "Reach")
	local hitboxSize = 6
	if reachTier > 0 then
		local reachUpgradeDef = PlayerData.UPGRADE_DEFS.Reach
		if reachUpgradeDef then
			hitboxSize = reachUpgradeDef.Values[reachTier] or 6
		end
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

	-- Hardened Thread Verification & Debounce Protection Lock
	local touchConnection: RBXScriptConnection?
	local isCatchRunning = false

	local function attemptCatch(p: Player)
		if isCatchRunning then return end
		if p.UserId == player.UserId then
			isCatchRunning = true

			if touchConnection then
				touchConnection:Disconnect()
				touchConnection = nil
			end

			local result = WanderSystem.Catch(p, wanderId)
			print("[Wild] catch attempt " .. tostring(wanderId) .. " -> success: " .. tostring(result and result.Success)
				.. ", reason: " .. tostring(result and (result.Reason or result.Error or result.Message)))
			if not (result and result.Success) then
				-- Don't delete the creature when a catch fails; tell the player and let them retry.
				local failHint = CachedRemotes["ShowHint"]
				if failHint then
					failHint:FireClient(p, "Couldn't catch that one - " .. tostring(result and (result.Reason or result.Error or result.Message) or "try again") .. "!")
				end
				task.delay(4, function()
					isCatchRunning = false
				end)
				return
			end
			if result and result.Success then
				VisualEffects.PlayWildCatch(spawnPos, wander.Rarity)
				SoundSystem.PlayForPlayer(p, "Catch" .. wander.Rarity)

				local newAch = AchievementSystem.RecordProgress(p, "wild_caught", 1)
				if wander.Rarity == "Rare" then
					for _, id in ipairs(AchievementSystem.RecordProgress(p, "rare_caught", 1)) do table.insert(newAch, id) end
				elseif wander.Rarity == "Epic" then
					for _, id in ipairs(AchievementSystem.RecordProgress(p, "epic_caught", 1)) do table.insert(newAch, id) end
				elseif wander.Rarity == "Legendary" then
					for _, id in ipairs(AchievementSystem.RecordProgress(p, "legendary_caught", 1)) do table.insert(newAch, id) end
				end

				if result.Shiny then
					for _, id in ipairs(AchievementSystem.RecordProgress(p, "shinies", 1)) do table.insert(newAch, id) end
				end

				for _, achId in ipairs(newAch) do
					local achievementDef = AchievementSystem.DEFS[achId]
					if achievementDef then
						local achUnlockedEvent = CachedRemotes["AchievementUnlocked"]
						if achUnlockedEvent then
							achUnlockedEvent:FireClient(p, { Name = achievementDef.Name, Desc = achievementDef.Desc })
						end
						SoundSystem.PlayForPlayer(p, "Achievement")
					end
				end

				local wildCaughtEvent = CachedRemotes["WildCaught"]
				if wildCaughtEvent then wildCaughtEvent:FireClient(p, result) end

				local hintEvent = CachedRemotes["ShowHint"]
				if hintEvent then
					local shinyText = if result.Shiny then " ✨ SHINY!" else ""
					hintEvent:FireClient(p, "Caught: " .. result.BrainrotName .. " (" .. result.Rarity .. ")!" .. shinyText)
				end

				autoShowcase(p)
				pushCollection(p)
				PlotSystem.RefreshPlot(p)
				QuestSystem.CheckObjective(p, "brainrots")
			end

			if wanderModels[player.UserId] then
				wanderModels[player.UserId][wanderId] = nil
			end
			if model and model.Parent then
				model:Destroy()
			end
			if wanderBeams[player.UserId] and wanderBeams[player.UserId][wanderId] then
				local beam = wanderBeams[player.UserId][wanderId]
				if beam and beam.Parent then beam:Destroy() end
				wanderBeams[player.UserId][wanderId] = nil
			end
		end
	end

	touchConnection = hitbox.Touched:Connect(function(hit: BasePart)
		if isCatchRunning then return end
		local char = hit and hit.Parent
		local p = char and Players:GetPlayerFromCharacter(char)
		if p then
			attemptCatch(p)
		end
	end)

	if not wanderModels[player.UserId] then wanderModels[player.UserId] = {} end
	wanderModels[player.UserId][wanderId] = model
	wander.Model = model

	if wander.Rarity == "Legendary" then
		local beam = VisualEffects.BuildLegendaryBeam(spawnPos)
		beam:SetAttribute("WildOwner", player.UserId)
		beam.Parent = workspace
		if not wanderBeams[player.UserId] then wanderBeams[player.UserId] = {} end
		wanderBeams[player.UserId][wanderId] = beam

		local hintEvent = CachedRemotes["ShowHint"]
		if hintEvent then
			hintEvent:FireClient(player, "🌟 LEGENDARY BRAINROT SPOTTED! Follow the golden beam! (3 min)")
		end
	end

	if wander.Rarity == "Rare" or wander.Rarity == "Epic" then
		local hintEvent = CachedRemotes["ShowHint"]
		local pc = player.Character
		local phrp = pc and pc:FindFirstChild("HumanoidRootPart")
		if hintEvent and phrp then
			local far = math.floor(((phrp :: BasePart).Position - spawnPos).Magnitude / 10 + 0.5) * 10
			hintEvent:FireClient(player, "A wild " .. wander.Rarity .. " brainrot appeared about " .. tostring(far) .. " studs away!")
		end
	end

	task.spawn(function()
		local cfg = wander.Config
		local currentPos = spawnPos
		local targetPos = currentPos
		local fleeing = false
		local fleeTime = 0
		local tiredTime = 0
		while model and model.Parent do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local playerPos = hrp and (hrp :: BasePart).Position
			if playerPos then
				-- Distance check as well as Touched: Touched is unreliable against a moving,
				-- fleeing creature, which is why running right over a Legendary did nothing.
				local flat = Vector3.new(playerPos.X - currentPos.X, 0, playerPos.Z - currentPos.Z).Magnitude
				if flat <= hitboxSize / 2 + 5 and math.abs(playerPos.Y - currentPos.Y) < 12 then
					attemptCatch(player)
					break
				end
			end
			if tiredTime > 0 then
				tiredTime -= 0.2
				fleeing = false
			elseif playerPos and cfg.FleeRadius > 0 then
				local dist = (currentPos - playerPos).Magnitude
				if dist < cfg.FleeRadius then
					local fleeDir = (currentPos - playerPos).Unit
					targetPos = currentPos + fleeDir * 20
					fleeing = true
					fleeTime += 0.2
					if fleeTime > 3.5 then
						-- worn out: stops running for a few seconds so it can be caught
						tiredTime = 3
						fleeTime = 0
						fleeing = false
					end
				else
					fleeing = false
					fleeTime = math.max(0, fleeTime - 0.2)
				end
			end

			if (currentPos - targetPos).Magnitude < 3 or math.random() < 0.2 then
				if not fleeing then
					targetPos = currentPos + Vector3.new(
						(math.random() - 0.5) * 40,
						0,
						(math.random() - 0.5) * 40
					)
				end
			end

			local dir = (targetPos - currentPos)
			dir = Vector3.new(dir.X, 0, dir.Z)

			if dir.Magnitude > 0.5 then
				dir = dir.Unit
				local speed = if fleeing then math.min(cfg.WalkSpeed * 1.5, 13) elseif tiredTime > 0 then cfg.WalkSpeed * 0.5 else cfg.WalkSpeed
				currentPos += dir * speed * 0.2
				-- Re-snap to the ground every step so slopes don't swallow the creature
				local gy = wildGroundY(currentPos.X, currentPos.Z, model)
				if gy then
					currentPos = Vector3.new(currentPos.X, gy + bottomOffset + 0.2, currentPos.Z)
				end

				local bobY = math.abs(math.sin(os.clock() * 8)) * 0.4
				local cf = CFrame.new(currentPos + Vector3.new(0, bobY, 0), currentPos + dir * 5)

				-- Robust Lifecycle Guard: Instantly exit thread memory space if asset was removed
				if not model or not model.Parent then break end
				model:PivotTo(cf)

				-- Safe verification layout context lookup
				local dynamicHitbox = model:FindFirstChild("WildHitbox")
				if dynamicHitbox and dynamicHitbox:IsA("BasePart") then
					dynamicHitbox.Position = currentPos + Vector3.new(0, 1, 0)
				end
			end
			task.wait(0.2)
		end
	end)
end

-- // Automated Respawn Configuration Processing Loop -----------------------------
local lastSpawn: { [number]: { [string]: number } } = {}
task.spawn(function()
	while true do
		task.wait(15)
		local now = os.time()

		for _, player in ipairs(Players:GetPlayers()) do
			-- Isolate player execution logic pipelines to prevent serial server thread stalling
			task.spawn(function()
				local userId = player.UserId
				if not player.Parent then return end

				if not lastSpawn[userId] then
					lastSpawn[userId] = {}
				end

				for _, rarity in ipairs({ "Common", "Rare", "Epic", "Legendary" }) do
					local cfg = WanderSystem.GetRarityConfig(rarity)
					if cfg then
						local last = lastSpawn[userId][rarity] or 0
						local interval = math.random(cfg.RespawnSecs[1], cfg.RespawnSecs[2])

						if now - last >= interval then
							local roll = math.random() * 100
							local totalWeight = 60 + 25 + 12 + 3
							local weight = cfg.Weight / totalWeight * 100
							local overdue = (now - last) / interval

							if roll < weight * overdue then
								local luckTier = PlayerData.GetUpgradeTier(player, 'Luck')
								local luckMult = 1
								if luckTier > 0 then
									local luckUpgradeDef = PlayerData.UPGRADE_DEFS.Luck
									if luckUpgradeDef then
										luckMult = luckUpgradeDef.Values[luckTier] or 1
									end
								end

								for attempt = 1, 5 do
									if not player.Parent then break end
									local wanderId = WanderSystem.SpawnWild(player, PlotSystem, luckMult)
									if wanderId then
										local wander = WanderSystem.GetWanderer(player, wanderId)
										if wander and wander.Rarity == rarity then
											spawnWildVisual(player, wanderId)
											lastSpawn[userId][rarity] = now
											break
										else
											WanderSystem.Remove(player, wanderId)
										end
									else
										break
									end
								end
							end
						end
					end
				end
			end)
		end

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

local buyUpgradeRemote = CachedRemotes["BuyUpgrade"]
if buyUpgradeRemote then
	buyUpgradeRemote.OnServerEvent:Connect(function(player: Player, stat: any)
		local statName = tostring(stat)
		local success, msg = PlayerData.BuyUpgrade(player, statName)
		if success then
			PlayerData.ApplyStats(player)
			pushCollection(player)
		end
		local hintEvent = CachedRemotes["ShowHint"]
		if hintEvent then hintEvent:FireClient(player, msg) end
	end)
end

local leaderboardUpdateRemote = CachedRemotes["LeaderboardUpdate"]
if leaderboardUpdateRemote then
	leaderboardUpdateRemote.OnServerEvent:Connect(function(player: Player)
		local top = LeaderboardSystem.GetTop(10)
		local myStats = LeaderboardSystem.GetPlayerRank(player)
		leaderboardUpdateRemote:FireClient(player, {
			Top = top,
			MyWins = myStats and myStats.Wins or 0,
		})
	end)
end

local function setupStatsOnSpawn(player: Player)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		if player and player.Parent then
			PlayerData.ApplyStats(player)
		end
	end)
	if player.Character then
		task.defer(function()
			if player and player.Parent then
				PlayerData.ApplyStats(player)
			end
		end)
	end
end

JanitorConnections.PlayerJoinStatsSetup = Players.PlayerAdded:Connect(setupStatsOnSpawn)
for _, existing in ipairs(Players:GetPlayers()) do
	setupStatsOnSpawn(existing)
end

JanitorConnections.PlayerLeaveWanderCleanup = Players.PlayerRemoving:Connect(function(player: Player)
	WanderSystem.ClearPlayer(player)
	local userId = player.UserId

	if wanderModels[userId] then
		for _, model in pairs(wanderModels[userId]) do
			if model and model.Parent then model:Destroy() end
		end
		wanderModels[userId] = nil
	end

	if wanderBeams[userId] then
		for _, beam in pairs(wanderBeams[userId]) do
			if beam and beam.Parent then beam:Destroy() end
		end
		wanderBeams[userId] = nil
	end

	if lastSpawn[userId] then
		table.clear(lastSpawn[userId])
		lastSpawn[userId] = nil
	end
end)

-- // Weather system ---------------------------------------------------------------
local function applyWeatherVisuals(weather: string)
	local lighting = game:GetService("Lighting")
	if weather == "Rain" then
		lighting.ClockTime = 14
		lighting.Brightness = 1.5
		lighting.FogEnd = 100000
		lighting.FogStart = 0
	elseif weather == "Storm" then
		lighting.ClockTime = 16
		lighting.Brightness = 1
		lighting.FogEnd = 100000
		lighting.FogStart = 0
	elseif weather == "Fog" then
		lighting.Brightness = 2
		lighting.FogEnd = 200
		lighting.FogStart = 50
	else
		lighting.FogEnd = 100000
		lighting.FogStart = 0
		lighting.Brightness = 2
	end

	local weatherUpdateEvent = CachedRemotes["WeatherUpdate"]
	if weatherUpdateEvent then
		weatherUpdateEvent:FireAllClients(WeatherSystem.GetInfo())
	end
end

task.spawn(function()
	while true do
		local weatherInfo = WeatherSystem.GetInfo()
		if weatherInfo and weatherInfo.CurrentWeather then
			applyWeatherVisuals(weatherInfo.CurrentWeather)
		end
		task.wait(60) -- Checks and syncs weather state every 60 seconds cleanly
	end
end)
