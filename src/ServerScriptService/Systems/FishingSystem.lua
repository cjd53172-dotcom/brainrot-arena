--!strict
--[[
	FishingSystem (ModuleScript -> ServerScriptService/Systems)
	Interactive fishing: cast at spots, wait for bite, reel with timing.
	Rewards: Fish materials, coins, rare materials, and water brainrots!
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local FishingSystem = {}

-- Active fishing sessions: [userId] = { SpotId, CastTime, BiteTime, State }
local sessions: { [number]: any } = {}

-- Reward table: roll -> reward
-- Common: Fish x3-5, Uncommon: coins, Rare: Pearl Shard, Epic: water brainrot, Legendary: Sunken Gold
local function rollReward(): any
	local roll = math.random() * 100
	if roll < 45 then
		return { Kind = "Fish", Amount = math.random(3, 6) }
	elseif roll < 70 then
		return { Kind = "Coins", Amount = math.random(20, 60) }
	elseif roll < 85 then
		return { Kind = "Material", Name = "Pearl Shard", Amount = math.random(1, 2) }
	elseif roll < 97 then
		-- Water brainrot!
		local candidates = {}
		for _, def in ipairs(BrainrotData.ROSTER) do
			if def.Type == "Water" and not BrainrotData.IsFusionOnlyRarity(def.Rarity) then
				table.insert(candidates, def)
			end
		end
		if #candidates > 0 then
			local picked = candidates[math.random(1, #candidates)]
			-- Weighted rarity: mostly Common/Rare water types
			return { Kind = "Brainrot", BrainrotId = picked.Id }
		else
			return { Kind = "Fish", Amount = math.random(3, 6) }
		end
	else
		return { Kind = "Material", Name = "Sunken Gold", Amount = 1 }
	end
end

-- Start fishing at a spot. Returns bite delay in seconds.
function FishingSystem.Cast(player: Player, spotId: string): number?
	if sessions[player.UserId] then
		return nil -- already fishing
	end
	-- Bite in 5-15 seconds
	local biteDelay = math.random(5, 15)
	sessions[player.UserId] = {
		SpotId = spotId,
		CastTime = os.clock(),
		BiteTime = os.clock() + biteDelay,
		State = "Waiting", -- Waiting -> Bite -> (Reel or Miss)
	}
	return biteDelay
end

-- Check if fish is biting. Called by client polling or server tick.
function FishingSystem.CheckBite(player: Player): string
	local session = sessions[player.UserId]
	if not session then return "None" end
	if session.State == "Waiting" and os.clock() >= session.BiteTime then
		session.State = "Bite"
		session.BiteExpire = os.clock() + 3 -- 3 seconds to reel!
		return "Bite"
	elseif session.State == "Bite" then
		if os.clock() >= session.BiteExpire then
			session.State = "Missed"
			return "Missed"
		end
		return "Bite"
	end
	return session.State
end

-- Reel in. timingQuality 0-1 (from client minigame). Returns reward or nil.
function FishingSystem.Reel(player: Player, timingQuality: number): any?
	local session = sessions[player.UserId]
	if not session then return nil end
	sessions[player.UserId] = nil

	if session.State ~= "Bite" then
		return { Kind = "Miss", Message = "Too slow! It got away..." }
	end

	-- Timing affects reward quality: perfect timing boosts rare chances
	local reward = rollReward()
	if timingQuality >= 0.9 and reward.Kind == "Fish" then
		-- Perfect timing upgrades fish to Pearl Shard
		reward = { Kind = "Material", Name = "Pearl Shard", Amount = 1 }
	elseif timingQuality < 0.3 then
		-- Poor timing: 50% chance to lose it
		if math.random() < 0.5 then
			return { Kind = "Miss", Message = "It slipped off the hook!" }
		end
	end

	-- Grant reward
	if reward.Kind == "Fish" then
		local data = PlayerData.Get(player)
		if data then
			-- Fish is a workstation material
			data.Materials.fishing = math.min(
				BrainrotData.MATERIAL_CAP,
				(data.Materials.fishing or 0) + reward.Amount
			)
		end
	elseif reward.Kind == "Coins" then
		PlayerData.AddCoins(player, reward.Amount)
		local DailyQuestSystem = require(script.Parent:WaitForChild("DailyQuestSystem"))
		DailyQuestSystem.RecordProgress(player, "coins_earned", reward.Amount)
	elseif reward.Kind == "Material" then
		PlayerData.AddRareMaterial(player, reward.Name, reward.Amount)
	elseif reward.Kind == "Brainrot" then
		local shiny = math.random() < BrainrotData.SHINY_CHANCE
		local variant = BrainrotData.RollVariant()
		local inst, err = PlayerData.TryAddBrainrot(player, reward.BrainrotId, shiny, variant)
		if inst then
			local def = BrainrotData.GetBrainrot(reward.BrainrotId)
			reward.BrainrotName = def and BrainrotData.GetDisplayName(def, variant, shiny) or "?"
			reward.Shiny = shiny
			reward.Variant = variant
			reward.Rarity = def and def.Rarity or "Common"
		else
			-- Inventory full: give coins instead
			reward = { Kind = "Coins", Amount = 100, Message = "Inventory full! +100 coins instead." }
			PlayerData.AddCoins(player, 100)
		end
	end

	return reward
end

-- Cancel fishing (player walked away).
function FishingSystem.Cancel(player: Player)
	sessions[player.UserId] = nil
end

-- Get session state for UI.
function FishingSystem.GetState(player: Player): string
	local session = sessions[player.UserId]
	if not session then return "None" end
	return FishingSystem.CheckBite(player)
end

return FishingSystem
