--!strict
--[[
	QuestSystem (ModuleScript -> ServerScriptService/Systems)
	Owns the story quest chain, progress tracking, and reward granting.

	Quest definitions:
	{
		Name, Description,
		Objective = "orbs" | "brainrots" | "workers" | "materials" | "fusions" | "rival",
		Goal = number,            -- for "rival", Goal is ignored (win once)
		RivalId = string?,        -- for Objective == "rival"
		Reward = { BrainrotId?, RandomRarity?, Coins? },
	}

	Quests unlock strictly in QUEST_ORDER. "orbs" progress comes from
	AddProgress (orb touches); everything else is checked via
	CheckObjective(player, objective) after the relevant game event.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local PlotSystem = require(script.Parent:WaitForChild("PlotSystem"))

local QuestSystem = {}

QuestSystem.QUEST_ORDER = {
	"first_steps",
	"growing_team",
	"clock_in",
	"material_gatherer",
	"fusion_discovery",
	"arena_entrant",
	"arena_gate_001",
	"arena_gate_005",
	"arena_gate_010",
	"arena_gate_025",
	"arena_gate_050",
	"arena_gate_100",
}

-- Old boss/rival quests mapped onto the 100-gate ladder.
local LEGACY_QUESTS: { [string]: string } = {
	rival_rocco = "arena_gate_001",
	rival_marina = "arena_gate_005",
	rival_bruno = "arena_gate_010",
	rival_umbra = "arena_gate_025",
	rival_campione = "arena_gate_050",
}

QuestSystem.QUESTS = {
	first_steps = {
		Name = "First Steps",
		Description = "Catch 1 wild brainrot roaming the world.",
		Objective = "brainrots",
		Goal = 1,
		Reward = { BrainrotId = "tung_sahur", Coins = 120 },
	},
	growing_team = {
		Name = "Growing Team",
		Description = "Own 4 brainrots.",
		Objective = "brainrots",
		Goal = 4,
		Reward = { Coins = 250 },
	},
	clock_in = {
		Name = "Clock In",
		Description = "Assign 1 brainrot to work at a station on your plot.",
		Objective = "workers",
		Goal = 1,
		Reward = { Coins = 200 },
	},
	material_gatherer = {
		Name = "Material Gatherer",
		Description = "Collect 30 materials from your workstations.",
		Objective = "materials",
		Goal = 30,
		Reward = { Coins = 400, RandomRarity = "Rare" },
	},
	fusion_discovery = {
		Name = "Fusion Discovery",
		Description = "Fuse 3 duplicates at the Fusion Lab.",
		Objective = "fusions",
		Goal = 1,
		Reward = { Coins = 600 },
	},
	arena_entrant = {
		Name = "Arena Entrant",
		Description = "Own 6 brainrots, then walk to the Colosseum.",
		Objective = "brainrots",
		Goal = 6,
		Reward = { Coins = 500 },
	},
	arena_gate_001 = {
		Name = "First Blood",
		Description = "Win Arena Battle 1 at the Colosseum.",
		Objective = "rival",
		Goal = 1,
		RivalId = "gate_001",
		Reward = { Coins = 800 },
	},
	arena_gate_005 = {
		Name = "Warming Up",
		Description = "Win Arena Battle 5. Commons will not carry you forever.",
		Objective = "rival",
		Goal = 1,
		RivalId = "gate_005",
		Reward = { Coins = 1800, RandomRarity = "Rare" },
	},
	arena_gate_010 = {
		Name = "Gate 10",
		Description = "Win Arena Battle 10.",
		Objective = "rival",
		Goal = 1,
		RivalId = "gate_010",
		Reward = { Coins = 3500, RandomRarity = "Rare" },
	},
	arena_gate_025 = {
		Name = "Quarter Century",
		Description = "Win Arena Battle 25. Bring Epics.",
		Objective = "rival",
		Goal = 1,
		RivalId = "gate_025",
		Reward = { Coins = 9000, RandomRarity = "Epic" },
	},
	arena_gate_050 = {
		Name = "Halfway Champion",
		Description = "Win Arena Battle 50.",
		Objective = "rival",
		Goal = 1,
		RivalId = "gate_050",
		Reward = { Coins = 22000, RandomRarity = "Legendary" },
	},
	arena_gate_100 = {
		Name = "Colosseum Crown",
		Description = "Win Arena Battle 100 and own the ladder.",
		Objective = "rival",
		Goal = 1,
		RivalId = "gate_100",
		Reward = { Coins = 60000, RandomRarity = "Legendary" },
	},
}

local function questRemote()
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("QuestUpdate")
end

local function collectionRemote()
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CollectionUpdate")
end

function QuestSystem.Sanitize(player: Player)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	local current = data.ActiveQuestId
	if current and LEGACY_QUESTS[current] then
		current = LEGACY_QUESTS[current]
		data.ActiveQuestId = current
		data.QuestProgress = 0
	end
	if current and not QuestSystem.QUESTS[current] then
		data.ActiveQuestId = nil
		for _, id in ipairs(QuestSystem.QUEST_ORDER) do
			if not data.QuestsCompleted[id] then
				data.ActiveQuestId = id
				data.QuestProgress = 0
				break
			end
		end
	end
end

-- Returns (questDef, questId) or (nil, nil).
function QuestSystem.GetActiveQuest(player: Player): (any?, string?)
	QuestSystem.Sanitize(player)
	local data = PlayerData.Get(player)
	if not data or not data.ActiveQuestId then
		return nil, nil
	end
	local quest = QuestSystem.QUESTS[data.ActiveQuestId]
	if not quest then
		return nil, nil
	end
	return quest, data.ActiveQuestId
end

-- Current value of a non-orb objective for this player.
function QuestSystem.GetObjectiveValue(player: Player, objective: string): number
	local data = PlayerData.Get(player)
	if not data then
		return 0
	end
	if objective == "brainrots" then
		return #data.Brainrots
	elseif objective == "workers" then
		local n = 0
		for _ in pairs(data.Jobs) do
			n += 1
		end
		return n
	elseif objective == "materials" then
		return data.LifetimeMaterials or 0
	elseif objective == "fusions" then
		return data.Fusions or 0
	end
	return 0
end

local function pushProgress(player: Player, data: any, quest: any, questId: string)
	questRemote():FireClient(player, {
		Type = "Progress",
		QuestId = questId,
		Name = quest.Name,
		Progress = data.QuestProgress,
		Goal = quest.Goal,
	})
end

-- Orb touches drive "orbs" quests.
function QuestSystem.AddProgress(player: Player, amount: number)
	local data = PlayerData.Get(player)
	if not data or not data.ActiveQuestId then
		return
	end
	local quest = QuestSystem.QUESTS[data.ActiveQuestId]
	if not quest or quest.Objective ~= "orbs" then
		return
	end
	data.QuestProgress = math.min(data.QuestProgress + amount, quest.Goal)
	pushProgress(player, data, quest, data.ActiveQuestId)
	if data.QuestProgress >= quest.Goal then
		QuestSystem.CompleteQuest(player, data.ActiveQuestId)
	end
end

-- Call after game events: "brainrots" (earned), "workers" (assigned),
-- "materials" (collected), "fusions" (fused), "rival" (battle won).
-- For "rival", pass the rivalId as extra.
function QuestSystem.CheckObjective(player: Player, objective: string, extra: any?)
	local data = PlayerData.Get(player)
	if not data or not data.ActiveQuestId then
		return
	end
	local questId = data.ActiveQuestId
	local quest = QuestSystem.QUESTS[questId]
	if not quest or quest.Objective ~= objective then
		return
	end
	if objective == "rival" then
		if quest.RivalId ~= extra then
			return
		end
		data.QuestProgress = quest.Goal
	else
		data.QuestProgress = math.min(QuestSystem.GetObjectiveValue(player, objective), quest.Goal)
	end
	pushProgress(player, data, quest, questId)
	if data.QuestProgress >= quest.Goal then
		QuestSystem.CompleteQuest(player, questId)
	end
end

function QuestSystem.CompleteQuest(player: Player, questId: string)
	local data = PlayerData.Get(player)
	local quest = QuestSystem.QUESTS[questId]
	if not data or not quest then
		return
	end

	data.QuestsCompleted[questId] = true
	data.QuestProgress = 0

	-- Advance to the next quest in the chain.
	data.ActiveQuestId = nil
	for i, id in ipairs(QuestSystem.QUEST_ORDER) do
		if id == questId and i < #QuestSystem.QUEST_ORDER then
			local nextId = QuestSystem.QUEST_ORDER[i + 1]
			if not data.QuestsCompleted[nextId] then
				data.ActiveQuestId = nextId
				break
			end
		end
	end

	local reward = quest.Reward or {}
	local grantedInstance: any = nil
	local inventoryFull = false
	local rewardBrainrotId: string? = reward.BrainrotId
	if reward.RandomRarity then
		rewardBrainrotId = BrainrotData.GetRandomIdOfRarity(reward.RandomRarity)
	end
	if rewardBrainrotId then
		local shiny = math.random() < BrainrotData.SHINY_CHANCE
		local variant = BrainrotData.RollVariant()
		local instance, err = PlayerData.TryAddBrainrot(player, rewardBrainrotId, shiny, variant)
		if instance then
			grantedInstance = instance
		elseif err == "full" then
			-- Kind fallback: convert the reward to coins instead of deleting it.
			inventoryFull = true
			PlayerData.AddCoins(player, 150)
		end
	end
	if reward.Coins then
		PlayerData.AddCoins(player, reward.Coins)
	end

	-- Show the new brainrot on the player's plot immediately.
	PlotSystem.RefreshPlot(player)

	-- Newly unlocked quest may already be satisfied (e.g. own 6 brainrots).
	local newQuest, newQuestId = QuestSystem.GetActiveQuest(player)
	if newQuest and newQuestId then
		if newQuest.Objective == "rival" and newQuest.RivalId then
			if PlayerData.HasBeatenRival(player, newQuest.RivalId) then
				QuestSystem.CheckObjective(player, "rival", newQuest.RivalId)
			end
		elseif newQuest.Objective ~= "orbs" then
			QuestSystem.CheckObjective(player, newQuest.Objective)
		end
	end

	questRemote():FireClient(player, {
		Type = "Completed",
		QuestName = quest.Name,
		BrainrotId = grantedInstance and grantedInstance.BrainrotId or nil,
		Variant = grantedInstance and grantedInstance.Variant or nil,
		Shiny = grantedInstance and grantedInstance.Shiny or false,
		InventoryFull = inventoryFull,
		Coins = reward.Coins or 0,
	})
	collectionRemote():FireClient(player, {
		Brainrots = data.Brainrots,
		Showcase = data.Showcase,
		Coins = data.Coins,
		Working = PlayerData.GetWorkingIds(player),
		Index = data.Index or {},
	})

	PlayerData.Save(player)

	-- Tell the client about the newly active quest (if any).
	if newQuest and newQuestId then
		questRemote():FireClient(player, {
			Type = "Progress",
			QuestId = newQuestId,
			Name = newQuest.Name,
			Progress = data.QuestProgress,
			Goal = newQuest.Goal,
		})
	end
end

return QuestSystem
