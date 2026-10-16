--!strict
--[[
	AchievementSystem (ModuleScript -> ServerScriptService/Systems)
	Long-term goals with coin/brainrot rewards.
	Progress tracked per player, persisted in PlayerData.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local AchievementSystem = {}

-- Achievement definitions
-- ProgressKey: what to track, Target: goal, Reward: { Coins, BrainrotId?, RandomRarity? }
AchievementSystem.DEFS = {
	-- Catching
	first_catch = {
		Name = "🎣 First Catch!",
		Desc = "Catch your first wild brainrot",
		ProgressKey = "wild_caught", Target = 1,
		Reward = { Coins = 100 },
	},
	catch_10 = {
		Name = "🌿 Nature Lover",
		Desc = "Catch 10 wild brainrots",
		ProgressKey = "wild_caught", Target = 10,
		Reward = { Coins = 500 },
	},
	catch_50 = {
		Name = "🏹 Expert Tracker",
		Desc = "Catch 50 wild brainrots",
		ProgressKey = "wild_caught", Target = 50,
		Reward = { Coins = 2000, RandomRarity = "Rare" },
	},
	catch_rare = {
		Name = "💎 Rare Hunter",
		Desc = "Catch a Rare wild brainrot",
		ProgressKey = "rare_caught", Target = 1,
		Reward = { Coins = 300 },
	},
	catch_epic = {
		Name = "⚡ Epic Encounter",
		Desc = "Catch an Epic wild brainrot",
		ProgressKey = "epic_caught", Target = 1,
		Reward = { Coins = 1000 },
	},
	catch_legendary = {
		Name = "🌟 Legendary!",
		Desc = "Catch a Legendary wild brainrot",
		ProgressKey = "legendary_caught", Target = 1,
		Reward = { Coins = 5000, RandomRarity = "Epic" },
	},

	-- Battles
	first_win = {
		Name = "⚔️ First Victory",
		Desc = "Win your first arena battle",
		ProgressKey = "battles_won", Target = 1,
		Reward = { Coins = 200 },
	},
	win_10 = {
		Name = "🛡️ Arena Regular",
		Desc = "Win 10 arena battles",
		ProgressKey = "battles_won", Target = 10,
		Reward = { Coins = 1000 },
	},
	win_25 = {
		Name = "👑 Arena Champion",
		Desc = "Win 25 arena battles",
		ProgressKey = "battles_won", Target = 25,
		Reward = { Coins = 3000, RandomRarity = "Rare" },
	},
	beat_campione = {
		Name = "🏆 Dethroned!",
		Desc = "Defeat Campione, the final rival",
		ProgressKey = "campione_beaten", Target = 1,
		Reward = { Coins = 5000, RandomRarity = "Epic" },
	},

	-- Collection
	collect_10 = {
		Name = "📦 Collector",
		Desc = "Own 10 different brainrots",
		ProgressKey = "unique_owned", Target = 10,
		Reward = { Coins = 500 },
	},
	collect_25 = {
		Name = "📚 Archivist",
		Desc = "Own 25 different brainrots",
		ProgressKey = "unique_owned", Target = 25,
		Reward = { Coins = 1500, RandomRarity = "Rare" },
	},
	shiny_found = {
		Name = "✨ Shiny!",
		Desc = "Obtain a shiny brainrot",
		ProgressKey = "shinies", Target = 1,
		Reward = { Coins = 2000 },
	},

	-- Other
	first_fusion = {
		Name = "⚗️ Alchemist",
		Desc = "Perform your first fusion",
		ProgressKey = "fusions", Target = 1,
		Reward = { Coins = 300 },
	},
	egg_hatched = {
		Name = "🥚 New Life",
		Desc = "Hatch a mystery egg",
		ProgressKey = "eggs_hatched", Target = 1,
		Reward = { Coins = 400 },
	},
	expedition_done = {
		Name = "🗺️ Explorer",
		Desc = "Complete an expedition",
		ProgressKey = "expeditions", Target = 1,
		Reward = { Coins = 400 },
	},
	fish_caught = {
		Name = "🎣 Gone Fishing",
		Desc = "Catch 10 fish",
		ProgressKey = "fish_caught", Target = 10,
		Reward = { Coins = 300 },
	},
	rich = {
		Name = "💰 Tycoon",
		Desc = "Hold 50,000 coins at once",
		ProgressKey = "max_coins", Target = 50000,
		Reward = { RandomRarity = "Epic" },
	},
}

-- Get or init achievement data for player.
local function getData(player: Player): any
	local data = PlayerData.Get(player)
	if not data then return nil end
	if not data.Achievements then
		data.Achievements = { Progress = {}, Completed = {} }
	end
	return data.Achievements
end

-- Record progress toward achievements. Returns newly completed achievement IDs.
function AchievementSystem.RecordProgress(player: Player, key: string, amount: number): { string }
	local achData = getData(player)
	if not achData then return {} end

	achData.Progress[key] = (achData.Progress[key] or 0) + amount
	local newlyCompleted = {}

	for achId, def in pairs(AchievementSystem.DEFS) do
		if def.ProgressKey == key and not achData.Completed[achId] then
			if (achData.Progress[key] or 0) >= def.Target then
				achData.Completed[achId] = true
				table.insert(newlyCompleted, achId)
				-- Grant reward
				local reward = def.Reward
				if reward.Coins then
					PlayerData.AddCoins(player, reward.Coins)
				end
				if reward.RandomRarity then
					local brainrotId = BrainrotData.GetRandomIdOfRarity(reward.RandomRarity)
					if brainrotId then
						PlayerData.TryAddBrainrot(player, brainrotId, false, BrainrotData.RollVariant())
					end
				end
				if reward.BrainrotId then
					PlayerData.TryAddBrainrot(player, reward.BrainrotId, false, BrainrotData.RollVariant())
				end
			end
		end
	end

	if #newlyCompleted > 0 then
		PlayerData.Save(player)
	end

	return newlyCompleted
end

-- Set a progress value directly (for max-type achievements).
function AchievementSystem.SetProgress(player: Player, key: string, value: number): { string }
	local achData = getData(player)
	if not achData then return {} end
	local current = achData.Progress[key] or 0
	if value > current then
		return AchievementSystem.RecordProgress(player, key, value - current)
	end
	return {}
end

-- Get achievement state for UI.
function AchievementSystem.GetState(player: Player): any
	local achData = getData(player)
	if not achData then return { Progress = {}, Completed = {} } end
	return {
		Progress = achData.Progress,
		Completed = achData.Completed,
	}
end

return AchievementSystem
