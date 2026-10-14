--!strict
--[[
	DailyQuestSystem (ModuleScript -> ServerScriptService/Systems)
	Three quest tiers per day (easy/medium/hard). Each tier completion
	awards a mystery egg. Completing all three gives a bonus.
	Resets daily at midnight (server-local date).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local DailyQuestSystem = {}

local function todayString(): string
	return os.date("%Y-%m-%d", os.time())
end

-- Roll today's quests if not already done. Called on player join and on request.
function DailyQuestSystem.EnsureToday(player: Player)
	local data = PlayerData.Get(player)
	if not data then return end
	local today = todayString()
	if data.DailyDate == today then return end -- already rolled
	data.DailyDate = today
	data.DailyQuests = {}
	data.DailyEggsClaimed = {}
	data.DailyAllComplete = false
	-- Pick one random quest per tier
	for tier, tierDef in pairs(BrainrotData.DAILY_TIERS) do
		local pool = BrainrotData.DAILY_QUEST_POOL[tier]
		if pool and #pool > 0 then
			local pick = pool[math.random(1, #pool)]
			data.DailyQuests[tier] = {
				Text = pick.Text,
				Target = pick.Target,
				Progress = 0,
				Done = false,
				Coins = pick.Coins,
				EggReward = tierDef.EggReward,
			}
		end
	end
end

-- Record progress toward daily quests. eventType matches quest triggers.
-- Supported: "obby_coins", "orbs", "workstation_collect", "battle_win",
--            "expedition_complete", "fuse", "coins_earned", "egg_hatched"
function DailyQuestSystem.RecordProgress(player: Player, eventType: string, amount: number)
	local data = PlayerData.Get(player)
	if not data then return end
	DailyQuestSystem.EnsureToday(player)
	amount = amount or 1
	-- Map event types to quest text keywords
	local keywordMap = {
		obby_coins = "obby",
		orbs = "Orbs",
		workstation_collect = "workstation",
		battle_win = "battle",
		expedition_complete = "expedition",
		fuse = "Fuse",
		coins_earned = "Earn",
		egg_hatched = "egg",
	}
	local keyword = keywordMap[eventType]
	if not keyword then return end
	for tier, quest in pairs(data.DailyQuests) do
		if not quest.Done and string.find(quest.Text, keyword) then
			quest.Progress = math.min(quest.Target, quest.Progress + amount)
			if quest.Progress >= quest.Target then
				quest.Done = true
				-- Auto-grant coin reward
				PlayerData.AddCoins(player, quest.Coins)
			end
		end
	end
	-- Check all-complete bonus
	local allDone = true
	for _, quest in pairs(data.DailyQuests) do
		if not quest.Done then allDone = false break end
	end
	if allDone and not data.DailyAllComplete then
		data.DailyAllComplete = true
	end
end

-- Claim the egg reward for a completed tier. Returns (success, message).
function DailyQuestSystem.ClaimEgg(player: Player, tier: string): (boolean, string?)
	local data = PlayerData.Get(player)
	if not data then return false, "No data" end
	DailyQuestSystem.EnsureToday(player)
	local quest = data.DailyQuests[tier]
	if not quest then return false, "Invalid tier" end
	if not quest.Done then return false, "Quest not complete" end
	if data.DailyEggsClaimed[tier] then return false, "Already claimed" end
	-- Check incubator space (via EggSystem)
	local EggSystem = require(script.Parent:WaitForChild("EggSystem"))
	if not EggSystem.HasSpace(player) then
		return false, "Incubator full"
	end
	data.DailyEggsClaimed[tier] = true
	EggSystem.GiveEgg(player, quest.EggReward)
	return true
end

-- Get daily quest status for UI.
function DailyQuestSystem.GetStatus(player: Player): any
	local data = PlayerData.Get(player)
	if not data then return { Quests = {} } end
	DailyQuestSystem.EnsureToday(player)
	local quests = {}
	for tier, tierDef in pairs(BrainrotData.DAILY_TIERS) do
		local q = data.DailyQuests[tier]
		if q then
			table.insert(quests, {
				Tier = tier,
				TierName = tierDef.Name,
				TierColor = tierDef.Color,
				Text = q.Text,
				Target = q.Target,
				Progress = q.Progress,
				Done = q.Done,
				Coins = q.Coins,
				EggReward = q.EggReward,
				EggClaimed = data.DailyEggsClaimed[tier] == true,
			})
		end
	end
	-- Sort: easy, medium, hard
	table.sort(quests, function(a, b)
		local order = { easy = 1, medium = 2, hard = 3 }
		return (order[a.Tier] or 99) < (order[b.Tier] or 99)
	end)
	return {
		Quests = quests,
		AllComplete = data.DailyAllComplete == true,
		Date = data.DailyDate,
	}
end

return DailyQuestSystem
