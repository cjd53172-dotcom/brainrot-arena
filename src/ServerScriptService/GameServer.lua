--!strict
--[[
	GameServer (Script -> ServerScriptService)
	Boots the game: creates RemoteEvents, sets up systems, spawns orb
	pickups and the quest board, and wires player join/leave.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

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
	"BuyUpgrade", "PlaySound", "WeatherUpdate", "AchievementUnlocked", "LeaderboardUpdate", "OpenStats", "SellBrainrots",
	"WorldEvent", "MusicUpdate", "ChallengePvp", "RespondPvp", "PvpInvite" 
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

local function paintArenaBoard()
	local top = LeaderboardSystem.GetTop(10)
	local lines = {}
	if #top == 0 then
		table.insert(lines, "No wins yet — beat a rival!")
	else
		for i, row in ipairs(top) do
			table.insert(lines, string.format("%d.  %s   —   %d wins", i, tostring(row.Name), tonumber(row.Wins) or 0))
		end
	end
	PlotSystem.SetArenaBoardText(table.concat(lines, "\n"))
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
	tool.ManualActivationOnly = false
	-- Handle Y is the bat's length (Roblox tools expect that).
	local baseGrip = CFrame.new(0, -0.15, 0.1)
	tool.Grip = baseGrip

	local wood = Color3.fromRGB(196, 142, 78)
	local barrelCol = Color3.fromRGB(214, 162, 92)
	local tape = Color3.fromRGB(38, 32, 28)
	local knobCol = Color3.fromRGB(160, 110, 60)
	local ringCol = Color3.fromRGB(230, 210, 150)

	local function weldTo(a: BasePart, b: BasePart)
		local w = Instance.new("WeldConstraint")
		w.Part0 = a
		w.Part1 = b
		w.Parent = b
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.32, 1.2, 0.32)
	handle.Color = tape
	handle.Material = Enum.Material.Fabric
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	-- Cylinder parts are long on X; rotate onto the handle's Y axis.
	local function cyl(name: string, length: number, dia: number, color: Color3, y: number, mat: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(length, dia, dia)
		p.Color = color
		p.Material = mat
		p.CanCollide = false
		p.Massless = true
		p.CFrame = handle.CFrame * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2)
		p.Parent = tool
		weldTo(handle, p)
		return p
	end

	local knob = Instance.new("Part")
	knob.Name = "Knob"
	knob.Shape = Enum.PartType.Ball
	knob.Size = Vector3.new(0.48, 0.48, 0.48)
	knob.Color = knobCol
	knob.Material = Enum.Material.Wood
	knob.CanCollide = false
	knob.Massless = true
	knob.CFrame = handle.CFrame * CFrame.new(0, -0.78, 0)
	knob.Parent = tool
	weldTo(handle, knob)

	cyl("Throat", 1.05, 0.26, wood, 1.05, Enum.Material.Wood)
	cyl("Taper", 0.55, 0.42, wood, 1.75, Enum.Material.Wood)
	cyl("Barrel", 2.35, 0.72, barrelCol, 3.05, Enum.Material.Wood)
	cyl("Cup", 0.28, 0.78, Color3.fromRGB(180, 128, 70), 4.22, Enum.Material.Wood)
	cyl("LabelRing", 0.12, 0.76, ringCol, 2.15, Enum.Material.SmoothPlastic)
	local brand = Instance.new("Part")
	brand.Name = "Brand"
	brand.Size = Vector3.new(0.22, 0.55, 0.04)
	brand.Color = Color3.fromRGB(40, 28, 18)
	brand.Material = Enum.Material.SmoothPlastic
	brand.CanCollide = false
	brand.Massless = true
	brand.CFrame = handle.CFrame * CFrame.new(0, 3.1, 0.38)
	brand.Parent = tool
	weldTo(handle, brand)

	local lastSwing = 0
	local swinging = false
	local function playSwing()
		if swinging then
			return
		end
		swinging = true
		task.spawn(function()
			-- Forward/back swing (pitch), opposite the old chop, not a sideways slash.
			for i = 1, 8 do
				local t = i / 8
				tool.Grip = baseGrip * CFrame.Angles(math.rad(115 * t), math.rad(-6 * t), 0)
				task.wait(0.018)
			end
			for i = 7, 0, -1 do
				local t = i / 8
				tool.Grip = baseGrip * CFrame.Angles(math.rad(115 * t), math.rad(-6 * t), 0)
				task.wait(0.015)
			end
			tool.Grip = baseGrip
			swinging = false
		end)
	end

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
		playSwing()

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
		local old = backpack:FindFirstChild("Baseball Bat")
		if old then
			old:Destroy()
		end
		if char then
			local held = char:FindFirstChild("Baseball Bat")
			if held then
				held:Destroy()
			end
		end
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

			local firstInst = PlayerData.GetInstance(player, instanceIds[1])
			local workId, matName, cost, coinFee = BrainrotData.GetFusionMaterialInfo(def, firstInst and firstInst.Variant)

			if not PlayerData.SpendCoins(player, coinFee) then
				local hintEvent = CachedRemotes["ShowHint"]
				if hintEvent then
					hintEvent:FireClient(player, "Need " .. tostring(coinFee) .. " coins to fuse.")
				end
				return
			end

			if not PlayerData.SpendMaterials(player, { [workId] = cost }) then
				PlayerData.AddCoins(player, coinFee)
				local have = (data.Materials[workId] or 0)
				local hintEvent = CachedRemotes["ShowHint"]
				if hintEvent then
					hintEvent:FireClient(player, ("Need %d %s from plot Work (you have %d). Assign matching workers, then Collect."):format(cost, matName, have))
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

		local payload: any = {
			Phase = "Turn",
			Events = result.events,
			State = BattleSystem.GetClientState(player),
		}

		local battleNow = BattleSystem.GetBattle(player)
		local viewers = if battleNow then BattleSystem.GetViewers(battleNow) else { player }
		task.spawn(function()
			for _, viewer in ipairs(viewers) do
				PlotSystem.PlayBattleTurn(viewer, result.events)
				if result.winner then
					local visWin = result.winner
					if battleNow and battleNow.pvp and viewer == battleNow.guest then
						visWin = if result.winner == "player" then "enemy" else "player"
					end
					PlotSystem.PlayVictory(viewer, visWin)
				end
			end
		end)
		if result.winner then
			local winnerPlr: Player? = nil
			if battleNow and battleNow.pvp then
				winnerPlr = if result.winner == "player" then battleNow.player else battleNow.guest
			elseif result.winner == "player" then
				winnerPlr = player
			end
			if winnerPlr then
				LeaderboardSystem.RecordWin(winnerPlr)
				SoundSystem.PlayForPlayer(winnerPlr, "BattleWin")
				task.defer(paintArenaBoard)
				local newAch = AchievementSystem.RecordProgress(winnerPlr, "battles_won", 1)
				for _, achId in ipairs(newAch) do
					local def = AchievementSystem.DEFS[achId]
					if def then
						local achEvent = CachedRemotes["AchievementUnlocked"]
						if achEvent then
							achEvent:FireClient(winnerPlr, { Name = def.Name, Desc = def.Desc })
						end
					end
				end
			end
			if result.winner == "player" and battleNow and not battleNow.pvp then
				local rival = BrainrotData.GetRival(battleNow.rivalId)
				if rival then
					battleReward(player, rival)
					payload.Rewards = {
						Coins = rival.RewardCoins or 0,
						RewardRarity = rival.RewardRarity,
					}
				end
			end
			task.delay(4, function()
				for _, viewer in ipairs(viewers) do
					PlotSystem.ClearBattleModels(viewer)
				end
				BattleSystem.ClearBattle(player)
			end)
		end

		local battleUpdateEvent = CachedRemotes["BattleUpdate"]
		if battleUpdateEvent then
			for _, viewer in ipairs(viewers) do
				local send: any = {
					Phase = "Turn",
					Events = result.events,
					State = BattleSystem.GetClientState(viewer),
				}
				if viewer == player then
					send.Rewards = payload.Rewards
				end
				battleUpdateEvent:FireClient(viewer, send)
			end
		end
	end)
end

local forfeitBattleRemote = CachedRemotes["ForfeitBattle"]
if forfeitBattleRemote then
	forfeitBattleRemote.OnServerEvent:Connect(function(player: Player)
		local battle = BattleSystem.Forfeit(player)
		if battle then
			local viewers = BattleSystem.GetViewers(battle)
			local battleUpdateEvent = CachedRemotes["BattleUpdate"]
			if battleUpdateEvent then
				for _, viewer in ipairs(viewers) do
					battleUpdateEvent:FireClient(viewer, {
						Phase = "End",
						State = BattleSystem.GetClientState(viewer),
					})
				end
			end
			task.delay(2, function()
				for _, viewer in ipairs(viewers) do
					PlotSystem.ClearBattleModels(viewer)
				end
				BattleSystem.ClearBattle(player)
			end)
		end
	end)
end

local pendingPvp: { [number]: any } = {}

local function otherArenaPlayers(except: Player): { any }
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= except then
			table.insert(out, { UserId = p.UserId, Name = p.DisplayName })
		end
	end
	return out
end

local challengePvpRemote = CachedRemotes["ChallengePvp"]
if challengePvpRemote then
	challengePvpRemote.OnServerEvent:Connect(function(player: Player, targetId: any, teamIds: any)
		if type(targetId) ~= "number" or type(teamIds) ~= "table" or #teamIds ~= 3 then
			return
		end
		local target = Players:GetPlayerByUserId(targetId)
		if not target or target == player then
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then
				hintEvent:FireClient(player, "That player is not available.")
			end
			return
		end
		if BattleSystem.GetBattle(player) or BattleSystem.GetBattle(target) then
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then
				hintEvent:FireClient(player, "Someone is already in a battle.")
			end
			return
		end
		pendingPvp[target.UserId] = {
			Host = player,
			HostTeam = teamIds,
			At = os.time(),
		}
		local invite = CachedRemotes["PvpInvite"]
		if invite then
			invite:FireClient(target, { HostUserId = player.UserId, HostName = player.DisplayName })
		end
		local hintEvent = CachedRemotes["ShowHint"]
		if hintEvent then
			hintEvent:FireClient(player, "Challenge sent to " .. target.DisplayName .. "!")
			hintEvent:FireClient(target, player.DisplayName .. " challenged you to PvP!")
		end
	end)
end

local respondPvpRemote = CachedRemotes["RespondPvp"]
if respondPvpRemote then
	respondPvpRemote.OnServerEvent:Connect(function(player: Player, accept: any, teamIds: any)
		local pending = pendingPvp[player.UserId]
		pendingPvp[player.UserId] = nil
		if not pending or not pending.Host or not pending.Host.Parent then
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then
				hintEvent:FireClient(player, "That challenge expired.")
			end
			return
		end
		local host = pending.Host :: Player
		if accept ~= true then
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then
				hintEvent:FireClient(host, player.DisplayName .. " declined PvP.")
			end
			return
		end
		if type(teamIds) ~= "table" or #teamIds ~= 3 then
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then
				hintEvent:FireClient(player, "Pick 3 fighters, then Accept.")
			end
			pendingPvp[player.UserId] = pending
			return
		end
		local battle, err = BattleSystem.StartPvpBattle(host, pending.HostTeam, player, teamIds)
		if not battle then
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then
				hintEvent:FireClient(player, "Can't start PvP: " .. tostring(err))
				hintEvent:FireClient(host, "Can't start PvP: " .. tostring(err))
			end
			return
		end
		task.spawn(function()
			PlotSystem.SpawnBattleModels(host, battle.pTeam, battle.eTeam)
			PlotSystem.SpawnBattleModels(player, battle.eTeam, battle.pTeam)
		end)
		local battleUpdateEvent = CachedRemotes["BattleUpdate"]
		if battleUpdateEvent then
			for _, viewer in ipairs(BattleSystem.GetViewers(battle)) do
				battleUpdateEvent:FireClient(viewer, {
					Phase = "Start",
					Events = battle.openingEvents or {},
					State = BattleSystem.GetClientState(viewer),
				})
			end
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
				Players = otherArenaPlayers(player),
			})
		end
	end)
end
task.defer(paintArenaBoard)

if PlotSystem.ArenaBoardPrompt then
	PlotSystem.ArenaBoardPrompt.Triggered:Connect(function(player: Player)
		paintArenaBoard()
		local hintEvent = CachedRemotes["ShowHint"]
		if hintEvent then
			hintEvent:FireClient(player, "Champions are listed on this board.")
		end
	end)
end

-- // Plaza kiosk: quests (expeditions open from zone portals) --------------------
local plazaFolder = workspace:FindFirstChild("Plaza") or workspace
local oldQuest = workspace:FindFirstChild("QuestBoard")
if oldQuest then
	oldQuest:Destroy()
end
local oldExp = workspace:FindFirstChild("ExpeditionBoard")
if oldExp then
	oldExp:Destroy()
end
local oldExpBtn = workspace:FindFirstChild("ExpeditionButton")
if oldExpBtn then
	oldExpBtn:Destroy()
end

local function attachKioskPrompt(model: Model, action: string, object: string, parentName: string?): ProximityPrompt
	local attach = (parentName and model:FindFirstChild(parentName, true)) or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 18
	prompt.RequiresLineOfSight = false
	prompt.Parent = attach
	return prompt
end

local questKiosk = VisualEffects.BuildQuestKiosk()
questKiosk.Parent = plazaFolder
local questSpot = PlotSystem.PlazaSpots.Quest
PlotSystem.SitOnTerrain(questKiosk, questSpot.X, questSpot.Y)
print("[GameServer] Quest kiosk at " .. tostring(questKiosk:GetPivot().Position))
local prompt = attachKioskPrompt(questKiosk, "Read Quests", "Quest Board", "Board")
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

	local trainerSpot = PlotSystem.PlazaSpots.Trainer
	local cx, cz = trainerSpot.X, trainerSpot.Y
	local groundY = 16
	local upParams = RaycastParams.new()
	upParams.FilterType = Enum.RaycastFilterType.Include
	upParams.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(cx, 500, cz), Vector3.new(0, -1000, 0), upParams)
	if hit then
		groundY = hit.Position.Y
	end

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

	local pad = stallPart("Floor", Vector3.new(8, 0.5, 8), Vector3.new(cx, groundY + 0.25, cz), Color3.fromRGB(70, 55, 40), Enum.Material.WoodPlanks)
	local counter = stallPart("Counter", Vector3.new(5, 1.4, 2), Vector3.new(cx, groundY + 1.2, cz + 2.2), Color3.fromRGB(120, 85, 50), Enum.Material.Wood)
	stallPart("Crate", Vector3.new(2.2, 1.6, 2.2), Vector3.new(cx - 2.4, groundY + 1.05, cz + 0.4), Color3.fromRGB(140, 95, 55), Enum.Material.WoodPlanks)

	local sign = stallPart("Sign", Vector3.new(8, 2.4, 0.4), Vector3.new(cx, groundY + 8.2, cz), Color3.fromRGB(35, 28, 22), Enum.Material.Wood)
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

	local promptParent: BasePart = counter
	local npc: Model? = nil
	local custom = ReplicatedStorage:FindFirstChild("StatTrainerModel")
	if custom and custom:IsA("Model") then
		npc = custom:Clone()
	else
		local ok, built = pcall(function()
			local desc = Instance.new("HumanoidDescription")
			desc.HeadColor = Color3.fromRGB(255, 204, 153)
			desc.TorsoColor = Color3.fromRGB(30, 90, 170)
			desc.LeftArmColor = Color3.fromRGB(255, 204, 153)
			desc.RightArmColor = Color3.fromRGB(255, 204, 153)
			desc.LeftLegColor = Color3.fromRGB(35, 35, 45)
			desc.RightLegColor = Color3.fromRGB(35, 35, 45)
			desc.HatAccessory = ""
			return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
		end)
		if ok and built and built:IsA("Model") then
			npc = built
		end
	end
	if npc then
		npc.Name = "Trainer"
		npc.Parent = stall
		local pivotY = groundY + 3
		npc:PivotTo(CFrame.new(cx, pivotY, cz - 0.4))
		local hum = npc:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.DisplayName = "Stat Trainer"
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			hum.AutoJumpEnabled = false
		end
		for _, d in ipairs(npc:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		local hrp = npc:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			promptParent = hrp
		end
	end

	stall.PrimaryPart = pad
	stall.Parent = plazaFolder
	print("[GameServer] Stat trainer placed at " .. tostring(Vector3.new(cx, groundY, cz)))

	local upPrompt = Instance.new("ProximityPrompt")
	upPrompt.ActionText = "Shop Upgrades"
	upPrompt.ObjectText = "Stat Trainer"
	upPrompt.HoldDuration = 0
	upPrompt.MaxActivationDistance = 14
	upPrompt.RequiresLineOfSight = false
	upPrompt.Parent = promptParent

	upPrompt.Triggered:Connect(function(player: Player)
		pushCollection(player)
		local openStats = CachedRemotes["OpenStats"]
		if openStats then
			openStats:FireClient(player)
		end
	end)
end

pushExpeditionState = function(player: Player)
	local status = ExpeditionSystem.GetStatus(player)
	local updateEvent = CachedRemotes["ExpeditionUpdate"]
	if updateEvent then
		updateEvent:FireClient(player, status)
	end
end

local function openExpeditionBoard(player: Player, selectZone: string?)
	local status = ExpeditionSystem.GetStatus(player)
	if type(status) ~= "table" then
		status = {}
	end
	status.OpenPanel = true
	if type(selectZone) == "string" then
		status.SelectZone = selectZone
	end
	local updateEvent = CachedRemotes["ExpeditionUpdate"]
	if updateEvent then
		updateEvent:FireClient(player, status)
	end
end

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
	trigger.CanTouch = true
	trigger.CFrame = portal:GetPivot()
	trigger.Parent = portal

	local lastUse: { [number]: number } = {}
	local function usePortal(p: Player)
		local now = os.clock()
		if lastUse[p.UserId] and now - lastUse[p.UserId] < 1.5 then
			return
		end
		lastUse[p.UserId] = now
		local discovered = ExpeditionSystem.UnlockZone(p, zoneId)
		if discovered then
			VisualEffects.PlayZoneDiscover(trigger.Position + Vector3.new(0, 4, 0), zoneColor)
			local hintEvent = CachedRemotes["ShowHint"]
			if hintEvent then
				hintEvent:FireClient(p, "Discovered " .. zoneName .. "! Send a team from this panel.")
			end
		end
		openExpeditionBoard(p, zoneId)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PortalPrompt"
	prompt.ActionText = "Open Expeditions"
	prompt.ObjectText = zoneName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = portal:FindFirstChild("PortalSurface") or trigger
	prompt.Triggered:Connect(usePortal)

	trigger.Touched:Connect(function(hit: BasePart)
		local char = hit and hit.Parent
		local p = char and Players:GetPlayerFromCharacter(char)
		if p then
			usePortal(p)
		end
	end)
end

-- Minigame gates: teleport to another Place in this Experience (Laser Tag, etc.).
local placeGatesOk, placeGatesErr = pcall(function()
do
	local lastHop: { [number]: number } = {}
	for _, gate in ipairs(BrainrotData.PLACE_GATES or {}) do
		local portal = VisualEffects.BuildPlacePortal(gate.Name, gate.Color)
		PlotSystem.SitOnTerrain(portal, gate.X, gate.Z)
		portal.Parent = workspace
		print("[GameServer] Place gate " .. tostring(gate.Id) .. " at " .. tostring(gate.X) .. ", " .. tostring(gate.Z))

		local function resolvedPlaceId(): number
			local attrName = gate.Attribute
			if type(attrName) == "string" then
				local attr = workspace:GetAttribute(attrName)
				if type(attr) == "number" and attr > 0 then
					return attr
				end
			end
			return gate.PlaceId or 0
		end

		local function hop(player: Player)
			local now = os.clock()
			if lastHop[player.UserId] and now - lastHop[player.UserId] < 4 then
				return
			end
			lastHop[player.UserId] = now
			local dest = resolvedPlaceId()
			local hintEvent = CachedRemotes["ShowHint"]
			if dest <= 0 then
				if hintEvent then
					hintEvent:FireClient(player, "Laser Tag isn't linked yet. Publish the Laser Tag template as a Place in this experience, then set PlaceId (or Workspace.LaserTagPlaceId).")
				end
				return
			end
			if dest == game.PlaceId then
				if hintEvent then
					hintEvent:FireClient(player, "That minigame is this same place — publish Laser Tag as a second Place.")
				end
				return
			end
			if hintEvent then
				hintEvent:FireClient(player, "Entering " .. gate.Name .. "...")
			end
			local options = Instance.new("TeleportOptions")
			options:SetTeleportData({
				ReturnPlaceId = game.PlaceId,
				From = "BrainrotArena",
				Minigame = gate.Id,
			})
			local ok, err = pcall(function()
				TeleportService:TeleportAsync(dest, { player }, options)
			end)
			if not ok and hintEvent then
				hintEvent:FireClient(player, "Teleport needs a published place. Studio Play cannot jump templates. " .. tostring(err))
			end
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PlacePrompt"
		prompt.ActionText = "Enter"
		prompt.ObjectText = gate.Name
		prompt.HoldDuration = 0.2
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = portal:FindFirstChild("PortalSurface") or portal:FindFirstChildWhichIsA("BasePart")
		prompt.Triggered:Connect(hop)

		if gate.Id == "laser_tag" then
			local pivot = portal:GetPivot()
			local frame = Instance.new("Part")
			frame.Name = "LaserTagKillBoard"
			frame.Size = Vector3.new(12, 9, 0.7)
			frame.Anchored = true
			frame.CanCollide = true
			frame.Color = Color3.fromRGB(12, 40, 18)
			frame.Material = Enum.Material.Neon
			frame.CFrame = pivot * CFrame.new(9, 5, 0)
			frame.Parent = portal
			local header = Instance.new("Part")
			header.Name = "LaserTagKillHeader"
			header.Size = Vector3.new(12, 2, 0.7)
			header.Anchored = true
			header.CanCollide = false
			header.Color = Color3.fromRGB(30, 90, 40)
			header.Material = Enum.Material.Neon
			header.CFrame = pivot * CFrame.new(9, 10.5, 0)
			header.Parent = portal
			local function face(part: BasePart, title: boolean): TextLabel
				local gui = Instance.new("SurfaceGui")
				gui.Face = Enum.NormalId.Front
				gui.PixelsPerStud = 30
				gui.LightInfluence = 0
				gui.Parent = part
				local label = Instance.new("TextLabel")
				label.Size = UDim2.new(1, -12, 1, -12)
				label.Position = UDim2.new(0, 6, 0, 6)
				label.BackgroundTransparency = 1
				label.Text = if title then "LASER TAG KILLS" else "Play Laser Tag to post kills."
				label.Font = Enum.Font.GothamBold
				label.TextScaled = title
				label.TextSize = 24
				label.TextColor3 = Color3.fromRGB(180, 255, 160)
				label.TextStrokeTransparency = 0.3
				label.TextWrapped = true
				label.TextYAlignment = if title then Enum.TextYAlignment.Center else Enum.TextYAlignment.Top
				label.Parent = gui
				local back = gui:Clone()
				back.Face = Enum.NormalId.Back
				back.Parent = part
				return label
			end
			face(header, true)
			local listLabel = face(frame, false)
			print("[GameServer] Laser kill board next to portal")

			local function paintLaserBoard()
				local top = LeaderboardSystem.GetLaserTagTop(8)
				if #top == 0 then
					listLabel.Text = "Play Laser Tag to post kills.\nKills save across visits."
					return
				end
				local lines = {}
				for i, row in ipairs(top) do
					table.insert(lines, string.format("%d.  %s   —   %d", i, tostring(row.Name), tonumber(row.Kills) or 0))
				end
				listLabel.Text = table.concat(lines, "\n")
			end
			paintLaserBoard()
			task.spawn(function()
				while frame.Parent do
					task.wait(15)
					paintLaserBoard()
				end
			end)
		end
	end
end
end)
if not placeGatesOk then
	warn("[GameServer] Place gates failed (continuing): " .. tostring(placeGatesErr))
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
	local function nearPlot(x: number, z: number): boolean
		local plots = workspace:FindFirstChild("Plots")
		if not plots then
			return false
		end
		for _, plot in ipairs(plots:GetChildren()) do
			local base = plot:FindFirstChild("Base")
			if base and base:IsA("BasePart") then
				local dx = x - (base :: BasePart).Position.X
				local dz = z - (base :: BasePart).Position.Z
				if math.abs(dx) < 72 and math.abs(dz) < 72 then
					return true
				end
			end
		end
		return false
	end
	local function waterScore(x: number, z: number): number
		local n = 0
		for ox = -40, 40, 10 do
			for oz = -40, 40, 10 do
				local h = hitAt(x + ox, z + oz)
				if h and h.Material == Enum.Material.Water then
					n += 1
				end
			end
		end
		return n
	end
	local shores: { any } = {}
	for x = -80, 360, 12 do
		for z = -120, 280, 12 do
			local h = hitAt(x, z)
			if h and h.Material == Enum.Material.Water then
				local score = waterScore(x, z)
				if score >= 8 then
					for _, d in ipairs({ Vector3.new(14, 0, 0), Vector3.new(-14, 0, 0), Vector3.new(0, 0, 14), Vector3.new(0, 0, -14) }) do
						local land = hitAt(x + d.X, z + d.Z)
						if land and land.Material ~= Enum.Material.Water and land.Normal.Y > 0.55 then
							local lx, lz = land.Position.X, land.Position.Z
							if not nearPlot(lx, lz) then
								table.insert(shores, {
									X = lx,
									Z = lz,
									Y = land.Position.Y,
									Yaw = math.atan2(-d.X, -d.Z),
									Score = score,
								})
							end
						end
					end
				end
			end
		end
	end
	table.sort(shores, function(a, b)
		return a.Score > b.Score
	end)
	local chosen: { any } = {}
	for _, s in ipairs(shores) do
		local ok = true
		for _, c in ipairs(chosen) do
			local dx, dz = s.X - c.X, s.Z - c.Z
			if dx * dx + dz * dz < 40 * 40 then
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
			{ X = 70, Z = 20, Y = 12, Yaw = 0 },
			{ X = 55, Z = 40, Y = 12, Yaw = math.pi / 2 },
		}
	end
	local names = { "Riverside Dock", "Lakeside Pier" }
	for i, s in ipairs(chosen) do
		local dock = VisualEffects.BuildFishingSpot()
		dock:PivotTo(CFrame.new(s.X, s.Y, s.Z) * CFrame.Angles(0, s.Yaw or 0, 0))
		dock.Parent = workspace
		local pad = dock:FindFirstChild("CastPad")
		if not (pad and pad:IsA("BasePart")) then
			pad = dock.PrimaryPart or dock:FindFirstChildWhichIsA("BasePart")
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "FishPrompt"
		prompt.ActionText = "Cast Line"
		prompt.ObjectText = names[i] or "Fishing Dock"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = pad
		table.insert(fishingSpots, { Id = "dock" .. i, Model = dock, Name = names[i] or ("Dock " .. i), Prompt = prompt })
		print("[GameServer] Fishing dock " .. tostring(i) .. " at " .. tostring(Vector3.new(s.X, s.Y, s.Z)))
		if i == 1 then
			local landmark = VisualEffects.BuildFishingLandmark()
			landmark:PivotTo(CFrame.new(s.X, s.Y + 2, s.Z) * CFrame.Angles(0, (s.Yaw or 0) + math.pi, 0))
			landmark.Parent = workspace
		end
	end
end

-- // Fishing System Core Logic Pipeline -------------------------------------------
local function pushFishingState(player: Player, state: string, reward: any?, openPanel: boolean?)
	local fishingUpdateEvent = CachedRemotes["FishingUpdate"]
	if fishingUpdateEvent then
		fishingUpdateEvent:FireClient(player, {
			State = state,
			Reward = reward,
			OpenPanel = openPanel == true,
		})
	end
end

local playerFishingGear: { [number]: any } = {}

local function finishReel(player: Player, quality: number)
	local gear = playerFishingGear[player.UserId]
	playerFishingGear[player.UserId] = nil
	local reward = FishingSystem.Reel(player, quality)
	local bobberPos = if gear and gear.Bobber then gear.Bobber.Position else nil
	if bobberPos and reward and reward.Kind ~= "Miss" then
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
	VisualEffects.ClearFishingGear(gear)
	if reward then
		pushFishingState(player, "None", reward)
		pushCollection(player)
		if reward.Kind == "Brainrot" then
			autoShowcase(player)
			PlotSystem.RefreshPlot(player)
		end
	end
end

local function startFishing(player: Player, spotId: string, openPanel: boolean)
		VisualEffects.ClearFishingGear(playerFishingGear[player.UserId])
		playerFishingGear[player.UserId] = nil
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

			pushFishingState(player, "Waiting", nil, openPanel)

			task.delay(biteDelay, function()
				local state = FishingSystem.CheckBite(player)
				if state == "Bite" then
					local gear = playerFishingGear[player.UserId]
					if gear and gear.Bobber then
						VisualEffects.PlayBite(gear.Bobber)
						local old = gear.Bobber:FindFirstChild("ReelPrompt")
						if old then
							old:Destroy()
						end
						local reelPrompt = Instance.new("ProximityPrompt")
						reelPrompt.Name = "ReelPrompt"
						reelPrompt.ActionText = "Reel In"
						reelPrompt.ObjectText = "Bite!"
						reelPrompt.HoldDuration = 0
						reelPrompt.MaxActivationDistance = 40
						reelPrompt.RequiresLineOfSight = false
						reelPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
						reelPrompt.KeyboardKeyCode = Enum.KeyCode.E
						reelPrompt.Parent = gear.Bobber
						reelPrompt.Triggered:Connect(function(p: Player)
							if p == player then
								finishReel(player, 0.7)
							end
						end)
					end
					pushFishingState(player, "Bite", nil, true)
				end
			end)

			task.delay(biteDelay + 3.5, function()
				local state = FishingSystem.GetState(player)
				if state == "Missed" then
					pushFishingState(player, "Missed")
					VisualEffects.ClearFishingGear(playerFishingGear[player.UserId])
					playerFishingGear[player.UserId] = nil
					FishingSystem.Cancel(player)
				end
			end)
		end
end

for _, spot in ipairs(fishingSpots) do
	if spot.Prompt and spot.Prompt:IsA("ProximityPrompt") then
		local id = spot.Id
		spot.Prompt.Triggered:Connect(function(player: Player)
			startFishing(player, id, true)
		end)
	end
end

local castLineRemote = CachedRemotes["CastLine"]
if castLineRemote then
	castLineRemote.OnServerEvent:Connect(function(player: Player, spotId: any)
		if type(spotId) ~= "string" then
			return
		end
		startFishing(player, spotId, true)
	end)
end

local reelInRemote = CachedRemotes["ReelIn"]
if reelInRemote then
	reelInRemote.OnServerEvent:Connect(function(player: Player, quality: any)
		finishReel(player, tonumber(quality) or 0.5)
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

-- Lucky blocks and hidden secrets (controller-friendly ProximityPrompts).
local luckOk, luckErr = pcall(function()
do
	local function hint(player: Player, text: string)
		local ev = CachedRemotes["ShowHint"]
		if ev then
			ev:FireClient(player, text)
		end
	end
	local function sitModel(model: Model, x: number, z: number)
		PlotSystem.SitOnTerrain(model, x, z)
		model.Parent = workspace
	end
	local function randomCommonId(): string
		local ids = {}
		for _, def in ipairs(BrainrotData.ROSTER) do
			if def.Rarity == "Common" then
				table.insert(ids, def.Id)
			end
		end
		if #ids == 0 then
			return "tung_sahur"
		end
		return ids[math.random(1, #ids)]
	end

	local luckSpots = {
		{ Id = "luck1", X = 140, Z = 70 },
		{ Id = "luck2", X = 40, Z = 110 },
		{ Id = "luck3", X = 200, Z = -20 },
		{ Id = "luck4", X = 300, Z = 180 },
		{ Id = "luck5", X = -40, Z = 40 },
	}
	for _, spot in ipairs(luckSpots) do
		local model = Instance.new("Model")
		model.Name = "LuckyBlock_" .. spot.Id
		local part = Instance.new("Part")
		part.Name = "Block"
		part.Size = Vector3.new(4.2, 4.2, 4.2)
		part.Color = Color3.fromRGB(255, 210, 60)
		part.Material = Enum.Material.Neon
		part.Anchored = true
		part.CanCollide = true
		part.Parent = model
		local symbol = Instance.new("BillboardGui")
		symbol.Size = UDim2.new(0, 80, 0, 36)
		symbol.StudsOffset = Vector3.new(0, 3.4, 0)
		symbol.AlwaysOnTop = false
		symbol.Parent = part
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextSize = 22
		label.TextColor3 = Color3.fromRGB(40, 20, 0)
		label.Text = "?"
		label.Parent = symbol
		local spark = Instance.new("ParticleEmitter")
		spark.Color = ColorSequence.new(Color3.fromRGB(255, 230, 80))
		spark.Rate = 8
		spark.Lifetime = NumberRange.new(0.6, 1.2)
		spark.Speed = NumberRange.new(1, 3)
		spark.LightEmission = 0.6
		spark.Parent = part
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = "Lucky Block"
		prompt.HoldDuration = 0.35
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = part
		sitModel(model, spot.X, spot.Z)
		local blockId = spot.Id
		prompt.Triggered:Connect(function(player: Player)
			local data = PlayerData.Get(player)
			if not data then
				return
			end
			if type(data.LuckyCooldown) ~= "table" then
				data.LuckyCooldown = {}
			end
			local now = os.time()
			local ready = data.LuckyCooldown[blockId] or 0
			if now < ready then
				hint(player, "Lucky Block recharges in " .. tostring(ready - now) .. "s")
				return
			end
			data.LuckyCooldown[blockId] = now + 90
			local roll = math.random()
			if roll < 0.08 then
				local id = randomCommonId()
				local inst = PlayerData.TryAddBrainrot(player, id, false, BrainrotData.RollVariant())
				if inst then
					hint(player, "Lucky Block! A brainrot popped out!")
					autoShowcase(player)
					pushCollection(player)
					PlotSystem.RefreshPlot(player)
				else
					PlayerData.AddCoins(player, 250)
					hint(player, "Lucky Block! Inventory full — +250 coins")
					pushCollection(player)
				end
			elseif roll < 0.28 then
				data.LuckBoostUntil = now + 180
				hint(player, "Lucky Block! 2x luck for 3 minutes")
			elseif roll < 0.55 then
				PlayerData.AddRareMaterial(player, "Pearl Shard", 1)
				hint(player, "Lucky Block! +1 Pearl Shard")
			else
				local coins = math.random(80, 280)
				PlayerData.AddCoins(player, coins)
				hint(player, "Lucky Block! +" .. tostring(coins) .. " coins")
				pushCollection(player)
			end
		end)
	end

	local secrets = {
		{ Id = "dock_crate", Name = "Sunken Crate", X = 250, Z = -90 },
		{ Id = "arena_nook", Name = "Colosseum Nook", X = -170, Z = -40 },
		{ Id = "woods_stump", Name = "Whispering Stump", X = 410, Z = 90 },
		{ Id = "peak_cache", Name = "Sky Cache", X = 173, Z = -190 },
		{ Id = "cave_glint", Name = "Crystal Glint", X = 370, Z = 250 },
		{ Id = "hill_mark", Name = "Hill Mark", X = 90, Z = 250 },
	}
	local secretCount = #secrets
	for _, spot in ipairs(secrets) do
		local model = Instance.new("Model")
		model.Name = "Secret_" .. spot.Id
		local part = Instance.new("Part")
		part.Name = "Cache"
		part.Size = Vector3.new(2.2, 1.4, 2.2)
		part.Color = Color3.fromRGB(70, 50, 90)
		part.Material = Enum.Material.Amethyst
		part.Anchored = true
		part.CanCollide = true
		part.Parent = model
		local glow = Instance.new("PointLight")
		glow.Brightness = 0.6
		glow.Range = 10
		glow.Color = Color3.fromRGB(180, 120, 255)
		glow.Parent = part
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Search"
		prompt.ObjectText = "Hidden Secret"
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = part
		sitModel(model, spot.X, spot.Z)
		local secretId = spot.Id
		local secretName = spot.Name
		prompt.Triggered:Connect(function(player: Player)
			local data = PlayerData.Get(player)
			if not data then
				return
			end
			if type(data.SecretsFound) ~= "table" then
				data.SecretsFound = {}
			end
			if data.SecretsFound[secretId] then
				hint(player, "You already found " .. secretName .. ".")
				return
			end
			data.SecretsFound[secretId] = true
			local found = 0
			for _ in pairs(data.SecretsFound) do
				found += 1
			end
			local coins = 150 + found * 50
			PlayerData.AddCoins(player, coins)
			hint(player, "Secret: " .. secretName .. "! +" .. tostring(coins) .. " coins (" .. tostring(found) .. "/" .. tostring(secretCount) .. ")")
			if found >= secretCount then
				PlayerData.AddCoins(player, 1000)
				hint(player, "All secrets found! +1000 bonus coins")
			end
			pushCollection(player)
		end)
	end
	print("[GameServer] Lucky blocks " .. tostring(#luckSpots) .. " secrets " .. tostring(secretCount))
end
end)
if not luckOk then
	warn("[GameServer] Lucky/secrets failed (continuing): " .. tostring(luckErr))
end

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

-- Zones only unlock from walking up to a portal, not a client remote.

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
		LeaderboardSystem.LastRefresh = 0
		paintArenaBoard()
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

local function cleanupWanderVisuals(items: { any })
	for _, item in ipairs(items) do
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

	local model = PlotSystem.BuildDisplayModel(def, wander.Shiny == true, wander.Variant)
	-- Plots stay at display size (~4 studs). Wilds are 6× that.
	local WILD_SIZE_MULT = 6
	pcall(function()
		model:ScaleTo(model:GetScale() * WILD_SIZE_MULT)
	end)

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			d:Destroy()
		end
	end
	model:SetAttribute("BrainrotId", def.Id)
	if wander.Variant then
		model:SetAttribute("Variant", wander.Variant)
	end
	if wander.Shiny then
		model:SetAttribute("Shiny", true)
	end
	VisualEffects.AddWildAura(model, wander.Rarity, BrainrotData.GetDisplayName(def, wander.Variant, wander.Shiny == true))
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
	PlotSystem.FitInWorld(model, 4.2 * WILD_SIZE_MULT)
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
	local hitboxSize = 6 * WILD_SIZE_MULT
	if reachTier > 0 then
		local reachUpgradeDef = PlayerData.UPGRADE_DEFS.Reach
		if reachUpgradeDef then
			hitboxSize = (reachUpgradeDef.Values[reachTier] or 6) * WILD_SIZE_MULT
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

	local catchPrompt = Instance.new("ProximityPrompt")
	catchPrompt.Name = "CatchPrompt"
	catchPrompt.ActionText = "Catch"
	catchPrompt.ObjectText = BrainrotData.GetDisplayName(def, wander.Variant, wander.Shiny == true)
	catchPrompt.HoldDuration = 0
	catchPrompt.MaxActivationDistance = 28
	catchPrompt.RequiresLineOfSight = false
	catchPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	catchPrompt.KeyboardKeyCode = Enum.KeyCode.E
	catchPrompt.Parent = hitbox
	catchPrompt.Triggered:Connect(function(p: Player)
		attemptCatch(p)
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
			if wander.EventRush then
				hintEvent:FireClient(player, "⚡ LEGENDARY RUSH — a Legendary spawned nearby! Follow the beam!")
			else
				hintEvent:FireClient(player, "🌟 LEGENDARY BRAINROT SPOTTED! Follow the golden beam! (3 min)")
			end
		end
	end

	if (wander.Rarity == "Rare" or wander.Rarity == "Epic") and not wander.EventRush then
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
					local hop = if wander.EventRush then 7 else 20
					targetPos = currentPos + fleeDir * hop
					fleeing = true
					fleeTime += 0.2
					if fleeTime > (if wander.EventRush then 1.6 else 3.5) then
						tiredTime = if wander.EventRush then 4 else 3
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
				local rush = wander.EventRush == true
				local speed = if fleeing then cfg.WalkSpeed * (if rush then 1.25 else 1.5) elseif tiredTime > 0 then cfg.WalkSpeed * 0.45 else cfg.WalkSpeed
				speed = math.min(speed, if rush then 14 else 13)
				currentPos += dir * speed * 0.2
				local home = Vector3.new(127, 0, 98)
				local fromHome = Vector3.new(currentPos.X - home.X, 0, currentPos.Z - home.Z)
				if fromHome.Magnitude > 170 then
					local n = fromHome.Unit * 170
					currentPos = Vector3.new(home.X + n.X, currentPos.Y, home.Z + n.Z)
					targetPos = currentPos
					fleeing = false
				end
				-- Re-snap to the ground every step so slopes don't swallow the creature
				local gy = wildGroundY(currentPos.X, currentPos.Z, model)
				if gy then
					currentPos = Vector3.new(currentPos.X, gy + bottomOffset + 0.2, currentPos.Z)
				end

				local bobY = math.abs(math.sin(os.clock() * 8)) * 0.4
				local cf = PlotSystem.FacingCFrame(model, currentPos + Vector3.new(0, bobY, 0), dir)

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
								local luckMult = 1
								pcall(function()
									luckMult = PlayerData.GetLuckMultiplier(player)
								end)

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

				if WanderSystem.EventActive then
					for _ = 1, 5 do
						if not player.Parent then
							break
						end
						local rushId = WanderSystem.SpawnWild(player, PlotSystem, 1, "Legendary", true)
						if rushId then
							spawnWildVisual(player, rushId)
						end
					end
					for _ = 1, 4 do
						if not player.Parent then
							break
						end
						local rushId = WanderSystem.SpawnWild(player, PlotSystem, 1, "Epic", true)
						if rushId then
							spawnWildVisual(player, rushId)
						end
					end
				end
			end)
		end

		local despawned = WanderSystem.TickDespawn()
		cleanupWanderVisuals(despawned)
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
		if weatherInfo and not WanderSystem.EventActive then
			applyWeatherVisuals(weatherInfo.Current or weatherInfo.CurrentWeather or "Clear")
		end
		task.wait(60)
	end
end)

local function applyEventScenery(active: boolean)
	local lighting = game:GetService("Lighting")
	local existing = workspace:FindFirstChild("LegendaryRushFX")
	if existing then
		existing:Destroy()
	end
	if active then
		lighting.ClockTime = 21.2
		lighting.Brightness = 1.15
		lighting.Ambient = Color3.fromRGB(70, 30, 90)
		lighting.OutdoorAmbient = Color3.fromRGB(90, 40, 30)
		lighting.ColorShift_Top = Color3.fromRGB(255, 140, 40)
		lighting.ColorShift_Bottom = Color3.fromRGB(80, 20, 120)
		lighting.FogColor = Color3.fromRGB(80, 20, 50)
		lighting.FogStart = 40
		lighting.FogEnd = 420
		local atmo = lighting:FindFirstChildOfClass("Atmosphere")
		if not atmo then
			atmo = Instance.new("Atmosphere")
			atmo.Parent = lighting
		end
		atmo.Density = 0.48
		atmo.Color = Color3.fromRGB(255, 120, 40)
		atmo.Decay = Color3.fromRGB(90, 20, 80)
		atmo.Haze = 4
		atmo.Glare = 0.6
		local cc = lighting:FindFirstChildOfClass("ColorCorrectionEffect")
		if not cc then
			cc = Instance.new("ColorCorrectionEffect")
			cc.Parent = lighting
		end
		cc.Saturation = 0.45
		cc.Contrast = 0.18
		cc.TintColor = Color3.fromRGB(255, 170, 90)
		local bloom = lighting:FindFirstChildOfClass("BloomEffect")
		if not bloom then
			bloom = Instance.new("BloomEffect")
			bloom.Parent = lighting
		end
		bloom.Intensity = 1.1
		bloom.Threshold = 0.6
		local fx = VisualEffects.BuildLegendaryRushFX()
		fx.Parent = workspace
	else
		pcall(function()
			WorldDesign.ApplyLighting()
		end)
		applyWeatherVisuals(WeatherSystem.GetInfo().Current or "Clear")
	end
end

local function broadcastEvent(active: boolean, endsAt: number?)
	local payload = {
		Active = active,
		Name = "Legendary Rush",
		EndsAt = endsAt or 0,
		MusicMode = if active then "Event" else "Normal",
	}
	local worldEvent = CachedRemotes["WorldEvent"]
	if worldEvent then
		worldEvent:FireAllClients(payload)
	end
	local musicUpdate = CachedRemotes["MusicUpdate"]
	if musicUpdate then
		musicUpdate:FireAllClients(payload.MusicMode)
	end
	local hintEvent = CachedRemotes["ShowHint"]
	if hintEvent then
		if active then
			hintEvent:FireAllClients("⚡ LEGENDARY RUSH! Legendaries and epics are spawning for 10 minutes!")
		else
			hintEvent:FireAllClients("Legendary Rush ended. The world settles down.")
		end
	end
end

task.spawn(function()
	local function nextHourUnix(): number
		local t = os.time()
		return t - (t % 3600) + 3600
	end
	local nextAt = nextHourUnix()
	print("[GameServer] Next Legendary Rush on the hour. unix " .. tostring(nextAt))
	while true do
		if os.time() >= nextAt then
			WanderSystem.SetEventActive(true)
			applyEventScenery(true)
			local endsAt = os.time() + 600
			broadcastEvent(true, endsAt)
			print("[GameServer] Legendary Rush started")
			task.wait(600)
			WanderSystem.SetEventActive(false)
			cleanupWanderVisuals(WanderSystem.ClearEventRush())
			applyEventScenery(false)
			broadcastEvent(false)
			print("[GameServer] Legendary Rush ended")
			nextAt = nextHourUnix()
		end
		task.wait(5)
	end
end)
