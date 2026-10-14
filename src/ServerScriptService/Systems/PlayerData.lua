--!strict
--[[
	PlayerData (ModuleScript -> ServerScriptService/Systems)
	Session-cached player data with DataStore persistence.
	All data access goes through this module — never touch the
	DataStore directly from anywhere else.

	Data shape:
	{
		Coins = number,
		Brainrots = {                       -- owned INSTANCES (not just IDs)
			[1] = { InstanceId = string, BrainrotId = string, Shiny = boolean },
			...
		},
		Showcase = { [1] = instanceId, ... }, -- up to BrainrotData.SHOWCASE_LIMIT
		QuestsCompleted = { [questId] = true, ... },
		ActiveQuestId = string | nil,
		QuestProgress = number,
	}

	Instances matter because of shinies and duplicates: two Tung Sahurs
	can be different (one shiny), and fusion (M2) eats specific instances.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))

local PlayerData = {}

local STORE_NAME = "BrainrotArena_SaveV1"
local store: DataStore? = nil

local ok, err = pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)
if not ok then
	warn("[PlayerData] DataStore unavailable, running session-only: " .. tostring(err))
	store = nil
end

local session: { [number]: any } = {} -- [userId] -> data table

local function defaultData()
	return {
		Coins = 0,
		Brainrots = {},
		Showcase = {},
		QuestsCompleted = {},
		ActiveQuestId = "first_steps",
		QuestProgress = 0,
		Materials = { foraging = 0, fishing = 0, smelting = 0, gathering = 0, mining = 0 },
		RareMaterials = {}, -- [materialName] = count (expedition-only mats)
		Jobs = {},    -- [instanceId] = { Station = workId, Slot = 1..2 }
		Stations = {}, -- [workId] = { Stored = 0.0, LastTick = os.time() }
		-- Milestone 2:
		OrbProgress = 0,      -- orbs toward the next Brainrot Cache (5 = cache)
		LifetimeMaterials = 0,-- materials ever collected (quest objective)
		Fusions = 0,          -- fusions ever performed (quest objective)
		RivalsBeaten = {},    -- [rivalId] = true
		-- Exploration & Expeditions:
		UnlockedZones = { whispering_woods = true }, -- first zone free
		Expeditions = {}, -- [expId] = { Zone, Team = {instanceIds}, StartTime, Duration }
		ExpeditionsCompleted = 0,
		-- Mystery Eggs:
		Eggs = {}, -- [eggId] = { Tier, Progress = 0 (playtime minutes) }
		IncubatorSlots = 3,
		EggsHatched = 0,
		-- Daily Quests:
		DailyDate = "", -- YYYY-MM-DD of current dailies
		DailyQuests = {}, -- [tier] = { Text, Target, Progress, Done, Coins }
		DailyEggsClaimed = {}, -- [tier] = true
		DailyAllComplete = false,
		-- Passive Income (Gold Mine):
		GoldMineLevel = 1,
		PassiveBanked = 0, -- coins accumulated
		LastPassiveTick = os.time(),
		-- Base Customization:
		PlotTheme = "default",
		UnlockedThemes = { default = true },
		Decorations = {}, -- [decoId] = true
	}
end

local function ensureStations(data)
	for _, workId in ipairs(BrainrotData.WORK_ORDER) do
		if not data.Stations[workId] then
			data.Stations[workId] = { Stored = 0, LastTick = os.time() }
		end
	end
end

-- Migrate ancient M1 saves (plain ID arrays) into instances.
local function migrateInstances(brainrots: any): any
	if type(brainrots) ~= "table" then
		return {}
	end
	local out = {}
	for _, entry in ipairs(brainrots) do
		if type(entry) == "string" then
			table.insert(out, {
				InstanceId = HttpService:GenerateGUID(false),
				BrainrotId = entry,
				Shiny = false,
			})
		elseif type(entry) == "table" and entry.BrainrotId then
			table.insert(out, entry)
		end
	end
	return out
end

local function mergeDefaults(saved: any)
	local data = defaultData()
	if type(saved) == "table" then
		for key, _ in pairs(data) do
			if saved[key] ~= nil then
				data[key] = saved[key]
			end
		end
		data.Brainrots = migrateInstances(data.Brainrots)
		-- Drop showcase entries that no longer exist.
		local valid: { [string]: boolean } = {}
		for _, inst in ipairs(data.Brainrots) do
			valid[inst.InstanceId] = true
		end
		local showcase = {}
		for _, id in ipairs(data.Showcase) do
			if valid[id] and #showcase < BrainrotData.SHOWCASE_LIMIT then
				table.insert(showcase, id)
			end
		end
		data.Showcase = showcase
		if type(data.Materials) ~= "table" then
			data.Materials = { foraging = 0, fishing = 0, smelting = 0, gathering = 0, mining = 0 }
		end
		if type(data.Jobs) ~= "table" then
			data.Jobs = {}
		end
		if type(data.Stations) ~= "table" then
			data.Stations = {}
		end
		-- Drop jobs whose instance is gone; keep station table complete.
		for instanceId, _ in pairs(data.Jobs) do
			local found = false
			for _, inst in ipairs(data.Brainrots) do
				if inst.InstanceId == instanceId then
					found = true
					break
				end
			end
			if not found then
				data.Jobs[instanceId] = nil
			end
		end
	end
	ensureStations(data)
	return data
end

function PlayerData.Load(player: Player)
	local data = defaultData()
	if store then
		local success, saved = pcall(function()
			return (store :: DataStore):GetAsync("player_" .. player.UserId)
		end)
		if success and type(saved) == "table" then
			data = mergeDefaults(saved)
		elseif not success then
			warn("[PlayerData] Load failed for " .. player.Name .. ", using defaults.")
		end
	end
	session[player.UserId] = data
	return data
end

function PlayerData.Get(player: Player)
	return session[player.UserId]
end

function PlayerData.Save(player: Player)
	local data = session[player.UserId]
	if not data or not store then
		return
	end
	local success, errMsg = pcall(function()
		(store :: DataStore):SetAsync("player_" .. player.UserId, data)
	end)
	if not success then
		warn("[PlayerData] Save failed for " .. player.Name .. ": " .. tostring(errMsg))
	end
end

function PlayerData.Release(player: Player)
	PlayerData.Save(player)
	session[player.UserId] = nil
end

function PlayerData.CountBrainrots(player: Player): number
	local data = session[player.UserId]
	if not data then
		return 0
	end
	return #data.Brainrots
end

function PlayerData.IsInventoryFull(player: Player): boolean
	return PlayerData.CountBrainrots(player) >= BrainrotData.INVENTORY_LIMIT
end

	-- // Milestone 2: fusion, battles, rivals ----------------------------------------
-- Set of instance IDs currently working (for battle/fusion validation + UI).
function PlayerData.GetWorkingIds(player: Player): { [string]: boolean }
	local data = session[player.UserId]
	local out: { [string]: boolean } = {}
	if data then
		for instanceId, _ in pairs(data.Jobs) do
			out[instanceId] = true
		end
	end
	return out
end

-- Permanently remove instances (fusion consumption). Cleans showcase/jobs.
function PlayerData.RemoveBrainrotInstances(player: Player, instanceIds: { string })
	local data = session[player.UserId]
	if not data then
		return
	end
	local gone: { [string]: boolean } = {}
	for _, id in ipairs(instanceIds) do
		gone[id] = true
	end
	local kept = {}
	for _, inst in ipairs(data.Brainrots) do
		if not gone[inst.InstanceId] then
			table.insert(kept, inst)
		end
	end
	data.Brainrots = kept
	local showcase = {}
	for _, id in ipairs(data.Showcase) do
		if not gone[id] then
			table.insert(showcase, id)
		end
	end
	data.Showcase = showcase
	for id, _ in pairs(gone) do
		data.Jobs[id] = nil
	end
end

-- Spend materials. costs = { [workId] = amount }. Returns false if short.
function PlayerData.SpendMaterials(player: Player, costs: { [string]: number }): boolean
	local data = session[player.UserId]
	if not data then
		return false
	end
	for workId, amount in pairs(costs) do
		if (data.Materials[workId] or 0) < amount then
			return false
		end
	end
	for workId, amount in pairs(costs) do
		data.Materials[workId] = (data.Materials[workId] or 0) - amount
	end
	return true
end

-- Fusion candidates: BrainrotId -> list of non-shiny owned instances.
-- Only ids with 3+ candidates are fusable.
function PlayerData.GetFusionGroups(player: Player): { [string]: any }
	local data = session[player.UserId]
	local groups: { [string]: any } = {}
	if not data then
		return groups
	end
	for _, inst in ipairs(data.Brainrots) do
		if not inst.Shiny then
			groups[inst.BrainrotId] = groups[inst.BrainrotId] or {}
			table.insert(groups[inst.BrainrotId], inst)
		end
	end
	local fusable: { [string]: any } = {}
	for brainrotId, list in pairs(groups) do
		if #list >= 3 then
			fusable[brainrotId] = list
		end
	end
	return fusable
end

function PlayerData.RecordRivalWin(player: Player, rivalId: string)
	local data = session[player.UserId]
	if data then
		data.RivalsBeaten = data.RivalsBeaten or {}
		data.RivalsBeaten[rivalId] = true
	end
end

function PlayerData.HasBeatenRival(player: Player, rivalId: string): boolean
	local data = session[player.UserId]
	return data ~= nil and data.RivalsBeaten ~= nil and data.RivalsBeaten[rivalId] == true
end

-- Adds a brainrot instance. Returns (instance, nil) on success,
-- (nil, "full") when the inventory is capped, (nil, "nodata") if
-- the player's session isn't loaded.
function PlayerData.TryAddBrainrot(player: Player, brainrotId: string, shiny: boolean, variantId: string?): (any?, string?)
	local data = session[player.UserId]
	if not data then
		return nil, "nodata"
	end
	if #data.Brainrots >= BrainrotData.INVENTORY_LIMIT then
		return nil, "full"
	end
	local instance = {
		InstanceId = HttpService:GenerateGUID(false),
		BrainrotId = brainrotId,
		Shiny = shiny == true,
		Variant = variantId, -- nil = base form
	}
	table.insert(data.Brainrots, instance)
	-- Auto-showcase while there's room; the player curates the rest.
	if #data.Showcase < BrainrotData.SHOWCASE_LIMIT then
		table.insert(data.Showcase, instance.InstanceId)
	end
	return instance, nil
end

function PlayerData.GetInstance(player: Player, instanceId: string)
	local data = session[player.UserId]
	if not data then
		return nil
	end
	for _, inst in ipairs(data.Brainrots) do
		if inst.InstanceId == instanceId then
			return inst
		end
	end
	return nil
end

-- Replace the showcase list wholesale. Validates ownership, dedupes,
-- and enforces the cap. Returns true if applied.
function PlayerData.SetShowcase(player: Player, instanceIds: any): boolean
	local data = session[player.UserId]
	if not data or type(instanceIds) ~= "table" then
		return false
	end
	if #instanceIds > BrainrotData.SHOWCASE_LIMIT then
		return false
	end
	local seen: { [string]: boolean } = {}
	local clean = {}
	for _, id in ipairs(instanceIds) do
		if type(id) ~= "string" or seen[id] then
			return false
		end
		if not PlayerData.GetInstance(player, id) then
			return false
		end
		seen[id] = true
		table.insert(clean, id)
	end
	data.Showcase = clean
	return true
end

function PlayerData.AddCoins(player: Player, amount: number)
	local data = session[player.UserId]
	if data then
		data.Coins = math.max(0, data.Coins + amount)
	end
end

-- Returns true if the player could afford it (deducts on success).
function PlayerData.SpendCoins(player: Player, amount: number): boolean
	local data = session[player.UserId]
	if not data or (data.Coins or 0) < amount then
		return false
	end
	data.Coins -= amount
	return true
end

-- // Work system ---------------------------------------------------------------
-- Lazy production: stations accrue only while the player is online.
-- TickStations advances every station's Stored count; call it before any
-- read or mutation (the server tick loop does this every 30s).

function PlayerData.TickStations(player: Player)
	local data = session[player.UserId]
	if not data then
		return
	end
	ensureStations(data)
	local now = os.time()
	for workId, st in pairs(data.Stations) do
		local elapsed = math.max(0, now - (st.LastTick or now))
		if elapsed > 0 then
			local perSec = 0
			for instanceId, job in pairs(data.Jobs) do
				if job.Station == workId then
					local inst = PlayerData.GetInstance(player, instanceId)
					local def = inst and BrainrotData.GetById(inst.BrainrotId)
					if def then
						local suit = BrainrotData.GetWorkSuitability(def, inst.Variant, workId)
						perSec += 1 / BrainrotData.WORK_SECONDS_PER_MATERIAL[suit]
					end
				end
			end
			if perSec > 0 then
				st.Stored = math.min(st.Stored + elapsed * perSec, BrainrotData.STATION_STORAGE_CAP)
			end
			st.LastTick = now
		end
	end
end

-- Called on join: workers rest while you're away (no offline accrual).
function PlayerData.ResetStationClocks(player: Player)
	local data = session[player.UserId]
	if not data then
		return
	end
	ensureStations(data)
	local now = os.time()
	for _, st in pairs(data.Stations) do
		st.LastTick = now
	end
end

local function freeSlot(data, workId: string): number?
	local used: { [number]: boolean } = {}
	for _, job in pairs(data.Jobs) do
		if job.Station == workId and job.Slot then
			used[job.Slot] = true
		end
	end
	for slot = 1, BrainrotData.STATION_SLOTS do
		if not used[slot] then
			return slot
		end
	end
	return nil
end

-- Assign an owned instance to a station. Moves it if already working.
-- A working brainrot leaves the showcase (one brainrot, one job).
-- Returns (true) or (false, reason).
function PlayerData.AssignJob(player: Player, instanceId: string, workId: string): (boolean, string?)
	local data = session[player.UserId]
	if not data then
		return false, "nodata"
	end
	if not BrainrotData.WORK_TYPES[workId] then
		return false, "badstation"
	end
	local inst = PlayerData.GetInstance(player, instanceId)
	if not inst then
		return false, "notowned"
	end
	PlayerData.TickStations(player)
	-- Unassign from wherever it was (moving stations is free).
	data.Jobs[instanceId] = nil
	local slot = freeSlot(data, workId)
	if not slot then
		return false, "full"
	end
	data.Jobs[instanceId] = { Station = workId, Slot = slot }
	-- Leave the showcase: it's at work now.
	local showcase = {}
	for _, id in ipairs(data.Showcase) do
		if id ~= instanceId then
			table.insert(showcase, id)
		end
	end
	data.Showcase = showcase
	return true, nil
end

function PlayerData.UnassignJob(player: Player, instanceId: string): boolean
	local data = session[player.UserId]
	if not data then
		return false
	end
	if not data.Jobs[instanceId] then
		return false
	end
	PlayerData.TickStations(player)
	data.Jobs[instanceId] = nil
	return true
end

-- Collect finished materials from a station. Returns the granted count.
function PlayerData.CollectStation(player: Player, workId: string): number
	local data = session[player.UserId]
	if not data or not data.Stations[workId] then
		return 0
	end
	PlayerData.TickStations(player)
	local st = data.Stations[workId]
	local granted = math.floor(st.Stored)
	if granted > 0 then
		st.Stored -= granted
		data.Materials[workId] = math.min(
			BrainrotData.MATERIAL_CAP,
			(data.Materials[workId] or 0) + granted
		)
	end
	return granted
end

-- Client-safe snapshot: floored storage + worker roster per station.
function PlayerData.GetWorkView(player: Player): any
	local data = session[player.UserId]
	if not data then
		return nil
	end
	PlayerData.TickStations(player)
	local stations: { [string]: any } = {}
	for _, workId in ipairs(BrainrotData.WORK_ORDER) do
		local st = data.Stations[workId]
		local workers = {}
		for instanceId, job in pairs(data.Jobs) do
			if job.Station == workId then
				local inst = PlayerData.GetInstance(player, instanceId)
				if inst then
					table.insert(workers, {
						Slot = job.Slot,
						InstanceId = instanceId,
						BrainrotId = inst.BrainrotId,
						Variant = inst.Variant,
						Shiny = inst.Shiny,
					})
				end
			end
		end
		table.sort(workers, function(a, b)
			return (a.Slot or 99) < (b.Slot or 99)
		end)
		stations[workId] = { Stored = math.floor(st.Stored or 0), Workers = workers }
	end
	return { Materials = data.Materials, RareMaterials = data.RareMaterials, Stations = stations }
end

-- // Expeditions -----------------------------------------------------------------
-- Check if a brainrot instance is available (not showcased, working, or on expedition).
function PlayerData.IsAvailableForExpedition(player: Player, instanceId: string): boolean
	local data = session[player.UserId]
	if not data then return false end
	-- Not on showcase
	for _, id in ipairs(data.Showcase) do
		if id == instanceId then return false end
	end
	-- Not working
	if data.Jobs[instanceId] then return false end
	-- Not already on expedition
	for _, exp in pairs(data.Expeditions) do
		for _, teamId in ipairs(exp.Team) do
			if teamId == instanceId then return false end
		end
	end
	return PlayerData.GetInstance(player, instanceId) ~= nil
end

function PlayerData.AddRareMaterial(player: Player, matName: string, amount: number)
	local data = session[player.UserId]
	if not data then return end
	data.RareMaterials[matName] = (data.RareMaterials[matName] or 0) + amount
	data.LifetimeMaterials += amount
end

function PlayerData.SpendRareMaterials(player: Player, costs: { [string]: number }): boolean
	local data = session[player.UserId]
	if not data then return false end
	for mat, cost in pairs(costs) do
		if (data.RareMaterials[mat] or 0) < cost then return false end
	end
	for mat, cost in pairs(costs) do
		data.RareMaterials[mat] -= cost
	end
	return true
end

-- // Passive Income ----------------------------------------------------------------
function PlayerData.TickPassiveIncome(player: Player): number
	-- Returns coins earned since last tick. Called periodically by GameServer.
	local data = session[player.UserId]
	if not data then return 0 end
	local now = os.time()
	local elapsed = now - (data.LastPassiveTick or now)
	data.LastPassiveTick = now
	if elapsed <= 0 then return 0 end
	local upgrade = BrainrotData.GOLD_MINE_UPGRADES[data.GoldMineLevel or 1]
	if not upgrade then return 0 end
	local ratePerSec = upgrade.RatePerMinute / 60
	-- Cap: only bank up to PASSIVE_CAP_MINUTES worth.
	local maxBank = BrainrotData.PASSIVE_CAP_MINUTES * upgrade.RatePerMinute
	local earned = math.floor(elapsed * ratePerSec)
	local newBank = math.min(maxBank, (data.PassiveBanked or 0) + earned)
	local actualGain = newBank - (data.PassiveBanked or 0)
	data.PassiveBanked = newBank
	return actualGain
end

function PlayerData.CollectPassive(player: Player): number
	local data = session[player.UserId]
	if not data then return 0 end
	local amount = math.floor(data.PassiveBanked or 0)
	data.PassiveBanked = 0
	if amount > 0 then
		PlayerData.AddCoins(player, amount)
	end
	return amount
end

-- // Customization ------------------------------------------------------------------
function PlayerData.UnlockTheme(player: Player, themeId: string): (boolean, string?)
	local data = session[player.UserId]
	local theme = BrainrotData.PLOT_THEMES[themeId]
	if not data or not theme then return false, "Invalid theme" end
	if data.UnlockedThemes[themeId] then return false, "Already unlocked" end
	if (data.Coins or 0) < theme.Cost then return false, "Not enough coins" end
	for mat, cost in pairs(theme.Materials) do
		if (data.RareMaterials[mat] or 0) < cost then
			return false, "Need " .. mat
		end
	end
	if not PlayerData.SpendCoins(player, theme.Cost) then return false, "Not enough coins" end
	if not PlayerData.SpendRareMaterials(player, theme.Materials) then
		-- Refund coins (shouldn't happen, but safe)
		PlayerData.AddCoins(player, theme.Cost)
		return false, "Need materials"
	end
	data.UnlockedThemes[themeId] = true
	data.PlotTheme = themeId
	return true
end

function PlayerData.BuyDecoration(player: Player, decoId: string): (boolean, string?)
	local data = session[player.UserId]
	local deco = BrainrotData.PLOT_DECORATIONS[decoId]
	if not data or not deco then return false, "Invalid decoration" end
	if data.Decorations[decoId] then return false, "Already owned" end
	if (data.Coins or 0) < deco.Cost then return false, "Not enough coins" end
	for mat, cost in pairs(deco.Materials) do
		-- Materials can be regular (Timber etc.) or rare
		local hasRare = (data.RareMaterials[mat] or 0) >= cost
		local workId = nil
		for _, wid in ipairs(BrainrotData.WORK_ORDER) do
			if BrainrotData.WORK_TYPES[wid].Material == mat then workId = wid break end
		end
		local hasRegular = workId and (data.Materials[workId] or 0) >= cost
		if not (hasRare or hasRegular) then
			return false, "Need " .. mat
		end
	end
	if not PlayerData.SpendCoins(player, deco.Cost) then return false, "Not enough coins" end
	-- Spend materials (prefer rare, fall back to regular)
	for mat, cost in pairs(deco.Materials) do
		if (data.RareMaterials[mat] or 0) >= cost then
			data.RareMaterials[mat] -= cost
		else
			for _, wid in ipairs(BrainrotData.WORK_ORDER) do
				if BrainrotData.WORK_TYPES[wid].Material == mat then
					data.Materials[wid] = math.max(0, (data.Materials[wid] or 0) - cost)
					break
				end
			end
		end
	end
	data.Decorations[decoId] = true
	return true
end

return PlayerData
