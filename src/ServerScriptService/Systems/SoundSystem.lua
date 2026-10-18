--!strict
--[[
	SoundSystem (ModuleScript -> ServerScriptService/Systems)
	Centralized sound + music management.
	All sound IDs are in one place for easy swapping.
	NOTE: Replace these IDs with your own uploaded audio if any don't load.
	Use https://create.roblox.com/dashboard/creations to upload custom sounds.
]]

local SoundSystem = {}

-- Sound IDs (public Roblox audio - swap with your own if needed)
SoundSystem.SOUNDS = {
	-- UI
	Click = "rbxassetid://3926305904",
	Hover = "rbxassetid://3926305904",
	Success = "rbxassetid://3926305904",
	Error = "rbxassetid://3926305904",

	-- Catching
	CatchCommon = "rbxassetid://3926305904",
	CatchRare = "rbxassetid://3926305904",
	CatchEpic = "rbxassetid://3926305904",
	CatchLegendary = "rbxassetid://3926305904",

	-- Battle
	BattleHit = "rbxassetid://3926305904",
	BattleCrit = "rbxassetid://3926305904",
	BattleWin = "rbxassetid://3926305904",
	BattleLose = "rbxassetid://3926305904",

	-- Other
	FusionComplete = "rbxassetid://3926305904",
	EggHatch = "rbxassetid://3926305904",
	LegendarySpawn = "rbxassetid://3926305904",
	CoinPickup = "rbxassetid://3926305904",
	LevelUp = "rbxassetid://3926305904",
	Achievement = "rbxassetid://3926305904",
}

-- Background music tracks (cycles through these)
SoundSystem.MUSIC_TRACKS = {
	"rbxassetid://1848354536",
	"rbxassetid://1837879082",
	"rbxassetid://1837464237",
	"rbxassetid://1837425213",
	"rbxassetid://1837849285",
}
SoundSystem.EVENT_MUSIC_TRACKS = {
	"rbxassetid://1837768517",
	"rbxassetid://1841647093",
	"rbxassetid://1838457437",
}

SoundSystem.MUSIC_VOLUME = 0.3
SoundSystem.SFX_VOLUME = 0.7

-- Play a sound for a specific player (via RemoteEvent to client).
-- The server tells the client which sound to play; client handles actual playback.
-- This avoids server-side sound replication issues.

-- Play a sound at a world position (all nearby players hear it).
function SoundSystem.PlayAtPosition(soundName: string, position: Vector3)
	-- Implemented via GameServer remote
	local remote = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	if remote then
		local playSound = remote:FindFirstChild("PlaySound")
		if playSound then
			(playSound :: RemoteEvent):FireAllClients(soundName, position)
		end
	end
end

-- Play a sound for one player.
function SoundSystem.PlayForPlayer(player: Player, soundName: string)
	local remote = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	if remote then
		local playSound = remote:FindFirstChild("PlaySound")
		if playSound then
			(playSound :: RemoteEvent):FireClient(player, soundName, nil)
		end
	end
end

return SoundSystem
