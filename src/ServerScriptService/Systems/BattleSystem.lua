--!strict
--[[
	BattleSystem (ModuleScript -> ServerScriptService/Systems)
	Server-authoritative turn-based 3v3 battle engine vs AI rivals.

	Flow: StartBattle validates the player's team of 3, then each turn the
	client submits one move index per fighter. The server picks AI moves,
	resolves all six fighters in Speed order, and returns turn events.
	The client is never trusted with damage math.

	Damage (simplified Pokemon-like, flat level 50):
	  base = ((((2*50/5 + 2) * Power * Atk/Def) / 50) + 2)
	  dmg  = floor(base * STAB(1.5) * effectiveness * rand(0.85-1.0) * crit(1.5))
	Crit chance 1/16. Accuracy roll per move. Targets: random living foe.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local BattleSystem = {}

local battles: { [number]: any } = {} -- [userId] -> battle state

local function buildFighter(def: any, variantId: string?, instanceId: string?): any
	local effType = BrainrotData.GetEffectiveType(def, variantId)
	return {
		InstanceId = instanceId,
		BrainrotId = def.Id,
		Variant = variantId,
		Name = BrainrotData.GetDisplayName(def, variantId, false),
		Type = effType,
		Shiny = false,
		MaxHP = def.HP,
		HP = def.HP,
		Attack = def.Attack,
		Defense = def.Defense,
		Speed = def.Speed,
		Moves = def.Moves,
	}
end

local function calcDamage(attacker: any, move: any, defender: any): any
	-- Accuracy check.
	if math.random() * 100 > (move.Accuracy or 100) then
		return { miss = true, damage = 0 }
	end
	local stab = if move.Type == attacker.Type then 1.5 else 1.0
	local eff = BrainrotData.GetEffectiveness(move.Type, defender.Type)
	local rand = 0.85 + math.random() * 0.15
	local crit = math.random() < 0.0625
	local base = ((((2 * 50 / 5 + 2) * move.Power * attacker.Attack / math.max(1, defender.Defense)) / 50) + 2)
	local dmg = math.floor(base * stab * eff * rand * (if crit then 1.5 else 1.0))
	dmg = math.max(1, dmg)
	return { miss = false, damage = dmg, effectiveness = eff, crit = crit }
end

local function livingFighters(team: any): any
	local out = {}
	for i, f in ipairs(team) do
		if f.HP > 0 then
			table.insert(out, { fighter = f, index = i })
		end
	end
	return out
end

-- AI: pick the highest-scoring move vs a random living player fighter.
local function pickAiMove(enemy: any, playerTeam: any): (number, number)
	local targets = livingFighters(playerTeam)
	if #targets == 0 then
		return 1, 0
	end
	local target = targets[math.random(1, #targets)].fighter
	local bestIdx, bestScore = 1, -1
	for i, move in ipairs(enemy.Moves) do
		local eff = BrainrotData.GetEffectiveness(move.Type, target.Type)
		local score = move.Power * eff * ((move.Accuracy or 100) / 100)
		if score > bestScore then
			bestScore = score
			bestIdx = i
		end
	end
	-- 20% of the time just pick something random (keeps AI human).
	if math.random() < 0.2 then
		bestIdx = math.random(1, #enemy.Moves)
	end
	return bestIdx, 0
end

-- Validate and create a battle. Returns (battle, nil) or (nil, err).
function BattleSystem.StartBattle(player: Player, rivalId: string, teamIds: any): (any?, string?)
	if battles[player.UserId] then
		return nil, "already"
	end
	local rival = BrainrotData.GetRival(rivalId)
	if not rival then
		return nil, "badrival"
	end
	-- Sequential unlock: rival N needs rival N-1 beaten.
	local idx = BrainrotData.GetRivalIndex(rivalId)
	if idx > 1 then
		local prev = BrainrotData.RIVALS[idx - 1]
		if not PlayerData.HasBeatenRival(player, prev.Id) then
			return nil, "locked"
		end
	end
	-- Validate team: 3 distinct owned instances, none working.
	if type(teamIds) ~= "table" or #teamIds ~= 3 then
		return nil, "badteam"
	end
	local working = PlayerData.GetWorkingIds(player)
	local seen: { [string]: boolean } = {}
	local pTeam = {}
	for _, id in ipairs(teamIds) do
		if type(id) ~= "string" or seen[id] then
			return nil, "badteam"
		end
		seen[id] = true
		if working[id] then
			return nil, "working"
		end
		local inst = PlayerData.GetInstance(player, id)
		if not inst then
			return nil, "badteam"
		end
		local def = BrainrotData.GetById(inst.BrainrotId)
		if not def then
			return nil, "badteam"
		end
		local f = buildFighter(def, inst.Variant, inst.InstanceId)
		f.Shiny = inst.Shiny == true
		table.insert(pTeam, f)
	end
	local eTeam = {}
	for _, brainrotId in ipairs(rival.Team) do
		local def = BrainrotData.GetById(brainrotId)
		if def then
			table.insert(eTeam, buildFighter(def, nil, nil))
		end
	end
	if #eTeam ~= 3 then
		return nil, "badrival"
	end
	local battle = {
		player = player,
		rivalId = rivalId,
		rivalName = rival.Name,
		pTeam = pTeam,
		eTeam = eTeam,
		turn = 0,
		over = false,
		winner = nil,
	}
	battles[player.UserId] = battle
	return battle, nil
end

function BattleSystem.GetBattle(player: Player): any
	return battles[player.UserId]
end

function BattleSystem.ClearBattle(player: Player)
	battles[player.UserId] = nil
end

function BattleSystem.Forfeit(player: Player): any?
	local battle = battles[player.UserId]
	if not battle or battle.over then
		return nil
	end
	battle.over = true
	battle.winner = "enemy"
	return battle
end

local function teamHp(team: any): any
	local out = {}
	for _, f in ipairs(team) do
		table.insert(out, f.HP)
	end
	return out
end

-- Resolve one turn. moveIndices = {m1, m2, m3} (1-based per fighter).
-- Returns (result, nil) or (nil, err). Result: {events, pHp, eHp, winner?}.
function BattleSystem.SubmitMoves(player: Player, moveIndices: any): (any?, string?)
	local battle = battles[player.UserId]
	if not battle then
		return nil, "nobattle"
	end
	if battle.over then
		return nil, "over"
	end
	if type(moveIndices) ~= "table" or #moveIndices ~= 3 then
		return nil, "badmoves"
	end

	-- Lock in player moves.
	local actions = {} -- {side, idx, fighter, moveIdx}
	for i, fighter in ipairs(battle.pTeam) do
		local mi = moveIndices[i]
		if type(mi) ~= "number" or mi < 1 or mi > #fighter.Moves then
			return nil, "badmoves"
		end
		if fighter.HP > 0 then
			table.insert(actions, { side = "player", idx = i, fighter = fighter, moveIdx = math.floor(mi) })
		end
	end
	-- AI moves.
	for i, fighter in ipairs(battle.eTeam) do
		if fighter.HP > 0 then
			local mi, _ = pickAiMove(fighter, battle.pTeam)
			table.insert(actions, { side = "enemy", idx = i, fighter = fighter, moveIdx = mi })
		end
	end

	-- Speed order (ties broken randomly).
	table.sort(actions, function(a, b)
		if a.fighter.Speed == b.fighter.Speed then
			return math.random() < 0.5
		end
		return a.fighter.Speed > b.fighter.Speed
	end)

	battle.turn += 1
	local events = {}
	for _, act in ipairs(actions) do
		local foeTeam = if act.side == "player" then battle.eTeam else battle.pTeam
		local foes = livingFighters(foeTeam)
		if act.fighter.HP > 0 and #foes > 0 then
			local target = foes[math.random(1, #foes)]
			local move = act.fighter.Moves[act.moveIdx]
			local res = calcDamage(act.fighter, move, target.fighter)
			local event: any = {
				attackerSide = act.side,
				attackerIdx = act.idx,
				attackerName = act.fighter.Name,
				moveName = move.Name,
				moveType = move.Type,
				movePower = move.Power,
				targetSide = if act.side == "player" then "enemy" else "player",
				targetIdx = target.index,
				targetName = target.fighter.Name,
				miss = res.miss,
				damage = res.damage,
				effectiveness = res.effectiveness or 1,
				crit = res.crit or false,
			}
			if not res.miss then
				target.fighter.HP = math.max(0, target.fighter.HP - res.damage)
				event.targetHp = target.fighter.HP
				event.fainted = target.fighter.HP <= 0
			end
			table.insert(events, event)
		end
	end

	-- Win check.
	local pAlive = #livingFighters(battle.pTeam) > 0
	local eAlive = #livingFighters(battle.eTeam) > 0
	local winner: string? = nil
	if not eAlive then
		winner = "player"
	elseif not pAlive then
		winner = "enemy"
	end
	if winner then
		battle.over = true
		battle.winner = winner
	end

	return {
		events = events,
		pHp = teamHp(battle.pTeam),
		eHp = teamHp(battle.eTeam),
		turn = battle.turn,
		winner = winner,
	}, nil
end

-- Snapshot for the client (no hidden AI state).
function BattleSystem.GetClientState(player: Player): any?
	local battle = battles[player.UserId]
	if not battle then
		return nil
	end
	local function pubFighter(f: any): any
		local moves = {}
		for _, m in ipairs(f.Moves) do
			table.insert(moves, { Name = m.Name, Type = m.Type, Power = m.Power })
		end
		return {
			Name = f.Name, Type = f.Type, Shiny = f.Shiny,
			HP = f.HP, MaxHP = f.MaxHP, Moves = moves,
		}
	end
	local pTeam, eTeam = {}, {}
	for _, f in ipairs(battle.pTeam) do
		table.insert(pTeam, pubFighter(f))
	end
	for _, f in ipairs(battle.eTeam) do
		table.insert(eTeam, pubFighter(f))
	end
	return {
		rivalId = battle.rivalId,
		rivalName = battle.rivalName,
		pTeam = pTeam,
		eTeam = eTeam,
		turn = battle.turn,
		over = battle.over,
		winner = battle.winner,
	}
end

return BattleSystem
