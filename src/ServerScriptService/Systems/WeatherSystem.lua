--!strict
--[[
	WeatherSystem (ModuleScript -> ServerScriptService/Systems)
	Dynamic weather: Clear, Rain, Storm, Fog.
	Cycles every 5-10 minutes. Affects wild spawns and visuals.
	- Rain: +50% Water-type spawn weight
	- Storm: +50% Electric-type spawn weight, lightning flashes
	- Fog: +50% Ghost/Dark-type spawn weight (Umbral variants)
	- Clear: no bonuses, best visibility
]]

local WeatherSystem = {}

export type WeatherType = "Clear" | "Rain" | "Storm" | "Fog"

WeatherSystem.Current = "Clear" :: WeatherType
WeatherSystem.NextChange = os.time() + 300 -- 5 min

-- Type bonuses per weather
WeatherSystem.TYPE_BONUSES = {
	Rain = { Water = 1.5 },
	Storm = { Electric = 1.5, Water = 1.2 },
	Fog = { Ghost = 1.5, Dark = 1.5 },
	Clear = {},
}

-- Duration ranges (seconds)
local DURATION = {
	Clear = { 300, 600 },  -- 5-10 min
	Rain = { 180, 360 },   -- 3-6 min
	Storm = { 120, 240 },  -- 2-4 min (rare, dramatic)
	Fog = { 180, 300 },    -- 3-5 min
}

-- Weather transition weights
local TRANSITION_WEIGHTS = {
	Clear = 50,
	Rain = 25,
	Storm = 10,
	Fog = 15,
}

-- Roll next weather.
local function rollWeather(): WeatherType
	local total = 0
	for _, w in pairs(TRANSITION_WEIGHTS) do
		total += w
	end
	local roll = math.random() * total
	local cumulative = 0
	for weather, weight in pairs(TRANSITION_WEIGHTS) do
		cumulative += weight
		if roll <= cumulative then
			return weather :: WeatherType
		end
	end
	return "Clear"
end

-- Check if weather should change. Returns new weather or nil.
function WeatherSystem.Tick(): WeatherType?
	local now = os.time()
	if now >= WeatherSystem.NextChange then
		local newWeather = rollWeather()
		WeatherSystem.Current = newWeather
		local dur = DURATION[newWeather]
		WeatherSystem.NextChange = now + math.random(dur[1], dur[2])
		return newWeather
	end
	return nil
end

-- Get type bonus multiplier for a brainrot type in current weather.
function WeatherSystem.GetTypeBonus(brainrotType: string): number
	local bonuses = WeatherSystem.TYPE_BONUSES[WeatherSystem.Current]
	if bonuses then
		return bonuses[brainrotType] or 1.0
	end
	return 1.0
end

-- Get weather info for UI.
function WeatherSystem.GetInfo(): any
	return {
		Current = WeatherSystem.Current,
		NextChange = WeatherSystem.NextChange,
		Bonuses = WeatherSystem.TYPE_BONUSES[WeatherSystem.Current],
	}
end

-- Force a weather change (for testing/events).
function WeatherSystem.SetWeather(weather: WeatherType)
	WeatherSystem.Current = weather
	local dur = DURATION[weather]
	WeatherSystem.NextChange = os.time() + math.random(dur[1], dur[2])
end

return WeatherSystem
