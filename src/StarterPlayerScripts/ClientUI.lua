--!strict
--[[
	ClientUI (LocalScript -> StarterPlayer > StarterPlayerScripts)
	Builds every UI element in code: quest tracker, coin counter,
	collection panel (all owned INSTANCES, shinies starred),
	showcase editor (pick up to 10 to display), reward banner, hint toast.
	Listens to server RemoteEvents. Never trusts the client with data.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local questRemote = remotes:WaitForChild("QuestUpdate")
local collectionRemote = remotes:WaitForChild("CollectionUpdate")
local hintRemote = remotes:WaitForChild("ShowHint")
local showcaseRemote = remotes:WaitForChild("UpdateShowcase")
-- Milestone 2 remotes.
local openFusionRemote = remotes:WaitForChild("OpenFusion")
local openArenaRemote = remotes:WaitForChild("OpenArena")
local fusionResultRemote = remotes:WaitForChild("FusionResult")
local battleUpdateRemote = remotes:WaitForChild("BattleUpdate")
local fuseRemote = remotes:WaitForChild("FuseBrainrots")
local startBattleRemote = remotes:WaitForChild("StartBattle")
local submitMovesRemote = remotes:WaitForChild("SubmitMoves")
local forfeitRemote = remotes:WaitForChild("ForfeitBattle")
-- Exploration & progression remotes
local startExpeditionRemote = remotes:WaitForChild("StartExpedition")
local expeditionUpdateRemote = remotes:WaitForChild("ExpeditionUpdate")
local unlockZoneRemote = remotes:WaitForChild("UnlockZone")
local claimDailyEggRemote = remotes:WaitForChild("ClaimDailyEgg")
local dailyUpdateRemote = remotes:WaitForChild("DailyUpdate")
local buyEggSlotRemote = remotes:WaitForChild("BuyEggSlot")
local eggUpdateRemote = remotes:WaitForChild("EggUpdate")
local collectPassiveRemote = remotes:WaitForChild("CollectPassive")
local passiveUpdateRemote = remotes:WaitForChild("PassiveUpdate")
local unlockThemeRemote = remotes:WaitForChild("UnlockTheme")
local buyDecorationRemote = remotes:WaitForChild("BuyDecoration")
local customizeUpdateRemote = remotes:WaitForChild("CustomizeUpdate")

-- Forward declarations: defined later in the file, used by M2 UI above.
local showBanner: (string, number) -> ()
local workPanel: ScrollingFrame
local pickerPanel: Frame

-- Client mirror of server state.
local ownedInstances: any = {}   -- array of { InstanceId, BrainrotId, Shiny }
local showcaseIds: { [string]: boolean } = {}
local pendingShowcase: { string } = {}
local workingIds: { [string]: boolean } = {} -- instances at work (M2)

-- // Root ------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "BrainrotUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function pad(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.Parent = parent
end

-- // Quest tracker (top-left) ------------------------------------------------------
local tracker = Instance.new("Frame")
tracker.Name = "QuestTracker"
tracker.Size = UDim2.new(0, 320, 0, 92)
tracker.Position = UDim2.new(0, 16, 0, 16)
tracker.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
tracker.BackgroundTransparency = 0.15
tracker.BorderSizePixel = 0
tracker.Parent = gui
corner(tracker, 10)

local questTitle = Instance.new("TextLabel")
questTitle.Size = UDim2.new(1, -20, 0, 28)
questTitle.Position = UDim2.new(0, 10, 0, 8)
questTitle.BackgroundTransparency = 1
questTitle.Text = "QUEST: ..."
questTitle.Font = Enum.Font.GothamBold
questTitle.TextSize = 18
questTitle.TextXAlignment = Enum.TextXAlignment.Left
questTitle.TextColor3 = Color3.fromRGB(255, 210, 80)
questTitle.Parent = tracker

local questProgress = Instance.new("TextLabel")
questProgress.Size = UDim2.new(1, -20, 0, 20)
questProgress.Position = UDim2.new(0, 10, 0, 36)
questProgress.BackgroundTransparency = 1
questProgress.Text = ""
questProgress.Font = Enum.Font.Gotham
questProgress.TextSize = 15
questProgress.TextXAlignment = Enum.TextXAlignment.Left
questProgress.TextColor3 = Color3.new(1, 1, 1)
questProgress.Parent = tracker

local barBack = Instance.new("Frame")
barBack.Size = UDim2.new(1, -20, 0, 12)
barBack.Position = UDim2.new(0, 10, 0, 62)
barBack.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
barBack.BorderSizePixel = 0
barBack.Parent = tracker
corner(barBack, 6)

local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(90, 200, 90)
barFill.BorderSizePixel = 0
barFill.Parent = barBack
corner(barFill, 6)

-- // Coin counter (top-right) -------------------------------------------------------
local coinsLabel = Instance.new("TextLabel")
coinsLabel.Size = UDim2.new(0, 200, 0, 40)
coinsLabel.Position = UDim2.new(1, -216, 0, 16)
coinsLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
coinsLabel.BackgroundTransparency = 0.15
coinsLabel.Text = "Coins: 0"
coinsLabel.Font = Enum.Font.GothamBold
coinsLabel.TextSize = 18
coinsLabel.TextColor3 = Color3.fromRGB(255, 210, 80)
coinsLabel.Parent = gui
corner(coinsLabel, 10)

-- // Bottom buttons (5) ------------------------------------------------------------------
local collectionBtn = Instance.new("TextButton")
collectionBtn.Size = UDim2.new(0, 104, 0, 48)
collectionBtn.Position = UDim2.new(0.5, -276, 1, -64)
collectionBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
collectionBtn.Text = "Brainrots"
collectionBtn.Font = Enum.Font.GothamBold
collectionBtn.TextSize = 14
collectionBtn.TextColor3 = Color3.new(1, 1, 1)
collectionBtn.Parent = gui
corner(collectionBtn, 10)

local workBtn = Instance.new("TextButton")
workBtn.Size = UDim2.new(0, 104, 0, 48)
workBtn.Position = UDim2.new(0.5, -164, 1, -64)
workBtn.BackgroundColor3 = Color3.fromRGB(45, 60, 35)
workBtn.Text = "Work"
workBtn.Font = Enum.Font.GothamBold
workBtn.TextSize = 14
workBtn.TextColor3 = Color3.fromRGB(180, 255, 170)
workBtn.Parent = gui
corner(workBtn, 10)

local fusionBtn = Instance.new("TextButton")
fusionBtn.Size = UDim2.new(0, 104, 0, 48)
fusionBtn.Position = UDim2.new(0.5, -52, 1, -64)
fusionBtn.BackgroundColor3 = Color3.fromRGB(60, 35, 80)
fusionBtn.Text = "Fusion"
fusionBtn.Font = Enum.Font.GothamBold
fusionBtn.TextSize = 14
fusionBtn.TextColor3 = Color3.fromRGB(220, 170, 255)
fusionBtn.Parent = gui
corner(fusionBtn, 10)

local arenaBtn = Instance.new("TextButton")
arenaBtn.Size = UDim2.new(0, 104, 0, 48)
arenaBtn.Position = UDim2.new(0.5, 60, 1, -64)
arenaBtn.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
arenaBtn.Text = "Arena"
arenaBtn.Font = Enum.Font.GothamBold
arenaBtn.TextSize = 14
arenaBtn.TextColor3 = Color3.fromRGB(255, 170, 170)
arenaBtn.Parent = gui
corner(arenaBtn, 10)

local showcaseBtn = Instance.new("TextButton")
showcaseBtn.Size = UDim2.new(0, 104, 0, 48)
showcaseBtn.Position = UDim2.new(0.5, 172, 1, -64)
showcaseBtn.BackgroundColor3 = Color3.fromRGB(55, 45, 25)
showcaseBtn.Text = "Showcase"
showcaseBtn.Font = Enum.Font.GothamBold
showcaseBtn.TextSize = 14
showcaseBtn.TextColor3 = Color3.fromRGB(255, 215, 0)
showcaseBtn.Parent = gui
corner(showcaseBtn, 10)

-- // Materials strip (top-center) ------------------------------------------------------
local materialsBar = Instance.new("Frame")
materialsBar.Size = UDim2.new(0, 520, 0, 40)
materialsBar.Position = UDim2.new(0.5, -260, 0, 16)
materialsBar.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
materialsBar.BackgroundTransparency = 0.15
materialsBar.BorderSizePixel = 0
materialsBar.Parent = gui
corner(materialsBar, 10)

local materialLabels: { [string]: TextLabel } = {}
do
	local i = 0
	for _, workId in ipairs(BrainrotData.WORK_ORDER) do
		local workDef = BrainrotData.WORK_TYPES[workId]
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0, 100, 1, 0)
		label.Position = UDim2.new(0, 4 + i * 104, 0, 0)
		label.BackgroundTransparency = 1
		label.Text = workDef.Material .. ": 0"
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = materialsBar
		materialLabels[workId] = label
		i += 1
	end
end

-- // Collection panel ------------------------------------------------------------------
local collectionPanel = Instance.new("ScrollingFrame")
collectionPanel.Size = UDim2.new(0, 440, 0, 420)
collectionPanel.Position = UDim2.new(0.5, -220, 0.5, -210)
collectionPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
collectionPanel.BackgroundTransparency = 0.05
collectionPanel.BorderSizePixel = 0
collectionPanel.Visible = false
collectionPanel.ScrollBarThickness = 6
collectionPanel.Parent = gui
corner(collectionPanel, 12)

local collectionLayout = Instance.new("UIListLayout")
collectionLayout.Padding = UDim.new(0, 8)
collectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
collectionLayout.Parent = collectionPanel
pad(collectionPanel, 12)

-- // Showcase editor panel --------------------------------------------------------------
local editorPanel = Instance.new("Frame")
editorPanel.Size = UDim2.new(0, 480, 0, 480)
editorPanel.Position = UDim2.new(0.5, -240, 0.5, -240)
editorPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
editorPanel.BorderSizePixel = 0
editorPanel.Visible = false
editorPanel.Parent = gui
corner(editorPanel, 12)

local editorTitle = Instance.new("TextLabel")
editorTitle.Size = UDim2.new(1, -24, 0, 36)
editorTitle.Position = UDim2.new(0, 12, 0, 10)
editorTitle.BackgroundTransparency = 1
editorTitle.Text = "Pick up to 10 brainrots to showcase"
editorTitle.Font = Enum.Font.GothamBold
editorTitle.TextSize = 18
editorTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
editorTitle.Parent = editorPanel

local editorList = Instance.new("ScrollingFrame")
editorList.Size = UDim2.new(1, -24, 1, -110)
editorList.Position = UDim2.new(0, 12, 0, 52)
editorList.BackgroundTransparency = 1
editorList.BorderSizePixel = 0
editorList.ScrollBarThickness = 6
editorList.Parent = editorPanel

local editorLayout = Instance.new("UIListLayout")
editorLayout.Padding = UDim.new(0, 6)
editorLayout.SortOrder = Enum.SortOrder.LayoutOrder
editorLayout.Parent = editorList

local saveBtn = Instance.new("TextButton")
saveBtn.Size = UDim2.new(1, -24, 0, 44)
saveBtn.Position = UDim2.new(0, 12, 1, -56)
saveBtn.BackgroundColor3 = Color3.fromRGB(60, 140, 60)
saveBtn.Text = "Save Showcase"
saveBtn.Font = Enum.Font.GothamBold
saveBtn.TextSize = 18
saveBtn.TextColor3 = Color3.new(1, 1, 1)
saveBtn.Parent = editorPanel
corner(saveBtn, 10)

local function instanceLabel(inst: any): string
	local def = BrainrotData.GetById(inst.BrainrotId)
	if not def then
		return inst.BrainrotId
	end
	local label = BrainrotData.GetDisplayName(def, inst.Variant, inst.Shiny)
	return label .. "  [" .. def.Rarity .. "]"
end

local function refreshButtons()
	collectionBtn.Text = ("Brainrots (%d)"):format(#ownedInstances)
	local shown = 0
	for _ in pairs(showcaseIds) do
		shown += 1
	end
	showcaseBtn.Text = ("Showcase (%d)"):format(shown)
end

local function refreshCollectionPanel()
	for _, child in ipairs(collectionPanel:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	if #ownedInstances == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -12, 0, 40)
		empty.BackgroundTransparency = 1
		empty.Text = "No brainrots yet — complete quests!"
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 15
		empty.TextColor3 = Color3.fromRGB(150, 150, 160)
		empty.Parent = collectionPanel
		return
	end
	for order, inst in ipairs(ownedInstances) do
		local def = BrainrotData.GetById(inst.BrainrotId)
		local entry = Instance.new("TextLabel")
		entry.Size = UDim2.new(1, -12, 0, 44)
		entry.BackgroundColor3 = inst.Shiny and Color3.fromRGB(70, 55, 20) or Color3.fromRGB(45, 45, 60)
		entry.Text = "  " .. instanceLabel(inst)
		entry.Font = Enum.Font.GothamBold
		entry.TextSize = 15
		entry.TextXAlignment = Enum.TextXAlignment.Left
		entry.TextColor3 = inst.Shiny and Color3.fromRGB(255, 215, 0) or Color3.new(1, 1, 1)
		entry.TextTruncate = Enum.TextTruncate.AtEnd
		entry.LayoutOrder = order
		entry.Parent = collectionPanel
		corner(entry, 8)
		if def then
			local stripe = Instance.new("Frame")
			stripe.Size = UDim2.new(0, 6, 1, 0)
			stripe.BackgroundColor3 = BrainrotData.RARITY_COLORS[def.Rarity] or Color3.new(1, 1, 1)
			stripe.BorderSizePixel = 0
			stripe.Parent = entry
			corner(stripe, 3)
		end
	end
end

local function isPending(id: string): boolean
	for _, pid in ipairs(pendingShowcase) do
		if pid == id then
			return true
		end
	end
	return false
end

local function refreshEditorPanel()
	for _, child in ipairs(editorList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for order, inst in ipairs(ownedInstances) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -6, 0, 44)
		row.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
		row.BorderSizePixel = 0
		row.LayoutOrder = order
		row.Parent = editorList
		corner(row, 8)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -110, 1, 0)
		label.Position = UDim2.new(0, 10, 0, 0)
		label.BackgroundTransparency = 1
		label.Text = instanceLabel(inst)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 14
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = inst.Shiny and Color3.fromRGB(255, 215, 0) or Color3.new(1, 1, 1)
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = row

		local toggle = Instance.new("TextButton")
		toggle.Size = UDim2.new(0, 96, 0, 32)
		toggle.Position = UDim2.new(1, -104, 0.5, -16)
		toggle.Font = Enum.Font.GothamBold
		toggle.TextSize = 14
		toggle.Parent = row
		corner(toggle, 8)

		local function paint()
			if isPending(inst.InstanceId) then
				toggle.Text = "ON DISPLAY"
				toggle.BackgroundColor3 = Color3.fromRGB(60, 140, 60)
				toggle.TextColor3 = Color3.new(1, 1, 1)
			else
				toggle.Text = "Display"
				toggle.BackgroundColor3 = Color3.fromRGB(70, 70, 85)
				toggle.TextColor3 = Color3.fromRGB(200, 200, 210)
			end
		end
		paint()

		toggle.MouseButton1Click:Connect(function()
			if isPending(inst.InstanceId) then
				for i, pid in ipairs(pendingShowcase) do
					if pid == inst.InstanceId then
						table.remove(pendingShowcase, i)
						break
					end
				end
			else
				if #pendingShowcase >= BrainrotData.SHOWCASE_LIMIT then
					return -- cap reached; silently ignore
				end
				table.insert(pendingShowcase, inst.InstanceId)
			end
			paint()
			saveBtn.Text = ("Save Showcase (%d/%d)"):format(#pendingShowcase, BrainrotData.SHOWCASE_LIMIT)
		end)
	end
	saveBtn.Text = ("Save Showcase (%d/%d)"):format(#pendingShowcase, BrainrotData.SHOWCASE_LIMIT)
end

-- // Milestone 2: Fusion panel ---------------------------------------------------------
local fusionPanel = Instance.new("ScrollingFrame")
fusionPanel.Size = UDim2.new(0, 500, 0, 460)
fusionPanel.Position = UDim2.new(0.5, -250, 0.5, -230)
fusionPanel.BackgroundColor3 = Color3.fromRGB(25, 20, 35)
fusionPanel.BackgroundTransparency = 0.05
fusionPanel.BorderSizePixel = 0
fusionPanel.Visible = false
fusionPanel.ScrollBarThickness = 6
fusionPanel.Parent = gui
corner(fusionPanel, 12)

local fusionLayout = Instance.new("UIListLayout")
fusionLayout.Padding = UDim.new(0, 8)
fusionLayout.SortOrder = Enum.SortOrder.LayoutOrder
fusionLayout.Parent = fusionPanel
pad(fusionPanel, 12)

local fusionTitle = Instance.new("TextLabel")
fusionTitle.Size = UDim2.new(1, -24, 0, 40)
fusionTitle.BackgroundTransparency = 1
fusionTitle.Text = "⚗ Fusion Lab — 3 duplicates + materials = higher rarity!"
fusionTitle.Font = Enum.Font.GothamBold
fusionTitle.TextSize = 15
fusionTitle.TextColor3 = Color3.fromRGB(220, 170, 255)
fusionTitle.TextWrapped = true
fusionTitle.LayoutOrder = 0
fusionTitle.Parent = fusionPanel

local function refreshFusionPanel()
	for _, child in ipairs(fusionPanel:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	-- Group non-shiny, non-working instances by brainrot.
	local groups: { [string]: any } = {}
	for _, inst in ipairs(ownedInstances) do
		if not inst.Shiny and not workingIds[inst.InstanceId] then
			groups[inst.BrainrotId] = groups[inst.BrainrotId] or {}
			table.insert(groups[inst.BrainrotId], inst)
		end
	end
	local order = 1
	local anyGroup = false
	for brainrotId, list in pairs(groups) do
		if #list >= 3 then
			anyGroup = true
			local def = BrainrotData.GetById(brainrotId)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -24, 0, 76)
			row.BackgroundColor3 = Color3.fromRGB(35, 28, 48)
			row.BorderSizePixel = 0
			row.LayoutOrder = order
			row.Parent = fusionPanel
			corner(row, 8)
			order += 1

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -120, 0, 26)
			nameLabel.Position = UDim2.new(0, 10, 0, 6)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = ("%s  x%d"):format(def and def.Name or brainrotId, #list)
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextSize = 15
			nameLabel.TextColor3 = Color3.new(1, 1, 1)
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Parent = row

			local costText: string
			if def.Rarity == "Legendary" then
				costText = "Result: guaranteed SHINY!"
			else
				local workId = BrainrotData.GetWorkIdForType(BrainrotData.GetEffectiveType(def, nil))
				local matName = workId and BrainrotData.WORK_TYPES[workId].Material or "materials"
				local resultRarity = BrainrotData.GetFusionResultRarity(def.Rarity) or "?"
				costText = ("Cost: %d %s → %s"):format(
					BrainrotData.FUSION_MATERIAL_COST[def.Rarity] or 15, matName, resultRarity)
			end
			local costLabel = Instance.new("TextLabel")
			costLabel.Size = UDim2.new(1, -120, 0, 22)
			costLabel.Position = UDim2.new(0, 10, 0, 34)
			costLabel.BackgroundTransparency = 1
			costLabel.Text = costText
			costLabel.Font = Enum.Font.Gotham
			costLabel.TextSize = 13
			costLabel.TextColor3 = Color3.fromRGB(200, 180, 220)
			costLabel.TextXAlignment = Enum.TextXAlignment.Left
			costLabel.Parent = row

			local fuseBtn = Instance.new("TextButton")
			fuseBtn.Size = UDim2.new(0, 96, 0, 40)
			fuseBtn.Position = UDim2.new(1, -106, 0, 18)
			fuseBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 180)
			fuseBtn.Text = "FUSE"
			fuseBtn.Font = Enum.Font.GothamBold
			fuseBtn.TextSize = 16
			fuseBtn.TextColor3 = Color3.new(1, 1, 1)
			fuseBtn.Parent = row
			corner(fuseBtn, 8)
			fuseBtn.MouseButton1Click:Connect(function()
				fuseRemote:FireServer({ list[1].InstanceId, list[2].InstanceId, list[3].InstanceId })
			end)
		end
	end
	if not anyGroup then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -24, 0, 60)
		empty.BackgroundTransparency = 1
		empty.Text = "No fusable groups yet.\nYou need 3 copies of the same brainrot (non-shiny, not working).\nTip: every 5 orbs earns a Brainrot Cache!"
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 14
		empty.TextColor3 = Color3.fromRGB(170, 150, 190)
		empty.TextWrapped = true
		empty.LayoutOrder = order
		empty.Parent = fusionPanel
	end
end

-- // Milestone 2: Arena panel (team + rival select) ----------------------------------
local arenaPanel = Instance.new("Frame")
arenaPanel.Size = UDim2.new(0, 560, 0, 520)
arenaPanel.Position = UDim2.new(0.5, -280, 0.5, -260)
arenaPanel.BackgroundColor3 = Color3.fromRGB(30, 18, 18)
arenaPanel.BorderSizePixel = 0
arenaPanel.Visible = false
arenaPanel.Parent = gui
corner(arenaPanel, 12)

local arenaTitle = Instance.new("TextLabel")
arenaTitle.Size = UDim2.new(1, 0, 0, 40)
arenaTitle.Position = UDim2.new(0, 0, 0, 8)
arenaTitle.BackgroundTransparency = 1
arenaTitle.Text = "⚔ Arena — pick 3 fighters, then a rival"
arenaTitle.Font = Enum.Font.GothamBold
arenaTitle.TextSize = 17
arenaTitle.TextColor3 = Color3.fromRGB(255, 170, 170)
arenaTitle.Parent = arenaPanel

local teamLabel = Instance.new("TextLabel")
teamLabel.Size = UDim2.new(1, -24, 0, 24)
teamLabel.Position = UDim2.new(0, 12, 0, 52)
teamLabel.BackgroundTransparency = 1
teamLabel.Text = "Your team (0/3):"
teamLabel.Font = Enum.Font.GothamBold
teamLabel.TextSize = 14
teamLabel.TextColor3 = Color3.new(1, 1, 1)
teamLabel.TextXAlignment = Enum.TextXAlignment.Left
teamLabel.Parent = arenaPanel

local teamList = Instance.new("ScrollingFrame")
teamList.Size = UDim2.new(1, -24, 0, 150)
teamList.Position = UDim2.new(0, 12, 0, 78)
teamList.BackgroundColor3 = Color3.fromRGB(22, 14, 14)
teamList.BorderSizePixel = 0
teamList.ScrollBarThickness = 6
teamList.Parent = arenaPanel
corner(teamList, 8)

local teamLayout = Instance.new("UIListLayout")
teamLayout.Padding = UDim.new(0, 4)
teamLayout.SortOrder = Enum.SortOrder.LayoutOrder
teamLayout.Parent = teamList

local rivalLabel = Instance.new("TextLabel")
rivalLabel.Size = UDim2.new(1, -24, 0, 24)
rivalLabel.Position = UDim2.new(0, 12, 0, 236)
rivalLabel.BackgroundTransparency = 1
rivalLabel.Text = "Rival:"
rivalLabel.Font = Enum.Font.GothamBold
rivalLabel.TextSize = 14
rivalLabel.TextColor3 = Color3.new(1, 1, 1)
rivalLabel.TextXAlignment = Enum.TextXAlignment.Left
rivalLabel.Parent = arenaPanel

local rivalList = Instance.new("ScrollingFrame")
rivalList.Size = UDim2.new(1, -24, 0, 170)
rivalList.Position = UDim2.new(0, 12, 0, 262)
rivalList.BackgroundColor3 = Color3.fromRGB(22, 14, 14)
rivalList.BorderSizePixel = 0
rivalList.ScrollBarThickness = 6
rivalList.Parent = arenaPanel
corner(rivalList, 8)

local rivalLayout = Instance.new("UIListLayout")
rivalLayout.Padding = UDim.new(0, 4)
rivalLayout.SortOrder = Enum.SortOrder.LayoutOrder
rivalLayout.Parent = rivalList

local startBattleBtn = Instance.new("TextButton")
startBattleBtn.Size = UDim2.new(1, -24, 0, 48)
startBattleBtn.Position = UDim2.new(0, 12, 1, -60)
startBattleBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
startBattleBtn.Text = "Start Battle"
startBattleBtn.Font = Enum.Font.GothamBold
startBattleBtn.TextSize = 18
startBattleBtn.TextColor3 = Color3.new(1, 1, 1)
startBattleBtn.Parent = arenaPanel
corner(startBattleBtn, 10)

local arenaClose = Instance.new("TextButton")
arenaClose.Size = UDim2.new(0, 40, 0, 40)
arenaClose.Position = UDim2.new(1, -48, 0, 8)
arenaClose.BackgroundColor3 = Color3.fromRGB(70, 70, 85)
arenaClose.Text = "X"
arenaClose.Font = Enum.Font.GothamBold
arenaClose.TextSize = 18
arenaClose.TextColor3 = Color3.new(1, 1, 1)
arenaClose.Parent = arenaPanel
corner(arenaClose, 8)

local selectedTeam: { string } = {} -- instanceIds, max 3
local selectedRivalId: string? = nil
local beatenRivals: { [string]: boolean } = {}

local function refreshArenaPanel()
	for _, child in ipairs(teamList:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for _, child in ipairs(rivalList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	-- Team picker.
	local order = 1
	for _, inst in ipairs(ownedInstances) do
		if not workingIds[inst.InstanceId] then
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, -12, 0, 34)
			btn.BackgroundColor3 = Color3.fromRGB(40, 28, 28)
			btn.BorderSizePixel = 0
			btn.Text = instanceLabel(inst)
			btn.Font = Enum.Font.Gotham
			btn.TextSize = 13
			btn.TextColor3 = Color3.new(1, 1, 1)
			btn.LayoutOrder = order
			btn.Parent = teamList
			corner(btn, 6)
			order += 1
			local function paint()
				local sel = false
				for _, id in ipairs(selectedTeam) do
					if id == inst.InstanceId then
						sel = true
						break
					end
				end
				btn.BackgroundColor3 = if sel then Color3.fromRGB(120, 40, 40) else Color3.fromRGB(40, 28, 28)
			end
			paint()
			btn.MouseButton1Click:Connect(function()
				local at = nil
				for i, id in ipairs(selectedTeam) do
					if id == inst.InstanceId then
						at = i
						break
					end
				end
				if at then
					table.remove(selectedTeam, at)
				elseif #selectedTeam < 3 then
					table.insert(selectedTeam, inst.InstanceId)
				end
				teamLabel.Text = ("Your team (%d/3):"):format(#selectedTeam)
				paint()
			end)
		end
	end
	-- Rival cards.
	local rOrder = 1
	for i, rival in ipairs(BrainrotData.RIVALS) do
		local locked = i > 1 and not beatenRivals[BrainrotData.RIVALS[i - 1].Id]
		local beaten = beatenRivals[rival.Id] == true
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -12, 0, 64)
		card.BackgroundColor3 = if locked then Color3.fromRGB(30, 30, 34)
			elseif beaten then Color3.fromRGB(35, 55, 35)
			else Color3.fromRGB(45, 30, 30)
		card.BorderSizePixel = 0
		card.LayoutOrder = rOrder
		card.Parent = rivalList
		corner(card, 8)
		rOrder += 1

		local teamNames = {}
		for _, bid in ipairs(rival.Team) do
			local d = BrainrotData.GetById(bid)
			table.insert(teamNames, d and d.Name or bid)
		end
		local info = Instance.new("TextLabel")
		info.Size = UDim2.new(1, -110, 1, 0)
		info.Position = UDim2.new(0, 10, 0, 0)
		info.BackgroundTransparency = 1
		info.Text = rival.Name .. " — " .. rival.Title .. "\n" .. table.concat(teamNames, ", ")
		info.Font = Enum.Font.Gotham
		info.TextSize = 12
		info.TextColor3 = if locked then Color3.fromRGB(120, 120, 130) else Color3.new(1, 1, 1)
		info.TextXAlignment = Enum.TextXAlignment.Left
		info.TextWrapped = true
		info.Parent = card

		if not locked then
			local pickBtn = Instance.new("TextButton")
			pickBtn.Size = UDim2.new(0, 90, 0, 36)
			pickBtn.Position = UDim2.new(1, -100, 0.5, -18)
			pickBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
			pickBtn.Text = if beaten then "Rematch" else "Fight!"
			pickBtn.Font = Enum.Font.GothamBold
			pickBtn.TextSize = 14
			pickBtn.TextColor3 = Color3.new(1, 1, 1)
			pickBtn.Parent = card
			corner(pickBtn, 8)
			pickBtn.MouseButton1Click:Connect(function()
				selectedRivalId = rival.Id
				for _, c in ipairs(rivalList:GetChildren()) do
					if c:IsA("Frame") then
						for _, b in ipairs(c:GetChildren()) do
							if b:IsA("TextButton") then
								b.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
							end
						end
					end
				end
				pickBtn.BackgroundColor3 = Color3.fromRGB(220, 80, 80)
			end)
		else
			local lockLabel = Instance.new("TextLabel")
			lockLabel.Size = UDim2.new(0, 90, 0, 36)
			lockLabel.Position = UDim2.new(1, -100, 0.5, -18)
			lockLabel.BackgroundTransparency = 1
			lockLabel.Text = "🔒 Locked"
			lockLabel.Font = Enum.Font.GothamBold
			lockLabel.TextSize = 13
			lockLabel.TextColor3 = Color3.fromRGB(120, 120, 130)
			lockLabel.Parent = card
		end
	end
end

arenaClose.MouseButton1Click:Connect(function()
	arenaPanel.Visible = false
end)

-- // Milestone 2: Battle panel ---------------------------------------------------------
local battlePanel = Instance.new("Frame")
battlePanel.Size = UDim2.new(0, 640, 0, 560)
battlePanel.Position = UDim2.new(0.5, -320, 0.5, -280)
battlePanel.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
battlePanel.BorderSizePixel = 0
battlePanel.Visible = false
battlePanel.Parent = gui
corner(battlePanel, 12)

local battleTitle = Instance.new("TextLabel")
battleTitle.Size = UDim2.new(1, 0, 0, 36)
battleTitle.Position = UDim2.new(0, 0, 0, 6)
battleTitle.BackgroundTransparency = 1
battleTitle.Text = "Battle!"
battleTitle.Font = Enum.Font.GothamBold
battleTitle.TextSize = 20
battleTitle.TextColor3 = Color3.fromRGB(255, 200, 200)
battleTitle.Parent = battlePanel

local enemyBars: any = {}
local playerBars: any = {}
do
	local y = 48
	for i = 1, 3 do
		local nameL = Instance.new("TextLabel")
		nameL.Size = UDim2.new(0.44, 0, 0, 20)
		nameL.Position = UDim2.new(0.03, 0, 0, y)
		nameL.BackgroundTransparency = 1
		nameL.Font = Enum.Font.GothamBold
		nameL.TextSize = 13
		nameL.TextColor3 = Color3.fromRGB(255, 150, 150)
		nameL.TextXAlignment = Enum.TextXAlignment.Left
		nameL.Parent = battlePanel
		local back = Instance.new("Frame")
		back.Size = UDim2.new(0.44, 0, 0, 12)
		back.Position = UDim2.new(0.03, 0, 0, y + 22)
		back.BackgroundColor3 = Color3.fromRGB(50, 20, 20)
		back.BorderSizePixel = 0
		back.Parent = battlePanel
		corner(back, 6)
		local fill = Instance.new("Frame")
		fill.Size = UDim2.new(1, 0, 1, 0)
		fill.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
		fill.BorderSizePixel = 0
		fill.Parent = back
		corner(fill, 6)
		enemyBars[i] = { name = nameL, fill = fill }
		y += 44
	end
end

local battleLog = Instance.new("ScrollingFrame")
battleLog.Size = UDim2.new(0.94, 0, 0, 110)
battleLog.Position = UDim2.new(0.03, 0, 0, 190)
battleLog.BackgroundColor3 = Color3.fromRGB(10, 10, 18)
battleLog.BorderSizePixel = 0
battleLog.ScrollBarThickness = 4
battleLog.Parent = battlePanel
corner(battleLog, 8)

local logLayout = Instance.new("UIListLayout")
logLayout.Padding = UDim.new(0, 2)
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Parent = battleLog

local logOrder = 0
local function battleLogLine(text: string, color: Color3?)
	logOrder += 1
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -8, 0, 18)
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = Enum.Font.Gotham
	l.TextSize = 12
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.LayoutOrder = logOrder
	l.Parent = battleLog
	battleLog.CanvasPosition = Vector2.new(0, 1e6)
end

local playerCards: any = {}
do
	local y = 312
	for i = 1, 3 do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(0.94, 0, 0, 64)
		card.Position = UDim2.new(0.03, 0, 0, y)
		card.BackgroundColor3 = Color3.fromRGB(22, 30, 22)
		card.BorderSizePixel = 0
		card.Parent = battlePanel
		corner(card, 8)
		local nameL = Instance.new("TextLabel")
		nameL.Size = UDim2.new(0.4, 0, 0, 20)
		nameL.Position = UDim2.new(0.02, 0, 0, 4)
		nameL.BackgroundTransparency = 1
		nameL.Font = Enum.Font.GothamBold
		nameL.TextSize = 13
		nameL.TextColor3 = Color3.fromRGB(170, 255, 170)
		nameL.TextXAlignment = Enum.TextXAlignment.Left
		nameL.Parent = card
		local back = Instance.new("Frame")
		back.Size = UDim2.new(0.4, 0, 0, 10)
		back.Position = UDim2.new(0.02, 0, 0, 26)
		back.BackgroundColor3 = Color3.fromRGB(20, 40, 20)
		back.BorderSizePixel = 0
		back.Parent = card
		corner(back, 5)
		local fill = Instance.new("Frame")
		fill.Size = UDim2.new(1, 0, 1, 0)
		fill.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
		fill.BorderSizePixel = 0
		fill.Parent = back
		corner(fill, 5)
		playerCards[i] = { card = card, name = nameL, fill = fill, moveBtns = {} }
		y += 70
	end
end

local forfeitBtn = Instance.new("TextButton")
forfeitBtn.Size = UDim2.new(0, 120, 0, 36)
forfeitBtn.Position = UDim2.new(0.5, -60, 1, -46)
forfeitBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 85)
forfeitBtn.Text = "Forfeit"
forfeitBtn.Font = Enum.Font.GothamBold
forfeitBtn.TextSize = 14
forfeitBtn.TextColor3 = Color3.new(1, 1, 1)
forfeitBtn.Parent = battlePanel
corner(forfeitBtn, 8)

local lockedMoves: { number? } = { nil, nil, nil }
local battleActive = false

-- Type colors for move buttons.
local MOVE_TYPE_COLORS: { [string]: Color3 } = {
	Wood = Color3.fromRGB(55, 150, 55),
	Water = Color3.fromRGB(45, 110, 220),
	Fire = Color3.fromRGB(215, 95, 30),
	Sky = Color3.fromRGB(110, 190, 235),
	Shadow = Color3.fromRGB(125, 65, 185),
}

-- Shake the battle panel on heavy hits (juice without touching the camera).
local function shakeBattlePanel(intensity: number)
	task.spawn(function()
		local basePos = battlePanel.Position
		for _ = 1, 7 do
			local off = UDim2.new(0, (math.random() - 0.5) * intensity, 0, (math.random() - 0.5) * intensity)
			battlePanel.Position = basePos + off
			task.wait(0.035)
		end
		battlePanel.Position = basePos
	end)
end

local function paintHp(fill: Instance, hp: number, maxHp: number)
	fill.Size = UDim2.new(math.clamp(hp / math.max(1, maxHp), 0, 1), 0, 1, 0)
end

local function buildBattleUI(state: any)
	battleTitle.Text = "⚔ vs " .. tostring(state.rivalName)
	logOrder = 0
	for _, child in ipairs(battleLog:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	lockedMoves = { nil, nil, nil }
	for i = 1, 3 do
		local ef = state.eTeam[i]
		enemyBars[i].name.Text = ef.Name
		paintHp(enemyBars[i].fill, ef.HP, ef.MaxHP)
		local pf = state.pTeam[i]
		local card = playerCards[i]
		card.name.Text = pf.Name
		paintHp(card.fill, pf.HP, pf.MaxHP)
		for _, b in ipairs(card.moveBtns) do
			b:Destroy()
		end
		card.moveBtns = {}
		for mi, move in ipairs(pf.Moves) do
			local mb = Instance.new("TextButton")
			mb.Size = UDim2.new(0.26, 0, 0, 30)
			mb.Position = UDim2.new(0.44 + (mi - 1) * 0.28, 0, 0, 4)
			mb.BackgroundColor3 = MOVE_TYPE_COLORS[move.Type] or Color3.fromRGB(45, 60, 45)
			mb.Text = move.Name .. "\n" .. tostring(move.Power) .. " PWR"
			mb.Font = Enum.Font.GothamBold
			mb.TextSize = 10
			mb.TextColor3 = Color3.new(1, 1, 1)
			mb.TextTruncate = Enum.TextTruncate.AtEnd
			mb.Parent = card.card
			corner(mb, 6)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.new(1, 1, 1)
			stroke.Thickness = 2.5
			stroke.Enabled = false
			stroke.Parent = mb
			table.insert(card.moveBtns, mb)
			local fIdx, mIdx = i, mi
			mb.MouseButton1Click:Connect(function()
				if not battleActive then
					return
				end
				lockedMoves[fIdx] = mIdx
				for j, b in ipairs(card.moveBtns) do
					local s = b:FindFirstChildOfClass("UIStroke")
					if s then
						s.Enabled = (j == mIdx)
					end
				end
				if lockedMoves[1] and lockedMoves[2] and lockedMoves[3] then
					battleActive = false -- lock input while resolving
					submitMovesRemote:FireServer({ lockedMoves[1], lockedMoves[2], lockedMoves[3] })
				end
			end)
		end
	end
	battleActive = true
	battleLogLine("Battle started! Pick a move for each fighter.", Color3.fromRGB(255, 220, 120))
end

local function applyTurn(payload: any)
	local state = payload.State
	local events = payload.Events or {}
	task.spawn(function()
		for _, ev in ipairs(events) do
			if ev.miss then
				battleLogLine(("%s's %s missed %s!"):format(ev.attackerName, ev.moveName, ev.targetName),
					Color3.fromRGB(170, 170, 170))
			else
				local effText = ""
				local col: Color3 = Color3.new(1, 1, 1)
				if (ev.effectiveness or 1) > 1 then
					effText = " Super effective!"
					col = Color3.fromRGB(255, 170, 80)
				elseif (ev.effectiveness or 1) < 1 then
					effText = " Not very effective."
					col = Color3.fromRGB(150, 150, 200)
				end
				if ev.crit then
					effText ..= " CRIT!"
				end
				battleLogLine(("%s used %s on %s (%d dmg).%s"):format(
					ev.attackerName, ev.moveName, ev.targetName, ev.damage, effText), col)
				if ev.crit or (ev.damage or 0) >= 40 then
					shakeBattlePanel(if ev.crit then 14 else 8)
				end
				if ev.fainted then
					battleLogLine(ev.targetName .. " fainted!", Color3.fromRGB(255, 100, 100))
				end
			end
			-- Refresh bars from authoritative state.
			if state then
				for i = 1, 3 do
					if state.eTeam[i] then
						paintHp(enemyBars[i].fill, state.eTeam[i].HP, state.eTeam[i].MaxHP)
					end
					if state.pTeam[i] then
						paintHp(playerCards[i].fill, state.pTeam[i].HP, state.pTeam[i].MaxHP)
					end
				end
			end
			task.wait(1.25)
		end
		lockedMoves = { nil, nil, nil }
		if payload.Phase == "Turn" and state then
			if state.winner == "player" then
				local rw = payload.Rewards or {}
				local txt = "🏆 Victory!"
				if rw.Coins and rw.Coins > 0 then
					txt ..= " +" .. tostring(rw.Coins) .. " coins!"
				end
				if rw.RewardRarity then
					txt ..= " A " .. tostring(rw.RewardRarity) .. " brainrot joins you!"
				end
				showBanner(txt, 6)
				battleLogLine("You win! Rewards claimed.", Color3.fromRGB(255, 220, 120))
				task.wait(2)
				battlePanel.Visible = false
			elseif state.winner == "enemy" then
				battleLogLine("Defeat... train up and try again!", Color3.fromRGB(255, 120, 120))
				showBanner("Defeat! Your brainrots need rest.", 4)
				task.wait(2)
				battlePanel.Visible = false
			else
				-- Reset move highlights for the next turn.
				for i = 1, 3 do
					for _, b in ipairs(playerCards[i].moveBtns) do
						local s = b:FindFirstChildOfClass("UIStroke")
						if s then
							s.Enabled = false
						end
					end
				end
				battleActive = true
				battleLogLine("Pick your moves!", Color3.fromRGB(255, 220, 120))
			end
		end
	end)
end

forfeitBtn.MouseButton1Click:Connect(function()
	forfeitRemote:FireServer()
	battlePanel.Visible = false
end)

-- // Exploration & Progression Panels -----------------------------------------------------
-- Second row of menu buttons
local exploreBtn = Instance.new("TextButton")
exploreBtn.Size = UDim2.new(0, 104, 0, 40)
exploreBtn.Position = UDim2.new(0.5, -276, 1, -112)
exploreBtn.BackgroundColor3 = Color3.fromRGB(35, 60, 35)
exploreBtn.Text = "Explore"
exploreBtn.Font = Enum.Font.GothamBold
exploreBtn.TextSize = 13
exploreBtn.TextColor3 = Color3.fromRGB(170, 255, 170)
exploreBtn.Parent = gui
corner(exploreBtn, 10)

local dailyBtn = Instance.new("TextButton")
dailyBtn.Size = UDim2.new(0, 104, 0, 40)
dailyBtn.Position = UDim2.new(0.5, -164, 1, -112)
dailyBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
dailyBtn.Text = "Dailies"
dailyBtn.Font = Enum.Font.GothamBold
dailyBtn.TextSize = 13
dailyBtn.TextColor3 = Color3.fromRGB(200, 200, 255)
dailyBtn.Parent = gui
corner(dailyBtn, 10)

local eggBtn = Instance.new("TextButton")
eggBtn.Size = UDim2.new(0, 104, 0, 40)
eggBtn.Position = UDim2.new(0.5, -52, 1, -112)
eggBtn.BackgroundColor3 = Color3.fromRGB(80, 65, 30)
eggBtn.Text = "Eggs"
eggBtn.Font = Enum.Font.GothamBold
eggBtn.TextSize = 13
eggBtn.TextColor3 = Color3.fromRGB(255, 230, 150)
eggBtn.Parent = gui
corner(eggBtn, 10)

local mineBtn = Instance.new("TextButton")
mineBtn.Size = UDim2.new(0, 104, 0, 40)
mineBtn.Position = UDim2.new(0.5, 60, 1, -112)
mineBtn.BackgroundColor3 = Color3.fromRGB(70, 55, 20)
mineBtn.Text = "Gold Mine"
mineBtn.Font = Enum.Font.GothamBold
mineBtn.TextSize = 13
mineBtn.TextColor3 = Color3.fromRGB(255, 210, 100)
mineBtn.Parent = gui
corner(mineBtn, 10)

local styleBtn = Instance.new("TextButton")
styleBtn.Size = UDim2.new(0, 104, 0, 40)
styleBtn.Position = UDim2.new(0.5, 172, 1, -112)
styleBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 70)
styleBtn.Text = "Style"
styleBtn.Font = Enum.Font.GothamBold
styleBtn.TextSize = 13
styleBtn.TextColor3 = Color3.fromRGB(220, 180, 255)
styleBtn.Parent = gui
corner(styleBtn, 10)

-- Helper to make a panel
local function makePanel(title: string, titleColor: Color3): (Frame, TextLabel)
	local panel = Instance.new("ScrollingFrame")
	panel.Size = UDim2.new(0, 560, 0, 520)
	panel.Position = UDim2.new(0.5, -280, 0.5, -260)
	panel.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	panel.ScrollBarThickness = 6
	corner(panel, 12)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel
	local pad2 = Instance.new("UIPadding")
	pad2.PaddingTop = UDim.new(0, 12)
	pad2.PaddingLeft = UDim.new(0, 16)
	pad2.PaddingRight = UDim.new(0, 16)
	pad2.PaddingBottom = UDim.new(0, 12)
	pad2.Parent = panel
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, 0, 0, 36)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = title
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.TextSize = 18
	titleLbl.TextColor3 = titleColor
	titleLbl.LayoutOrder = 0
	titleLbl.Parent = panel
	return panel, titleLbl
end

local function makeRow(parent: Instance, order: number, height: number): Frame
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, height)
	row.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = parent
	corner(row, 8)
	return row
end

local function makeLabel(parent: Instance, text: string, size: number, color: Color3, order: number): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 24)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = size
	lbl.TextColor3 = color
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.LayoutOrder = order
	lbl.Parent = parent
	return lbl
end

-- Expedition Panel
local expeditionPanel, _expTitle = makePanel("🗺 Expeditions — send brainrots to gather (15 min)", Color3.fromRGB(170, 255, 170))
local expZoneList: ScrollingFrame? = nil
local expActiveList: Frame? = nil
local selectedZone: string? = nil
local selectedTeam: { string } = {}

-- Daily Panel
local dailyPanel, _dailyTitle = makePanel("📅 Daily Quests — complete for mystery eggs", Color3.fromRGB(200, 200, 255))

-- Egg Panel
local eggPanel, _eggTitle = makePanel("🥚 Mystery Eggs — hatch with playtime", Color3.fromRGB(255, 230, 150))

-- Mine Panel
local minePanel, _mineTitle = makePanel("⛏ Gold Mine — coins while you play", Color3.fromRGB(255, 210, 100))

-- Customize Panel
local customizePanel, _custTitle = makePanel("🎨 Customize Your Plot", Color3.fromRGB(220, 180, 255))

-- Button handlers
exploreBtn.MouseButton1Click:Connect(function()
	local was = expeditionPanel.Visible
	hideAllPanels()
	if not was then expeditionPanel.Visible = true end
end)
dailyBtn.MouseButton1Click:Connect(function()
	local was = dailyPanel.Visible
	hideAllPanels()
	if not was then dailyPanel.Visible = true end
end)
eggBtn.MouseButton1Click:Connect(function()
	local was = eggPanel.Visible
	hideAllPanels()
	if not was then eggPanel.Visible = true end
end)
mineBtn.MouseButton1Click:Connect(function()
	local was = minePanel.Visible
	hideAllPanels()
	if not was then minePanel.Visible = true end
end)
styleBtn.MouseButton1Click:Connect(function()
	local was = customizePanel.Visible
	hideAllPanels()
	if not was then customizePanel.Visible = true end
end)

-- // Shared panel helper -----------------------------------------------------------------
local function hideAllPanels()
	collectionPanel.Visible = false
	editorPanel.Visible = false
	workPanel.Visible = false
	pickerPanel.Visible = false
	fusionPanel.Visible = false
	arenaPanel.Visible = false
	expeditionPanel.Visible = false
	dailyPanel.Visible = false
	eggPanel.Visible = false
	minePanel.Visible = false
	customizePanel.Visible = false
end

fusionBtn.MouseButton1Click:Connect(function()
	local was = fusionPanel.Visible
	hideAllPanels()
	if not was then
		refreshFusionPanel()
		fusionPanel.Visible = true
	end
end)

arenaBtn.MouseButton1Click:Connect(function()
	local was = arenaPanel.Visible
	hideAllPanels()
	if not was then
		selectedTeam = {}
		teamLabel.Text = "Your team (0/3):"
		refreshArenaPanel()
		arenaPanel.Visible = true
	end
end)

collectionBtn.MouseButton1Click:Connect(function()
	local was = collectionPanel.Visible
	hideAllPanels()
	collectionPanel.Visible = not was
end)

showcaseBtn.MouseButton1Click:Connect(function()
	local was = editorPanel.Visible
	hideAllPanels()
	if not was then
		-- Seed the editor from the current showcase.
		pendingShowcase = {}
		for _, inst in ipairs(ownedInstances) do
			if showcaseIds[inst.InstanceId] then
				table.insert(pendingShowcase, inst.InstanceId)
			end
		end
		refreshEditorPanel()
		editorPanel.Visible = true
	end
end)

saveBtn.MouseButton1Click:Connect(function()
	showcaseRemote:FireServer(pendingShowcase)
	editorPanel.Visible = false
end)

-- // Work panel ----------------------------------------------------------------------------
local assignWorkerRemote = remotes:WaitForChild("AssignWorker")
local collectRemote = remotes:WaitForChild("CollectStation")
local workUpdateRemote = remotes:WaitForChild("WorkUpdate")

local workState: any = { Materials = {}, Stations = {} }
local jobsByInstance: { [string]: string } = {} -- instanceId -> workId
local pickingForWorkId: string? = nil

local function pips(level: number): string
	return string.rep("●", level) .. string.rep("○", 3 - level)
end

workPanel = Instance.new("ScrollingFrame")
workPanel.Size = UDim2.new(0, 500, 0, 460)
workPanel.Position = UDim2.new(0.5, -250, 0.5, -230)
workPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
workPanel.BackgroundTransparency = 0.05
workPanel.BorderSizePixel = 0
workPanel.Visible = false
workPanel.ScrollBarThickness = 6
workPanel.Parent = gui
corner(workPanel, 12)

local workLayout = Instance.new("UIListLayout")
workLayout.Padding = UDim.new(0, 10)
workLayout.SortOrder = Enum.SortOrder.LayoutOrder
workLayout.Parent = workPanel
pad(workPanel, 12)

-- Worker picker (choose a brainrot for a station slot).
pickerPanel = Instance.new("Frame")
pickerPanel.Size = UDim2.new(0, 460, 0, 440)
pickerPanel.Position = UDim2.new(0.5, -230, 0.5, -220)
pickerPanel.BackgroundColor3 = Color3.fromRGB(25, 25, 38)
pickerPanel.BorderSizePixel = 0
pickerPanel.Visible = false
pickerPanel.Parent = gui
corner(pickerPanel, 12)

local pickerTitle = Instance.new("TextLabel")
pickerTitle.Size = UDim2.new(1, -24, 0, 36)
pickerTitle.Position = UDim2.new(0, 12, 0, 10)
pickerTitle.BackgroundTransparency = 1
pickerTitle.Text = "Pick a worker"
pickerTitle.Font = Enum.Font.GothamBold
pickerTitle.TextSize = 18
pickerTitle.TextColor3 = Color3.fromRGB(180, 255, 170)
pickerTitle.Parent = pickerPanel

local pickerList = Instance.new("ScrollingFrame")
pickerList.Size = UDim2.new(1, -24, 1, -104)
pickerList.Position = UDim2.new(0, 12, 0, 52)
pickerList.BackgroundTransparency = 1
pickerList.BorderSizePixel = 0
pickerList.ScrollBarThickness = 6
pickerList.Parent = pickerPanel

local pickerLayout = Instance.new("UIListLayout")
pickerLayout.Padding = UDim.new(0, 6)
pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder
pickerLayout.Parent = pickerList

local pickerClose = Instance.new("TextButton")
pickerClose.Size = UDim2.new(1, -24, 0, 40)
pickerClose.Position = UDim2.new(0, 12, 1, -52)
pickerClose.BackgroundColor3 = Color3.fromRGB(70, 70, 85)
pickerClose.Text = "Cancel"
pickerClose.Font = Enum.Font.GothamBold
pickerClose.TextSize = 16
pickerClose.TextColor3 = Color3.new(1, 1, 1)
pickerClose.Parent = pickerPanel
corner(pickerClose, 10)
pickerClose.MouseButton1Click:Connect(function()
	pickerPanel.Visible = false
	pickingForWorkId = nil
end)

local function openPicker(workId: string)
	pickingForWorkId = workId
	for _, child in ipairs(pickerList:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local workDef = BrainrotData.WORK_TYPES[workId]
	pickerTitle.Text = "Pick a worker — " .. workDef.Name

	-- Candidates: owned, not already working, sorted by suitability.
	local candidates = {}
	for _, inst in ipairs(ownedInstances) do
		if not jobsByInstance[inst.InstanceId] then
			local def = BrainrotData.GetById(inst.BrainrotId)
			if def then
				table.insert(candidates, {
					inst = inst,
					suit = BrainrotData.GetWorkSuitability(def, inst.Variant, workId),
				})
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.suit > b.suit
	end)

	if #candidates == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -6, 0, 40)
		empty.BackgroundTransparency = 1
		empty.Text = "No free brainrots — unassign one first."
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 14
		empty.TextColor3 = Color3.fromRGB(150, 150, 160)
		empty.Parent = pickerList
	end

	for order, c in ipairs(candidates) do
		local def = BrainrotData.GetById(c.inst.BrainrotId)
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, -6, 0, 44)
		row.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
		row.Text = ""
		row.LayoutOrder = order
		row.Parent = pickerList
		corner(row, 8)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -90, 1, 0)
		label.Position = UDim2.new(0, 10, 0, 0)
		label.BackgroundTransparency = 1
		label.Text = instanceLabel(c.inst)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 14
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = c.inst.Shiny and Color3.fromRGB(255, 215, 0) or Color3.new(1, 1, 1)
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = row

		local suitLabel = Instance.new("TextLabel")
		suitLabel.Size = UDim2.new(0, 80, 1, 0)
		suitLabel.Position = UDim2.new(1, -84, 0, 0)
		suitLabel.BackgroundTransparency = 1
		suitLabel.Text = pips(c.suit)
		suitLabel.Font = Enum.Font.GothamBold
		suitLabel.TextSize = 16
		suitLabel.TextColor3 = Color3.fromRGB(255, 210, 80)
		suitLabel.Parent = row

		row.MouseButton1Click:Connect(function()
			assignWorkerRemote:FireServer(c.inst.InstanceId, workId)
			pickerPanel.Visible = false
			pickingForWorkId = nil
		end)
	end
	pickerPanel.Visible = true
end

local function refreshWorkPanel()
	for _, child in ipairs(workPanel:GetChildren()) do
		if child:IsA("Frame") and child.Name == "StationSection" then
			child:Destroy()
		end
	end
	local order = 0
	for _, workId in ipairs(BrainrotData.WORK_ORDER) do
		order += 1
		local workDef = BrainrotData.WORK_TYPES[workId]
		local st = (workState.Stations or {})[workId] or { Stored = 0, Workers = {} }
		local section = Instance.new("Frame")
		section.Name = "StationSection"
		section.Size = UDim2.new(1, -12, 0, 150)
		section.BackgroundColor3 = Color3.fromRGB(30, 32, 42)
		section.BorderSizePixel = 0
		section.LayoutOrder = order
		section.Parent = workPanel
		corner(section, 10)

		local header = Instance.new("TextLabel")
		header.Size = UDim2.new(1, -120, 0, 30)
		header.Position = UDim2.new(0, 12, 0, 8)
		header.BackgroundTransparency = 1
		header.Text = ("%s — %s: %d/%d"):format(workDef.Name, workDef.Material, st.Stored or 0, BrainrotData.STATION_STORAGE_CAP)
		header.Font = Enum.Font.GothamBold
		header.TextSize = 16
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.TextColor3 = Color3.new(1, 1, 1)
		header.Parent = section

		local collectBtn = Instance.new("TextButton")
		collectBtn.Size = UDim2.new(0, 96, 0, 32)
		collectBtn.Position = UDim2.new(1, -108, 0, 8)
		collectBtn.BackgroundColor3 = Color3.fromRGB(60, 140, 60)
		collectBtn.Text = "Collect"
		collectBtn.Font = Enum.Font.GothamBold
		collectBtn.TextSize = 15
		collectBtn.TextColor3 = Color3.new(1, 1, 1)
		collectBtn.Parent = section
		corner(collectBtn, 8)
		collectBtn.MouseButton1Click:Connect(function()
			collectRemote:FireServer(workId)
		end)

		-- Worker slots.
		local bySlot: { [number]: any } = {}
		for _, w in ipairs(st.Workers or {}) do
			bySlot[w.Slot] = w
		end
		for slot = 1, BrainrotData.STATION_SLOTS do
			local w = bySlot[slot]
			local rowY = 44 + (slot - 1) * 50
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -24, 0, 44)
			row.Position = UDim2.new(0, 12, 0, rowY)
			row.BackgroundColor3 = Color3.fromRGB(40, 42, 55)
			row.BorderSizePixel = 0
			row.Parent = section
			corner(row, 8)

			if w then
				local def = BrainrotData.GetById(w.BrainrotId)
				local suit = def and BrainrotData.GetWorkSuitability(def, w.Variant, workId) or 0
				local nameLabel = Instance.new("TextLabel")
				nameLabel.Size = UDim2.new(1, -120, 1, 0)
				nameLabel.Position = UDim2.new(0, 10, 0, 0)
				nameLabel.BackgroundTransparency = 1
				nameLabel.Text = (def and BrainrotData.GetDisplayName(def, w.Variant, w.Shiny) or w.BrainrotId) .. "  " .. pips(suit)
				nameLabel.Font = Enum.Font.GothamBold
				nameLabel.TextSize = 14
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.TextColor3 = Color3.new(1, 1, 1)
				nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
				nameLabel.Parent = row

				local unassignBtn = Instance.new("TextButton")
				unassignBtn.Size = UDim2.new(0, 96, 0, 30)
				unassignBtn.Position = UDim2.new(1, -106, 0.5, -15)
				unassignBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 60)
				unassignBtn.Text = "Unassign"
				unassignBtn.Font = Enum.Font.GothamBold
				unassignBtn.TextSize = 13
				unassignBtn.TextColor3 = Color3.new(1, 1, 1)
				unassignBtn.Parent = row
				corner(unassignBtn, 8)
				local instId = w.InstanceId
				unassignBtn.MouseButton1Click:Connect(function()
					assignWorkerRemote:FireServer(instId, nil)
				end)
			else
				local emptyLabel = Instance.new("TextLabel")
				emptyLabel.Size = UDim2.new(1, -120, 1, 0)
				emptyLabel.Position = UDim2.new(0, 10, 0, 0)
				emptyLabel.BackgroundTransparency = 1
				emptyLabel.Text = "Empty slot"
				emptyLabel.Font = Enum.Font.Gotham
				emptyLabel.TextSize = 14
				emptyLabel.TextXAlignment = Enum.TextXAlignment.Left
				emptyLabel.TextColor3 = Color3.fromRGB(130, 130, 140)
				emptyLabel.Parent = row

				local assignBtn = Instance.new("TextButton")
				assignBtn.Size = UDim2.new(0, 96, 0, 30)
				assignBtn.Position = UDim2.new(1, -106, 0.5, -15)
				assignBtn.BackgroundColor3 = Color3.fromRGB(60, 100, 160)
				assignBtn.Text = "Assign"
				assignBtn.Font = Enum.Font.GothamBold
				assignBtn.TextSize = 13
				assignBtn.TextColor3 = Color3.new(1, 1, 1)
				assignBtn.Parent = row
				corner(assignBtn, 8)
				assignBtn.MouseButton1Click:Connect(function()
					openPicker(workId)
				end)
			end
		end
	end
end

workBtn.MouseButton1Click:Connect(function()
	local was = workPanel.Visible
	hideAllPanels()
	workPanel.Visible = not was
	if workPanel.Visible then
		refreshWorkPanel()
	end
end)

-- Hide the work panel when other panels open (all connected handlers fire).
collectionBtn.MouseButton1Click:Connect(function()
	workPanel.Visible = false
	pickerPanel.Visible = false
end)
showcaseBtn.MouseButton1Click:Connect(function()
	workPanel.Visible = false
	pickerPanel.Visible = false
end)

workUpdateRemote.OnClientEvent:Connect(function(payload: any)
	workState = payload or { Materials = {}, Stations = {} }
	jobsByInstance = {}
	for workId, st in pairs(workState.Stations or {}) do
		for _, w in ipairs(st.Workers or {}) do
			jobsByInstance[w.InstanceId] = workId
		end
	end
	for _, workId in ipairs(BrainrotData.WORK_ORDER) do
		local workDef = BrainrotData.WORK_TYPES[workId]
		local label = materialLabels[workId]
		if label then
			label.Text = ("%s: %d"):format(workDef.Material, (workState.Materials or {})[workId] or 0)
		end
	end
	if workPanel.Visible then
		refreshWorkPanel()
	end
end)

-- // Reward banner (center) -----------------------------------------------------------
local banner = Instance.new("Frame")
banner.Size = UDim2.new(0, 460, 0, 180)
banner.Position = UDim2.new(0.5, -230, 0.35, -90)
banner.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
banner.BorderSizePixel = 0
banner.Visible = false
banner.Parent = gui
corner(banner, 14)

local bannerStroke = Instance.new("UIStroke")
bannerStroke.Color = Color3.fromRGB(255, 180, 60)
bannerStroke.Thickness = 3
bannerStroke.Parent = banner

local bannerText = Instance.new("TextLabel")
bannerText.Size = UDim2.new(1, -30, 1, -30)
bannerText.Position = UDim2.new(0, 15, 0, 15)
bannerText.BackgroundTransparency = 1
bannerText.Text = ""
bannerText.Font = Enum.Font.GothamBold
bannerText.TextSize = 22
bannerText.TextColor3 = Color3.new(1, 1, 1)
bannerText.TextWrapped = true
bannerText.Parent = banner

showBanner = function(text: string, seconds: number)
	bannerText.Text = text
	banner.Visible = true
	task.delay(seconds, function()
		banner.Visible = false
	end)
end

-- // Hint toast (bottom) ----------------------------------------------------------------
local hintLabel = Instance.new("TextLabel")
hintLabel.Size = UDim2.new(0, 500, 0, 44)
hintLabel.Position = UDim2.new(0.5, -250, 1, -130)
hintLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
hintLabel.BackgroundTransparency = 0.2
hintLabel.Text = ""
hintLabel.Font = Enum.Font.Gotham
hintLabel.TextSize = 16
hintLabel.TextColor3 = Color3.new(1, 1, 1)
hintLabel.TextWrapped = true
hintLabel.Visible = false
hintLabel.Parent = gui
corner(hintLabel, 10)

-- // Server events -----------------------------------------------------------------------
questRemote.OnClientEvent:Connect(function(payload: any)
	if payload.Type == "Progress" then
		questTitle.Text = "QUEST: " .. payload.Name
		questProgress.Text = ("%d / %d"):format(payload.Progress, payload.Goal)
		barFill.Size = UDim2.new(math.clamp(payload.Progress / payload.Goal, 0, 1), 0, 1, 0)
	elseif payload.Type == "Completed" then
		questTitle.Text = "QUEST COMPLETE!"
		questProgress.Text = ""
		barFill.Size = UDim2.new(1, 0, 1, 0)

		local text = "Quest Complete: " .. payload.QuestName .. "!\n"
		if payload.BrainrotId then
			local def = BrainrotData.GetById(payload.BrainrotId)
			if def then
				local name = BrainrotData.GetDisplayName(def, payload.Variant, payload.Shiny)
				if payload.Shiny or payload.Variant then
					text ..= "Rare find: " .. name .. "!\n"
				else
					text ..= "New brainrot: " .. name .. "\n"
				end
			end
		elseif payload.InventoryFull then
			text ..= "Inventory full! +150 coins instead.\n"
		end
		if payload.Coins and payload.Coins > 0 then
			text ..= "+" .. tostring(payload.Coins) .. " coins! "
		end
		text ..= "Check your plot!"
		showBanner(text, 5)
	end
end)

collectionRemote.OnClientEvent:Connect(function(payload: any)
	ownedInstances = payload.Brainrots or {}
	showcaseIds = {}
	for _, id in ipairs(payload.Showcase or {}) do
		showcaseIds[id] = true
	end
	workingIds = payload.Working or {}
	coinsLabel.Text = "Coins: " .. tostring(payload.Coins or 0)
	refreshButtons()
	refreshCollectionPanel()
	if editorPanel.Visible then
		refreshEditorPanel()
	end
end)

hintRemote.OnClientEvent:Connect(function(text: string)
	hintLabel.Text = text
	hintLabel.Visible = true
	task.delay(6, function()
		hintLabel.Visible = false
	end)
end)

-- // Milestone 2: server events ------------------------------------------------------------
startBattleBtn.MouseButton1Click:Connect(function()
	if #selectedTeam ~= 3 then
		hintLabel.Text = "Pick 3 fighters first!"
		hintLabel.Visible = true
		task.delay(3, function()
			hintLabel.Visible = false
		end)
		return
	end
	if not selectedRivalId then
		hintLabel.Text = "Pick a rival to fight!"
		hintLabel.Visible = true
		task.delay(3, function()
			hintLabel.Visible = false
		end)
		return
	end
	startBattleRemote:FireServer(selectedRivalId, selectedTeam)
end)

openFusionRemote.OnClientEvent:Connect(function()
	hideAllPanels()
	refreshFusionPanel()
	fusionPanel.Visible = true
end)

openArenaRemote.OnClientEvent:Connect(function(payload: any)
	beatenRivals = payload.Beaten or {}
	hideAllPanels()
	selectedTeam = {}
	selectedRivalId = nil
	teamLabel.Text = "Your team (0/3):"
	refreshArenaPanel()
	arenaPanel.Visible = true
end)

fusionResultRemote.OnClientEvent:Connect(function(payload: any)
	local text: string
	if payload.Kind == "Cache" then
		text = "📦 Brainrot Cache! "
	else
		text = "⚗ Fusion complete! "
	end
	if payload.BrainrotId then
		local def = BrainrotData.GetById(payload.BrainrotId)
		if def then
			local name = BrainrotData.GetDisplayName(def, payload.Variant, payload.Shiny)
			if payload.Shiny then
				text ..= "✨ SHINY " .. name .. "! ✨\n"
			elseif payload.Variant then
				text ..= "Rare find: " .. name .. "!\n"
			else
				text ..= "New brainrot: " .. name .. "\n"
			end
		end
	elseif payload.InventoryFull then
		text ..= "Inventory full! +150 coins instead.\n"
	end
	if payload.Coins and payload.Coins > 0 then
		text ..= "+" .. tostring(payload.Coins) .. " coins! "
	end
	showBanner(text, 5)
	if fusionPanel.Visible then
		refreshFusionPanel()
	end
end)

battleUpdateRemote.OnClientEvent:Connect(function(payload: any)
	if payload.Phase == "Start" then
		hideAllPanels()
		arenaPanel.Visible = false
		buildBattleUI(payload.State)
		battlePanel.Visible = true
	elseif payload.Phase == "Turn" then
		applyTurn(payload)
	elseif payload.Phase == "End" then
		battlePanel.Visible = false
		battleActive = false
	end
end)

-- // Exploration UI Logic ---------------------------------------------------------------
local expeditionData: any = { Expeditions = {}, UnlockedZones = {} }
local dailyData: any = { Quests = {} }
local eggData: any = { Eggs = {}, Slots = 3 }
local passiveBanked: number = 0
local customizeData: any = { Theme = "default", UnlockedThemes = {}, Decorations = {} }

local function clearChildren(parent: Instance)
	for _, c in ipairs(parent:GetChildren()) do
		if c:IsA("GuiObject") and c.Name ~= "Title" then
			c:Destroy()
		end
	end
end

local function refreshExpeditionPanel()
	-- Clear dynamic content (keep title at LayoutOrder 0)
	for _, c in ipairs(expeditionPanel:GetChildren()) do
		if c:IsA("GuiObject") and (c :: GuiObject).LayoutOrder > 0 then
			c:Destroy()
		end
	end
	local order = 1
	-- Active expeditions
	if #expeditionData.Expeditions > 0 then
		makeLabel(expeditionPanel, "Active Expeditions:", 15, Color3.fromRGB(255, 255, 255), order)
		order += 1
		for _, exp in ipairs(expeditionData.Expeditions) do
			local row = makeRow(expeditionPanel, order, 56)
			order += 1
			local mins = math.floor(exp.RemainingSecs / 60)
			local secs = exp.RemainingSecs % 60
			local status = exp.Complete and "✅ Complete!" or string.format("⏳ %d:%02d left", mins, secs)
			makeLabel(row, exp.ZoneName .. " — " .. table.concat(exp.TeamNames, ", "), 13, Color3.new(1,1,1), 1).Position = UDim2.new(0, 8, 0, 4)
			makeLabel(row, status, 12, Color3.fromRGB(170, 255, 170), 2).Position = UDim2.new(0, 8, 0, 28)
		end
	end
	-- Zone list
	makeLabel(expeditionPanel, "Zones (walk there to discover):", 15, Color3.fromRGB(255, 255, 255), order)
	order += 1
	for _, zoneId in ipairs(BrainrotData.ZONE_ORDER) do
		local zone = BrainrotData.ZONES[zoneId]
		local unlocked = expeditionData.UnlockedZones[zoneId]
		local row = makeRow(expeditionPanel, order, 72)
		order += 1
		if unlocked then
			row.BackgroundColor3 = zone.Color
			makeLabel(row, "📍 " .. zone.Name, 14, Color3.new(1,1,1), 1).Position = UDim2.new(0, 8, 0, 4)
			makeLabel(row, "Best: " .. zone.FavoredType .. " | Drops: " .. table.concat(zone.Materials, ", "), 11, Color3.fromRGB(230, 230, 230), 2).Position = UDim2.new(0, 8, 0, 26)
			makeLabel(row, zone.Description, 11, Color3.fromRGB(210, 210, 210), 3).Position = UDim2.new(0, 8, 0, 44)
			-- Select button
			local selBtn = Instance.new("TextButton")
			selBtn.Size = UDim2.new(0, 80, 0, 28)
			selBtn.Position = UDim2.new(1, -88, 0, 8)
			selBtn.Text = if selectedZone == zoneId then "✓" else "Select"
			selBtn.BackgroundColor3 = if selectedZone == zoneId then Color3.fromRGB(60, 160, 60) else Color3.fromRGB(60, 60, 80)
			selBtn.TextColor3 = Color3.new(1,1,1)
			selBtn.Font = Enum.Font.GothamBold
			selBtn.TextSize = 12
			selBtn.Parent = row
			corner(selBtn, 6)
			selBtn.MouseButton1Click:Connect(function()
				selectedZone = zoneId
				refreshExpeditionPanel()
			end)
		else
			makeLabel(row, "❓ ??? (undiscovered)", 14, Color3.fromRGB(150, 150, 150), 1).Position = UDim2.new(0, 8, 0, 4)
			makeLabel(row, "Hint: " .. zone.UnlockHint, 11, Color3.fromRGB(130, 130, 130), 2).Position = UDim2.new(0, 8, 0, 28)
		end
	end
	-- Team selection & start
	if selectedZone then
		makeLabel(expeditionPanel, "Team (tap brainrots to add, max 3):", 15, Color3.fromRGB(255, 255, 255), order)
		order += 1
		local teamRow = makeRow(expeditionPanel, order, 40)
		order += 1
		local teamText = #selectedTeam == 0 and "No brainrots selected" or table.concat(selectedTeam, ", ")
		-- Show names instead of IDs
		local names = {}
		for _, iid in ipairs(selectedTeam) do
			for _, inst in ipairs(ownedInstances) do
				if inst.InstanceId == iid then
					local def = BrainrotData.GetBrainrot(inst.BrainrotId)
					table.insert(names, def and def.Name or "?")
					break
				end
			end
		end
		makeLabel(teamRow, if #names == 0 then "No brainrots selected" else table.concat(names, ", "), 13, Color3.new(1,1,1), 1).Position = UDim2.new(0, 8, 0, 8)
		-- Available brainrots (not working/showcase/on expedition)
		local availCount = 0
		for _, inst in ipairs(ownedInstances) do
			local iid = inst.InstanceId
			if not workingIds[iid] and not showcaseIds[iid] then
				-- Check not on expedition (simplified: allow, server validates)
				availCount += 1
				if availCount > 12 then break end -- limit display
				local def = BrainrotData.GetBrainrot(inst.BrainrotId)
				local bBtn = Instance.new("TextButton")
				bBtn.Size = UDim2.new(0, 160, 0, 28)
				bBtn.Text = (def and def.Name or "?") .. if table.find(selectedTeam, iid) then " ✓" else ""
				bBtn.BackgroundColor3 = if table.find(selectedTeam, iid) then Color3.fromRGB(60, 140, 60) else Color3.fromRGB(50, 50, 70)
				bBtn.TextColor3 = Color3.new(1,1,1)
				bBtn.Font = Enum.Font.Gotham
				bBtn.TextSize = 11
				bBtn.LayoutOrder = order
				bBtn.Parent = expeditionPanel
				corner(bBtn, 6)
				order += 1
				bBtn.MouseButton1Click:Connect(function()
					local idx = table.find(selectedTeam, iid)
					if idx then
						table.remove(selectedTeam, idx)
					elseif #selectedTeam < 3 then
						table.insert(selectedTeam, iid)
					end
					refreshExpeditionPanel()
				end)
			end
		end
		local startBtn = Instance.new("TextButton")
		startBtn.Size = UDim2.new(1, 0, 0, 44)
		startBtn.Text = "🚀 Start 15-min Expedition"
		startBtn.BackgroundColor3 = Color3.fromRGB(60, 140, 60)
		startBtn.TextColor3 = Color3.new(1,1,1)
		startBtn.Font = Enum.Font.GothamBold
		startBtn.TextSize = 15
		startBtn.LayoutOrder = order
		startBtn.Parent = expeditionPanel
		corner(startBtn, 8)
		startBtn.MouseButton1Click:Connect(function()
			if selectedZone and #selectedTeam > 0 then
				startExpeditionRemote:FireServer(selectedZone, selectedTeam)
				selectedTeam = {}
			end
		end)
	end
end

local function refreshDailyPanel()
	for _, c in ipairs(dailyPanel:GetChildren()) do
		if c:IsA("GuiObject") and (c :: GuiObject).LayoutOrder > 0 then
			c:Destroy()
		end
	end
	local order = 1
	for _, q in ipairs(dailyData.Quests) do
		local row = makeRow(dailyPanel, order, 88)
		order += 1
		row.BackgroundColor3 = q.TierColor
		makeLabel(row, q.TierName .. ": " .. q.Text, 14, Color3.new(1,1,1), 1).Position = UDim2.new(0, 8, 0, 4)
		makeLabel(row, string.format("Progress: %d/%d", q.Progress, q.Target), 12, Color3.new(1,1,1), 2).Position = UDim2.new(0, 8, 0, 26)
		-- Progress bar
		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(1, -16, 0, 10)
		barBg.Position = UDim2.new(0, 8, 0, 48)
		barBg.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
		barBg.Parent = row
		corner(barBg, 5)
		local barFill = Instance.new("Frame")
		barFill.Size = UDim2.new(math.clamp(q.Progress / q.Target, 0, 1), 0, 1, 0)
		barFill.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
		barFill.Parent = barBg
		corner(barFill, 5)
		if q.Done then
			if not q.EggClaimed then
				local claimBtn = Instance.new("TextButton")
				claimBtn.Size = UDim2.new(0, 110, 0, 28)
				claimBtn.Position = UDim2.new(1, -118, 0, 52)
				claimBtn.Text = "🥚 Claim Egg"
				claimBtn.BackgroundColor3 = Color3.fromRGB(200, 160, 50)
				claimBtn.TextColor3 = Color3.new(1,1,1)
				claimBtn.Font = Enum.Font.GothamBold
				claimBtn.TextSize = 12
				claimBtn.Parent = row
				corner(claimBtn, 6)
				claimBtn.MouseButton1Click:Connect(function()
					claimDailyEggRemote:FireServer(q.Tier)
				end)
			else
				makeLabel(row, "✅ Egg claimed", 12, Color3.fromRGB(170, 255, 170), 3).Position = UDim2.new(1, -118, 0, 56)
			end
		end
	end
	if dailyData.AllComplete then
		makeLabel(dailyPanel, "🌟 All dailies complete! Come back tomorrow.", 14, Color3.fromRGB(255, 220, 100), order)
	end
end

local function refreshEggPanel()
	for _, c in ipairs(eggPanel:GetChildren()) do
		if c:IsA("GuiObject") and (c :: GuiObject).LayoutOrder > 0 then
			c:Destroy()
		end
	end
	local order = 1
	makeLabel(eggPanel, string.format("Incubator: %d/%d slots used", eggData.UsedSlots or 0, eggData.Slots or 3), 14, Color3.new(1,1,1), order)
	order += 1
	for _, egg in ipairs(eggData.Eggs) do
		local row = makeRow(eggPanel, order, 64)
		order += 1
		row.BackgroundColor3 = egg.Color
		makeLabel(row, "🥚 " .. egg.TierName .. " (mystery!)", 14, Color3.new(1,1,1), 1).Position = UDim2.new(0, 8, 0, 4)
		makeLabel(row, string.format("%d / %d min playtime", math.floor(egg.Progress), egg.Needed), 12, Color3.new(1,1,1), 2).Position = UDim2.new(0, 8, 0, 26)
		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(1, -16, 0, 8)
		barBg.Position = UDim2.new(0, 8, 0, 48)
		barBg.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
		barBg.Parent = row
		corner(barBg, 4)
		local barFill = Instance.new("Frame")
		barFill.Size = UDim2.new(egg.Percent, 0, 1, 0)
		barFill.BackgroundColor3 = Color3.fromRGB(255, 220, 100)
		barFill.Parent = barBg
		corner(barFill, 4)
	end
	if (eggData.UsedSlots or 0) == 0 then
		makeLabel(eggPanel, "No eggs incubating. Complete daily quests!", 13, Color3.fromRGB(180, 180, 180), order)
		order += 1
	end
	local buyBtn = Instance.new("TextButton")
	buyBtn.Size = UDim2.new(1, 0, 0, 40)
	buyBtn.Text = "➕ Buy Incubator Slot"
	buyBtn.BackgroundColor3 = Color3.fromRGB(80, 65, 30)
	buyBtn.TextColor3 = Color3.new(1,1,1)
	buyBtn.Font = Enum.Font.GothamBold
	buyBtn.TextSize = 14
	buyBtn.LayoutOrder = order
	buyBtn.Parent = eggPanel
	corner(buyBtn, 8)
	buyBtn.MouseButton1Click:Connect(function()
		buyEggSlotRemote:FireServer()
	end)
end

local function refreshMinePanel()
	for _, c in ipairs(minePanel:GetChildren()) do
		if c:IsA("GuiObject") and (c :: GuiObject).LayoutOrder > 0 then
			c:Destroy()
		end
	end
	local order = 1
	makeLabel(minePanel, "Your gold mine earns coins while you play!", 14, Color3.new(1,1,1), order)
	order += 1
	local bankRow = makeRow(minePanel, order, 72)
	order += 1
	bankRow.BackgroundColor3 = Color3.fromRGB(70, 55, 20)
	makeLabel(bankRow, "💰 Banked: " .. tostring(passiveBanked) .. " coins", 16, Color3.fromRGB(255, 220, 100), 1).Position = UDim2.new(0, 8, 0, 8)
	local collectBtn = Instance.new("TextButton")
	collectBtn.Size = UDim2.new(0, 120, 0, 32)
	collectBtn.Position = UDim2.new(0, 8, 0, 34)
	collectBtn.Text = "Collect"
	collectBtn.BackgroundColor3 = Color3.fromRGB(200, 160, 50)
	collectBtn.TextColor3 = Color3.new(1,1,1)
	collectBtn.Font = Enum.Font.GothamBold
	collectBtn.TextSize = 14
	collectBtn.Parent = bankRow
	corner(collectBtn, 6)
	collectBtn.MouseButton1Click:Connect(function()
		collectPassiveRemote:FireServer()
	end)
	makeLabel(minePanel, "Tip: stay in-game to keep earning. Bank caps at 2 hours.", 12, Color3.fromRGB(180, 180, 180), order)
end

local function refreshCustomizePanel()
	for _, c in ipairs(customizePanel:GetChildren()) do
		if c:IsA("GuiObject") and (c :: GuiObject).LayoutOrder > 0 then
			c:Destroy()
		end
	end
	local order = 1
	makeLabel(customizePanel, "Plot Themes:", 15, Color3.new(1,1,1), order)
	order += 1
	for themeId, theme in pairs(BrainrotData.PLOT_THEMES) do
		local unlocked = customizeData.UnlockedThemes[themeId]
		local isActive = customizeData.Theme == themeId
		local row = makeRow(customizePanel, order, 56)
		order += 1
		if unlocked then row.BackgroundColor3 = theme.Color end
		makeLabel(row, (if isActive then "✓ " else "") .. theme.Name, 14, Color3.new(1,1,1), 1).Position = UDim2.new(0, 8, 0, 4)
		if not unlocked then
			local matText = ""
			for mat, cost in pairs(theme.Materials) do
				matText ..= mat .. " x" .. tostring(cost) .. " "
			end
			makeLabel(row, "Cost: " .. tostring(theme.Cost) .. " coins" .. (if matText ~= "" then " + " .. matText else ""), 12, Color3.fromRGB(200, 200, 200), 2).Position = UDim2.new(0, 8, 0, 26)
			local buyBtn = Instance.new("TextButton")
			buyBtn.Size = UDim2.new(0, 80, 0, 28)
			buyBtn.Position = UDim2.new(1, -88, 0, 14)
			buyBtn.Text = "Unlock"
			buyBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 100)
			buyBtn.TextColor3 = Color3.new(1,1,1)
			buyBtn.Font = Enum.Font.GothamBold
			buyBtn.TextSize = 12
			buyBtn.Parent = row
			corner(buyBtn, 6)
			buyBtn.MouseButton1Click:Connect(function()
				unlockThemeRemote:FireServer(themeId)
			end)
		end
	end
	makeLabel(customizePanel, "Decorations:", 15, Color3.new(1,1,1), order)
	order += 1
	for decoId, deco in pairs(BrainrotData.PLOT_DECORATIONS) do
		local owned = customizeData.Decorations[decoId]
		local row = makeRow(customizePanel, order, 56)
		order += 1
		makeLabel(row, (if owned then "✓ " else "") .. deco.Name, 14, Color3.new(1,1,1), 1).Position = UDim2.new(0, 8, 0, 4)
		if not owned then
			local matText = ""
			for mat, cost in pairs(deco.Materials) do
				matText ..= mat .. " x" .. tostring(cost) .. " "
			end
			makeLabel(row, "Cost: " .. tostring(deco.Cost) .. " coins + " .. matText, 12, Color3.fromRGB(200, 200, 200), 2).Position = UDim2.new(0, 8, 0, 26)
			local buyBtn = Instance.new("TextButton")
			buyBtn.Size = UDim2.new(0, 80, 0, 28)
			buyBtn.Position = UDim2.new(1, -88, 0, 14)
			buyBtn.Text = "Buy"
			buyBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 100)
			buyBtn.TextColor3 = Color3.new(1,1,1)
			buyBtn.Font = Enum.Font.GothamBold
			buyBtn.TextSize = 12
			buyBtn.Parent = row
			corner(buyBtn, 6)
			buyBtn.MouseButton1Click:Connect(function()
				buyDecorationRemote:FireServer(decoId)
			end)
		end
	end
end

-- Remote handlers
expeditionUpdateRemote.OnClientEvent:Connect(function(payload: any)
	expeditionData = payload
	if expeditionPanel.Visible then
		refreshExpeditionPanel()
	end
end)

dailyUpdateRemote.OnClientEvent:Connect(function(payload: any)
	dailyData = payload
	if dailyPanel.Visible then
		refreshDailyPanel()
	end
end)

eggUpdateRemote.OnClientEvent:Connect(function(payload: any)
	eggData = payload
	if eggPanel.Visible then
		refreshEggPanel()
	end
end)

passiveUpdateRemote.OnClientEvent:Connect(function(payload: any)
	if payload.Banked ~= nil then
		passiveBanked = payload.Banked
	end
	if minePanel.Visible then
		refreshMinePanel()
	end
	-- Update mine button text with banked amount
	if passiveBanked > 0 then
		mineBtn.Text = "Mine (" .. tostring(passiveBanked) .. ")"
	else
		mineBtn.Text = "Gold Mine"
	end
end)

customizeUpdateRemote.OnClientEvent:Connect(function(payload: any)
	customizeData = payload
	if customizePanel.Visible then
		refreshCustomizePanel()
	end
end)

refreshButtons()
print("[Brainrot Arena] Client UI ready.")
