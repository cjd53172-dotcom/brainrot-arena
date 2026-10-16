--!strict
--[[
	ExpeditionSystem (ModuleScript -> ServerScriptService/Systems)
	Send 1-3 brainrots on 15-minute gathering expeditions to zones.
	Type-matched teams earn bonus materials. Rewards rare zone materials.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local ExpeditionSystem = {}

-- Start an expedition. Returns (success, message).
function ExpeditionSystem.StartExpedition(player: Player, zoneId: string, teamIds: { string }): (boolean, string?)
	local data = PlayerData.Get(player)
	local zone = BrainrotData.ZONES[zoneId]
	if not data or not zone then
		return false, "Invalid zone"
	end
	if not data.UnlockedZones[zoneId] then
		return false, "Zone not discovered yet"
	end
	if #teamIds < BrainrotData.EXPEDITION_TEAM_MIN or #teamIds > BrainrotData.EXPEDITION_TEAM_MAX then
		return false, "Team must be 1-3 brainrots"
	end
	-- Validate each team member is available
	for _, instanceId in ipairs(teamIds) do
		if not PlayerData.IsAvailableForExpedition(player, instanceId) then
			return false, "A brainrot is not available"
		end
	end
	-- One expedition per zone at a time (per player)
	for _, exp in pairs(data.Expeditions) do
		if exp.Zone == zoneId then
			return false, "Already exploring there"
		end
	end

	local expId = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
	data.Expeditions[expId] = {
		Zone = zoneId,
		Team = teamIds,
		StartTime = os.time(),
		Duration = BrainrotData.EXPEDITION_DURATION,
	}
	return true
end

-- Check for completed expeditions, grant rewards. Returns list of results.
function ExpeditionSystem.TickExpeditions(player: Player): { any }
	local data = PlayerData.Get(player)
	if not data then return {} end
	local results = {}
	local now = os.time()
	local toRemove = {}
	for expId, exp in pairs(data.Expeditions) do
		if now - exp.StartTime >= exp.Duration then
			local result = ExpeditionSystem.CompleteExpedition(player, exp)
			table.insert(results, result)
			table.insert(toRemove, expId)
		end
	end
	for _, expId in ipairs(toRemove) do
		data.Expeditions[expId] = nil
	end
	return results
end

-- Calculate and grant rewards for a finished expedition.
function ExpeditionSystem.CompleteExpedition(player: Player, exp: any): any
	local data = PlayerData.Get(player)
	local zone = BrainrotData.ZONES[exp.Zone]
	local result = {
		Zone = exp.Zone,
		ZoneName = zone and zone.Name or "Unknown",
		Materials = {},
		Coins = 0,
		TypeBonus = false,
	}

	-- Base material count scales with team size
	local teamSize = #exp.Team
	local baseCount = math.floor(BrainrotData.EXPEDITION_BASE_MATS * (0.7 + 0.3 * teamSize))

	-- Type bonus: if any team member matches zone FavoredType, 1.5x
	local hasTypeMatch = false
	for _, instanceId in ipairs(exp.Team) do
		local inst = PlayerData.GetInstance(player, instanceId)
		if inst then
			local def = BrainrotData.GetBrainrot(inst.BrainrotId)
			if def then
				local effType = BrainrotData.GetEffectiveType(def, inst.Variant)
				if effType == zone.FavoredType then
					hasTypeMatch = true
					break
				end
			end
		end
	end
	if hasTypeMatch then
		baseCount = math.floor(baseCount * BrainrotData.EXPEDITION_TYPE_BONUS)
		result.TypeBonus = true
	end

	-- Distribute across zone materials (weighted: first = common, rest = rarer)
	local mats = zone.Materials
	for i = 1, baseCount do
		local roll = math.random()
		local matName: string
		if roll < 0.5 then
			matName = mats[1] -- common zone material (50%)
		elseif roll < 0.8 and #mats >= 2 then
			matName = mats[2] -- uncommon (30%)
		elseif #mats >= 3 then
			matName = mats[3] -- rare (20%)
		else
			matName = mats[1]
		end
		result.Materials[matName] = (result.Materials[matName] or 0) + 1
	end

	-- Grant materials
	for matName, count in pairs(result.Materials) do
		-- Check if it's a workstation material or rare
		local isWorkstationMat = false
		for _, workId in ipairs(BrainrotData.WORK_ORDER) do
			if BrainrotData.WORK_TYPES[workId].Material == matName then
				data.Materials[workId] = math.min(
					BrainrotData.MATERIAL_CAP,
					(data.Materials[workId] or 0) + count
				)
				isWorkstationMat = true
				break
			end
		end
		if not isWorkstationMat then
			PlayerData.AddRareMaterial(player, matName, count)
		end
	end

	-- Coin bonus for completion
	result.Coins = 50 * teamSize
	PlayerData.AddCoins(player, result.Coins)

	data.ExpeditionsCompleted = (data.ExpeditionsCompleted or 0) + 1

	return result
end

-- Get expedition status for UI.
function ExpeditionSystem.GetStatus(player: Player): any
	local data = PlayerData.Get(player)
	if not data then return { Expeditions = {}, UnlockedZones = {} } end
	local now = os.time()
	local exps = {}
	for expId, exp in pairs(data.Expeditions) do
		local elapsed = now - exp.StartTime
		local remaining = math.max(0, exp.Duration - elapsed)
		local zone = BrainrotData.ZONES[exp.Zone]
		-- Get team member names for display
		local teamNames = {}
		for _, instanceId in ipairs(exp.Team) do
			local inst = PlayerData.GetInstance(player, instanceId)
			if inst then
				local def = BrainrotData.GetBrainrot(inst.BrainrotId)
				table.insert(teamNames, def and def.Name or "?")
			end
		end
		table.insert(exps, {
			Id = expId,
			Zone = exp.Zone,
			ZoneName = zone and zone.Name or "?",
			ZoneColor = zone and zone.Color,
			TeamNames = teamNames,
			TeamSize = #exp.Team,
			RemainingSecs = remaining,
			Progress = 1 - (remaining / exp.Duration),
			Complete = remaining <= 0,
		})
	end
	return {
		Expeditions = exps,
		UnlockedZones = data.UnlockedZones,
		Zones = BrainrotData.ZONES,
		ZoneOrder = BrainrotData.ZONE_ORDER,
	}
end

-- Unlock a zone (called when player discovers it via exploration).
function ExpeditionSystem.UnlockZone(player: Player, zoneId: string): boolean
	local data = PlayerData.Get(player)
	if not data or not BrainrotData.ZONES[zoneId] then return false end
	if data.UnlockedZones[zoneId] then return false end -- already unlocked
	data.UnlockedZones[zoneId] = true
	return true
end

return ExpeditionSystem
