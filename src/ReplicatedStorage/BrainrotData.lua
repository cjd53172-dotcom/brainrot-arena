--!strict
--[[
	BrainrotData (ModuleScript -> ReplicatedStorage)
	Single source of truth for every brainrot: stats, types, moves, rarities,
	and display-model specs. Required by both server and client.

	To add a brainrot: append an entry to ROSTER. Everything else
	(quest rewards, collection UI, plot pedestals) picks it up automatically.
]]

local BrainrotData = {}

-- // Types ------------------------------------------------------------------
BrainrotData.TYPES = { "Wood", "Water", "Fire", "Sky", "Shadow" }

-- Attacker type -> defender type -> damage multiplier. Anything unlisted = 1x.
-- Every type has two strengths and two resists so matchups always matter.
BrainrotData.EFFECTIVENESS = {
	Wood   = { Water = 2, Shadow = 2, Fire = 0.5, Sky = 0.5 },
	Water  = { Fire = 2,  Sky = 2,    Wood = 0.5, Shadow = 0.5 },
	Fire   = { Wood = 2,  Shadow = 2, Water = 0.5, Sky = 0.5 },
	Sky    = { Wood = 2,  Fire = 2,   Shadow = 0.5, Water = 0.5 },
	Shadow = { Sky = 2,   Water = 2,  Fire = 0.5, Wood = 0.5 },
}

-- Commons stay glass cannons; legendaries carry the late ladder.
BrainrotData.RARITY_POWER = {
	Common = 0.68,
	Rare = 1.00,
	Epic = 1.34,
	Legendary = 1.75,
}

-- Extra coverage / utility so every brainrot has a 4-move kit.
BrainrotData.TYPE_MOVES = {
	Wood = {
		{ Name = "Vine Snap", Type = "Wood", Power = 40, Accuracy = 100, Description = "A quick lash of vines." },
		{ Name = "Timber Crash", Type = "Wood", Power = 80, Accuracy = 88, Description = "A falling-tree haymaker." },
		{ Name = "Root Guard", Type = "Wood", Power = 0, Accuracy = 100, Effect = "shield", Description = "Harden bark. Defense up." },
		{ Name = "Spore Dart", Type = "Wood", Power = 55, Accuracy = 95, Description = "Needles of living green." },
	},
	Water = {
		{ Name = "Puddle Jab", Type = "Water", Power = 40, Accuracy = 100, Description = "A wet slap that stings." },
		{ Name = "Tidal Crush", Type = "Water", Power = 80, Accuracy = 88, Description = "A wall of water." },
		{ Name = "Soak", Type = "Water", Power = 0, Accuracy = 100, Effect = "heal", Description = "Drink deep. Restore HP." },
		{ Name = "Riptide", Type = "Water", Power = 55, Accuracy = 95, Description = "Drag them under." },
	},
	Fire = {
		{ Name = "Spark Bite", Type = "Fire", Power = 40, Accuracy = 100, Description = "A hot nibble." },
		{ Name = "Magma Burst", Type = "Fire", Power = 80, Accuracy = 88, Description = "The floor is lava." },
		{ Name = "Hype Up", Type = "Fire", Power = 0, Accuracy = 100, Effect = "focus", Description = "Attack sharply up." },
		{ Name = "Cinder Shot", Type = "Fire", Power = 55, Accuracy = 95, Description = "A coal straight to the face." },
	},
	Sky = {
		{ Name = "Gust Peck", Type = "Sky", Power = 40, Accuracy = 100, Description = "Wind and beak." },
		{ Name = "Cyclone Dive", Type = "Sky", Power = 80, Accuracy = 88, Description = "From the clouds, hard." },
		{ Name = "Tailwind", Type = "Sky", Power = 0, Accuracy = 100, Effect = "focus", Description = "Speed of the wind. Attack up." },
		{ Name = "Cloud Cut", Type = "Sky", Power = 55, Accuracy = 95, Description = "A blade of compressed air." },
	},
	Shadow = {
		{ Name = "Hex Nibble", Type = "Shadow", Power = 40, Accuracy = 100, Description = "A curse with teeth." },
		{ Name = "Void Slam", Type = "Shadow", Power = 80, Accuracy = 88, Description = "Darkness packed into a fist." },
		{ Name = "Night Sip", Type = "Shadow", Power = 0, Accuracy = 100, Effect = "heal", Description = "Steal a little life back." },
		{ Name = "Bad Omen", Type = "Shadow", Power = 55, Accuracy = 95, Description = "They already lost." },
	},
}

function BrainrotData.GetEffectiveness(attackType: string, defendType: string): number
	local row = BrainrotData.EFFECTIVENESS[attackType]
	if row then
		local mult = row[defendType]
		if mult ~= nil then
			return mult
		end
	end
	return 1
end

-- // Rarities ----------------------------------------------------------------
BrainrotData.RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary" }

BrainrotData.RARITY_COLORS = {
	Common    = Color3.fromRGB(160, 160, 160),
	Rare      = Color3.fromRGB(0, 140, 255),
	Epic      = Color3.fromRGB(170, 60, 250),
	Legendary = Color3.fromRGB(255, 150, 0),
}

-- // Collection rules -----------------------------------------------------------
-- The roster can grow forever; the inventory and showcase stay bounded.
BrainrotData.INVENTORY_LIMIT = 1000
BrainrotData.SHOWCASE_LIMIT = 10
BrainrotData.SHINY_CHANCE = 0.003 -- 0.3% (roughly 1 in 333): true trophy rarity

-- Shift a color's hue to produce a shiny variant. Deterministic per color,
-- so current AND future brainrots get shinies with zero extra authoring.
function BrainrotData.GetShinyColor(color: Color3): Color3
	local h, s, v = Color3.toHSV(color)
	h = (h + 0.38) % 1
	s = math.clamp(s * 1.2 + 0.1, 0, 1)
	v = math.clamp(v * 1.05 + 0.05, 0, 1)
	return Color3.fromHSV(h, s, v)
end

-- // Variants -------------------------------------------------------------------
-- Variant TEMPLATES apply to every brainrot: 40 brainrots x 7 forms = 280
-- collectible forms. Type, moves, and color treatment come from the template,
-- so newly added brainrots get all variants automatically. The variant is
-- stored on the owned instance (nil = base form).
local VARIANTS: { [string]: any } = {
	umbral = {
		Name = "Umbral",
		Type = "Shadow",
		Weight = 5,
		Tint = function(c: Color3): Color3
			local h, s, v = Color3.toHSV(c)
			return Color3.fromHSV(h, math.min(1, s + 0.25), v * 0.45)
		end,
		Moves = {
			{ Name = "Shadow Claw",    Type = "Shadow", Power = 55, Accuracy = 95, Description = "Claws of living dark." },
			{ Name = "Nightmare Veil", Type = "Shadow", Power = 75, Accuracy = 90, Description = "The dark closes in." },
		},
	},
	ember = {
		Name = "Ember",
		Type = "Fire",
		Weight = 4,
		Tint = function(c: Color3): Color3
			local _, s, v = Color3.toHSV(c)
			return Color3.fromHSV(0.06, math.min(1, s + 0.3), math.min(1, v + 0.1))
		end,
		Moves = {
			{ Name = "Cinder Lash",   Type = "Fire", Power = 55, Accuracy = 95, Description = "A whip of embers." },
			{ Name = "Inferno Bloom", Type = "Fire", Power = 75, Accuracy = 90, Description = "Fire blossoms outward." },
		},
	},
	abyssal = {
		Name = "Abyssal",
		Type = "Water",
		Weight = 4,
		Tint = function(c: Color3): Color3
			local _, s, v = Color3.toHSV(c)
			return Color3.fromHSV(0.62, math.min(1, s + 0.2), v * 0.8)
		end,
		Moves = {
			{ Name = "Deep Current", Type = "Water", Power = 55, Accuracy = 95, Description = "Dragged into the deep." },
			{ Name = "Trench Crush", Type = "Water", Power = 75, Accuracy = 90, Description = "The pressure of the abyss." },
		},
	},
	venom = {
		Name = "Venom",
		Type = "Wood",
		Weight = 4,
		Tint = function(c: Color3): Color3
			local _, s, v = Color3.toHSV(c)
			return Color3.fromHSV(0.28, math.min(1, s + 0.3), v)
		end,
		Moves = {
			{ Name = "Toxic Spit",  Type = "Wood", Power = 55, Accuracy = 95, Description = "Venom with range." },
			{ Name = "Spore Cloud", Type = "Wood", Power = 75, Accuracy = 90, Description = "Breathe it in. Regret it after." },
		},
	},
	gale = {
		Name = "Gale",
		Type = "Sky",
		Weight = 2,
		Tint = function(c: Color3): Color3
			local _, s, v = Color3.toHSV(c)
			return Color3.fromHSV(0.52, s * 0.6, math.min(1, v + 0.15))
		end,
		Moves = {
			{ Name = "Razor Wind",   Type = "Sky", Power = 55, Accuracy = 95, Description = "Wind with an edge." },
			{ Name = "Cyclone Dive", Type = "Sky", Power = 75, Accuracy = 90, Description = "A storm with intent." },
		},
	},
	gilded = {
		Name = "Gilded",
		Type = nil,
		Weight = 1,
		Tint = function(_c: Color3): Color3
			return Color3.fromHSV(0.12, 0.85, 1)
		end,
		Moves = nil,
	},
	oro = {
		Name = "Oro",
		Type = nil,
		Tint = function(_c: Color3): Color3
			return Color3.fromHSV(0.12, 0.9, 1)
		end,
	},
	lava = {
		Name = "Lava",
		Type = "Fire",
		Tint = function(_c: Color3): Color3
			return Color3.fromHSV(0.04, 1, 1)
		end,
	},
	diamante = {
		Name = "Diamante",
		Type = "Sky",
		Tint = function(_c: Color3): Color3
			return Color3.fromHSV(0.55, 0.25, 1)
		end,
	},
	galaxia = {
		Name = "Galaxia",
		Type = "Shadow",
		Tint = function(_c: Color3): Color3
			return Color3.fromHSV(0.75, 0.85, 0.7)
		end,
	},
	hacker = {
		Name = "Hacker",
		Type = "Shadow",
		Tint = function(_c: Color3): Color3
			return Color3.fromHSV(0.38, 1, 0.9)
		end,
	},
	arcoiris = {
		Name = "Arcoíris",
		Type = nil,
		Tint = function(c: Color3): Color3
			local h, s, v = Color3.toHSV(c)
			return Color3.fromHSV((h + 0.2) % 1, math.min(1, s + 0.2), math.min(1, v + 0.1))
		end,
	},
	solido = {
		Name = "Sólido",
		Type = "Wood",
		Tint = function(c: Color3): Color3
			local h, s, v = Color3.toHSV(c)
			return Color3.fromHSV(h, s * 0.4, v * 0.75)
		end,
	},
}
BrainrotData.VARIANTS = VARIANTS

-- Pack folder name (lowercased) -> variant id. Normal stays the base form.
BrainrotData.PACK_FOLDERS = {
	normal = nil,
	oro = "oro",
	lava = "lava",
	diamante = "diamante",
	galaxia = "galaxia",
	hacker = "hacker",
	arcoiris = "arcoiris",
	solido = "solido",
}

-- Normal is most of the drops; Galaxia is a trophy.
-- Includes pack forms (oro, lava, …) and the type templates (umbral, ember, …).
BrainrotData.VARIANT_ROLL = {
	{ Id = nil, Weight = 68 },
	{ Id = "umbral", Weight = 5 },
	{ Id = "ember", Weight = 4 },
	{ Id = "abyssal", Weight = 4 },
	{ Id = "venom", Weight = 4 },
	{ Id = "solido", Weight = 4 },
	{ Id = "oro", Weight = 3 },
	{ Id = "lava", Weight = 2.5 },
	{ Id = "gale", Weight = 2 },
	{ Id = "arcoiris", Weight = 1.5 },
	{ Id = "diamante", Weight = 1 },
	{ Id = "gilded", Weight = 0.8 },
	{ Id = "hacker", Weight = 0.5 },
	{ Id = "galaxia", Weight = 0.2 },
}

function BrainrotData.RollVariant(): string?
	local total = 0
	for _, row in ipairs(BrainrotData.VARIANT_ROLL) do
		total += row.Weight
	end
	local roll = math.random() * total
	for _, row in ipairs(BrainrotData.VARIANT_ROLL) do
		roll -= row.Weight
		if roll <= 0 then
			return row.Id
		end
	end
	return nil
end

function BrainrotData.GetEffectiveType(def: any, variantId: string?): string
	local v: any = variantId and VARIANTS[variantId] or nil
	if v and v.Type then
		return v.Type
	end
	return def.Type
end

function BrainrotData.GetBattleMoves(def: any, variantId: string?): { any }
	local moves: { any } = {}
	local seen: { [string]: boolean } = {}
	local variant = if variantId then VARIANTS[variantId] else nil
	local src = (variant and variant.Moves) or def.Moves or {}
	for _, m in ipairs(src) do
		if m.Name and not seen[m.Name] then
			seen[m.Name] = true
			table.insert(moves, m)
		end
	end
	local t = BrainrotData.GetEffectiveType(def, variantId)
	local pool = BrainrotData.TYPE_MOVES[t] or BrainrotData.TYPE_MOVES.Wood
	for _, extra in ipairs(pool) do
		if #moves >= 4 then
			break
		end
		if extra.Name and not seen[extra.Name] then
			seen[extra.Name] = true
			table.insert(moves, extra)
		end
	end
	return moves
end

function BrainrotData.GetMoves(def: any, variantId: string?): any
	local v: any = variantId and VARIANTS[variantId] or nil
	if v and v.Moves then
		return v.Moves
	end
	return def.Moves
end

function BrainrotData.GetVariantTint(variantId: string?): any
	local v: any = variantId and VARIANTS[variantId] or nil
	if v then
		return v.Tint
	end
	return nil
end

function BrainrotData.GetDisplayName(def: any, variantId: string?, shiny: boolean): string
	local name = def.Name
	local v: any = variantId and VARIANTS[variantId] or nil
	if v then
		name = v.Name .. " " .. name
	end
	if shiny then
		name = "★ " .. name .. " ★"
	end
	return name
end

-- // Work system (Palworld-style) --------------------------------------------------
-- Five work types, one per battle type. Workers are assigned to workstations
-- on their plot and passively produce materials for crafting/fusion.
BrainrotData.WORK_TYPES = {
	foraging  = { Name = "Foraging",  Type = "Wood",   Material = "Timber",       Color = Color3.fromRGB(120, 85, 50) },
	fishing   = { Name = "Fishing",   Type = "Water",  Material = "Fish",         Color = Color3.fromRGB(60, 130, 200) },
	smelting  = { Name = "Smelting",  Type = "Fire",   Material = "Ingots",       Color = Color3.fromRGB(230, 120, 50) },
	gathering = { Name = "Gathering", Type = "Sky",    Material = "Cloud Cotton", Color = Color3.fromRGB(150, 200, 235) },
	mining    = { Name = "Mining",    Type = "Shadow", Material = "Dark Stone",   Color = Color3.fromRGB(80, 80, 95) },
}
BrainrotData.WORK_ORDER = { "foraging", "fishing", "smelting", "gathering", "mining" }

-- Seconds per material by suitability level 0-3. Tunable.
BrainrotData.WORK_SECONDS_PER_MATERIAL = { [0] = 600, [1] = 300, [2] = 180, [3] = 90 }
BrainrotData.STATION_SLOTS = 2
BrainrotData.STATION_STORAGE_CAP = 40 -- materials; then the station pauses until collected
BrainrotData.MATERIAL_CAP = 999

-- Character-specific suitability overrides (absolute 0-3). Flavor over formula:
-- Bombardiro mines with bombs, Chef Crab was born to smelt, Tralalero fishes.
BrainrotData.WORK_OVERRIDES = {
	bombardiro = { mining = 3 },
	tralalero = { fishing = 3 },
	tralaleritos = { fishing = 3 },
	tralaleritas = { fishing = 2 },
	orcalero = { fishing = 3 },
	chef_crab = { smelting = 3 },
	nuclearo = { mining = 3, smelting = 3 },
	patapim = { foraging = 3 },
	cocofanto = { foraging = 3 },
	bulblito = { foraging = 3 },
	orangutini = { foraging = 2 },
	ballerina = { gathering = 3 },
	saturnita = { gathering = 3 },
	piccione = { gathering = 3 },
	svinina = { smelting = 2 },
	frigo_camelo = { fishing = 2 },
	gangster = { mining = 2 },
}

-- Suitability 0-3 for a work type. Default: 2 in the work matching the
-- EFFECTIVE type — variant type counts, so an Umbral Tung Sahur (Shadow)
-- is a miner, not a forager. Character overrides are absolute.
-- Gilded: +1 to every nonzero suitability (cap 3) — golden workers.
function BrainrotData.GetWorkSuitability(def: any, variantId: string?, workId: string): number
	local workDef = BrainrotData.WORK_TYPES[workId]
	if not workDef then
		return 0
	end
	local level: number
	local overrides: any = BrainrotData.WORK_OVERRIDES[def.Id]
	if overrides and overrides[workId] ~= nil then
		level = overrides[workId]
	else
		local effectiveType = BrainrotData.GetEffectiveType(def, variantId)
		level = if workDef.Type == effectiveType then 2 else 0
	end
	if variantId == "gilded" and level > 0 then
		level = math.min(3, level + 1)
	end
	return level
end

-- // Roster -------------------------------------------------------------------
-- Display.Shape: "Block" | "Ball" | "Cylinder" | "Wedge"
-- Display.Accessory (optional): { Shape, Color, Size, Offset, Rotation? }
--   Offset is relative to the body center. Rotation is an optional
--   Vector3 of radians applied to the accessory (e.g. flat rings).
-- Moves: { Name, Type, Power, Accuracy, Description }

BrainrotData.ROSTER = {
	{
		Id = "tung_sahur",
		Name = "Tung Tung Tung Sahur",
		Type = "Wood",
		Rarity = "Common",
		HP = 55, Attack = 55, Defense = 50, Speed = 45,
		Description = "A living log who never puts down his baseball bat. Loud, loyal, and the perfect first partner.",
		Display = {
			Shape = "Cylinder",
			Color = Color3.fromRGB(139, 90, 43),
			Size = Vector3.new(2.2, 3.4, 2.2),
			Face = "angry",
			Extras = {
				{ Name = "BatKnob", Shape = "Ball", Color = Color3.fromRGB(160, 110, 60), Size = Vector3.new(0.42, 0.42, 0.42), Offset = Vector3.new(1.15, -0.55, 0.35) },
				{ Name = "BatGrip", Shape = "Cylinder", Color = Color3.fromRGB(40, 32, 28), Size = Vector3.new(0.32, 1.1, 0.32), Offset = Vector3.new(1.35, 0.05, 0.35), Rotation = Vector3.new(0, 0, -0.45) },
				{ Name = "Bat", Shape = "Cylinder", Color = Color3.fromRGB(214, 162, 92), Size = Vector3.new(0.55, 2.4, 0.55), Offset = Vector3.new(1.95, 1.35, 0.35), Rotation = Vector3.new(0, 0, -0.45) },
				{ Name = "BatTip", Shape = "Cylinder", Color = Color3.fromRGB(180, 128, 70), Size = Vector3.new(0.68, 0.35, 0.68), Offset = Vector3.new(2.45, 2.35, 0.35), Rotation = Vector3.new(0, 0, -0.45) },
			},
		},
		Moves = {
			{ Name = "Bat Bonk",     Type = "Wood", Power = 40, Accuracy = 100, Description = "A classic swing of the bat." },
			{ Name = "Timber Shout", Type = "Wood", Power = 60, Accuracy = 90,  Description = "TUNG TUNG! A shockwave of pure noise." },
		},
	},
	{
		Id = "tralalero",
		Name = "Tralalero Tralala",
		Type = "Water",
		Rarity = "Common",
		HP = 60, Attack = 52, Defense = 45, Speed = 60,
		Description = "A shark in sneakers. Faster than he looks, and he looks fast.",
		Display = {
			Shape = "Ball",
			Color = Color3.fromRGB(60, 130, 200),
			Size = Vector3.new(3.2, 2.6, 4.2),
			Face = true,
			Extras = {
				{ Name = "Dorsal", Shape = "Wedge", Color = Color3.fromRGB(40, 100, 170), Size = Vector3.new(1.2, 1.4, 0.5), Offset = Vector3.new(0, 1.8, -0.6) },
				{ Name = "Tail", Shape = "Wedge", Color = Color3.fromRGB(40, 100, 170), Size = Vector3.new(1.8, 1.4, 0.4), Offset = Vector3.new(0, 0.3, -2.5) },
				{ Name = "ShoeL", Shape = "Block", Color = Color3.fromRGB(230, 230, 235), Size = Vector3.new(0.9, 0.6, 1.5), Offset = Vector3.new(-0.8, -1.5, 0.9) },
				{ Name = "ShoeR", Shape = "Block", Color = Color3.fromRGB(230, 230, 235), Size = Vector3.new(0.9, 0.6, 1.5), Offset = Vector3.new(0.8, -1.5, 0.9) },
				{ Name = "Belly", Shape = "Ball", Color = Color3.fromRGB(200, 225, 245), Size = Vector3.new(2.4, 1.6, 3.0), Offset = Vector3.new(0, -0.7, 0.4) },
			},
		},
		Moves = {
			{ Name = "Sneaker Splash", Type = "Water", Power = 40, Accuracy = 100, Description = "A tidal wave kicked up by fresh kicks." },
			{ Name = "Shark Bite",     Type = "Water", Power = 65, Accuracy = 90,  Description = "Three rows of teeth. Zero mercy." },
		},
	},
	{
		Id = "bananini",
		Name = "Chimpanzini Bananini",
		Type = "Fire",
		Rarity = "Common",
		HP = 50, Attack = 60, Defense = 40, Speed = 70,
		Description = "A monkey who ate a spicy pepper once. Never recovered. Never slowed down.",
		Display = {
			Shape = "Ball",
			Color = Color3.fromRGB(250, 220, 60),
			Size = Vector3.new(2.6, 3.2, 2.6),
			Face = true,
			Extras = {
				{ Name = "EarL", Shape = "Ball", Color = Color3.fromRGB(120, 80, 40), Size = Vector3.new(0.8, 0.8, 0.4), Offset = Vector3.new(-1.3, 1.2, 0) },
				{ Name = "EarR", Shape = "Ball", Color = Color3.fromRGB(120, 80, 40), Size = Vector3.new(0.8, 0.8, 0.4), Offset = Vector3.new(1.3, 1.2, 0) },
				{ Name = "Tip", Shape = "Cylinder", Color = Color3.fromRGB(110, 70, 35), Size = Vector3.new(0.4, 0.5, 0.4), Offset = Vector3.new(0, 1.9, 0) },
			},
		},
		Moves = {
			{ Name = "Banana Barrage", Type = "Fire", Power = 35, Accuracy = 100, Description = "A flurry of flaming peels." },
			{ Name = "Peel Out",       Type = "Fire", Power = 55, Accuracy = 95,  Description = "Burns rubber. Literally." },
		},
	},
	{
		Id = "lirili",
		Name = "Lirili Larila",
		Type = "Water",
		Rarity = "Rare",
		HP = 75, Attack = 65, Defense = 70, Speed = 50,
		Description = "A cactus-elephant who wandered out of the desert and into legend.",
		Display = {
			Shape = "Cylinder",
			Color = Color3.fromRGB(70, 160, 70),
			Size = Vector3.new(3.0, 3.0, 3.0),
			Face = true,
			Extras = {
				{ Name = "Trunk", Shape = "Cylinder", Color = Color3.fromRGB(55, 130, 55), Size = Vector3.new(0.7, 2.0, 0.7), Offset = Vector3.new(0, -0.6, 1.9), Rotation = Vector3.new(0.5, 0, 0) },
				{ Name = "EarL", Shape = "Ball", Color = Color3.fromRGB(60, 145, 60), Size = Vector3.new(0.5, 1.4, 1.2), Offset = Vector3.new(-1.8, 0.8, 0) },
				{ Name = "EarR", Shape = "Ball", Color = Color3.fromRGB(60, 145, 60), Size = Vector3.new(0.5, 1.4, 1.2), Offset = Vector3.new(1.8, 0.8, 0) },
				{ Name = "Spike1", Shape = "Wedge", Color = Color3.fromRGB(140, 220, 140), Size = Vector3.new(0.4, 0.8, 0.4), Offset = Vector3.new(-0.8, 1.7, -0.5) },
				{ Name = "Spike2", Shape = "Wedge", Color = Color3.fromRGB(140, 220, 140), Size = Vector3.new(0.4, 0.8, 0.4), Offset = Vector3.new(0.8, 1.7, -0.5) },
			},
		},
		Moves = {
			{ Name = "Oasis Stomp",   Type = "Water", Power = 55, Accuracy = 95, Description = "The ground becomes a swimming pool." },
			{ Name = "Desert Mirage", Type = "Water", Power = 70, Accuracy = 90, Description = "You never saw it coming. Neither did he." },
		},
	},
	{
		Id = "cappuccino_assassino",
		Name = "Cappuccino Assassino",
		Type = "Shadow",
		Rarity = "Rare",
		HP = 65, Attack = 75, Defense = 55, Speed = 80,
		Description = "A cappuccino cup trained in the silent arts. You never hear the foam coming.",
		Display = {
			Shape = "Cylinder",
			Color = Color3.fromRGB(200, 160, 110),
			Size = Vector3.new(2.6, 2.8, 2.6),
			Face = "angry",
			Extras = {
				{ Name = "Foam", Shape = "Cylinder", Color = Color3.fromRGB(245, 235, 220), Size = Vector3.new(2.7, 0.5, 2.7), Offset = Vector3.new(0, 1.5, 0) },
				{ Name = "Headband", Shape = "Block", Color = Color3.fromRGB(25, 25, 28), Size = Vector3.new(2.7, 0.4, 2.7), Offset = Vector3.new(0, 1.0, 0) },
				{ Name = "Katana", Shape = "Block", Color = Color3.fromRGB(200, 200, 210), Size = Vector3.new(0.18, 3.4, 0.5), Offset = Vector3.new(1.8, 0.4, 0), Rotation = Vector3.new(0, 0, -0.4) },
				{ Name = "Handle", Shape = "Cylinder", Color = Color3.fromRGB(40, 40, 45), Size = Vector3.new(0.9, 0.7, 0.9), Offset = Vector3.new(1.7, 0, 0), Rotation = Vector3.new(0, 0, 1.57) },
			},
		},
		Moves = {
			{ Name = "Silent Sip",    Type = "Shadow", Power = 50, Accuracy = 100, Description = "Strikes without spilling a drop." },
			{ Name = "Shadow Strike", Type = "Shadow", Power = 75, Accuracy = 90,  Description = "From the darkness, with caffeine." },
		},
	},
	{
		Id = "gusini",
		Name = "Bombombini Gusini",
		Type = "Sky",
		Rarity = "Rare",
		HP = 70, Attack = 70, Defense = 60, Speed = 65,
		Description = "A bomber goose with perfect formation flying and questionable morals.",
		Display = {
			Shape = "Ball",
			Color = Color3.fromRGB(220, 220, 225),
			Size = Vector3.new(2.8, 2.4, 3.4),
			Face = "angry",
			Extras = {
				{ Name = "Beak", Shape = "Wedge", Color = Color3.fromRGB(240, 150, 40), Size = Vector3.new(0.8, 0.5, 1.0), Offset = Vector3.new(0, 0.2, 1.9) },
				{ Name = "BombL", Shape = "Ball", Color = Color3.fromRGB(60, 60, 65), Size = Vector3.new(0.9, 0.9, 0.9), Offset = Vector3.new(-1.0, -1.4, 0) },
				{ Name = "BombR", Shape = "Ball", Color = Color3.fromRGB(60, 60, 65), Size = Vector3.new(0.9, 0.9, 0.9), Offset = Vector3.new(1.0, -1.4, 0) },
				{ Name = "WingL", Shape = "Block", Color = Color3.fromRGB(190, 190, 195), Size = Vector3.new(1.4, 0.25, 2.0), Offset = Vector3.new(-1.9, 0.3, -0.5) },
				{ Name = "WingR", Shape = "Block", Color = Color3.fromRGB(190, 190, 195), Size = Vector3.new(1.4, 0.25, 2.0), Offset = Vector3.new(1.9, 0.3, -0.5) },
			},
		},
		Moves = {
			{ Name = "Goose Dive",   Type = "Sky", Power = 55, Accuracy = 95, Description = "Honk. Then pain." },
			{ Name = "Payload Drop", Type = "Sky", Power = 70, Accuracy = 90, Description = "Precision delivery, explosive results." },
		},
	},
	{
		Id = "bombardiro",
		Name = "Bombardiro Crocodilo",
		Type = "Fire",
		Rarity = "Epic",
		HP = 85, Attack = 90, Defense = 70, Speed = 70,
		Description = "A crocodile fused with a bomber plane. The sky is no longer safe.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(60, 140, 70),
			Size = Vector3.new(2.4, 1.6, 4.6),
			Face = "angry",
			Extras = {
				{ Name = "WingL", Shape = "Block", Color = Color3.fromRGB(45, 115, 55), Size = Vector3.new(3.2, 0.25, 1.6), Offset = Vector3.new(-2.2, 0, -0.3) },
				{ Name = "WingR", Shape = "Block", Color = Color3.fromRGB(45, 115, 55), Size = Vector3.new(3.2, 0.25, 1.6), Offset = Vector3.new(2.2, 0, -0.3) },
				{ Name = "Snout", Shape = "Block", Color = Color3.fromRGB(60, 140, 70), Size = Vector3.new(1.6, 0.9, 1.4), Offset = Vector3.new(0, -0.2, 2.8) },
				{ Name = "Teeth", Shape = "Block", Color = Color3.fromRGB(240, 240, 240), Size = Vector3.new(1.2, 0.25, 0.9), Offset = Vector3.new(0, -0.55, 2.8) },
				{ Name = "Tailfin", Shape = "Wedge", Color = Color3.fromRGB(45, 115, 55), Size = Vector3.new(0.4, 1.6, 1.2), Offset = Vector3.new(0, 1.2, -2.2) },
			},
		},
		Moves = {
			{ Name = "Carpet Bomb", Type = "Fire", Power = 70, Accuracy = 95, Description = "The whole runway is the target." },
			{ Name = "Croc Chomp",  Type = "Fire", Power = 85, Accuracy = 90, Description = "Jets are optional. Teeth are forever." },
		},
	},
	{
		Id = "ballerina",
		Name = "Ballerina Cappuccina",
		Type = "Sky",
		Rarity = "Epic",
		HP = 75, Attack = 80, Defense = 65, Speed = 95,
		Description = "A cappuccino ballerina. Graceful, deadly, and always on pointe.",
		Display = {
			Shape = "Cylinder",
			Color = Color3.fromRGB(235, 215, 190),
			Size = Vector3.new(2.2, 2.6, 2.2),
			Face = true,
			Extras = {
				{ Name = "Foam", Shape = "Cylinder", Color = Color3.fromRGB(250, 245, 235), Size = Vector3.new(2.3, 0.4, 2.3), Offset = Vector3.new(0, 1.4, 0) },
				{ Name = "Tutu", Shape = "Cylinder", Color = Color3.fromRGB(245, 170, 200), Size = Vector3.new(3.8, 0.4, 3.8), Offset = Vector3.new(0, -0.9, 0) },
				{ Name = "Tiara", Shape = "Cylinder", Color = Color3.fromRGB(250, 210, 90), Size = Vector3.new(1.0, 0.5, 1.0), Offset = Vector3.new(0, 1.9, 0) },
				{ Name = "ShoeL", Shape = "Block", Color = Color3.fromRGB(240, 150, 180), Size = Vector3.new(0.6, 0.5, 1.0), Offset = Vector3.new(-0.5, -1.5, 0.6) },
				{ Name = "ShoeR", Shape = "Block", Color = Color3.fromRGB(240, 150, 180), Size = Vector3.new(0.6, 0.5, 1.0), Offset = Vector3.new(0.5, -1.5, 0.6) },
			},
		},
		Moves = {
			{ Name = "Pirouette Kick",  Type = "Sky", Power = 60, Accuracy = 100, Description = "Three spins. One knockout." },
			{ Name = "Espresso Encore", Type = "Sky", Power = 80, Accuracy = 90,  Description = "The crowd goes wild. So does the damage." },
		},
	},
	{
		Id = "saturnita",
		Name = "La Vaca Saturno Saturnita",
		Type = "Sky",
		Rarity = "Legendary",
		HP = 100, Attack = 95, Defense = 90, Speed = 85,
		Description = "A cosmic cow ringed by Saturn itself. Moo echoes across galaxies.",
		Display = {
			Shape = "Ball",
			Color = Color3.fromRGB(240, 240, 240),
			Size = Vector3.new(3.0, 3.0, 3.0),
			Face = true,
			Extras = {
				{ Name = "Spot1", Shape = "Ball", Color = Color3.fromRGB(30, 30, 30), Size = Vector3.new(0.9, 0.9, 0.5), Offset = Vector3.new(0.8, 0.8, 1.2) },
				{ Name = "Spot2", Shape = "Ball", Color = Color3.fromRGB(30, 30, 30), Size = Vector3.new(0.7, 0.7, 0.5), Offset = Vector3.new(-0.7, -0.5, 1.3) },
				{ Name = "Ring", Shape = "Cylinder", Color = Color3.fromRGB(230, 190, 120), Size = Vector3.new(6.5, 0.25, 6.5), Offset = Vector3.new(0, 0.3, 0), Rotation = Vector3.new(0.35, 0, 0.15) },
				{ Name = "HornL", Shape = "Cylinder", Color = Color3.fromRGB(240, 230, 200), Size = Vector3.new(0.3, 0.8, 0.3), Offset = Vector3.new(-0.9, 1.7, 0.3) },
				{ Name = "HornR", Shape = "Cylinder", Color = Color3.fromRGB(240, 230, 200), Size = Vector3.new(0.3, 0.8, 0.3), Offset = Vector3.new(0.9, 1.7, 0.3) },
			},
		},
		Moves = {
			{ Name = "Cosmic Moo", Type = "Sky", Power = 80, Accuracy = 95, Description = "A moo that bends spacetime." },
			{ Name = "Ring Toss",  Type = "Sky", Power = 95, Accuracy = 90, Description = "Saturn's ring, thrown like a frisbee." },
		},
	},
	{
		Id = "patapim",
		Name = "Brr Brr Patapim",
		Type = "Wood",
		Rarity = "Legendary",
		HP = 105, Attack = 90, Defense = 95, Speed = 60,
		Description = "An ancient tree spirit. It has seen forests rise and fall, and it hits like all of them.",
		Display = {
			Shape = "Cylinder",
			Color = Color3.fromRGB(110, 75, 45),
			Size = Vector3.new(2.4, 3.6, 2.4),
			Face = "angry",
			Extras = {
				{ Name = "Canopy", Shape = "Ball", Color = Color3.fromRGB(60, 140, 60), Size = Vector3.new(4.2, 2.6, 4.2), Offset = Vector3.new(0, 2.8, 0) },
				{ Name = "Canopy2", Shape = "Ball", Color = Color3.fromRGB(75, 160, 75), Size = Vector3.new(2.6, 1.8, 2.6), Offset = Vector3.new(1.4, 3.6, 0.5) },
				{ Name = "RootL", Shape = "Wedge", Color = Color3.fromRGB(95, 65, 40), Size = Vector3.new(1.0, 1.0, 1.4), Offset = Vector3.new(-1.2, -1.6, 0.4) },
				{ Name = "RootR", Shape = "Wedge", Color = Color3.fromRGB(95, 65, 40), Size = Vector3.new(1.0, 1.0, 1.4), Offset = Vector3.new(1.2, -1.6, 0.4) },
			},
		},
		Moves = {
			{ Name = "Brr Barrage",   Type = "Wood", Power = 70, Accuracy = 100, Description = "A hailstorm of ancient leaves." },
			{ Name = "Forest Rumble", Type = "Wood", Power = 85, Accuracy = 90,  Description = "The whole forest swings at once." },
		},
	},
	{
		Id = "frigo_camelo",
		Name = "Frigo Camelo",
		Type = "Water",
		Rarity = "Common",
		HP = 62, Attack = 48, Defense = 62, Speed = 40,
		Description = "A camel crossed with a refrigerator. Keeps your drinks cold and your enemies colder.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(170, 175, 185),
			Size = Vector3.new(2.6, 3.4, 2.2),
			Face = true,
			Extras = {
				{ Name = "HumpL", Shape = "Ball", Color = Color3.fromRGB(200, 160, 110), Size = Vector3.new(1.2, 1.0, 1.2), Offset = Vector3.new(-0.6, 2.0, -0.2) },
				{ Name = "HumpR", Shape = "Ball", Color = Color3.fromRGB(200, 160, 110), Size = Vector3.new(1.2, 1.0, 1.2), Offset = Vector3.new(0.6, 2.0, -0.2) },
				{ Name = "Head", Shape = "Block", Color = Color3.fromRGB(200, 160, 110), Size = Vector3.new(1.2, 1.2, 1.6), Offset = Vector3.new(0, 0.8, 1.7) },
				{ Name = "Handle", Shape = "Block", Color = Color3.fromRGB(60, 60, 65), Size = Vector3.new(0.25, 1.4, 0.25), Offset = Vector3.new(0.9, 0.3, 1.15) },
				{ Name = "DoorLine", Shape = "Block", Color = Color3.fromRGB(120, 125, 135), Size = Vector3.new(0.08, 3.0, 0.08), Offset = Vector3.new(0, 0, 1.12) },
			},
		},
		Moves = {
			{ Name = "Ice Box Slam", Type = "Water", Power = 45, Accuracy = 100, Description = "A door slams. The temperature drops." },
			{ Name = "Frosty Hump",  Type = "Water", Power = 60, Accuracy = 90,  Description = "Chilled to absolute zero. Almost." },
		},
	},
	{
		Id = "orangutini",
		Name = "Orangutini Ananassini",
		Type = "Fire",
		Rarity = "Common",
		HP = 58, Attack = 58, Defense = 45, Speed = 55,
		Description = "An orangutan-pineapple hybrid. Sweet on the outside, spicy on the inside.",
		Display = {
			Shape = "Ball",
			Color = Color3.fromRGB(230, 130, 50),
			Size = Vector3.new(2.8, 3.0, 2.8),
			Face = true,
			Extras = {
				{ Name = "Spike1", Shape = "Wedge", Color = Color3.fromRGB(70, 160, 70), Size = Vector3.new(0.5, 1.0, 0.5), Offset = Vector3.new(-0.5, 1.9, 0) },
				{ Name = "Spike2", Shape = "Wedge", Color = Color3.fromRGB(70, 160, 70), Size = Vector3.new(0.5, 1.0, 0.5), Offset = Vector3.new(0, 2.0, 0) },
				{ Name = "Spike3", Shape = "Wedge", Color = Color3.fromRGB(70, 160, 70), Size = Vector3.new(0.5, 1.0, 0.5), Offset = Vector3.new(0.5, 1.9, 0) },
				{ Name = "ArmL", Shape = "Cylinder", Color = Color3.fromRGB(200, 110, 45), Size = Vector3.new(0.6, 2.2, 0.6), Offset = Vector3.new(-1.7, -0.3, 0), Rotation = Vector3.new(0, 0, 0.25) },
				{ Name = "ArmR", Shape = "Cylinder", Color = Color3.fromRGB(200, 110, 45), Size = Vector3.new(0.6, 2.2, 0.6), Offset = Vector3.new(1.7, -0.3, 0), Rotation = Vector3.new(0, 0, -0.25) },
			},
		},
		Moves = {
			{ Name = "Pineapple Punch", Type = "Fire", Power = 45, Accuracy = 100, Description = "Tropical. Blunt. Effective." },
			{ Name = "Jungle Blaze",    Type = "Fire", Power = 60, Accuracy = 90,  Description = "The whole canopy catches fire." },
		},
	},
	{
		Id = "cocofanto",
		Name = "Cocofanto Elefanto",
		Type = "Wood",
		Rarity = "Rare",
		HP = 80, Attack = 62, Defense = 75, Speed = 42,
		Description = "A coconut elephant. Hard shell, soft heart, devastating trunk.",
		Display = {
			Shape = "Ball",
			Color = Color3.fromRGB(130, 90, 55),
			Size = Vector3.new(3.2, 3.0, 3.2),
			Face = true,
			Extras = {
				{ Name = "Trunk", Shape = "Cylinder", Color = Color3.fromRGB(115, 80, 50), Size = Vector3.new(0.8, 2.2, 0.8), Offset = Vector3.new(0, -0.8, 1.9), Rotation = Vector3.new(0.45, 0, 0) },
				{ Name = "EarL", Shape = "Ball", Color = Color3.fromRGB(110, 75, 45), Size = Vector3.new(0.4, 1.8, 1.6), Offset = Vector3.new(-1.9, 0.6, 0.2) },
				{ Name = "EarR", Shape = "Ball", Color = Color3.fromRGB(110, 75, 45), Size = Vector3.new(0.4, 1.8, 1.6), Offset = Vector3.new(1.9, 0.6, 0.2) },
				{ Name = "Crack", Shape = "Block", Color = Color3.fromRGB(90, 60, 35), Size = Vector3.new(1.4, 0.18, 0.3), Offset = Vector3.new(0, 1.2, 1.0), Rotation = Vector3.new(0, 0, 0.4) },
			},
		},
		Moves = {
			{ Name = "Coconut Crush", Type = "Wood", Power = 60, Accuracy = 95, Description = "Crack! Right on the helmet." },
			{ Name = "Trunk Slam",    Type = "Wood", Power = 70, Accuracy = 90, Description = "A trunk with the force of a falling palm tree." },
		},
	},
	{
		Id = "rhino_toasterino",
		Name = "Rhino Toasterino",
		Type = "Fire",
		Rarity = "Rare",
		HP = 78, Attack = 74, Defense = 68, Speed = 48,
		Description = "A rhinoceros crossed with a toaster. Charges at breakfast speed. Breakfast is hot.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(190, 195, 205),
			Size = Vector3.new(2.8, 2.2, 2.0),
			Face = "angry",
			Extras = {
				{ Name = "Horn", Shape = "Wedge", Color = Color3.fromRGB(150, 150, 155), Size = Vector3.new(0.7, 1.2, 0.7), Offset = Vector3.new(0, 0.2, 1.3), Rotation = Vector3.new(-0.3, 0, 0) },
				{ Name = "Toast", Shape = "Block", Color = Color3.fromRGB(220, 180, 120), Size = Vector3.new(1.4, 1.0, 0.3), Offset = Vector3.new(0, 1.6, 0) },
				{ Name = "Slot", Shape = "Block", Color = Color3.fromRGB(60, 60, 65), Size = Vector3.new(1.8, 0.15, 0.6), Offset = Vector3.new(0, 1.12, 0) },
				{ Name = "EarL", Shape = "Wedge", Color = Color3.fromRGB(170, 175, 185), Size = Vector3.new(0.5, 0.7, 0.4), Offset = Vector3.new(-1.0, 1.3, -0.4) },
				{ Name = "EarR", Shape = "Wedge", Color = Color3.fromRGB(170, 175, 185), Size = Vector3.new(0.5, 0.7, 0.4), Offset = Vector3.new(1.0, 1.3, -0.4) },
			},
		},
		Moves = {
			{ Name = "Toast Charge", Type = "Fire", Power = 60, Accuracy = 95, Description = "Golden brown and coming in hot." },
			{ Name = "Pop-Up Blast", Type = "Fire", Power = 70, Accuracy = 90,  Description = "DING! Maximum heat achieved." },
		},
	},
	{
		Id = "svinina",
		Name = "Svinina Bombardino",
		Type = "Shadow",
		Rarity = "Legendary",
		HP = 98, Attack = 100, Defense = 80, Speed = 92,
		Description = "A pig crossed with a bomber plane. When pigs fly, everything explodes.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(245, 170, 180),
			Size = Vector3.new(2.4, 1.8, 4.2),
			Face = true,
			Extras = {
				{ Name = "WingL", Shape = "Block", Color = Color3.fromRGB(225, 140, 150), Size = Vector3.new(3.0, 0.25, 1.4), Offset = Vector3.new(-2.1, 0.2, -0.5) },
				{ Name = "WingR", Shape = "Block", Color = Color3.fromRGB(225, 140, 150), Size = Vector3.new(3.0, 0.25, 1.4), Offset = Vector3.new(2.1, 0.2, -0.5) },
				{ Name = "Snout", Shape = "Cylinder", Color = Color3.fromRGB(230, 150, 160), Size = Vector3.new(1.0, 0.6, 1.0), Offset = Vector3.new(0, -0.2, 2.3), Rotation = Vector3.new(1.57, 0, 0) },
				{ Name = "BombL", Shape = "Ball", Color = Color3.fromRGB(60, 60, 65), Size = Vector3.new(0.8, 0.8, 0.8), Offset = Vector3.new(-0.9, -1.2, 0) },
				{ Name = "BombR", Shape = "Ball", Color = Color3.fromRGB(60, 60, 65), Size = Vector3.new(0.8, 0.8, 0.8), Offset = Vector3.new(0.9, -1.2, 0) },
				{ Name = "EarL", Shape = "Wedge", Color = Color3.fromRGB(230, 150, 160), Size = Vector3.new(0.5, 0.6, 0.3), Offset = Vector3.new(-0.7, 1.1, 1.2) },
				{ Name = "EarR", Shape = "Wedge", Color = Color3.fromRGB(230, 150, 160), Size = Vector3.new(0.5, 0.6, 0.3), Offset = Vector3.new(0.7, 1.1, 1.2) },
			},
		},
		Moves = {
			{ Name = "Pork Barrel Bomb", Type = "Shadow", Power = 85, Accuracy = 90, Description = "Legislative-grade explosives." },
			{ Name = "Swine Dive",      Type = "Shadow", Power = 95, Accuracy = 90, Description = "The sky screams. Then silence." },
		},
	},
	{
		Id = "cacto",
		Name = "Il Cacto Ippopotamo",
		Type = "Wood",
		Rarity = "Common",
		HP = 70, Attack = 50, Defense = 65, Speed = 35,
		Description = "A cactus hippo. Don't hug it. Seriously.",
		Display = {
			Shape = "Ball",
			Color = Color3.fromRGB(75, 165, 75),
			Size = Vector3.new(3.4, 3.0, 3.4),
			Face = "angry",
			Extras = {
				{ Name = "Snout", Shape = "Block", Color = Color3.fromRGB(65, 150, 65), Size = Vector3.new(1.8, 1.2, 1.2), Offset = Vector3.new(0, -0.5, 1.9) },
				{ Name = "Spike1", Shape = "Wedge", Color = Color3.fromRGB(140, 220, 140), Size = Vector3.new(0.4, 0.9, 0.4), Offset = Vector3.new(-1.0, 1.7, 0.3) },
				{ Name = "Spike2", Shape = "Wedge", Color = Color3.fromRGB(140, 220, 140), Size = Vector3.new(0.4, 0.9, 0.4), Offset = Vector3.new(0, 1.8, 0.3) },
				{ Name = "Spike3", Shape = "Wedge", Color = Color3.fromRGB(140, 220, 140), Size = Vector3.new(0.4, 0.9, 0.4), Offset = Vector3.new(1.0, 1.7, 0.3) },
				{ Name = "Spike4", Shape = "Wedge", Color = Color3.fromRGB(140, 220, 140), Size = Vector3.new(0.4, 0.9, 0.4), Offset = Vector3.new(-1.5, 0.6, 0.9) },
				{ Name = "Spike5", Shape = "Wedge", Color = Color3.fromRGB(140, 220, 140), Size = Vector3.new(0.4, 0.9, 0.4), Offset = Vector3.new(1.5, 0.6, 0.9) },
				{ Name = "EarL", Shape = "Ball", Color = Color3.fromRGB(65, 150, 65), Size = Vector3.new(0.5, 0.5, 0.3), Offset = Vector3.new(-0.8, 1.5, 0.6) },
				{ Name = "EarR", Shape = "Ball", Color = Color3.fromRGB(65, 150, 65), Size = Vector3.new(0.5, 0.5, 0.3), Offset = Vector3.new(0.8, 1.5, 0.6) },
			},
		},
		Moves = {
			{ Name = "Spiky Stomp", Type = "Wood", Power = 45, Accuracy = 100, Description = "Two tons of spikes." },
			{ Name = "Hippo Hug",   Type = "Wood", Power = 60, Accuracy = 90,  Description = "The last hug you'll ever want." },
		},
	},
	{
		Id = "trippi",
		Name = "Trippi Troppi",
		Type = "Water",
		Rarity = "Common",
		HP = 60, Attack = 52, Defense = 55, Speed = 50,
		Description = "A fish-bear hybrid. Swims like a bear, mauls like a fish. Wait.",
		Display = {
			Shape = "Ball",
			Color = Color3.fromRGB(170, 120, 80),
			Size = Vector3.new(3.0, 2.8, 3.0),
			Face = true,
			Extras = {
				{ Name = "Tail", Shape = "Wedge", Color = Color3.fromRGB(200, 140, 70), Size = Vector3.new(1.8, 1.6, 0.4), Offset = Vector3.new(0, 0, -2.0) },
				{ Name = "Dorsal", Shape = "Wedge", Color = Color3.fromRGB(150, 105, 65), Size = Vector3.new(1.0, 1.0, 0.4), Offset = Vector3.new(0, 1.7, -0.3) },
				{ Name = "EarL", Shape = "Ball", Color = Color3.fromRGB(150, 105, 65), Size = Vector3.new(0.6, 0.6, 0.4), Offset = Vector3.new(-1.0, 1.4, 0.3) },
				{ Name = "EarR", Shape = "Ball", Color = Color3.fromRGB(150, 105, 65), Size = Vector3.new(0.6, 0.6, 0.4), Offset = Vector3.new(1.0, 1.4, 0.3) },
			},
		},
		Moves = {
			{ Name = "Fish Slap",     Type = "Water", Power = 45, Accuracy = 100, Description = "Disrespectful. Effective." },
			{ Name = "Bear Hug Wave", Type = "Water", Power = 60, Accuracy = 90,  Description = "A tidal wave with arms." },
		},
	},
	{
		Id = "pipi_kiwi",
		Name = "Pipi Kiwi",
		Type = "Sky",
		Rarity = "Common",
		HP = 48, Attack = 52, Defense = 42, Speed = 80,
		Description = "A tiny kiwi bird with enormous confidence.",
		Display = {
			Shape = "Ball",
			Color = Color3.fromRGB(150, 110, 70),
			Size = Vector3.new(1.8, 1.8, 1.8),
			Face = true,
			Extras = {
				{ Name = "Beak", Shape = "Cylinder", Color = Color3.fromRGB(210, 170, 110), Size = Vector3.new(0.25, 1.2, 0.25), Offset = Vector3.new(0, 0, 1.3), Rotation = Vector3.new(1.57, 0, 0) },
				{ Name = "WingL", Shape = "Block", Color = Color3.fromRGB(130, 95, 60), Size = Vector3.new(0.25, 0.9, 0.8), Offset = Vector3.new(-1.0, 0, 0) },
				{ Name = "WingR", Shape = "Block", Color = Color3.fromRGB(130, 95, 60), Size = Vector3.new(0.25, 0.9, 0.8), Offset = Vector3.new(1.0, 0, 0) },
				{ Name = "FootL", Shape = "Block", Color = Color3.fromRGB(210, 150, 80), Size = Vector3.new(0.4, 0.25, 0.7), Offset = Vector3.new(-0.4, -1.0, 0.3) },
				{ Name = "FootR", Shape = "Block", Color = Color3.fromRGB(210, 150, 80), Size = Vector3.new(0.4, 0.25, 0.7), Offset = Vector3.new(0.4, -1.0, 0.3) },
			},
		},
		Moves = {
			{ Name = "Peck Storm",   Type = "Sky", Power = 45, Accuracy = 100, Description = "A thousand tiny pecks." },
			{ Name = "Kiwi Cyclone", Type = "Sky", Power = 60, Accuracy = 90,  Description = "Small bird. Big tornado." },
		},
	},
	{
		Id = "blueberrinni",
		Name = "Blueberrinni Octopussini",
		Type = "Water",
		Rarity = "Rare",
		HP = 70, Attack = 68, Defense = 62, Speed = 60,
		Description = "A blueberry octopus. Eight arms, all of them sticky.",
		Display = {
			Shape = "Ball",
			Color = Color3.fromRGB(70, 90, 200),
			Size = Vector3.new(2.8, 2.6, 2.8),
			Face = true,
			Extras = {
				{ Name = "Tent1", Shape = "Cylinder", Color = Color3.fromRGB(55, 70, 170), Size = Vector3.new(0.4, 1.8, 0.4), Offset = Vector3.new(-1.0, -1.8, 0.3) },
				{ Name = "Tent2", Shape = "Cylinder", Color = Color3.fromRGB(55, 70, 170), Size = Vector3.new(0.4, 1.9, 0.4), Offset = Vector3.new(-0.35, -1.9, -0.2) },
				{ Name = "Tent3", Shape = "Cylinder", Color = Color3.fromRGB(55, 70, 170), Size = Vector3.new(0.4, 1.9, 0.4), Offset = Vector3.new(0.35, -1.9, -0.2) },
				{ Name = "Tent4", Shape = "Cylinder", Color = Color3.fromRGB(55, 70, 170), Size = Vector3.new(0.4, 1.8, 0.4), Offset = Vector3.new(1.0, -1.8, 0.3) },
				{ Name = "Crown", Shape = "Wedge", Color = Color3.fromRGB(90, 180, 90), Size = Vector3.new(0.7, 0.6, 0.7), Offset = Vector3.new(0, 1.6, 0) },
			},
		},
		Moves = {
			{ Name = "Ink Burst",  Type = "Water", Power = 55, Accuracy = 95, Description = "Blueberry ink. Stains forever." },
			{ Name = "Berry Slam", Type = "Water", Power = 70, Accuracy = 90, Description = "Splat." },
		},
	},
	{
		Id = "chef_crab",
		Name = "Chef Crabracadabra",
		Type = "Fire",
		Rarity = "Rare",
		HP = 68, Attack = 76, Defense = 58, Speed = 62,
		Description = "A crab chef whose signature dish is his opponent. Served flambéed.",
		Display = {
			Shape = "Ball",
			Color = Color3.fromRGB(220, 70, 60),
			Size = Vector3.new(3.2, 2.0, 2.6),
			Face = "angry",
			Extras = {
				{ Name = "HatTop", Shape = "Cylinder", Color = Color3.fromRGB(245, 245, 245), Size = Vector3.new(1.6, 1.2, 1.6), Offset = Vector3.new(0, 1.8, 0) },
				{ Name = "HatBrim", Shape = "Cylinder", Color = Color3.fromRGB(240, 240, 240), Size = Vector3.new(2.0, 0.3, 2.0), Offset = Vector3.new(0, 1.25, 0) },
				{ Name = "ClawL", Shape = "Ball", Color = Color3.fromRGB(190, 55, 45), Size = Vector3.new(1.0, 1.0, 1.0), Offset = Vector3.new(-1.9, -0.3, 1.0) },
				{ Name = "ClawR", Shape = "Ball", Color = Color3.fromRGB(190, 55, 45), Size = Vector3.new(1.0, 1.0, 1.0), Offset = Vector3.new(1.9, -0.3, 1.0) },
				{ Name = "LegL", Shape = "Cylinder", Color = Color3.fromRGB(190, 55, 45), Size = Vector3.new(0.3, 1.4, 0.3), Offset = Vector3.new(-1.4, -1.0, -0.6), Rotation = Vector3.new(0, 0, 0.4) },
				{ Name = "LegR", Shape = "Cylinder", Color = Color3.fromRGB(190, 55, 45), Size = Vector3.new(0.3, 1.4, 0.3), Offset = Vector3.new(1.4, -1.0, -0.6), Rotation = Vector3.new(0, 0, -0.4) },
			},
		},
		Moves = {
			{ Name = "Sear Slam",     Type = "Fire", Power = 55, Accuracy = 95, Description = "Seared on both sides." },
			{ Name = "Flambé Finale", Type = "Fire", Power = 75, Accuracy = 90, Description = "The grand finale. It's on fire." },
		},
	},
	{
		Id = "zibra",
		Name = "Zibra Zubra Zibralini",
		Type = "Shadow",
		Rarity = "Rare",
		HP = 66, Attack = 72, Defense = 60, Speed = 78,
		Description = "A zebra that only appears at midnight. The stripes are a warning.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(45, 45, 55),
			Size = Vector3.new(2.4, 2.6, 3.8),
			Face = "angry",
			Extras = {
				{ Name = "Stripe1", Shape = "Block", Color = Color3.fromRGB(235, 235, 235), Size = Vector3.new(2.5, 2.7, 0.35), Offset = Vector3.new(0, 0, -1.2) },
				{ Name = "Stripe2", Shape = "Block", Color = Color3.fromRGB(235, 235, 235), Size = Vector3.new(2.5, 2.7, 0.35), Offset = Vector3.new(0, 0, 0) },
				{ Name = "Stripe3", Shape = "Block", Color = Color3.fromRGB(235, 235, 235), Size = Vector3.new(2.5, 2.7, 0.35), Offset = Vector3.new(0, 0, 1.2) },
				{ Name = "Mane", Shape = "Wedge", Color = Color3.fromRGB(20, 20, 25), Size = Vector3.new(0.5, 1.0, 2.6), Offset = Vector3.new(0, 1.7, -0.2) },
				{ Name = "Tail", Shape = "Cylinder", Color = Color3.fromRGB(20, 20, 25), Size = Vector3.new(0.25, 1.8, 0.25), Offset = Vector3.new(0, 0, -2.3), Rotation = Vector3.new(0.5, 0, 0) },
			},
		},
		Moves = {
			{ Name = "Stripe Slash",    Type = "Shadow", Power = 55, Accuracy = 95, Description = "Black and white and red all over." },
			{ Name = "Midnight Gallop", Type = "Shadow", Power = 70, Accuracy = 90, Description = "Heard, never seen. Until it's too late." },
		},
	},
	{
		Id = "chicleteira",
		Name = "Chicleteira Bicicleteira",
		Type = "Sky",
		Rarity = "Rare",
		HP = 64, Attack = 66, Defense = 58, Speed = 88,
		Description = "A bubble-gum bicycle. Sticky, speedy, and impossible to park.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(245, 150, 200),
			Size = Vector3.new(1.2, 1.2, 3.6),
			Extras = {
				{ Name = "WheelF", Shape = "Cylinder", Color = Color3.fromRGB(30, 30, 30), Size = Vector3.new(0.5, 1.8, 1.8), Offset = Vector3.new(0, -1.2, 1.5), Rotation = Vector3.new(0, 0, 1.57) },
				{ Name = "WheelB", Shape = "Cylinder", Color = Color3.fromRGB(30, 30, 30), Size = Vector3.new(0.5, 1.8, 1.8), Offset = Vector3.new(0, -1.2, -1.5), Rotation = Vector3.new(0, 0, 1.57) },
				{ Name = "Bar", Shape = "Cylinder", Color = Color3.fromRGB(180, 180, 185), Size = Vector3.new(0.25, 1.6, 0.25), Offset = Vector3.new(0, 1.0, 1.7), Rotation = Vector3.new(0, 0, 1.57) },
				{ Name = "Seat", Shape = "Block", Color = Color3.fromRGB(60, 60, 65), Size = Vector3.new(0.8, 0.3, 0.9), Offset = Vector3.new(0, 0.8, -1.2) },
				{ Name = "Bubble", Shape = "Ball", Color = Color3.fromRGB(250, 180, 210), Size = Vector3.new(1.6, 1.6, 1.6), Offset = Vector3.new(0, 1.6, 0.6), Transparency = 0.3 },
			},
		},
		Moves = {
			{ Name = "Bubble Barrage", Type = "Sky", Power = 55, Accuracy = 95, Description = "Pop! Pop! Pop!" },
			{ Name = "Spoke Spin",     Type = "Sky", Power = 70, Accuracy = 90, Description = "A wheel of pink fury." },
		},
	},
	{
		Id = "pot_hotspot",
		Name = "Pot Hotspot",
		Type = "Fire",
		Rarity = "Epic",
		HP = 85, Attack = 88, Defense = 70, Speed = 60,
		Description = "A pressure cooker with anger issues. Do NOT lift the lid.",
		Display = {
			Shape = "Cylinder",
			Color = Color3.fromRGB(180, 185, 195),
			Size = Vector3.new(2.8, 2.4, 2.8),
			Face = "angry",
			Extras = {
				{ Name = "Lid", Shape = "Cylinder", Color = Color3.fromRGB(150, 155, 165), Size = Vector3.new(3.0, 0.5, 3.0), Offset = Vector3.new(0, 1.4, 0) },
				{ Name = "Knob", Shape = "Ball", Color = Color3.fromRGB(40, 40, 45), Size = Vector3.new(0.5, 0.5, 0.5), Offset = Vector3.new(0, 1.85, 0) },
				{ Name = "Steam1", Shape = "Ball", Color = Color3.fromRGB(245, 245, 245), Size = Vector3.new(0.8, 0.8, 0.8), Offset = Vector3.new(-0.5, 2.5, 0), Transparency = 0.5 },
				{ Name = "Steam2", Shape = "Ball", Color = Color3.fromRGB(245, 245, 245), Size = Vector3.new(0.6, 0.6, 0.6), Offset = Vector3.new(0.4, 2.9, 0.2), Transparency = 0.5 },
				{ Name = "HandleL", Shape = "Block", Color = Color3.fromRGB(120, 125, 135), Size = Vector3.new(0.8, 0.35, 0.5), Offset = Vector3.new(-1.7, 0.6, 0) },
				{ Name = "HandleR", Shape = "Block", Color = Color3.fromRGB(120, 125, 135), Size = Vector3.new(0.8, 0.35, 0.5), Offset = Vector3.new(1.7, 0.6, 0) },
			},
		},
		Moves = {
			{ Name = "Boil Over",      Type = "Fire", Power = 70, Accuracy = 95, Description = "The lid is off. Run." },
			{ Name = "Pressure Burst", Type = "Fire", Power = 85, Accuracy = 90, Description = "Maximum PSI. Minimum survivors." },
		},
	},
	{
		Id = "gorillo",
		Name = "Gorillo Watermelondrillo",
		Type = "Wood",
		Rarity = "Epic",
		HP = 95, Attack = 92, Defense = 78, Speed = 55,
		Description = "A watermelon gorilla. King of the jungle buffet.",
		Display = {
			Shape = "Ball",
			Color = Color3.fromRGB(45, 130, 60),
			Size = Vector3.new(3.2, 3.2, 3.0),
			Face = "angry",
			Extras = {
				{ Name = "ArmL", Shape = "Cylinder", Color = Color3.fromRGB(35, 110, 50), Size = Vector3.new(0.9, 2.6, 0.9), Offset = Vector3.new(-2.0, -0.6, 0), Rotation = Vector3.new(0, 0, 0.2) },
				{ Name = "ArmR", Shape = "Cylinder", Color = Color3.fromRGB(35, 110, 50), Size = Vector3.new(0.9, 2.6, 0.9), Offset = Vector3.new(2.0, -0.6, 0), Rotation = Vector3.new(0, 0, -0.2) },
				{ Name = "Stripe1", Shape = "Block", Color = Color3.fromRGB(25, 90, 35), Size = Vector3.new(3.3, 0.4, 0.7), Offset = Vector3.new(0, 1.0, -0.5) },
				{ Name = "Stripe2", Shape = "Block", Color = Color3.fromRGB(25, 90, 35), Size = Vector3.new(3.3, 0.4, 0.7), Offset = Vector3.new(0, -0.4, -0.7) },
				{ Name = "Chest", Shape = "Ball", Color = Color3.fromRGB(90, 170, 95), Size = Vector3.new(1.8, 2.0, 0.8), Offset = Vector3.new(0, -0.2, 1.3) },
			},
		},
		Moves = {
			{ Name = "Rind Wrecker",     Type = "Wood", Power = 70, Accuracy = 95, Description = "The rind is the weapon." },
			{ Name = "Jungle King Slam", Type = "Wood", Power = 85, Accuracy = 90, Description = "All hail. Then, slam." },
		},
	},
	{
		Id = "tralaleritos",
		Name = "Los Tralaleritos",
		Type = "Water",
		Rarity = "Epic",
		HP = 75, Attack = 85, Defense = 65, Speed = 92,
		Description = "Three mini shark pups in tiny sneakers. Triple the trouble.",
		Display = {
			Shape = "Ball",
			Color = Color3.fromRGB(70, 140, 210),
			Size = Vector3.new(2.4, 2.0, 2.8),
			Face = true,
			Extras = {
				{ Name = "PupL", Shape = "Ball", Color = Color3.fromRGB(70, 140, 210), Size = Vector3.new(1.2, 1.0, 1.4), Offset = Vector3.new(-1.7, -0.4, 0.3) },
				{ Name = "PupR", Shape = "Ball", Color = Color3.fromRGB(70, 140, 210), Size = Vector3.new(1.2, 1.0, 1.4), Offset = Vector3.new(1.7, -0.4, 0.3) },
				{ Name = "Dorsal", Shape = "Wedge", Color = Color3.fromRGB(50, 110, 180), Size = Vector3.new(0.9, 1.0, 0.4), Offset = Vector3.new(0, 1.3, -0.3) },
				{ Name = "ShoeL", Shape = "Block", Color = Color3.fromRGB(235, 235, 240), Size = Vector3.new(0.7, 0.5, 1.1), Offset = Vector3.new(-0.6, -1.15, 0.7) },
				{ Name = "ShoeR", Shape = "Block", Color = Color3.fromRGB(235, 235, 240), Size = Vector3.new(0.7, 0.5, 1.1), Offset = Vector3.new(0.6, -1.15, 0.7) },
			},
		},
		Moves = {
			{ Name = "Triple Splash",     Type = "Water", Power = 65, Accuracy = 95, Description = "One pup, two pups, THREE pups." },
			{ Name = "Tiny Terror Tide",  Type = "Water", Power = 80, Accuracy = 90, Description = "Small teeth. Big wave." },
		},
	},
	{
		Id = "orcalero",
		Name = "Orcalero Orcala",
		Type = "Water",
		Rarity = "Legendary",
		HP = 102, Attack = 96, Defense = 92, Speed = 78,
		Description = "The orca queen of the deep. The ocean has a ruler, and she is not asking.",
		Display = {
			Shape = "Ball",
			Color = Color3.fromRGB(35, 35, 40),
			Size = Vector3.new(3.2, 2.8, 4.0),
			Face = true,
			Extras = {
				{ Name = "Belly", Shape = "Ball", Color = Color3.fromRGB(240, 240, 240), Size = Vector3.new(2.6, 2.0, 3.2), Offset = Vector3.new(0, -0.7, 0.5) },
				{ Name = "Dorsal", Shape = "Wedge", Color = Color3.fromRGB(25, 25, 30), Size = Vector3.new(1.2, 1.6, 0.4), Offset = Vector3.new(0, 1.9, -0.5) },
				{ Name = "Crown", Shape = "Cylinder", Color = Color3.fromRGB(250, 205, 70), Size = Vector3.new(1.4, 0.8, 1.4), Offset = Vector3.new(0, 1.8, 0.6) },
				{ Name = "FlukeL", Shape = "Wedge", Color = Color3.fromRGB(25, 25, 30), Size = Vector3.new(1.2, 0.5, 0.9), Offset = Vector3.new(-0.7, -0.2, -2.3) },
				{ Name = "FlukeR", Shape = "Wedge", Color = Color3.fromRGB(25, 25, 30), Size = Vector3.new(1.2, 0.5, 0.9), Offset = Vector3.new(0.7, -0.2, -2.3) },
			},
		},
		Moves = {
			{ Name = "Abyssal Breach", Type = "Water", Power = 85, Accuracy = 90, Description = "The surface shatters." },
			{ Name = "Orca Oblivion",  Type = "Water", Power = 100, Accuracy = 85, Description = "No witnesses. Only bubbles." },
		},
	},
	{
		Id = "1x1x1x1",
		Name = "1x1x1x1",
		Type = "Tech",
		Rarity = "Rare",
		HP = 80, Attack = 82, Defense = 77, Speed = 67,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Data Blast", Type = "Tech", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "System Crash", Type = "Tech", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "agarrini_la_pallini",
		Name = "Agarrini La Pallini",
		Type = "Normal",
		Rarity = "Common",
		HP = 61, Attack = 50, Defense = 66, Speed = 64,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "avocadini_guffo",
		Name = "Avocadini Guffo",
		Type = "Grass",
		Rarity = "Common",
		HP = 64, Attack = 41, Defense = 47, Speed = 66,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Vine Whip", Type = "Grass", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Leaf Blade", Type = "Grass", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "ballerino_lololo",
		Name = "Ballerino Lololo",
		Type = "Charm",
		Rarity = "Common",
		HP = 41, Attack = 65, Defense = 50, Speed = 52,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Charm", Type = "Charm", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Dazzle", Type = "Charm", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "bambini_crostini",
		Name = "Bambini Crostini",
		Type = "Normal",
		Rarity = "Rare",
		HP = 68, Attack = 62, Defense = 66, Speed = 89,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "banana_dancana",
		Name = "Banana Dancana",
		Type = "Grass",
		Rarity = "Rare",
		HP = 90, Attack = 78, Defense = 88, Speed = 82,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Vine Whip", Type = "Grass", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Leaf Blade", Type = "Grass", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "bobrito_bandito",
		Name = "Bobrito Bandito",
		Type = "Normal",
		Rarity = "Common",
		HP = 54, Attack = 44, Defense = 48, Speed = 44,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "boneca_ambalabu",
		Name = "Boneca Ambalabu",
		Type = "Charm",
		Rarity = "Common",
		HP = 47, Attack = 63, Defense = 57, Speed = 57,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Charm", Type = "Charm", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Dazzle", Type = "Charm", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "brri_brri_bicus_dicus",
		Name = "Brri Brri Bicus Dicus",
		Type = "Normal",
		Rarity = "Common",
		HP = 48, Attack = 63, Defense = 58, Speed = 53,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "burbaloni_luliloli",
		Name = "Burbaloni Luliloli",
		Type = "Normal",
		Rarity = "Common",
		HP = 68, Attack = 58, Defense = 52, Speed = 51,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "cachorrito_melonito",
		Name = "Cachorrito Melonito",
		Type = "Grass",
		Rarity = "Common",
		HP = 47, Attack = 44, Defense = 56, Speed = 55,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Vine Whip", Type = "Grass", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Leaf Blade", Type = "Grass", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "cavallo_virtuoso",
		Name = "Cavallo Virtuoso",
		Type = "Beast",
		Rarity = "Rare",
		HP = 63, Attack = 64, Defense = 80, Speed = 65,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Tackle", Type = "Beast", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Crunch", Type = "Beast", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "chicleteirina_bicicleteirina",
		Name = "Chicleteirina Bicicleteirina",
		Type = "Normal",
		Rarity = "Common",
		HP = 65, Attack = 61, Defense = 53, Speed = 59,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "chillin_chili",
		Name = "Chillin Chili",
		Type = "Fire",
		Rarity = "Common",
		HP = 42, Attack = 52, Defense = 52, Speed = 59,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Ember", Type = "Fire", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Flame Burst", Type = "Fire", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "dragon_cannelloni",
		Name = "Dragon Cannelloni",
		Type = "Fire",
		Rarity = "Rare",
		HP = 74, Attack = 76, Defense = 68, Speed = 77,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Ember", Type = "Fire", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Flame Burst", Type = "Fire", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "esok_sekolah",
		Name = "Esok Sekolah",
		Type = "Normal",
		Rarity = "Epic",
		HP = 107, Attack = 110, Defense = 80, Speed = 101,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "espresso_signora",
		Name = "Espresso Signora",
		Type = "Electric",
		Rarity = "Common",
		HP = 63, Attack = 43, Defense = 61, Speed = 68,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Spark", Type = "Electric", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Thunderbolt", Type = "Electric", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "fluri_flura",
		Name = "Fluri Flura",
		Type = "Normal",
		Rarity = "Epic",
		HP = 97, Attack = 104, Defense = 88, Speed = 104,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "ganganzelli_trulala",
		Name = "Ganganzelli Trulala",
		Type = "Normal",
		Rarity = "Rare",
		HP = 80, Attack = 70, Defense = 63, Speed = 69,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "garamararam",
		Name = "Garamararam",
		Type = "Normal",
		Rarity = "Common",
		HP = 53, Attack = 45, Defense = 54, Speed = 40,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "girafa_celeste",
		Name = "Girafa Celeste",
		Type = "Beast",
		Rarity = "Common",
		HP = 70, Attack = 63, Defense = 68, Speed = 63,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Tackle", Type = "Beast", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Crunch", Type = "Beast", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "glorbo_fruttodrillo",
		Name = "Glorbo Fruttodrillo",
		Type = "Normal",
		Rarity = "Legendary",
		HP = 108, Attack = 116, Defense = 124, Speed = 105,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "illuminato_triangolo",
		Name = "Illuminato Triangolo",
		Type = "Electric",
		Rarity = "Common",
		HP = 56, Attack = 69, Defense = 43, Speed = 67,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Spark", Type = "Electric", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Thunderbolt", Type = "Electric", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "job_job_job_sahur",
		Name = "Job Job Job Sahur",
		Type = "Fire",
		Rarity = "Common",
		HP = 60, Attack = 49, Defense = 66, Speed = 60,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Ember", Type = "Fire", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Flame Burst", Type = "Fire", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "karkerkar_kurkur",
		Name = "Karkerkar Kurkur",
		Type = "Normal",
		Rarity = "Common",
		HP = 56, Attack = 59, Defense = 46, Speed = 44,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "la_grande_combinasion",
		Name = "La Grande Combinasion",
		Type = "Normal",
		Rarity = "Epic",
		HP = 91, Attack = 104, Defense = 85, Speed = 97,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "lerulerulerule",
		Name = "Lerulerulerule",
		Type = "Normal",
		Rarity = "Epic",
		HP = 109, Attack = 80, Defense = 99, Speed = 90,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "lionel_cactuseli",
		Name = "Lionel Cactuseli",
		Type = "Grass",
		Rarity = "Rare",
		HP = 75, Attack = 60, Defense = 63, Speed = 89,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Vine Whip", Type = "Grass", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Leaf Blade", Type = "Grass", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "madudung",
		Name = "Madudung",
		Type = "Normal",
		Rarity = "Common",
		HP = 51, Attack = 68, Defense = 66, Speed = 65,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "matteo",
		Name = "Matteo",
		Type = "Tech",
		Rarity = "Legendary",
		HP = 109, Attack = 107, Defense = 101, Speed = 107,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Data Blast", Type = "Tech", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "System Crash", Type = "Tech", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "meowl",
		Name = "Meowl",
		Type = "Normal",
		Rarity = "Common",
		HP = 68, Attack = 58, Defense = 70, Speed = 42,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "noo_my_examen",
		Name = "Noo My Examen",
		Type = "Normal",
		Rarity = "Rare",
		HP = 62, Attack = 83, Defense = 75, Speed = 86,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "nyannini_cattalini",
		Name = "Nyannini Cattalini",
		Type = "Beast",
		Rarity = "Epic",
		HP = 82, Attack = 104, Defense = 97, Speed = 104,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Tackle", Type = "Beast", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Crunch", Type = "Beast", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "odin_din_din_dun",
		Name = "Odin Din Din Dun",
		Type = "Normal",
		Rarity = "Rare",
		HP = 64, Attack = 64, Defense = 81, Speed = 75,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "pakrahmatmamat",
		Name = "Pakrahmatmamat",
		Type = "Normal",
		Rarity = "Epic",
		HP = 110, Attack = 97, Defense = 85, Speed = 88,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "pakrahmatmatina",
		Name = "Pakrahmatmatina",
		Type = "Normal",
		Rarity = "Rare",
		HP = 76, Attack = 87, Defense = 79, Speed = 73,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "pipi_potato",
		Name = "Pipi Potato",
		Type = "Normal",
		Rarity = "Common",
		HP = 64, Attack = 63, Defense = 62, Speed = 46,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "quesadilla_crocodila",
		Name = "Quesadilla Crocodila",
		Type = "Normal",
		Rarity = "Common",
		HP = 62, Attack = 49, Defense = 52, Speed = 61,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "six_seven",
		Name = "Six Seven",
		Type = "Normal",
		Rarity = "Common",
		HP = 60, Attack = 51, Defense = 54, Speed = 68,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "smurfo_gatto",
		Name = "Smurfo Gatto",
		Type = "Beast",
		Rarity = "Common",
		HP = 56, Attack = 54, Defense = 43, Speed = 47,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Tackle", Type = "Beast", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Crunch", Type = "Beast", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "strawberrelli_flamingelli",
		Name = "Strawberrelli Flamingelli",
		Type = "Normal",
		Rarity = "Common",
		HP = 47, Attack = 42, Defense = 50, Speed = 40,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "strawberry_elephant",
		Name = "Strawberry Elephant",
		Type = "Normal",
		Rarity = "Common",
		HP = 58, Attack = 57, Defense = 47, Speed = 58,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "swag_soda",
		Name = "Swag Soda",
		Type = "Tech",
		Rarity = "Common",
		HP = 47, Attack = 40, Defense = 42, Speed = 62,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Data Blast", Type = "Tech", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "System Crash", Type = "Tech", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "ta_ta_ta_ta_sahur",
		Name = "Ta Ta Ta Ta Sahur",
		Type = "Fire",
		Rarity = "Rare",
		HP = 80, Attack = 61, Defense = 67, Speed = 62,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Ember", Type = "Fire", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Flame Burst", Type = "Fire", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "talpa_di_fero",
		Name = "Talpa Di Fero",
		Type = "Normal",
		Rarity = "Common",
		HP = 68, Attack = 41, Defense = 67, Speed = 50,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "tigroligre_frutonni",
		Name = "Tigroligre Frutonni",
		Type = "Beast",
		Rarity = "Common",
		HP = 42, Attack = 56, Defense = 47, Speed = 48,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Tackle", Type = "Beast", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Crunch", Type = "Beast", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "tim_cheese",
		Name = "Tim Cheese",
		Type = "Tech",
		Rarity = "Common",
		HP = 61, Attack = 55, Defense = 46, Speed = 57,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Data Blast", Type = "Tech", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "System Crash", Type = "Tech", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "tirilikalika_tirilikalako",
		Name = "Tirilikalika Tirilikalako",
		Type = "Normal",
		Rarity = "Common",
		HP = 44, Attack = 63, Defense = 69, Speed = 68,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "torrtuginni_dragonfrutini",
		Name = "Torrtuginni Dragonfrutini",
		Type = "Fire",
		Rarity = "Epic",
		HP = 98, Attack = 98, Defense = 95, Speed = 87,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Ember", Type = "Fire", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Flame Burst", Type = "Fire", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "tralaledon",
		Name = "Tralaledon",
		Type = "Water",
		Rarity = "Rare",
		HP = 85, Attack = 75, Defense = 85, Speed = 73,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Water Gun", Type = "Water", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Aqua Tail", Type = "Water", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "tralalita_tralala",
		Name = "Tralalita Tralala",
		Type = "Water",
		Rarity = "Rare",
		HP = 66, Attack = 63, Defense = 63, Speed = 81,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Water Gun", Type = "Water", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Aqua Tail", Type = "Water", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "tric_trac_barabum",
		Name = "Tric Trac Barabum",
		Type = "Normal",
		Rarity = "Common",
		HP = 53, Attack = 51, Defense = 53, Speed = 53,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "trulimero_trulicina",
		Name = "Trulimero Trulicina",
		Type = "Charm",
		Rarity = "Common",
		HP = 61, Attack = 60, Defense = 60, Speed = 43,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Charm", Type = "Charm", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Dazzle", Type = "Charm", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "w_or_l",
		Name = "W Or L",
		Type = "Normal",
		Rarity = "Common",
		HP = 41, Attack = 52, Defense = 63, Speed = 50,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
	{
		Id = "yess_my_examen",
		Name = "Yess My Examen",
		Type = "Normal",
		Rarity = "Legendary",
		HP = 125, Attack = 127, Defense = 103, Speed = 107,
		Description = "A wild brainrot from the expanded collection.",
		Display = {
			Shape = "Block",
			Color = Color3.fromRGB(150, 150, 150),
			Size = Vector3.new(2.0, 2.0, 2.0),
			Face = true,
		},
		Moves = {
			{ Name = "Pound", Type = "Normal", Power = 45, Accuracy = 100, Description = "A basic attack." },
			{ Name = "Body Slam", Type = "Normal", Power = 65, Accuracy = 95, Description = "A strong attack." },
		},
	},
}

-- // Lookups ------------------------------------------------------------------
local byId = {}
for _, def in ipairs(BrainrotData.ROSTER) do
	byId[def.Id] = def
end

function BrainrotData.GetById(id: string)
	return byId[id]
end

-- Alias: much of the codebase calls this GetBrainrot.
BrainrotData.GetBrainrot = BrainrotData.GetById

function BrainrotData.GetStarterId(): string
	return "tung_sahur"
end

-- // Milestone 2: fusion, orb rewards, rivals ----------------------------------
-- Weighted random reward for orb caches: mostly Commons, rarely better.
BrainrotData.ORB_REWARD_WEIGHTS = {
	Common = 62, Rare = 27, Epic = 9, Legendary = 2,
}

function BrainrotData.GetRandomIdOfRarity(rarity: string): string?
	local pool = {}
	for _, def in ipairs(BrainrotData.ROSTER) do
		if def.Rarity == rarity then
			table.insert(pool, def.Id)
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[math.random(1, #pool)]
end

function BrainrotData.RollRewardRarity(): string
	local total = 0
	for _, w in pairs(BrainrotData.ORB_REWARD_WEIGHTS) do
		total += w
	end
	local roll = math.random() * total
	for _, rarity in ipairs(BrainrotData.RARITY_ORDER) do
		roll -= BrainrotData.ORB_REWARD_WEIGHTS[rarity] or 0
		if roll <= 0 then
			return rarity
		end
	end
	return "Common"
end

-- Fusion: 3 duplicates of one brainrot + materials -> next rarity up.
-- Material type follows the sacrificed brainrot's effective type.
-- 3 Legendaries -> a guaranteed SHINY (any brainrot). Shiny sacrifices
-- are blocked to protect lucky pulls.
BrainrotData.FUSION_MATERIAL_COST = { Common = 15, Rare = 30, Epic = 60 }
BrainrotData.FUSION_COIN_COST = { Common = 100, Rare = 250, Epic = 500, Legendary = 1000 }

function BrainrotData.GetFusionResultRarity(rarity: string): string?
	for i, r in ipairs(BrainrotData.RARITY_ORDER) do
		if r == rarity and i < #BrainrotData.RARITY_ORDER then
			return BrainrotData.RARITY_ORDER[i + 1]
		end
	end
	return nil
end

-- Effective type -> work station that produces its material.
function BrainrotData.GetWorkIdForType(brainrotType: string): string?
	for workId, workDef in pairs(BrainrotData.WORK_TYPES) do
		if workDef.Type == brainrotType then
			return workId
		end
	end
	return nil
end

-- Fusion spends plot-work materials matching the brainrot's type.
-- Unknown types (Normal, Charm, …) spend Timber so fusion still works.
function BrainrotData.GetFusionMaterialInfo(def: any, variantId: string?): (string, string, number, number)
	local rarity = (def and def.Rarity) or "Common"
	local matCost = BrainrotData.FUSION_MATERIAL_COST[rarity] or 15
	local coinCost = BrainrotData.FUSION_COIN_COST[rarity] or 100
	local t = BrainrotData.GetEffectiveType(def, variantId)
	local workId = BrainrotData.GetWorkIdForType(t) or "foraging"
	local workDef = BrainrotData.WORK_TYPES[workId]
	local matName = workDef and workDef.Material or "Timber"
	return workId, matName, matCost, coinCost
end

-- 100 sequential arena gates. Teams and power scale with the gate number.
local function idsOfRarity(rarity: string): { string }
	local pool = {}
	for _, def in ipairs(BrainrotData.ROSTER) do
		if def.Rarity == rarity then
			table.insert(pool, def.Id)
		end
	end
	return pool
end

local commonIds = idsOfRarity("Common")
local rareIds = idsOfRarity("Rare")
local epicIds = idsOfRarity("Epic")
local legendIds = idsOfRarity("Legendary")

local function cycleId(pool: { string }, n: number, offset: number): string
	if #pool == 0 then
		return "tung_sahur"
	end
	return pool[((n + offset - 1) % #pool) + 1]
end

local function teamForGate(n: number): { string }
	if n <= 12 then
		return { cycleId(commonIds, n, 0), cycleId(commonIds, n, 3), cycleId(commonIds, n, 7) }
	elseif n <= 28 then
		return { cycleId(commonIds, n, 1), cycleId(commonIds, n, 5), cycleId(rareIds, n, 0) }
	elseif n <= 45 then
		return { cycleId(commonIds, n, 2), cycleId(rareIds, n, 1), cycleId(rareIds, n, 4) }
	elseif n <= 62 then
		return { cycleId(rareIds, n, 2), cycleId(rareIds, n, 6), cycleId(epicIds, n, 0) }
	elseif n <= 78 then
		return { cycleId(rareIds, n, 3), cycleId(epicIds, n, 1), cycleId(epicIds, n, 5) }
	elseif n <= 90 then
		return { cycleId(epicIds, n, 2), cycleId(epicIds, n, 6), cycleId(legendIds, n, 0) }
	elseif n <= 99 then
		return { cycleId(epicIds, n, 3), cycleId(legendIds, n, 1), cycleId(legendIds, n, 4) }
	end
	return { cycleId(legendIds, n, 0), cycleId(legendIds, n, 2), cycleId(legendIds, n, 5) }
end

local GATE_TITLES = {
	"Backyard Brawler", "Street Scrapper", "Harbor Hitter", "Forest Duelist",
	"River Rascal", "Hill Hunter", "Cave Crusher", "Sky Scrapper",
	"Ember Acolyte", "Tide Warden", "Shadow Pupil", "Timber Knight",
	"Arena Regular", "Pit Veteran", "Crowd Favorite", "Gatekeeper",
	"Storm Caller", "Ash Champion", "Deep Current", "Night Blade",
	"Colosseum Elite", "Grand Duelist", "War Priest", "Finalist",
	"Undefeated", "World Threat", "Brainrot King", "Last Legend",
}

BrainrotData.RIVALS = {}
for n = 1, 100 do
	local coins = 180 + n * 45 + math.floor(n * n * 0.65)
	local rarityReward: string? = nil
	if n == 100 then
		rarityReward = "Legendary"
		coins += 20000
	elseif n % 25 == 0 then
		rarityReward = "Legendary"
	elseif n % 10 == 0 then
		rarityReward = "Epic"
	elseif n % 5 == 0 then
		rarityReward = "Rare"
	end
	table.insert(BrainrotData.RIVALS, {
		Id = "gate_" .. string.format("%03d", n),
		Name = "Battle " .. tostring(n),
		Title = GATE_TITLES[((n - 1) % #GATE_TITLES) + 1],
		Team = teamForGate(n),
		PowerScale = 0.55 + ((n - 1) / 99) * 1.85,
		RewardCoins = coins,
		RewardRarity = rarityReward,
		Gate = n,
	})
end

local rivalById = {}
for _, rival in ipairs(BrainrotData.RIVALS) do
	rivalById[rival.Id] = rival
end

function BrainrotData.GetRival(id: string)
	return rivalById[id]
end

function BrainrotData.GetRivalIndex(id: string): number
	for i, rival in ipairs(BrainrotData.RIVALS) do
		if rival.Id == id then
			return i
		end
	end
	return 0
end

-- // Exploration & Expeditions ---------------------------------------------------
-- Five discoverable zones. Each has unique materials and a favored brainrot type.
-- Send 1-3 brainrots on a 15-minute expedition; type match boosts yields.
BrainrotData.ZONES = {
	whispering_woods = {
		Name = "Whispering Woods",
		Description = "Ancient trees hum with old magic. Wood types feel at home here.",
		Color = Color3.fromRGB(45, 130, 70),
		FavoredType = "Wood",
		Materials = { "Timber", "Ancient Bark", "Glowcap" },
		UnlockHint = "Use the green Expedition Gate",
	},
	sunken_ruins = {
		Name = "Sunken Ruins",
		Description = "Flooded temples hide treasures below. Water types dive deepest.",
		Color = Color3.fromRGB(40, 110, 160),
		FavoredType = "Water",
		Materials = { "Fish", "Pearl Shard", "Sunken Gold" },
		UnlockHint = "Use the blue Expedition Gate",
	},
	ember_peaks = {
		Name = "Ember Peaks",
		Description = "Volcanic rock and rivers of lava. Fire types thrive in the heat.",
		Color = Color3.fromRGB(200, 70, 30),
		FavoredType = "Fire",
		Materials = { "Ingots", "Ember Crystal", "Obsidian" },
		UnlockHint = "Use the red Expedition Gate",
	},
	crystal_caves = {
		Name = "Crystal Caves",
		Description = "Light refracts through endless crystal. Sky types navigate the echoes.",
		Color = Color3.fromRGB(130, 180, 230),
		FavoredType = "Sky",
		Materials = { "Cloud Cotton", "Prism Shard", "Echo Stone" },
		UnlockHint = "Use the crystal Expedition Gate",
	},
	storm_summit = {
		Name = "Storm Summit",
		Description = "The highest peak, wrapped in eternal storm. Shadow types slip through unseen.",
		Color = Color3.fromRGB(70, 70, 100),
		FavoredType = "Shadow",
		Materials = { "Dark Stone", "Storm Core", "Void Essence" },
		UnlockHint = "Use the storm Expedition Gate",
	},
}
BrainrotData.ZONE_ORDER = { "whispering_woods", "sunken_ruins", "ember_peaks", "crystal_caves", "storm_summit" }

-- Other Places in this Experience (Creator Hub → Places). 0 = not linked yet.
-- After you publish the Laser Tag template as a place under Brainrot Arena,
-- paste its Place ID here (or set Workspace attribute LaserTagPlaceId).
BrainrotData.PLACE_GATES = {
	{
		Id = "laser_tag",
		Name = "Laser Tag",
		PlaceId = 0,
		Color = Color3.fromRGB(40, 220, 70),
		X = 44,
		Z = 28,
		Attribute = "LaserTagPlaceId",
	},
}

-- Expedition tuning.
BrainrotData.EXPEDITION_DURATION = 15 * 60 -- 15 minutes, as requested
BrainrotData.EXPEDITION_TEAM_MIN = 1
BrainrotData.EXPEDITION_TEAM_MAX = 3
BrainrotData.EXPEDITION_BASE_MATS = 8 -- base materials per expedition (scaled by team/type)
BrainrotData.EXPEDITION_TYPE_BONUS = 1.5 -- multiplier if any team member matches zone FavoredType

-- Rare expedition-only materials and their colors (for UI).
BrainrotData.RARE_MATERIALS = {
	["Ancient Bark"] = Color3.fromRGB(110, 75, 40),
	["Glowcap"]      = Color3.fromRGB(120, 230, 150),
	["Pearl Shard"]  = Color3.fromRGB(240, 230, 220),
	["Sunken Gold"]  = Color3.fromRGB(255, 200, 60),
	["Ember Crystal"]= Color3.fromRGB(255, 100, 40),
	["Obsidian"]     = Color3.fromRGB(35, 35, 45),
	["Prism Shard"]  = Color3.fromRGB(180, 220, 255),
	["Echo Stone"]   = Color3.fromRGB(150, 150, 190),
	["Storm Core"]   = Color3.fromRGB(100, 140, 255),
	["Void Essence"] = Color3.fromRGB(60, 30, 90),
}

-- // Mystery Eggs ----------------------------------------------------------------
-- Earned from daily quests. Full mystery: no preview. Hatch with playtime.
BrainrotData.EGG_TIERS = {
	small = {
		Name = "Small Egg",
		Color = Color3.fromRGB(180, 200, 180),
		HatchMinutes = 20, -- of active playtime
		Weights = { Common = 70, Rare = 22, Epic = 7, Legendary = 1 },
	},
	big = {
		Name = "Big Egg",
		Color = Color3.fromRGB(140, 180, 230),
		HatchMinutes = 45,
		Weights = { Common = 40, Rare = 35, Epic = 20, Legendary = 5 },
	},
	golden = {
		Name = "Golden Egg",
		Color = Color3.fromRGB(255, 200, 60),
		HatchMinutes = 90,
		Weights = { Common = 15, Rare = 30, Epic = 35, Legendary = 20 },
	},
}
BrainrotData.EGG_ORDER = { "small", "big", "golden" }
BrainrotData.INCUBATOR_SLOTS = 3 -- base; more purchasable with coins

-- // Daily Quests -----------------------------------------------------------------
-- Three tiers per day. Complete all three for a bonus egg.
BrainrotData.DAILY_TIERS = {
	easy =   { Name = "Easy",   EggReward = "small",  Color = Color3.fromRGB(120, 200, 120) },
	medium = { Name = "Medium", EggReward = "big",    Color = Color3.fromRGB(100, 150, 230) },
	hard =   { Name = "Hard",   EggReward = "golden", Color = Color3.fromRGB(230, 150, 60) },
}
-- Quest templates: { Description, Target, RewardCoins }. Target varies by tier.
BrainrotData.DAILY_QUEST_POOL = {
	easy = {
		{ Text = "Collect 10 coins from the obby", Target = 10, Coins = 150 },
		{ Text = "Collect 3 Brainrot Orbs", Target = 3, Coins = 150 },
		{ Text = "Collect materials from a workstation", Target = 5, Coins = 180 },
	},
	medium = {
		{ Text = "Win 1 battle in the Arena", Target = 1, Coins = 500 },
		{ Text = "Complete 1 expedition", Target = 1, Coins = 450 },
		{ Text = "Fuse 1 brainrot", Target = 1, Coins = 500 },
		{ Text = "Collect 30 coins from the obby", Target = 30, Coins = 400 },
	},
	hard = {
		{ Text = "Win 5 battles in the Arena", Target = 5, Coins = 2200 },
		{ Text = "Complete 3 expeditions", Target = 3, Coins = 1600 },
		{ Text = "Hatch 1 mystery egg", Target = 1, Coins = 1400 },
		{ Text = "Earn 500 coins", Target = 500, Coins = 1800 },
	},
}

-- // Passive Income (Gold Mine) -------------------------------------------------------
-- Single currency: coins. The gold mine on your plot generates coins per minute
-- while you are actively in-game. Rewards playtime, not idling.
BrainrotData.PASSIVE_COINS_PER_MINUTE = 5
BrainrotData.PASSIVE_CAP_MINUTES = 120 -- max 2 hours banked; collect to reset
BrainrotData.GOLD_MINE_UPGRADES = {
	-- level -> { Cost, RatePerMinute }
	{ Cost = 0,    RatePerMinute = 5 },
	{ Cost = 500,  RatePerMinute = 10 },
	{ Cost = 1500, RatePerMinute = 20 },
	{ Cost = 4000, RatePerMinute = 35 },
}

-- // Base Customization ----------------------------------------------------------------
-- Spend coins + materials to personalize your plot. Pure self-expression.
BrainrotData.PLOT_THEMES = {
	default = { Name = "Meadow", Cost = 0, Materials = {}, Color = Color3.fromRGB(90, 160, 90) },
	crystal = { Name = "Crystal", Cost = 1000, Materials = { ["Prism Shard"] = 5 }, Color = Color3.fromRGB(150, 200, 255) },
	volcanic = { Name = "Volcanic", Cost = 1000, Materials = { ["Ember Crystal"] = 5 }, Color = Color3.fromRGB(180, 60, 30) },
	ocean = { Name = "Ocean", Cost = 1000, Materials = { ["Pearl Shard"] = 5 }, Color = Color3.fromRGB(50, 130, 180) },
	shadow = { Name = "Shadow", Cost = 2000, Materials = { ["Void Essence"] = 5 }, Color = Color3.fromRGB(60, 60, 90) },
}
BrainrotData.PLOT_DECORATIONS = {
	banner =   { Name = "Victory Banner", Cost = 300, Materials = { Timber = 10 } },
	fountain = { Name = "Coin Fountain", Cost = 800, Materials = { ["Sunken Gold"] = 3 } },
	torch =    { Name = "Ember Torch", Cost = 500, Materials = { ["Ember Crystal"] = 2 } },
	crystal_deco = { Name = "Crystal Cluster", Cost = 500, Materials = { ["Prism Shard"] = 2 } },
	statue =   { Name = "Golden Statue", Cost = 2000, Materials = { ["Sunken Gold"] = 5 } },
	garden =   { Name = "Flower Garden", Cost = 400, Materials = { Timber = 5, ["Glowcap"] = 2 } },
	flags =    { Name = "Pennant Flags", Cost = 350, Materials = { ["Cloud Cotton"] = 5 } },
	lantern =  { Name = "Spirit Lantern", Cost = 600, Materials = { ["Echo Stone"] = 2 } },
	golem =    { Name = "Stone Golem", Cost = 1500, Materials = { ["Dark Stone"] = 10, ["Obsidian"] = 2 } },
}

return BrainrotData
