--!strict
--[[
	EggSystem (ModuleScript -> ServerScriptService/Systems)
	Mystery eggs: full surprise, no preview. Hatch with active playtime.
	Earned from daily quests. Incubator has limited slots.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local EggSystem = {}

-- Check if player has incubator space.
function EggSystem.HasSpace(player: Player): boolean
	local data = PlayerData.Get(player)
	if not data then return false end
	local count = 0
	for _ in pairs(data.Eggs) do count += 1 end
	return count < (data.IncubatorSlots or BrainrotData.INCUBATOR_SLOTS)
end

-- Give a mystery egg. Returns eggId or nil if full.
function EggSystem.GiveEgg(player: Player, tierId: string): string?
	local data = PlayerData.Get(player)
	if not data then return nil end
	if not BrainrotData.EGG_TIERS[tierId] then return nil end
	if not EggSystem.HasSpace(player) then return nil end
	local eggId = "egg_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
	data.Eggs[eggId] = {
		Tier = tierId,
		Progress = 0, -- playtime minutes accumulated
	}
	return eggId
end

-- Tick egg incubation by playtime minutes. Returns list of hatched egg info.
-- Called periodically by GameServer while player is in-game.
function EggSystem.TickIncubation(player: Player, minutesElapsed: number): { any }
	local data = PlayerData.Get(player)
	if not data then return {} end
	local hatched = {}
	local toRemove = {}
	for eggId, egg in pairs(data.Eggs) do
		local tierDef = BrainrotData.EGG_TIERS[egg.Tier]
		if tierDef then
			egg.Progress = (egg.Progress or 0) + minutesElapsed
			if egg.Progress >= tierDef.HatchMinutes then
				local result = EggSystem.HatchEgg(player, eggId)
				if result then
					table.insert(hatched, result)
				end
				table.insert(toRemove, eggId)
			end
		end
	end
	for _, eggId in ipairs(toRemove) do
		data.Eggs[eggId] = nil
	end
	return hatched
end

-- Hatch an egg into a random brainrot. Full mystery — no preview.
-- Returns { BrainrotName, Rarity, Shiny, InstanceId } or nil.
function EggSystem.HatchEgg(player: Player, eggId: string): any?
	local data = PlayerData.Get(player)
	if not data then return nil end
	local egg = data.Eggs[eggId]
	if not egg then return nil end
	local tierDef = BrainrotData.EGG_TIERS[egg.Tier]
	if not tierDef then return nil end

	-- Roll rarity by weights
	local roll = math.random() * 100
	local cumulative = 0
	local rarity = "Common"
	for _, r in ipairs(BrainrotData.RARITY_ORDER) do
		cumulative += tierDef.Weights[r] or 0
		if roll <= cumulative then
			rarity = r
			break
		end
	end

	-- Pick random brainrot of that rarity
	local candidates = {}
	for _, def in ipairs(BrainrotData.ROSTER) do
		if def.Rarity == rarity then
			table.insert(candidates, def)
		end
	end
	if #candidates == 0 then return nil end
	local picked = candidates[math.random(1, #candidates)]

	-- Roll shiny (standard chance) and variant (20% as usual)
	local shiny = math.random() < BrainrotData.SHINY_CHANCE
	local variantId = nil
	if math.random() < 0.2 then
		local variantKeys = {}
		for k in pairs(BrainrotData.VARIANTS) do table.insert(variantKeys, k) end
		variantId = variantKeys[math.random(1, #variantKeys)]
	end

	local inst, errMsg = PlayerData.TryAddBrainrot(player, picked.Id, shiny, variantId)
	if not inst then
		warn("[EggSystem] Failed to add hatched brainrot: " .. tostring(errMsg))
		return nil
	end

	data.Eggs[eggId] = nil
	data.EggsHatched = (data.EggsHatched or 0) + 1

	-- Record for daily quest
	local DailyQuestSystem = require(script.Parent:WaitForChild("DailyQuestSystem"))
	DailyQuestSystem.RecordProgress(player, "egg_hatched", 1)

	return {
		BrainrotName = picked.Name,
		BrainrotId = picked.Id,
		Rarity = rarity,
		RarityColor = BrainrotData.RARITY_COLORS[rarity],
		Shiny = shiny,
		Variant = variantId,
		InstanceId = inst.InstanceId,
	}
end

-- Buy an extra incubator slot with coins. Returns (success, message).
function EggSystem.BuySlot(player: Player): (boolean, string?)
	local data = PlayerData.Get(player)
	if not data then return false, "No data" end
	local current = data.IncubatorSlots or BrainrotData.INCUBATOR_SLOTS
	local cost = 500 * current -- escalating: 1500, 2000, 2500...
	if not PlayerData.SpendCoins(player, cost) then
		return false, "Need " .. tostring(cost) .. " coins"
	end
	data.IncubatorSlots = current + 1
	return true
end

-- Get egg status for UI.
function EggSystem.GetStatus(player: Player): any
	local data = PlayerData.Get(player)
	if not data then return { Eggs = {}, Slots = 0 } end
	local eggs = {}
	for eggId, egg in pairs(data.Eggs) do
		local tierDef = BrainrotData.EGG_TIERS[egg.Tier]
		if tierDef then
			table.insert(eggs, {
				Id = eggId,
				Tier = egg.Tier,
				TierName = tierDef.Name,
				Color = tierDef.Color,
				Progress = egg.Progress or 0,
				Needed = tierDef.HatchMinutes,
				Percent = math.min(1, (egg.Progress or 0) / tierDef.HatchMinutes),
			})
		end
	end
	return {
		Eggs = eggs,
		Slots = data.IncubatorSlots or BrainrotData.INCUBATOR_SLOTS,
		UsedSlots = #eggs,
		Hatched = data.EggsHatched or 0,
	}
end

return EggSystem
