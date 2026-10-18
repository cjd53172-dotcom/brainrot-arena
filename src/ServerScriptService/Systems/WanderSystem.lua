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
		RespawnSecs = { 20, 40 },    -- every 20-40 sec
		DespawnSecs = 600,            -- 10 min to catch
		WalkSpeed = 4,                -- slow waddle
		FleeRadius = 0,               -- doesn't run
	},
	Rare = {
		Weight = 25,
		RespawnSecs = { 80, 120 },    -- every 1.5-2 min
		DespawnSecs = 480,            -- 8 min
		WalkSpeed = 8,
		FleeRadius = 6,
	},
	Epic = {
		Weight = 12,
		RespawnSecs = { 300, 500 },   -- every 5-8 min
		DespawnSecs = 360,            -- 6 min
		WalkSpeed = 12,
		FleeRadius = 10,
	},
	Legendary = {
		Weight = 3,
		RespawnSecs = { 1200, 1800 },
		DespawnSecs = 180,
		WalkSpeed = 16,
		FleeRadius = 15,
		Announce = true,
	},
	Mythic = {
		Weight = 1.2,
		RespawnSecs = { 1800, 2800 },
		DespawnSecs = 150,
		WalkSpeed = 18,
		FleeRadius = 16,
		Announce = true,
	},
}

WanderSystem.MAX_WANDERERS = 16
WanderSystem.EventActive = false

function WanderSystem.SetEventActive(active: boolean)
	WanderSystem.EventActive = active
end

function WanderSystem.GetMaxWanderers(): number
	return if WanderSystem.EventActive then 52 else WanderSystem.MAX_WANDERERS
end

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
function WanderSystem.SpawnWild(player: Player, plotSystem: any, luckMult: number?, forceRarity: string?, eventRush: boolean?): string?
	local list = getWanderers(player)
	-- Count active
	local count = 0
	for _ in pairs(list) do count += 1 end
	if count >= WanderSystem.GetMaxWanderers() then
		return nil
	end

	local rarity = forceRarity or rollRarity(luckMult)
	if BrainrotData.IsFusionOnlyRarity(rarity) then
		rarity = "Mythic"
	end
	local brainrotId = BrainrotData.GetRandomIdOfRarity(rarity)
	if not brainrotId then return nil end

	local wanderId = "wild_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
	local baseCfg = RARITY_CONFIG[rarity]
	local cfg = {
		Weight = baseCfg.Weight,
		RespawnSecs = baseCfg.RespawnSecs,
		DespawnSecs = if eventRush then 90 else baseCfg.DespawnSecs,
		WalkSpeed = if eventRush then (if rarity == "Legendary" then 11 else 8) else baseCfg.WalkSpeed,
		FleeRadius = if eventRush then (if rarity == "Legendary" then 8 else 6) else baseCfg.FleeRadius,
		Announce = eventRush or baseCfg.Announce,
	}

	-- Spawn position: ring OUTSIDE the plot cluster (plots span ~±50).
	-- Ring: 70-130 studs from gameplay center, so wilds roam the world, not the plots.
	-- Event rush: spawn near the player so they can actually catch them.
	local angle = math.random() * math.pi * 2
	local dist = 70 + math.random() * 60
	local cx = 127 + math.cos(angle) * dist
	local cz = 98 + math.sin(angle) * dist
	if eventRush then
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			dist = 16 + math.random() * 22
			cx = hrp.Position.X + math.cos(angle) * dist
			cz = hrp.Position.Z + math.sin(angle) * dist
		end
	end

	list[wanderId] = {
		BrainrotId = brainrotId,
		Rarity = rarity,
		Config = cfg,
		SpawnTime = os.time(),
		DespawnTime = os.time() + cfg.DespawnSecs,
		SpawnPos = Vector3.new(cx, 20, cz),
		Model = nil, -- set by GameServer after building visual
		Announced = false,
		EventRush = eventRush == true,
		Variant = BrainrotData.RollVariant(),
		Shiny = math.random() < BrainrotData.SHINY_CHANCE,
	}

	return wanderId
end

function WanderSystem.ForceSpawn(player: Player, brainrotId: string, spawnPos: Vector3?, despawnSecs: number?, variantId: string?): string?
	local def = BrainrotData.GetById(brainrotId)
	if not def then
		return nil
	end
	local rarity = def.Rarity
	local baseCfg = RARITY_CONFIG[rarity] or RARITY_CONFIG.Common
	if not baseCfg then
		return nil
	end
	local list = getWanderers(player)
	local wanderId = "wild_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
	local angle = math.random() * math.pi * 2
	local dist = 16 + math.random() * 22
	local cx = 127
	local cz = 98
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if spawnPos then
		cx = spawnPos.X
		cz = spawnPos.Z
	elseif hrp and hrp:IsA("BasePart") then
		cx = hrp.Position.X + math.cos(angle) * dist
		cz = hrp.Position.Z + math.sin(angle) * dist
	end
	list[wanderId] = {
		BrainrotId = def.Id,
		Rarity = if RARITY_CONFIG[rarity] then rarity else "Common",
		Config = {
			Weight = baseCfg.Weight,
			RespawnSecs = baseCfg.RespawnSecs,
			DespawnSecs = despawnSecs or 600,
			WalkSpeed = 4,
			FleeRadius = 0,
			Announce = false,
		},
		SpawnTime = os.time(),
		DespawnTime = os.time() + (despawnSecs or 600),
		SpawnPos = Vector3.new(cx, 20, cz),
		Model = nil,
		Announced = false,
		EventRush = true,
		Variant = variantId,
		Shiny = false,
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

	local shiny = wander.Shiny == true
	local variant = wander.Variant
	local inst, err = PlayerData.TryAddBrainrot(player, wander.BrainrotId, shiny, variant)

	local def = BrainrotData.GetBrainrot(wander.BrainrotId)
	if inst then
		-- Daily quest progress (counts as orb-like acquisition)
		local DailyQuestSystem = require(script.Parent:WaitForChild("DailyQuestSystem"))
		DailyQuestSystem.RecordProgress(player, "orbs", 1)

		return {
			Success = true,
			BrainrotId = wander.BrainrotId,
			BrainrotName = def and BrainrotData.GetDisplayName(def, variant, shiny) or "?",
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

-- Remove event-only legendaries and epics. Returns { UserId, WanderId } for visuals.
function WanderSystem.ClearEventRush(): { any }
	local toRemove = {}
	for userId, list in pairs(wanderers) do
		for wanderId, wander in pairs(list) do
			if wander.EventRush == true then
				table.insert(toRemove, { UserId = userId, WanderId = wanderId })
			end
		end
	end
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
