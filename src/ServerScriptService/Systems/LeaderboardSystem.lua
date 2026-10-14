--!strict
--[[
	LeaderboardSystem (ModuleScript -> ServerScriptService/Systems)
	Global battle wins leaderboard using OrderedDataStore.
	Tracks total arena wins per player.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local LeaderboardSystem = {}

local winsStore: OrderedDataStore? = nil
pcall(function()
	winsStore = DataStoreService:GetOrderedDataStore("BattleWins_v1")
end)

-- Cache for leaderboard display (refreshed periodically)
LeaderboardSystem.CachedBoard = {}
LeaderboardSystem.LastRefresh = 0

-- Record a battle win for a player.
function LeaderboardSystem.RecordWin(player: Player)
	if not winsStore then return end
	local userId = player.UserId
	pcall(function()
		local current = 0
		local success, value = pcall(function()
			return (winsStore :: OrderedDataStore):GetAsync(tostring(userId))
		end)
		if success and value then
			current = value
		end
		pcall(function()
			(winsStore :: OrderedDataStore):SetAsync(tostring(userId), current + 1)
		end)
	end)
end

-- Get top N players. Returns { { UserId, Wins, Name } }.
function LeaderboardSystem.GetTop(n: number): { any }
	if not winsStore then return {} end

	-- Use cache if fresh (< 60s)
	if os.time() - LeaderboardSystem.LastRefresh < 60 and #LeaderboardSystem.CachedBoard > 0 then
		return LeaderboardSystem.CachedBoard
	end

	local result = {}
	pcall(function()
		local pages = (winsStore :: OrderedDataStore):GetSortedAsync(false, n)
		local items = pages:GetCurrentPage()
		for _, item in ipairs(items) do
			local userId = tonumber(item.key)
			local name = "Player" .. tostring(userId)
			-- Try to get name
			pcall(function()
				name = Players:GetNameFromUserIdAsync(userId)
			end)
			table.insert(result, {
				UserId = userId,
				Wins = item.value,
				Name = name,
			})
		end
	end)

	LeaderboardSystem.CachedBoard = result
	LeaderboardSystem.LastRefresh = os.time()
	return result
end

-- Get a player's rank and wins.
function LeaderboardSystem.GetPlayerRank(player: Player): any
	if not winsStore then return { Rank = 0, Wins = 0 } end
	local userId = player.UserId
	local wins = 0
	pcall(function()
		local success, value = pcall(function()
			return (winsStore :: OrderedDataStore):GetAsync(tostring(userId))
		end)
		if success and value then
			wins = value
		end
	end)
	return { Rank = 0, Wins = wins } -- rank calculation omitted for simplicity
end

return LeaderboardSystem
