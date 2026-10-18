--!strict
--[[
	BattleSystem
	Turn-by-turn 3v3: one brainrot acts at a time in Speed order.
	Player picks a move only when it is their fighter's turn.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local BattleSystem = {}

local battles: { [number]: any } = {}

local function rarityMult(rarity: string?): number
	local tableRef = BrainrotData.RARITY_POWER
	if tableRef and rarity and tableRef[rarity] then
		return tableRef[rarity]
	end
	return 1
end

local function buildFighter(def: any, variantId: string?, instanceId: string?, powerScale: number): any
	local effType = BrainrotData.GetEffectiveType(def, variantId)
	local scale = rarityMult(def.Rarity) * math.max(0.2, powerScale)
	local hp = math.max(8, math.floor(def.HP * scale))
	return {
		InstanceId = instanceId,
		BrainrotId = def.Id,
		Variant = variantId,
		Name = BrainrotData.GetDisplayName(def, variantId, false),
		Type = effType,
		Rarity = def.Rarity,
		Shiny = false,
		MaxHP = hp,
		HP = hp,
		Attack = math.max(5, math.floor(def.Attack * scale)),
		Defense = math.max(5, math.floor(def.Defense * scale)),
		Speed = math.max(5, math.floor(def.Speed * (0.85 + rarityMult(def.Rarity) * 0.15))),
		Moves = BrainrotData.GetBattleMoves(def, variantId),
	}
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

local function teamFainted(team: any): boolean
	return #livingFighters(team) == 0
end

local function pickAiMove(enemy: any, playerTeam: any): number
	local targets = livingFighters(playerTeam)
	if #targets == 0 or not enemy.Moves or #enemy.Moves == 0 then
		return 1
	end
	local bestIdx, bestScore = 1, -1e9
	for i, move in ipairs(enemy.Moves) do
		local score = 0
		if move.Effect == "heal" then
			score = if enemy.HP < enemy.MaxHP * 0.55 then 90 else 10
		elseif move.Effect == "focus" or move.Effect == "shield" then
			score = 35
		else
			local target = targets[1].fighter
			local bestEff = 0
			for _, t in ipairs(targets) do
				local eff = BrainrotData.GetEffectiveness(move.Type, t.fighter.Type)
				if eff > bestEff then
					bestEff = eff
					target = t.fighter
				end
			end
			score = (move.Power or 0) * bestEff * ((move.Accuracy or 100) / 100)
			if move.Type == enemy.Type then
				score *= 1.2
			end
			if target.HP < target.MaxHP * 0.35 and bestEff >= 1 then
				score += 20
			end
		end
		if score > bestScore then
			bestScore = score
			bestIdx = i
		end
	end
	if math.random() < 0.12 then
		bestIdx = math.random(1, #enemy.Moves)
	end
	return bestIdx
end

local function pickTarget(foeTeam: any, move: any): any?
	local foes = livingFighters(foeTeam)
	if #foes == 0 then
		return nil
	end
	local best = foes[1]
	local bestEff = -1
	for _, t in ipairs(foes) do
		local eff = BrainrotData.GetEffectiveness(move.Type or "", t.fighter.Type)
		if eff > bestEff then
			bestEff = eff
			best = t
		elseif eff == bestEff and t.fighter.HP < best.fighter.HP then
			best = t
		end
	end
	return best
end

local function resolveAction(battle: any, act: any, moveIdx: number): any
	local fighter = act.fighter
	local move = fighter.Moves[moveIdx] or fighter.Moves[1]
	local event: any = {
		kind = "attack",
		attackerSide = act.side,
		attackerIdx = act.idx,
		attackerName = fighter.Name,
		moveName = move.Name,
		moveType = move.Type,
		movePower = move.Power,
		miss = false,
		damage = 0,
		effectiveness = 1,
		crit = false,
	}

	if math.random() * 100 > (move.Accuracy or 100) then
		event.miss = true
		local foes = livingFighters(if act.side == "player" then battle.eTeam else battle.pTeam)
		if #foes > 0 then
			event.targetSide = if act.side == "player" then "enemy" else "player"
			event.targetIdx = foes[1].index
			event.targetName = foes[1].fighter.Name
		end
		return event
	end

	if move.Effect == "heal" then
		local heal = math.max(6, math.floor(fighter.MaxHP * 0.28))
		fighter.HP = math.min(fighter.MaxHP, fighter.HP + heal)
		event.kind = "heal"
		event.heal = heal
		event.targetSide = act.side
		event.targetIdx = act.idx
		event.targetName = fighter.Name
		event.targetHp = fighter.HP
		return event
	end

	if move.Effect == "focus" then
		fighter.Attack = math.floor(fighter.Attack * 1.35)
		event.kind = "boost"
		event.boost = "Attack"
		event.targetSide = act.side
		event.targetIdx = act.idx
		event.targetName = fighter.Name
		return event
	end

	if move.Effect == "shield" then
		fighter.Defense = math.floor(fighter.Defense * 1.4)
		event.kind = "boost"
		event.boost = "Defense"
		event.targetSide = act.side
		event.targetIdx = act.idx
		event.targetName = fighter.Name
		return event
	end

	local foeTeam = if act.side == "player" then battle.eTeam else battle.pTeam
	local target = pickTarget(foeTeam, move)
	if not target then
		event.miss = true
		return event
	end

	local stab = if move.Type == fighter.Type then 1.5 else 1.0
	local eff = BrainrotData.GetEffectiveness(move.Type, target.fighter.Type)
	local rand = 0.85 + math.random() * 0.15
	local crit = math.random() < 0.08
	local power = math.max(1, move.Power or 40)
	local base = ((((2 * 50 / 5 + 2) * power * fighter.Attack / math.max(1, target.fighter.Defense)) / 50) + 2)
	local dmg = math.floor(base * stab * eff * rand * (if crit then 1.6 else 1.0))
	dmg = math.max(1, dmg)
	target.fighter.HP = math.max(0, target.fighter.HP - dmg)

	event.targetSide = if act.side == "player" then "enemy" else "player"
	event.targetIdx = target.index
	event.targetName = target.fighter.Name
	event.damage = dmg
	event.effectiveness = eff
	event.crit = crit
	event.targetHp = target.fighter.HP
	event.fainted = target.fighter.HP <= 0
	return event
end

local function checkWinner(battle: any): string?
	if teamFainted(battle.eTeam) then
		return "player"
	end
	if teamFainted(battle.pTeam) then
		return "enemy"
	end
	return nil
end

local function rebuildQueue(battle: any)
	local actions = {}
	for i, f in ipairs(battle.pTeam) do
		if f.HP > 0 then
			table.insert(actions, { side = "player", idx = i, fighter = f })
		end
	end
	for i, f in ipairs(battle.eTeam) do
		if f.HP > 0 then
			table.insert(actions, { side = "enemy", idx = i, fighter = f })
		end
	end
	table.sort(actions, function(a, b)
		if a.fighter.Speed == b.fighter.Speed then
			return math.random() < 0.5
		end
		return a.fighter.Speed > b.fighter.Speed
	end)
	battle.queue = actions
	battle.queuePos = 1
end

local function skipDead(battle: any)
	while battle.queuePos <= #battle.queue do
		local act = battle.queue[battle.queuePos]
		if act.fighter.HP > 0 then
			return
		end
		battle.queuePos += 1
	end
end

local function runUntilPlayer(battle: any): { any }
	local events = {}
	local guard = 0
	while guard < 40 and not battle.over do
		guard += 1
		skipDead(battle)
		if battle.queuePos > #battle.queue then
			rebuildQueue(battle)
			skipDead(battle)
			if battle.queuePos > #battle.queue then
				break
			end
		end
		local act = battle.queue[battle.queuePos]
		if act.side == "player" then
			battle.waitingFor = { side = "player", idx = act.idx, name = act.fighter.Name }
			return events
		end
		if battle.pvp then
			battle.waitingFor = { side = "enemy", idx = act.idx, name = act.fighter.Name }
			return events
		end
		local mi = pickAiMove(act.fighter, battle.pTeam)
		table.insert(events, resolveAction(battle, act, mi))
		battle.queuePos += 1
		local winner = checkWinner(battle)
		if winner then
			battle.over = true
			battle.winner = winner
			battle.waitingFor = nil
			return events
		end
	end
	battle.waitingFor = nil
	return events
end

local function makePlayerTeam(player: Player, teamIds: any): (any?, string?)
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
		local f = buildFighter(def, inst.Variant, inst.InstanceId, 1)
		f.Shiny = inst.Shiny == true
		table.insert(pTeam, f)
	end
	return pTeam, nil
end

function BattleSystem.StartBattle(player: Player, rivalId: string, teamIds: any): (any?, string?)
	if battles[player.UserId] then
		return nil, "already"
	end
	local rival = BrainrotData.GetRival(rivalId)
	if not rival then
		return nil, "badrival"
	end
	local idx = BrainrotData.GetRivalIndex(rivalId)
	if idx > 1 then
		local prev = BrainrotData.RIVALS[idx - 1]
		if not PlayerData.HasBeatenRival(player, prev.Id) then
			return nil, "locked"
		end
	end
	local pTeam, teamErr = makePlayerTeam(player, teamIds)
	if not pTeam then
		return nil, teamErr
	end
	local eTeam = {}
	local powerScale = rival.PowerScale or 1
	for _, brainrotId in ipairs(rival.Team) do
		local def = BrainrotData.GetById(brainrotId)
		if def then
			table.insert(eTeam, buildFighter(def, nil, nil, powerScale))
		end
	end
	if #eTeam ~= 3 then
		return nil, "badrival"
	end
	local battle = {
		player = player,
		rivalId = rivalId,
		rivalName = rival.Name .. " — " .. (rival.Title or ""),
		gate = rival.Gate or idx,
		pTeam = pTeam,
		eTeam = eTeam,
		turn = 1,
		over = false,
		winner = nil,
		waitingFor = nil,
		openingEvents = {},
	}
	battles[player.UserId] = battle
	rebuildQueue(battle)
	battle.openingEvents = runUntilPlayer(battle)
	return battle, nil
end

function BattleSystem.StartPvpBattle(host: Player, hostTeam: any, guest: Player, guestTeam: any): (any?, string?)
	if host == guest then
		return nil, "self"
	end
	if battles[host.UserId] or battles[guest.UserId] then
		return nil, "already"
	end
	local pTeam, errA = makePlayerTeam(host, hostTeam)
	if not pTeam then
		return nil, errA
	end
	local eTeam, errB = makePlayerTeam(guest, guestTeam)
	if not eTeam then
		return nil, errB
	end
	local battle = {
		pvp = true,
		player = host,
		guest = guest,
		rivalId = "pvp",
		rivalName = guest.DisplayName,
		gate = 0,
		pTeam = pTeam,
		eTeam = eTeam,
		turn = 1,
		over = false,
		winner = nil,
		waitingFor = nil,
		openingEvents = {},
	}
	battles[host.UserId] = battle
	battles[guest.UserId] = battle
	rebuildQueue(battle)
	battle.openingEvents = runUntilPlayer(battle)
	return battle, nil
end

function BattleSystem.GetBattle(player: Player): any
	return battles[player.UserId]
end

function BattleSystem.GetViewers(battle: any): { Player }
	local out = { battle.player }
	if battle.pvp and battle.guest then
		table.insert(out, battle.guest)
	end
	return out
end

function BattleSystem.ClearBattle(player: Player)
	local battle = battles[player.UserId]
	if battle then
		if battle.player then
			battles[battle.player.UserId] = nil
		end
		if battle.guest then
			battles[battle.guest.UserId] = nil
		end
	end
	battles[player.UserId] = nil
end

function BattleSystem.Forfeit(player: Player): any?
	local battle = battles[player.UserId]
	if not battle or battle.over then
		return nil
	end
	battle.over = true
	if battle.pvp and battle.guest and player == battle.guest then
		battle.winner = "player"
	else
		battle.winner = "enemy"
	end
	battle.waitingFor = nil
	return battle
end

local function teamHp(team: any): any
	local out = {}
	for _, f in ipairs(team) do
		table.insert(out, f.HP)
	end
	return out
end

function BattleSystem.SubmitSingleMove(player: Player, slot: number, moveIdx: number): (any?, string?)
	local battle = battles[player.UserId]
	if not battle then
		return nil, "nobattle"
	end
	if battle.over then
		return nil, "over"
	end
	local isGuest = battle.pvp and battle.guest ~= nil and player == battle.guest
	local expectSide = if isGuest then "enemy" else "player"
	local waiting = battle.waitingFor
	if not waiting or waiting.side ~= expectSide or waiting.idx ~= slot then
		return nil, "notyourturn"
	end
	local team = if expectSide == "player" then battle.pTeam else battle.eTeam
	local fighter = team[slot]
	if not fighter or fighter.HP <= 0 then
		return nil, "fainted"
	end
	if type(moveIdx) ~= "number" or moveIdx < 1 or moveIdx > #fighter.Moves then
		return nil, "badmoves"
	end
	local act = battle.queue[battle.queuePos]
	if not act or act.side ~= expectSide or act.idx ~= slot then
		return nil, "notyourturn"
	end
	local events = { resolveAction(battle, act, math.floor(moveIdx)) }
	battle.queuePos += 1
	local winner = checkWinner(battle)
	if winner then
		battle.over = true
		battle.winner = winner
		battle.waitingFor = nil
	else
		local rest = runUntilPlayer(battle)
		for _, ev in ipairs(rest) do
			table.insert(events, ev)
		end
		winner = battle.winner
	end
	battle.turn += 1
	return {
		events = events,
		pHp = teamHp(battle.pTeam),
		eHp = teamHp(battle.eTeam),
		turn = battle.turn,
		winner = winner,
	}, nil
end

-- Back-compat: old 3-move payload is ignored; sequential combat uses SubmitSingleMove.
function BattleSystem.SubmitMoves(player: Player, moveIndices: any): (any?, string?)
	if type(moveIndices) == "table" and type(moveIndices.Slot) == "number" then
		return BattleSystem.SubmitSingleMove(player, moveIndices.Slot, moveIndices.Move)
	end
	return nil, "badmoves"
end

function BattleSystem.GetClientState(player: Player): any?
	local battle = battles[player.UserId]
	if not battle then
		return nil
	end
	local function pubFighter(f: any): any
		local moves = {}
		for _, m in ipairs(f.Moves) do
			table.insert(moves, {
				Name = m.Name,
				Type = m.Type,
				Power = m.Power,
				Effect = m.Effect,
				Description = m.Description,
			})
		end
		return {
			Name = f.Name, Type = f.Type, Rarity = f.Rarity, Shiny = f.Shiny,
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
	local waiting = battle.waitingFor
	local winner = battle.winner
	local rivalName = battle.rivalName
	local swap = battle.pvp and battle.guest ~= nil and player == battle.guest
	if swap then
		pTeam, eTeam = eTeam, pTeam
		if waiting then
			waiting = {
				side = if waiting.side == "player" then "enemy" else "player",
				idx = waiting.idx,
				name = waiting.name,
			}
		end
		if winner == "player" then
			winner = "enemy"
		elseif winner == "enemy" then
			winner = "player"
		end
		rivalName = battle.player and battle.player.DisplayName or "Rival"
	end
	return {
		rivalId = battle.rivalId,
		rivalName = rivalName,
		gate = battle.gate,
		pvp = battle.pvp == true,
		pTeam = pTeam,
		eTeam = eTeam,
		turn = battle.turn,
		over = battle.over,
		winner = winner,
		waitingFor = waiting,
	}
end

return BattleSystem
