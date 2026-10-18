--!strict
--[[
	LeaderboardSystem (ModuleScript -> ServerScriptService/Systems)
	Arena wins board: OrderedDataStore plus live session/online players
	so Studio and empty stores still show names.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local LeaderboardSystem = {}

local winsStore: OrderedDataStore? = nil
pcall(function()
	winsStore = DataStoreService:GetOrderedDataStore("BattleWins_v1")
end)

local sessionWins: { [number]: number } = {}

LeaderboardSystem.CachedBoard = {}
LeaderboardSystem.LastRefresh = 0

function LeaderboardSystem.RecordWin(player: Player)
	local userId = player.UserId
	sessionWins[userId] = (sessionWins[userId] or 0) + 1
	LeaderboardSystem.LastRefresh = 0
	if winsStore then
		pcall(function()
			(winsStore :: OrderedDataStore):IncrementAsync(tostring(userId), 1)
		end)
	end
end

function LeaderboardSystem.GetTop(n: number): { any }
	n = math.max(1, n)
	if os.time() - LeaderboardSystem.LastRefresh < 15 and #LeaderboardSystem.CachedBoard >= n then
		local slice = {}
		for i = 1, n do
			slice[i] = LeaderboardSystem.CachedBoard[i]
		end
		return slice
	end

	local byId: { [number]: any } = {}

	if winsStore then
		pcall(function()
			local pages = (winsStore :: OrderedDataStore):GetSortedAsync(false, n)
			local items = pages:GetCurrentPage()
			for _, item in ipairs(items) do
				local userId = tonumber(item.key)
				if userId then
					local name = "Player" .. tostring(userId)
					pcall(function()
						name = Players:GetNameFromUserIdAsync(userId)
					end)
					byId[userId] = {
						UserId = userId,
						Wins = tonumber(item.value) or 0,
						Name = name,
					}
				end
			end
		end)
	end

	for userId, wins in pairs(sessionWins) do
		local row = byId[userId]
		if row then
			if wins > (row.Wins or 0) then
				row.Wins = wins
			end
		else
			local name = "Player" .. tostring(userId)
			local live = Players:GetPlayerByUserId(userId)
			if live then
				name = live.Name
			else
				pcall(function()
					name = Players:GetNameFromUserIdAsync(userId)
				end)
			end
			byId[userId] = { UserId = userId, Wins = wins, Name = name }
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local row = byId[player.UserId]
		if row then
			row.Name = player.Name
			if (sessionWins[player.UserId] or 0) > (row.Wins or 0) then
				row.Wins = sessionWins[player.UserId]
			end
		else
			byId[player.UserId] = {
				UserId = player.UserId,
				Wins = sessionWins[player.UserId] or 0,
				Name = player.Name,
			}
		end
	end

	local result = {}
	for _, row in pairs(byId) do
		table.insert(result, row)
	end
	table.sort(result, function(a, b)
		if a.Wins == b.Wins then
			return tostring(a.Name) < tostring(b.Name)
		end
		return (a.Wins or 0) > (b.Wins or 0)
	end)
	while #result > n do
		table.remove(result)
	end

	LeaderboardSystem.CachedBoard = result
	LeaderboardSystem.LastRefresh = os.time()
	return result
end

function LeaderboardSystem.GetPlayerRank(player: Player): any
	local top = LeaderboardSystem.GetTop(50)
	for i, row in ipairs(top) do
		if row.UserId == player.UserId then
			return { Rank = i, Wins = row.Wins or 0 }
		end
	end
	return { Rank = 0, Wins = sessionWins[player.UserId] or 0 }
end

-- Laser Tag kills (same DataStore as the Laser Tag place script).
local laserStore: OrderedDataStore? = nil
pcall(function()
	laserStore = DataStoreService:GetOrderedDataStore("LaserTagKills_v1")
end)
local laserCache: { any } = {}
local laserCacheAt = 0

function LeaderboardSystem.GetLaserTagTop(n: number): { any }
	n = math.max(1, n)
	if os.time() - laserCacheAt < 12 and #laserCache >= n then
		local slice = {}
		for i = 1, n do
			slice[i] = laserCache[i]
		end
		return slice
	end
	local result = {}
	if laserStore then
		pcall(function()
			local pages = (laserStore :: OrderedDataStore):GetSortedAsync(false, n)
			for _, item in ipairs(pages:GetCurrentPage()) do
				local userId = tonumber(item.key)
				if userId then
					local name = "Player" .. tostring(userId)
					pcall(function()
						name = Players:GetNameFromUserIdAsync(userId)
					end)
					local live = Players:GetPlayerByUserId(userId)
					if live then
						name = live.Name
					end
					table.insert(result, {
						UserId = userId,
						Name = name,
						Kills = tonumber(item.value) or 0,
					})
				end
			end
		end)
	end
	laserCache = result
	laserCacheAt = os.time()
	return result
end

return LeaderboardSystem
