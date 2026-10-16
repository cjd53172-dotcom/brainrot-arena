--!strict
--[[
	WanderSystem (ModuleScript -> ServerScriptService/Systems)
	Wild brainrots wander the world. Each player sees their own spawns.
	Touch to catch. Higher rarity = faster, runs away, despawns sooner.
	Legendary spawns are server-wide events with a light beam.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local WanderSystem = {}

-- Active wanderers: [userId] = { [wanderId] = { BrainrotId, Rarity, Model, SpawnTime, DespawnTime } }
local wanderers: { [number]: { [string]: any } } = {}

-- Rarity spawn weights and timing (tuned for dopamine, not too easy)
local RARITY_CONFIG = {
	Common = {
		Weight = 60,
		RespawnSecs = { 60, 120 },   -- every 1-2 min
		DespawnSecs = 600,            -- 10 min to catch
		WalkSpeed = 4,                -- slow waddle
		FleeRadius = 0,               -- doesn't run
	},
	Rare = {
		Weight = 25,
		RespawnSecs = { 240, 360 },   -- every 4-6 min
		DespawnSecs = 480,            -- 8 min
		WalkSpeed = 8,
		FleeRadius = 6,
	},
	Epic = {
		Weight = 12,
		RespawnSecs = { 900, 1500 },  -- every 15-25 min
		DespawnSecs = 360,            -- 6 min
		WalkSpeed = 12,
		FleeRadius = 10,
	},
	Legendary = {
		Weight = 3,
		RespawnSecs = { 3600, 5400 }, -- every 60-90 min
		DespawnSecs = 180,            -- 3 min URGENCY
		WalkSpeed = 16,               -- very fast
		FleeRadius = 15,
		Announce = true,              -- server-wide beam + message
	},
}

WanderSystem.MAX_WANDERERS = 8

-- Roll a rarity by weight. luckMult boosts Rare+ weights.
local function rollRarity(luckMult: number?): string
	luckMult = luckMult or 1
	local weights = {}
	local total = 0
	for rarity, cfg in pairs(RARITY_CONFIG) do
		local w = cfg.Weight
		if rarity ~= "Common" then
			w *= luckMult
		end
		weights[rarity] = w
		total += w
	end
	local roll = math.random() * total
	local cumulative = 0
	for rarity, w in pairs(weights) do
		cumulative += w
		if roll <= cumulative then
			return rarity
		end
	end
	return "Common"
end

-- Get or create wanderer list for player.
local function getWanderers(player: Player): { [string]: any }
	local userId = player.UserId
	if not wanderers[userId] then
		wanderers[userId] = {}
	end
	return wanderers[userId]
end

-- Spawn a wild brainrot for a player. Returns wanderId or nil.
-- luckMult: from Lucky Charm upgrade (boosts Rare+ odds).
function WanderSystem.SpawnWild(player: Player, plotSystem: any, luckMult: number?): string?
	local list = getWanderers(player)
	-- Count active
	local count = 0
	for _ in pairs(list) do count += 1 end
	if count >= WanderSystem.MAX_WANDERERS then
		return nil
	end

	local rarity = rollRarity(luckMult)
	local brainrotId = BrainrotData.GetRandomIdOfRarity(rarity)
	if not brainrotId then return nil end

	local wanderId = "wild_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
	local cfg = RARITY_CONFIG[rarity]

	-- Spawn position: ring OUTSIDE the plot cluster (plots span ~±50).
	-- Ring: 70-130 studs from gameplay center, so wilds roam the world, not the plots.
	local angle = math.random() * math.pi * 2
	local dist = 70 + math.random() * 60
	local cx = 127 + math.cos(angle) * dist
	local cz = 98 + math.sin(angle) * dist

	list[wanderId] = {
		BrainrotId = brainrotId,
		Rarity = rarity,
		Config = cfg,
		SpawnTime = os.time(),
		DespawnTime = os.time() + cfg.DespawnSecs,
		SpawnPos = Vector3.new(cx, 20, cz),
		Model = nil, -- set by GameServer after building visual
		Announced = false,
	}

	return wanderId
end

-- Get wanderer info.
function WanderSystem.GetWanderer(player: Player, wanderId: string): any?
	local list = getWanderers(player)
	return list[wanderId]
end

-- Catch a wild brainrot. Returns reward info or nil.
function WanderSystem.Catch(player: Player, wanderId: string): any?
	local list = getWanderers(player)
	local wander = list[wanderId]
	if not wander then return nil end

	-- Remove from active
	list[wanderId] = nil

	-- Grant the brainrot
	local shiny = math.random() < BrainrotData.SHINY_CHANCE
	local variant = BrainrotData.RollVariant()
	local inst, err = PlayerData.TryAddBrainrot(player, wander.BrainrotId, shiny, variant)

	local def = BrainrotData.GetBrainrot(wander.BrainrotId)
	if inst then
		-- Daily quest progress (counts as orb-like acquisition)
		local DailyQuestSystem = require(script.Parent:WaitForChild("DailyQuestSystem"))
		DailyQuestSystem.RecordProgress(player, "orbs", 1)

		return {
			Success = true,
			BrainrotId = wander.BrainrotId,
			BrainrotName = def and def.Name or "?",
			Rarity = wander.Rarity,
			RarityColor = BrainrotData.RARITY_COLORS[wander.Rarity],
			Shiny = shiny,
			Variant = variant,
		}
	else
		return {
			Success = false,
			Message = err == "full" and "Inventory full!" or "Could not catch",
		}
	end
end

-- Remove a wanderer (despawned or caught). Returns the wanderer data.
function WanderSystem.Remove(player: Player, wanderId: string): any?
	local list = getWanderers(player)
	local wander = list[wanderId]
	list[wanderId] = nil
	return wander
end

-- Check for despawns. Returns list of { Player, WanderId } to clean up.
function WanderSystem.TickDespawn(): { any }
	local toRemove = {}
	local now = os.time()
	for userId, list in pairs(wanderers) do
		for wanderId, wander in pairs(list) do
			if now >= wander.DespawnTime then
				table.insert(toRemove, { UserId = userId, WanderId = wanderId })
			end
		end
	end
	-- Actually remove them
	for _, item in ipairs(toRemove) do
		if wanderers[item.UserId] then
			wanderers[item.UserId][item.WanderId] = nil
		end
	end
	return toRemove
end

-- Cleanup when player leaves.
function WanderSystem.ClearPlayer(player: Player)
	wanderers[player.UserId] = nil
end

-- Get rarity config for tuning UI.
function WanderSystem.GetRarityConfig(rarity: string): any?
	return RARITY_CONFIG[rarity]
end

return WanderSystem
