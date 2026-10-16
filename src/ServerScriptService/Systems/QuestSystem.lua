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
	"rival_rocco",
	"rival_marina",
	"rival_bruno",
	"rival_umbra",
	"rival_campione",
}

QuestSystem.QUESTS = {
	first_steps = {
		Name = "First Steps",
		Description = "Catch 1 wild brainrot roaming the world.",
		Objective = "brainrots",
		Goal = 1,
		Reward = { BrainrotId = "tung_sahur", Coins = 50 },
	},
	growing_team = {
		Name = "Growing Team",
		Description = "Own 4 brainrots.",
		Objective = "brainrots",
		Goal = 4,
		Reward = { Coins = 100 },
	},
	clock_in = {
		Name = "Clock In",
		Description = "Assign 1 brainrot to work at a station on your plot.",
		Objective = "workers",
		Goal = 1,
		Reward = { Coins = 75 },
	},
	material_gatherer = {
		Name = "Material Gatherer",
		Description = "Collect 30 materials from your workstations.",
		Objective = "materials",
		Goal = 30,
		Reward = { RandomRarity = "Rare" },
	},
	fusion_discovery = {
		Name = "Fusion Discovery",
		Description = "Fuse 3 duplicates at the Fusion Lab on your plot.",
		Objective = "fusions",
		Goal = 1,
		Reward = { Coins = 150 },
	},
	arena_entrant = {
		Name = "Arena Entrant",
		Description = "Own 6 brainrots, then face the arena rivals.",
		Objective = "brainrots",
		Goal = 6,
		Reward = { Coins = 100 },
	},
	rival_rocco = {
		Name = "Rival: Rocco the Rookie",
		Description = "Defeat Rocco the Rookie in a 3v3 arena battle.",
		Objective = "rival",
		Goal = 1,
		RivalId = "rocco",
		Reward = { Coins = 200 },
	},
	rival_marina = {
		Name = "Rival: Marina",
		Description = "Defeat Marina, Tidecaller of the plaza.",
		Objective = "rival",
		Goal = 1,
		RivalId = "marina",
		Reward = { Coins = 100, RandomRarity = "Epic" },
	},
	rival_bruno = {
		Name = "Rival: Chef Bruno",
		Description = "Defeat Chef Bruno. He cooks his opponents.",
		Objective = "rival",
		Goal = 1,
		RivalId = "bruno",
		Reward = { Coins = 400 },
	},
	rival_umbra = {
		Name = "Rival: Umbra",
		Description = "Defeat Umbra and silence the whispers.",
		Objective = "rival",
		Goal = 1,
		RivalId = "umbra",
		Reward = { Coins = 600 },
	},
	rival_campione = {
		Name = "Rival: Campione",
		Description = "Defeat Campione, the undisputed plaza champion.",
		Objective = "rival",
		Goal = 1,
		RivalId = "campione",
		Reward = { Coins = 1000, RandomRarity = "Legendary" },
	},
}

local function questRemote()
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("QuestUpdate")
end

local function collectionRemote()
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CollectionUpdate")
end

-- Returns (questDef, questId) or (nil, nil).
function QuestSystem.GetActiveQuest(player: Player): (any?, string?)
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
	if newQuest and newQuestId and newQuest.Objective ~= "orbs" and newQuest.Objective ~= "rival" then
		QuestSystem.CheckObjective(player, newQuest.Objective)
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
