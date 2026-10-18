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
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

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
local challengePvpRemote = remotes:WaitForChild("ChallengePvp")
local respondPvpRemote = remotes:WaitForChild("RespondPvp")
local pvpInviteRemote = remotes:WaitForChild("PvpInvite")
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
local castRemote = remotes:WaitForChild("CastLine")
local reelRemote = remotes:WaitForChild("ReelIn")
local fishingUpdateRemote = remotes:WaitForChild("FishingUpdate")

-- Forward declarations: defined later in the file, used by code above them.
-- (A function used before its "local function" line resolves to nil at runtime,
-- so everything the button handlers call must be declared up here.)
local showBanner: (string, number) -> ()
local workPanel: ScrollingFrame
local pickerPanel: Frame
local leaderboardPanel: Frame
local hideAllPanels: () -> ()
local refreshExpeditionPanel: () -> ()
local refreshDailyPanel: () -> ()
local refreshEggPanel: () -> ()
local refreshMinePanel: () -> ()
local refreshCustomizePanel: () -> ()

-- Client mirror of server state.
local ownedInstances: any = {}   -- array of { InstanceId, BrainrotId, Shiny }
local showcaseIds: { [string]: boolean } = {}
local pendingShowcase: { string } = {}
local workingIds: { [string]: boolean } = {} -- instances at work (M2)
local selectedZone: string? = nil
local expeditionTeam: { string } = {}

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

-- // Steal a Brainrot Style Nameplate Generator (Distance Scaling & Fixed Size) --------------------------------
local function applyBrainrotNametag(model: Model, brainrotName: string, rarity: string)
	if not model or not model.Parent then return end

	local oldGui = model:FindFirstChild("NameTagGui")
	if oldGui then
		oldGui:Destroy()
	end
	local oldServerTag = model:FindFirstChild("NameTag")
	if oldServerTag then
		oldServerTag:Destroy()
	end

	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not part then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTagGui"
	billboard.Size = UDim2.new(0, 110, 0, 28)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 50
	billboard.Adornee = part
	billboard.Parent = model

	local function sitTagOnTop()
		if not (model.Parent and part.Parent) then
			return
		end
		local ok, bbCF, bbSize = pcall(function()
			return model:GetBoundingBox()
		end)
		local wild = model:GetAttribute("WildOwner") ~= nil
		if wild then
			billboard.AlwaysOnTop = true
		end
		if ok and bbCF and bbSize then
			local topY = (bbCF :: CFrame).Position.Y + (bbSize :: Vector3).Y / 2
			local pad = if wild then 3 else 1.5
			if wild and (bbSize :: Vector3).Y < 10 then
				billboard.StudsOffsetWorldSpace = Vector3.new()
				billboard.StudsOffset = Vector3.new(0, 16, 0)
			else
				billboard.StudsOffsetWorldSpace = Vector3.new(0, (topY - part.Position.Y) + pad, 0)
			end
		else
			billboard.StudsOffset = Vector3.new(0, if wild then 16 else 3, 0)
		end
	end
	sitTagOnTop()
	task.defer(sitTagOnTop)
	task.delay(0.5, sitTagOnTop)
	task.delay(1.5, sitTagOnTop)

	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 1)
	layout.Parent = billboard

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "RarityLabel"
	rarityLabel.Size = UDim2.new(1, 0, 0, 10)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Text = string.upper(rarity or "Common")
	rarityLabel.Font = Enum.Font.GothamBlack
	rarityLabel.TextSize = 8
	rarityLabel.TextStrokeTransparency = 0
	rarityLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	rarityLabel.LayoutOrder = 1
	rarityLabel.Parent = billboard

	local upperRarity = string.lower(rarity or "")
	if upperRarity == "legendary" then
		rarityLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	elseif upperRarity == "epic" then
		rarityLabel.TextColor3 = Color3.fromRGB(180, 100, 255)
	elseif upperRarity == "rare" then
		rarityLabel.TextColor3 = Color3.fromRGB(50, 160, 255)
	else
		rarityLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	end

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = brainrotName or "Brainrot"
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeTransparency = 0
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.LayoutOrder = 2
	nameLabel.Parent = billboard
end

local function hideIfForeignWild(inst: Instance)
	local cur: Instance? = inst
	local foreign = false
	while cur and cur ~= workspace do
		local owner = cur:GetAttribute("WildOwner")
		if owner ~= nil then
			foreign = owner ~= player.UserId
			break
		end
		cur = cur.Parent
	end
	if not foreign then
		return
	end
	local anyInst: any = inst
	if inst:IsA("BasePart") then
		anyInst.LocalTransparencyModifier = 1
	elseif inst:IsA("GuiObject") or inst:IsA("Decal") or inst:IsA("Texture") then
		pcall(function()
			anyInst.Visible = false
		end)
	end
	if inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
		anyInst.Enabled = false
	elseif inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") or inst:IsA("Light") then
		pcall(function()
			anyInst.Enabled = false
		end)
	end
end

workspace.DescendantAdded:Connect(hideIfForeignWild)
for _, existing in ipairs(workspace:GetDescendants()) do
	hideIfForeignWild(existing)
end

workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("Model") and descendant:GetAttribute("BrainrotId") then
		local def = BrainrotData.GetById(descendant:GetAttribute("BrainrotId") :: string)
		if def then
			local variantId = descendant:GetAttribute("Variant")
			local shiny = descendant:GetAttribute("Shiny") == true
			applyBrainrotNametag(descendant, BrainrotData.GetDisplayName(def, variantId :: any, shiny), def.Rarity)

			-- Server already sits and orients these. Client PivotTo was flattening pack meshes.
		end
	end
end)

-- // UI Theme: mobile-friendly + pretty -------------------------------------------
local camera = workspace.CurrentCamera
local viewportSize = camera and camera.ViewportSize or Vector2.new(1920, 1080)
-- Phone/tablet = touch screen without a keyboard (or a really narrow window).
-- A small desktop/Studio window is NOT a phone, so it keeps the normal button layout.
-- (Window size is NOT used: it can read as tiny during startup and wrongly flip this on.)
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local uiScale = if isMobile then 1.25 else 1.0

local function fitLegacyPanel(panel: Instance)
	if isMobile then
		local obj = panel :: GuiObject
		obj.Size = UDim2.new(0.92, 0, 0.78, 0)
		obj.Position = UDim2.new(0.04, 0, 0.11, 0)
	end
end

local THEME = {
	Background = Color3.fromRGB(22, 22, 35),
	Panel = Color3.fromRGB(30, 30, 48),
	Card = Color3.fromRGB(42, 42, 62),
	Accent = Color3.fromRGB(255, 180, 80),
	AccentDark = Color3.fromRGB(200, 130, 40),
	Success = Color3.fromRGB(80, 200, 120),
	Danger = Color3.fromRGB(220, 80, 80),
	Text = Color3.fromRGB(255, 255, 255),
	TextDim = Color3.fromRGB(180, 180, 200),
	Gradient1 = Color3.fromRGB(62, 62, 94),
	Gradient2 = Color3.fromRGB(38, 38, 60),
}

local function styleFrame(frame: GuiObject, useAccent: boolean?)
	-- A UIGradient also tints the TEXT of buttons and labels (white text came out dark),
	-- so only plain frames/panels get the gradient. Text objects keep their solid color.
	if not (frame:IsA("TextButton") or frame:IsA("TextLabel")) then
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, THEME.Gradient1),
			ColorSequenceKeypoint.new(1, THEME.Gradient2),
		})
		grad.Rotation = 90
		grad.Parent = frame
		-- A UIGradient MULTIPLIES the frame's own color. Dark color x dark gradient = black,
		-- which is why Stats / Style / Explore / Mine etc. looked black. A white base lets the
		-- gradient colors show exactly as written.
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
	end

	local stroke = Instance.new("UIStroke")
	stroke.Color = if useAccent then THEME.Accent else Color3.fromRGB(70, 70, 95)
	stroke.Thickness = 1
	stroke.Transparency = 0.4
	stroke.Parent = frame
end

local function sp(px: number): number
	return math.floor(px * uiScale)
end

-- // Quest tracker (top-left) ------------------------------------------------------
local tracker = Instance.new("Frame")
tracker.Name = "QuestTracker"
tracker.Size = UDim2.new(0, 320, 0, 92)
tracker.Position = UDim2.new(0, 16, 0, 64)
tracker.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
tracker.BackgroundTransparency = 0.15
tracker.BorderSizePixel = 0
tracker.Parent = gui
corner(tracker, 12)
styleFrame(tracker, true)

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
collectionBtn.Position = UDim2.new(0.5, -276, 1, -124)
collectionBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
collectionBtn.Text = "Brainrots"
collectionBtn.Font = Enum.Font.GothamBold
collectionBtn.TextSize = 14
collectionBtn.TextColor3 = Color3.new(1, 1, 1)
collectionBtn.Parent = gui
corner(collectionBtn, 12)
styleFrame(collectionBtn, false)

local workBtn = Instance.new("TextButton")
workBtn.Size = UDim2.new(0, 104, 0, 48)
workBtn.Position = UDim2.new(0.5, -164, 1, -124)
workBtn.BackgroundColor3 = Color3.fromRGB(45, 60, 35)
workBtn.Text = "Work"
workBtn.Font = Enum.Font.GothamBold
workBtn.TextSize = 14
workBtn.TextColor3 = Color3.fromRGB(180, 255, 170)
workBtn.Parent = gui
corner(workBtn, 12)
styleFrame(workBtn, false)

local fusionBtn = Instance.new("TextButton")
fusionBtn.Size = UDim2.new(0, 104, 0, 48)
fusionBtn.Position = UDim2.new(0.5, -52, 1, -124)
fusionBtn.BackgroundColor3 = Color3.fromRGB(60, 35, 80)
fusionBtn.Text = "Fusion"
fusionBtn.Font = Enum.Font.GothamBold
fusionBtn.TextSize = 14
fusionBtn.TextColor3 = Color3.fromRGB(220, 170, 255)
fusionBtn.Parent = gui
corner(fusionBtn, 12)
styleFrame(fusionBtn, false)

local arenaBtn = Instance.new("TextButton")
arenaBtn.Size = UDim2.new(0, 104, 0, 48)
arenaBtn.Position = UDim2.new(0.5, 60, 1, -124)
arenaBtn.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
arenaBtn.Text = "Arena"
arenaBtn.Font = Enum.Font.GothamBold
arenaBtn.TextSize = 14
arenaBtn.TextColor3 = Color3.fromRGB(255, 170, 170)
arenaBtn.Parent = gui
arenaBtn.Visible = false
corner(arenaBtn, 12)
styleFrame(arenaBtn, false)

local showcaseBtn = Instance.new("TextButton")
showcaseBtn.Size = UDim2.new(0, 104, 0, 48)
showcaseBtn.Position = UDim2.new(0.5, 172, 1, -124)
showcaseBtn.BackgroundColor3 = Color3.fromRGB(55, 45, 25)
showcaseBtn.Text = "Showcase"
showcaseBtn.Font = Enum.Font.GothamBold
showcaseBtn.TextSize = 14
showcaseBtn.TextColor3 = Color3.fromRGB(255, 215, 0)
showcaseBtn.Parent = gui
corner(showcaseBtn, 12)
styleFrame(showcaseBtn, false)

-- // Materials strip (top-center) ------------------------------------------------------
local materialsBar = Instance.new("Frame")
materialsBar.Size = UDim2.new(0, 520, 0, 40)
materialsBar.Position = UDim2.new(0.5, -260, 0, 16)
materialsBar.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
materialsBar.BackgroundTransparency = 0.15
materialsBar.BorderSizePixel = 0
materialsBar.Parent = gui
corner(materialsBar, 12)
styleFrame(materialsBar, false)

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
fitLegacyPanel(collectionPanel)
collectionPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
collectionPanel.BackgroundTransparency = 0.05
collectionPanel.BorderSizePixel = 0
collectionPanel.Visible = false
collectionPanel.ScrollBarThickness = 6
collectionPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
collectionPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
collectionPanel.Parent = gui
corner(collectionPanel, 12)

local collectionLayout = Instance.new("UIListLayout")
collectionLayout.Padding = UDim.new(0, 8)
collectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
collectionLayout.Parent = collectionPanel
pad(collectionPanel, 12)

-- // Showcase editor panel --------------------------------------------------------------
local editorPanel = Instance.new("ScrollingFrame")
editorPanel.Size = UDim2.new(0, 480, 0, 480)
editorPanel.Position = UDim2.new(0.5, -240, 0.5, -240)
editorPanel.CanvasSize = UDim2.new(0, 0, 0, 480)
editorPanel.ScrollBarThickness = 6
editorPanel.ScrollingDirection = Enum.ScrollingDirection.Y
fitLegacyPanel(editorPanel)
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
editorList.CanvasSize = UDim2.new(0, 0, 0, 0)
editorList.AutomaticCanvasSize = Enum.AutomaticSize.Y
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

-- Looks a brainrot definition up with either getter the data module offers.
local function lookupDef(id: any): any
	return BrainrotData.GetById(id) or BrainrotData.GetBrainrot(id)
end

-- Display only: the server decides the real price (keep in step with SELL_PRICE in GameServer).
local SELL_PRICE: { [string]: number } = { Common = 25, Rare = 100, Epic = 400, Legendary = 2000 }
local sellRemote = remotes:WaitForChild("SellBrainrots", 5)

local function sellPriceFor(inst: any): number
	local def = lookupDef(inst.BrainrotId)
	local price = if def then (SELL_PRICE[def.Rarity] or 10) else 10
	if inst.Shiny then
		price *= 5
	end
	return price
end

local function instanceLabel(inst: any): string
	local def = lookupDef(inst.BrainrotId)
	if not def then
		return tostring(inst.BrainrotId)
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
		local def = lookupDef(inst.BrainrotId)
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

		local textPad = Instance.new("UIPadding")
		textPad.PaddingRight = UDim.new(0, 112)
		textPad.Parent = entry

		local sellBtn = Instance.new("TextButton")
		sellBtn.Size = UDim2.new(0, 100, 0, 30)
		sellBtn.Position = UDim2.new(1, -106, 0.5, -15)
		sellBtn.Font = Enum.Font.GothamBold
		sellBtn.TextSize = 12
		sellBtn.TextColor3 = Color3.new(1, 1, 1)
		sellBtn.Parent = entry
		corner(sellBtn, 8)
		local sellLabel = "Sell " .. tostring(sellPriceFor(inst)) .. " coins"
		local sellColor = Color3.fromRGB(150, 90, 40)
		if workingIds[inst.InstanceId] then
			sellBtn.Text = "At work"
			sellBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
			sellBtn.AutoButtonColor = false
		else
			sellBtn.Text = sellLabel
			sellBtn.BackgroundColor3 = sellColor
			local armed = false
			sellBtn.MouseButton1Click:Connect(function()
				if not sellRemote then
					return
				end
				if not armed then
					-- first click asks to confirm, so nobody sells by accident
					armed = true
					sellBtn.Text = "Confirm?"
					sellBtn.BackgroundColor3 = Color3.fromRGB(190, 60, 60)
					task.delay(3, function()
						if armed and sellBtn.Parent then
							armed = false
							sellBtn.Text = sellLabel
							sellBtn.BackgroundColor3 = sellColor
						end
					end)
					return
				end
				armed = false
				local sellEvent = sellRemote :: RemoteEvent
				sellEvent:FireServer({ inst.InstanceId })
			end)
		end
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

-- Sends the showcase to the server shortly after the last change, so toggling a brainrot
-- off takes effect on the plot even if you close the panel without pressing Save.
local showcaseSaveToken = 0
local function queueShowcaseSave()
	showcaseSaveToken += 1
	local token = showcaseSaveToken
	task.delay(0.5, function()
		if token == showcaseSaveToken then
			showcaseRemote:FireServer(pendingShowcase)
		end
	end)
end

local function refreshEditorPanel()
	for _, child in ipairs(editorList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local sortedOwned: { any } = {}
	for _, pid in ipairs(pendingShowcase) do
		for _, inst in ipairs(ownedInstances) do
			if inst.InstanceId == pid then
				table.insert(sortedOwned, inst)
				break
			end
		end
	end
	for _, inst in ipairs(ownedInstances) do
		if not isPending(inst.InstanceId) then
			table.insert(sortedOwned, inst)
		end
	end
	for order, inst in ipairs(sortedOwned) do
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
					showBanner("Showcase is full (" .. tostring(BrainrotData.SHOWCASE_LIMIT) .. "). Remove one first!", 3)
					return
				end
				table.insert(pendingShowcase, inst.InstanceId)
			end
			paint()
			saveBtn.Text = ("Save Showcase (%d/%d)"):format(#pendingShowcase, BrainrotData.SHOWCASE_LIMIT)
			queueShowcaseSave()
		end)
	end
	saveBtn.Text = ("Save Showcase (%d/%d)"):format(#pendingShowcase, BrainrotData.SHOWCASE_LIMIT)
end

local clearShowcaseBtn = Instance.new("TextButton")
clearShowcaseBtn.Size = UDim2.new(0, 96, 0, 28)
clearShowcaseBtn.Position = UDim2.new(1, -156, 0, 14)
clearShowcaseBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 60)
clearShowcaseBtn.Text = "Clear all"
clearShowcaseBtn.Font = Enum.Font.GothamBold
clearShowcaseBtn.TextSize = 13
clearShowcaseBtn.TextColor3 = Color3.new(1, 1, 1)
clearShowcaseBtn.Parent = editorPanel
corner(clearShowcaseBtn, 8)
clearShowcaseBtn.MouseButton1Click:Connect(function()
	pendingShowcase = {}
	refreshEditorPanel()
	queueShowcaseSave()
end)

-- // Milestone 2: Fusion panel ---------------------------------------------------------
local fusionPanel = Instance.new("ScrollingFrame")
fusionPanel.Size = UDim2.new(0, 500, 0, 460)
fusionPanel.Position = UDim2.new(0.5, -250, 0.5, -230)
fitLegacyPanel(fusionPanel)
fusionPanel.BackgroundColor3 = Color3.fromRGB(25, 20, 35)
fusionPanel.BackgroundTransparency = 0.05
fusionPanel.BorderSizePixel = 0
fusionPanel.Visible = false
fusionPanel.ScrollBarThickness = 6
fusionPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
fusionPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
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
fusionTitle.Text = "⚗ Fusion Lab — 3 copies + type materials + coins"
fusionTitle.Font = Enum.Font.GothamBold
fusionTitle.TextSize = 15
fusionTitle.TextColor3 = Color3.fromRGB(220, 170, 255)
fusionTitle.TextWrapped = true
fusionTitle.LayoutOrder = 0
fusionTitle.Parent = fusionPanel

local workState: any = { Materials = {}, Stations = {} }

local fusionHowTo = Instance.new("TextLabel")
fusionHowTo.Size = UDim2.new(1, -24, 0, 72)
fusionHowTo.BackgroundTransparency = 1
fusionHowTo.Text = "Materials come from Work stations on your plot (assign brainrots, then Collect).\nWood→Timber  Water→Fish  Fire→Ingots  Sky→Cloud Cotton  Shadow→Dark Stone.\nOther types spend Timber. Rare gems come from Expeditions, not fusion."
fusionHowTo.Font = Enum.Font.Gotham
fusionHowTo.TextSize = 13
fusionHowTo.TextColor3 = Color3.fromRGB(190, 170, 220)
fusionHowTo.TextWrapped = true
fusionHowTo.TextXAlignment = Enum.TextXAlignment.Left
fusionHowTo.LayoutOrder = 0
fusionHowTo.Parent = fusionPanel

local function refreshFusionPanel()
	for _, child in ipairs(fusionPanel:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local groups: { [string]: any } = {}
	for _, inst in ipairs(ownedInstances) do
		if not inst.Shiny and not workingIds[inst.InstanceId] and lookupDef(inst.BrainrotId) then
			groups[inst.BrainrotId] = groups[inst.BrainrotId] or {}
			table.insert(groups[inst.BrainrotId], inst)
		end
	end
	local order = 1
	local anyGroup = false
	for brainrotId, list in pairs(groups) do
		if #list >= 3 then
			anyGroup = true
			local def = lookupDef(brainrotId)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -24, 0, 92)
			row.BackgroundColor3 = Color3.fromRGB(35, 28, 48)
			row.BorderSizePixel = 0
			row.LayoutOrder = order
			row.Parent = fusionPanel
			corner(row, 8)
			order += 1

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -120, 0, 24)
			nameLabel.Position = UDim2.new(0, 10, 0, 6)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = ("%s  x%d"):format(def and def.Name or brainrotId, #list)
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextSize = 15
			nameLabel.TextColor3 = Color3.new(1, 1, 1)
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Parent = row

			local costText: string
			local costColor = Color3.fromRGB(200, 180, 220)
			if def and def.Rarity == "Legendary" then
				local coins = BrainrotData.FUSION_COIN_COST.Legendary or 1000
				costText = ("Need %d coins → guaranteed SHINY"):format(coins)
			else
				local variantId = list[1] and list[1].Variant
				local workId, matName, matCost, coinFee = BrainrotData.GetFusionMaterialInfo(def, variantId)
				local have = ((workState.Materials or {})[workId] or 0)
				local resultRarity = def and BrainrotData.GetFusionResultRarity(def.Rarity) or "?"
				costText = ("Need %d %s (have %d) + %d coins → %s"):format(matCost, matName, have, coinFee, resultRarity)
				if have < matCost then
					costColor = Color3.fromRGB(255, 150, 140)
				end
			end
			local costLabel = Instance.new("TextLabel")
			costLabel.Size = UDim2.new(1, -120, 0, 48)
			costLabel.Position = UDim2.new(0, 10, 0, 32)
			costLabel.BackgroundTransparency = 1
			costLabel.Text = costText
			costLabel.Font = Enum.Font.Gotham
			costLabel.TextSize = 13
			costLabel.TextColor3 = costColor
			costLabel.TextWrapped = true
			costLabel.TextXAlignment = Enum.TextXAlignment.Left
			costLabel.TextYAlignment = Enum.TextYAlignment.Top
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
local arenaPanel = Instance.new("ScrollingFrame")
arenaPanel.Size = UDim2.new(0, 560, 0, 520)
arenaPanel.Position = UDim2.new(0.5, -280, 0.5, -260)
arenaPanel.CanvasSize = UDim2.new(0, 0, 0, 520)
arenaPanel.ScrollBarThickness = 6
arenaPanel.ScrollingDirection = Enum.ScrollingDirection.Y
fitLegacyPanel(arenaPanel)
arenaPanel.BackgroundColor3 = Color3.fromRGB(30, 18, 18)
arenaPanel.BorderSizePixel = 0
arenaPanel.Visible = false
arenaPanel.Parent = gui
corner(arenaPanel, 12)

local arenaTitle = Instance.new("TextLabel")
arenaTitle.Size = UDim2.new(1, 0, 0, 40)
arenaTitle.Position = UDim2.new(0, 0, 0, 8)
arenaTitle.BackgroundTransparency = 1
arenaTitle.Text = "⚔ Arena — pick 3, then a gate (1–100)"
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
teamList.CanvasSize = UDim2.new(0, 0, 0, 0)
teamList.AutomaticCanvasSize = Enum.AutomaticSize.Y
teamList.Parent = arenaPanel
corner(teamList, 8)

local teamLayout = Instance.new("UIListLayout")
teamLayout.Padding = UDim.new(0, 4)
teamLayout.SortOrder = Enum.SortOrder.LayoutOrder
teamLayout.Parent = teamList

local pvpLabel = Instance.new("TextLabel")
pvpLabel.Size = UDim2.new(1, -24, 0, 22)
pvpLabel.Position = UDim2.new(0, 12, 0, 232)
pvpLabel.BackgroundTransparency = 1
pvpLabel.Text = "PvP — challenge a player:"
pvpLabel.Font = Enum.Font.GothamBold
pvpLabel.TextSize = 14
pvpLabel.TextColor3 = Color3.fromRGB(255, 210, 120)
pvpLabel.TextXAlignment = Enum.TextXAlignment.Left
pvpLabel.Parent = arenaPanel

local pvpList = Instance.new("ScrollingFrame")
pvpList.Size = UDim2.new(1, -24, 0, 72)
pvpList.Position = UDim2.new(0, 12, 0, 254)
pvpList.BackgroundColor3 = Color3.fromRGB(22, 14, 14)
pvpList.BorderSizePixel = 0
pvpList.ScrollBarThickness = 6
pvpList.CanvasSize = UDim2.new(0, 0, 0, 0)
pvpList.AutomaticCanvasSize = Enum.AutomaticSize.Y
pvpList.Parent = arenaPanel
corner(pvpList, 8)
local pvpLayout = Instance.new("UIListLayout")
pvpLayout.Padding = UDim.new(0, 4)
pvpLayout.SortOrder = Enum.SortOrder.LayoutOrder
pvpLayout.Parent = pvpList

local rivalLabel = Instance.new("TextLabel")
rivalLabel.Size = UDim2.new(1, -24, 0, 24)
rivalLabel.Position = UDim2.new(0, 12, 0, 330)
rivalLabel.BackgroundTransparency = 1
rivalLabel.Text = "NPC gates:"
rivalLabel.Font = Enum.Font.GothamBold
rivalLabel.TextSize = 14
rivalLabel.TextColor3 = Color3.new(1, 1, 1)
rivalLabel.TextXAlignment = Enum.TextXAlignment.Left
rivalLabel.Parent = arenaPanel

local rivalList = Instance.new("ScrollingFrame")
rivalList.Size = UDim2.new(1, -24, 0, 96)
rivalList.Position = UDim2.new(0, 12, 0, 354)
rivalList.BackgroundColor3 = Color3.fromRGB(22, 14, 14)
rivalList.BorderSizePixel = 0
rivalList.ScrollBarThickness = 6
rivalList.CanvasSize = UDim2.new(0, 0, 0, 0)
rivalList.AutomaticCanvasSize = Enum.AutomaticSize.Y
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

local selectedTeam: { string } = {}
local selectedRivalId: string? = nil
local selectedPvpUserId: number? = nil
local beatenRivals: { [string]: boolean } = {}
local nearbyPlayers: { any } = {}

local function refreshArenaPanel()
	for _, child in ipairs(teamList:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for _, child in ipairs(pvpList:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for _, child in ipairs(rivalList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if #nearbyPlayers == 0 then
		local empty = Instance.new("TextButton")
		empty.Size = UDim2.new(1, -8, 0, 28)
		empty.BackgroundTransparency = 1
		empty.Text = "No other players here yet."
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 13
		empty.TextColor3 = Color3.fromRGB(160, 160, 170)
		empty.LayoutOrder = 0
		empty.Active = false
		empty.Parent = pvpList
	else
		for i, row in ipairs(nearbyPlayers) do
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, -8, 0, 30)
			btn.BackgroundColor3 = if selectedPvpUserId == row.UserId then Color3.fromRGB(180, 110, 40) else Color3.fromRGB(50, 36, 22)
			btn.Text = "⚔  " .. tostring(row.Name)
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = 14
			btn.TextColor3 = Color3.new(1, 1, 1)
			btn.LayoutOrder = i
			btn.Parent = pvpList
			corner(btn, 6)
			btn.MouseButton1Click:Connect(function()
				selectedPvpUserId = row.UserId
				selectedRivalId = nil
				startBattleBtn.Text = "Challenge " .. tostring(row.Name)
				refreshArenaPanel()
			end)
		end
	end
	local order = 1
	for _, inst in ipairs(ownedInstances) do
		if not workingIds[inst.InstanceId] and lookupDef(inst.BrainrotId) then
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
	local rOrder = 1
	for i, rival in ipairs(BrainrotData.RIVALS) do
		local locked = i > 1 and not beatenRivals[BrainrotData.RIVALS[i - 1].Id]
		local beaten = beatenRivals[rival.Id] == true
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -12, 0, 74)
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
			local d = lookupDef(bid)
			table.insert(teamNames, d and d.Name or bid)
		end
		local info = Instance.new("TextLabel")
		info.Size = UDim2.new(1, -110, 1, 0)
		info.Position = UDim2.new(0, 10, 0, 0)
		info.BackgroundTransparency = 1
		local rewardBits = { "+" .. tostring(rival.RewardCoins or 0) .. " coins" }
		if rival.RewardRarity then
			table.insert(rewardBits, rival.RewardRarity .. " brainrot")
		end
		info.Text = rival.Name .. " — " .. rival.Title .. "\n" .. table.concat(teamNames, ", ") .. "\n" .. table.concat(rewardBits, " · ")
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
				selectedPvpUserId = nil
				startBattleBtn.Text = "Start Battle"
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
local battlePanel = Instance.new("ScrollingFrame")
battlePanel.Size = UDim2.new(0, 640, 0, 560)
battlePanel.Position = UDim2.new(0.5, -320, 0.5, -280)
battlePanel.CanvasSize = UDim2.new(0, 0, 0, 560)
battlePanel.ScrollBarThickness = 6
battlePanel.ScrollingDirection = Enum.ScrollingDirection.Y
fitLegacyPanel(battlePanel)
battlePanel.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
battlePanel.BackgroundTransparency = 1
battlePanel.BorderSizePixel = 0
battlePanel.Visible = false
battlePanel.Parent = gui
corner(battlePanel, 12)
if not isMobile then
	-- Dock to the left edge so the arena fight stays visible on the right.
	battlePanel.AnchorPoint = Vector2.new(0, 0.5)
	battlePanel.Position = UDim2.new(0, 12, 0.5, 0)
end
local battleScale = Instance.new("UIScale")
battleScale.Scale = 0.7
battleScale.Parent = battlePanel

local battleTitle = Instance.new("TextLabel")
battleTitle.Size = UDim2.new(1, 0, 0, 36)
battleTitle.Position = UDim2.new(0, 0, 0, 6)
battleTitle.BackgroundTransparency = 1
battleTitle.Text = "Battle!"
battleTitle.Font = Enum.Font.GothamBold
battleTitle.TextSize = 20
battleTitle.TextColor3 = Color3.fromRGB(255, 200, 200)
battleTitle.TextStrokeTransparency = 0.4
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
		nameL.TextStrokeTransparency = 0.4
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
battleLog.BackgroundTransparency = 0.35
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
		card.BackgroundTransparency = 0.3
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
		nameL.TextStrokeTransparency = 0.4
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

local MOVE_TYPE_COLORS: { [string]: Color3 } = {
	Wood = Color3.fromRGB(55, 150, 55),
	Water = Color3.fromRGB(45, 110, 220),
	Fire = Color3.fromRGB(215, 95, 30),
	Sky = Color3.fromRGB(110, 190, 235),
	Shadow = Color3.fromRGB(125, 65, 185),
}

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
	local bar = fill :: GuiObject
	bar.Size = UDim2.new(math.clamp(hp / math.max(1, maxHp), 0, 1), 0, 1, 0)
end

local currentBattleState: any = nil

local function fighterAlive(i: number): boolean
	local st: any = currentBattleState
	local f = st and st.pTeam and st.pTeam[i]
	return f ~= nil and (f.HP or 0) > 0
end

local function refreshMoveButtons()
	local st: any = currentBattleState
	local waiting = st and st.waitingFor
	local waitIdx = if waiting and waiting.side == "player" then waiting.idx else 0
	for i = 1, 3 do
		local alive = fighterAlive(i)
		local myTurn = alive and i == waitIdx
		for _, b in ipairs(playerCards[i].moveBtns) do
			local mb = b :: TextButton
			mb.Active = myTurn
			mb.AutoButtonColor = myTurn
			mb.BackgroundTransparency = if myTurn then 0 else 0.7
		end
		playerCards[i].card.BackgroundTransparency = if myTurn then 0.05 elseif alive then 0.3 else 0.7
	end
end

-- The old code waited for ALL THREE fighters to pick a move, so once one fainted the turn
-- could never be sent and the battle froze after the first round. Only living fighters pick now.
local function trySubmitMoves()
	if not battleActive then
		return
	end
	local st: any = currentBattleState
	local waiting = st and st.waitingFor
	if not waiting or waiting.side ~= "player" then
		return
	end
	local slot = waiting.idx
	local m = lockedMoves[slot]
	if not m then
		return
	end
	battleActive = false
	submitMovesRemote:FireServer({ Slot = slot, Move = m })
end

local function buildBattleUI(state: any)
	currentBattleState = state
	local cam = workspace.CurrentCamera
	if isMobile or not cam then
		battleScale.Scale = 1
	else
		battleScale.Scale = math.clamp(cam.ViewportSize.Y / 950, 0.45, 0.75)
	end
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
			local extra = if move.Effect then string.upper(tostring(move.Effect)) else (tostring(move.Power) .. " PWR")
			mb.Text = move.Name .. "\n" .. extra
			mb.Font = Enum.Font.GothamBold
			mb.TextSize = 10
			mb.TextColor3 = Color3.new(1, 1, 1)
			mb.TextTruncate = Enum.TextTruncate.AtEnd
			mb.Parent = card.card
			corner(mb, 6)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.new(1, 1, 1)
			stroke.Thickness = 2.5
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
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
				trySubmitMoves()
			end)
		end
	end
	battleActive = true
	refreshMoveButtons()
	local waiting = state.waitingFor
	local waitName = waiting and waiting.name or "your fighter"
	if waiting and waiting.side ~= "player" then
		battleLogLine("Waiting for " .. waitName .. "...", Color3.fromRGB(200, 200, 220))
	else
		battleLogLine("Speed order! " .. waitName .. " is up first — pick a move.", Color3.fromRGB(255, 220, 120))
	end
end

local function applyTurn(payload: any)
	local state = payload.State
	local events = payload.Events or {}
	task.spawn(function()
		for _, ev in ipairs(events) do
			if ev.kind == "heal" then
				battleLogLine(("%s used %s and recovered %d HP!"):format(ev.attackerName, ev.moveName, ev.heal or 0),
					Color3.fromRGB(120, 255, 160))
			elseif ev.kind == "boost" then
				battleLogLine(("%s used %s — %s rose!"):format(ev.attackerName, ev.moveName, ev.boost or "power"),
					Color3.fromRGB(255, 210, 90))
			elseif ev.miss then
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
		if state then
			currentBattleState = state
		end
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
				for i = 1, 3 do
					for _, b in ipairs(playerCards[i].moveBtns) do
						local s = b:FindFirstChildOfClass("UIStroke")
						if s then
							s.Enabled = false
						end
					end
				end
				battleActive = true
				refreshMoveButtons()
				local waitName = state.waitingFor and state.waitingFor.name or "your fighter"
				battleLogLine(waitName .. "'s turn — pick a move.", Color3.fromRGB(255, 220, 120))
			end
		end
	end)
end

forfeitBtn.MouseButton1Click:Connect(function()
	forfeitRemote:FireServer()
	battlePanel.Visible = false
end)

-- // Exploration & Progression Panels -----------------------------------------------------
local exploreBtn = Instance.new("TextButton")
exploreBtn.Size = UDim2.new(0, 104, 0, 40)
exploreBtn.Position = UDim2.new(0.5, -276, 1, -172)
exploreBtn.BackgroundColor3 = Color3.fromRGB(35, 60, 35)
exploreBtn.Text = "Explore"
exploreBtn.Font = Enum.Font.GothamBold
exploreBtn.TextSize = 13
exploreBtn.TextColor3 = Color3.fromRGB(170, 255, 170)
exploreBtn.Parent = gui
exploreBtn.Visible = false
corner(exploreBtn, 10)

local dailyBtn = Instance.new("TextButton")
dailyBtn.Size = UDim2.new(0, 104, 0, 40)
dailyBtn.Position = UDim2.new(0.5, -164, 1, -172)
dailyBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
dailyBtn.Text = "Dailies"
dailyBtn.Font = Enum.Font.GothamBold
dailyBtn.TextSize = 13
dailyBtn.TextColor3 = Color3.fromRGB(200, 200, 255)
dailyBtn.Parent = gui
corner(dailyBtn, 10)

local eggBtn = Instance.new("TextButton")
eggBtn.Size = UDim2.new(0, 104, 0, 40)
eggBtn.Position = UDim2.new(0.5, -52, 1, -172)
eggBtn.BackgroundColor3 = Color3.fromRGB(80, 65, 30)
eggBtn.Text = "Eggs"
eggBtn.Font = Enum.Font.GothamBold
eggBtn.TextSize = 13
eggBtn.TextColor3 = Color3.fromRGB(255, 230, 150)
eggBtn.Parent = gui
corner(eggBtn, 10)

local mineBtn = Instance.new("TextButton")
mineBtn.Size = UDim2.new(0, 104, 0, 40)
mineBtn.Position = UDim2.new(0.5, 60, 1, -172)
mineBtn.BackgroundColor3 = Color3.fromRGB(70, 55, 20)
mineBtn.Text = "Gold Mine"
mineBtn.Font = Enum.Font.GothamBold
mineBtn.TextSize = 13
mineBtn.TextColor3 = Color3.fromRGB(255, 210, 100)
mineBtn.Parent = gui
corner(mineBtn, 10)

local styleBtn = Instance.new("TextButton")
styleBtn.Size = UDim2.new(0, 104, 0, 40)
styleBtn.Position = UDim2.new(0.5, 172, 1, -172)
styleBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 70)
styleBtn.Text = "Style"
styleBtn.Font = Enum.Font.GothamBold
styleBtn.TextSize = 13
styleBtn.TextColor3 = Color3.fromRGB(220, 180, 255)
styleBtn.Parent = gui
corner(styleBtn, 10)

local statsBtn = Instance.new("TextButton")
statsBtn.Size = UDim2.new(0, 104, 0, 40)
statsBtn.Position = UDim2.new(0.5, 284, 1, -124)
statsBtn.BackgroundColor3 = Color3.fromRGB(70, 50, 20)
statsBtn.Text = "📊 Stats"
statsBtn.Font = Enum.Font.GothamBold
statsBtn.TextSize = 13
statsBtn.TextColor3 = Color3.fromRGB(255, 200, 100)
statsBtn.Parent = gui
statsBtn.Visible = false
corner(statsBtn, 10)

local function makePanel(title: string, titleColor: Color3): (Frame, TextLabel)
	local panel = Instance.new("ScrollingFrame")
	if isMobile then
		panel.Size = UDim2.new(0.92, 0, 0.78, 0)
		panel.Position = UDim2.new(0.04, 0, 0.11, 0)
	else
		panel.Size = UDim2.new(0, 560, 0, 520)
		panel.Position = UDim2.new(0.5, -280, 0.5, -260)
	end
	panel.BackgroundColor3 = THEME.Panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	panel.ScrollBarThickness = 6
	panel.ScrollingDirection = Enum.ScrollingDirection.Y
	panel.CanvasSize = UDim2.new(0, 0, 0, 0)
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	corner(panel, 16)
	styleFrame(panel, false)
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
	return panel :: any, titleLbl
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

local expeditionPanel, _expTitle = makePanel("🗺 Expeditions — send brainrots to gather (15 min)", Color3.fromRGB(170, 255, 170))
local dailyPanel, _dailyTitle = makePanel("📅 Daily Quests — complete for mystery eggs", Color3.fromRGB(200, 200, 255))
local eggPanel, _eggTitle = makePanel("🥚 Mystery Eggs — hatch with playtime", Color3.fromRGB(255, 230, 150))
local minePanel, _mineTitle = makePanel("⛏ Gold Mine — coins while you play", Color3.fromRGB(255, 210, 100))
local customizePanel, _custTitle = makePanel("🎨 Customize Your Plot", Color3.fromRGB(220, 180, 255))
local statsPanel, _statsTitle = makePanel("📊 Stat Upgrades", Color3.fromRGB(255, 200, 100))
local _lbTitle: TextLabel
leaderboardPanel, _lbTitle = makePanel("🏆 Battle Wins Leaderboard", Color3.fromRGB(255, 210, 100))

local refreshStatsPanel: () -> ()
local refreshFishingPanel: () -> ()

-- Defined here (before any button uses it) so every click handler below can call it.
hideAllPanels = function()
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
	statsPanel.Visible = false
	leaderboardPanel.Visible = false
end

exploreBtn.MouseButton1Click:Connect(function()
	local was = expeditionPanel.Visible
	hideAllPanels()
	if not was then
		refreshExpeditionPanel()
		expeditionPanel.Visible = true
	end
end)
dailyBtn.MouseButton1Click:Connect(function()
	local was = dailyPanel.Visible
	hideAllPanels()
	if not was then
		refreshDailyPanel()
		dailyPanel.Visible = true
	end
end)
eggBtn.MouseButton1Click:Connect(function()
	local was = eggPanel.Visible
	hideAllPanels()
	if not was then
		refreshEggPanel()
		eggPanel.Visible = true
	end
end)
mineBtn.MouseButton1Click:Connect(function()
	local was = minePanel.Visible
	hideAllPanels()
	if not was then
		refreshMinePanel()
		minePanel.Visible = true
	end
end)
styleBtn.MouseButton1Click:Connect(function()
	local was = customizePanel.Visible
	hideAllPanels()
	if not was then
		refreshCustomizePanel()
		customizePanel.Visible = true
	end
end)
statsBtn.MouseButton1Click:Connect(function()
	local was = statsPanel.Visible
	hideAllPanels()
	if not was then
		statsPanel.Visible = true
		refreshStatsPanel()
	end
end)

local fishingPanel, _fishTitle = makePanel("🎣 Fishing — catch brainrots and treasures!", Color3.fromRGB(150, 200, 255))
local fishingState: string = "None"

-- Fishing panel wasn't covered by hideAllPanels before it existed; wrap it so it closes too.
local baseHideAll = hideAllPanels
hideAllPanels = function()
	baseHideAll()
	fishingPanel.Visible = false
end

refreshFishingPanel = function()
	pcall(function()
		game:GetService("ContextActionService"):UnbindAction("BrainrotReel")
	end)
	local oldReel = gui:FindFirstChild("ReelNowButton")
	if oldReel then
		oldReel:Destroy()
	end
	for _, c in ipairs(fishingPanel:GetChildren()) do
		if c:IsA("GuiObject") and (c :: GuiObject).LayoutOrder > 0 then
			c:Destroy()
		end
	end
	local order = 1
	if fishingState == "None" then
		makeLabel(fishingPanel, "Walk onto a dock under the FISHING sign and press Cast Line.", 14, Color3.new(1,1,1), order)
	elseif fishingState == "Waiting" then
		makeLabel(fishingPanel, "⏳ Waiting for a bite...", 16, Color3.fromRGB(150, 200, 255), order)
		order += 1
		makeLabel(fishingPanel, "Watch the bobber!", 13, Color3.fromRGB(180, 180, 180), order)
	elseif fishingState == "Bite" then
		makeLabel(fishingPanel, "❗ BITE! REEL NOW! ❗", 20, Color3.fromRGB(255, 220, 50), order)
		order += 1
		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(1, 0, 0, 30)
		barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
		barBg.LayoutOrder = order
		barBg.Parent = fishingPanel
		corner(barBg, 8)
		order += 1
		local sweetSpot = Instance.new("Frame")
		sweetSpot.Size = UDim2.new(0.2, 0, 1, 0)
		sweetSpot.Position = UDim2.new(0.4, 0, 0, 0)
		sweetSpot.BackgroundColor3 = Color3.fromRGB(60, 200, 60)
		sweetSpot.Parent = barBg
		corner(sweetSpot, 8)
		local marker = Instance.new("Frame")
		marker.Size = UDim2.new(0.05, 0, 1, 0)
		marker.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		marker.Parent = barBg
		corner(marker, 4)
		local markerPos = 0
		local direction = 1
		task.spawn(function()
			while fishingState == "Bite" and marker and marker.Parent do
				markerPos += direction * 0.03
				if markerPos >= 0.95 then direction = -1 end
				if markerPos <= 0 then direction = 1 end
				marker.Position = UDim2.new(markerPos, 0, 0, 0)
				task.wait(0.03)
			end
		end)
		makeLabel(fishingPanel, "Controller: press X (or A / RT / E) to reel.", 13, Color3.fromRGB(200, 220, 255), order)
		order += 1
		local reelBtn = Instance.new("TextButton")
		reelBtn.Size = UDim2.new(1, 0, 0, 56)
		reelBtn.Text = "🎣 REEL IN!  (X / E)"
		reelBtn.BackgroundColor3 = Color3.fromRGB(200, 150, 50)
		reelBtn.TextColor3 = Color3.new(1,1,1)
		reelBtn.Font = Enum.Font.GothamBold
		reelBtn.TextSize = 18
		reelBtn.LayoutOrder = order
		reelBtn.Selectable = true
		reelBtn.Parent = fishingPanel
		corner(reelBtn, 8)
		local overlay = gui:FindFirstChild("ReelNowButton")
		if overlay and overlay:IsA("TextButton") then
			overlay:Destroy()
		end
		local bigReel = Instance.new("TextButton")
		bigReel.Name = "ReelNowButton"
		bigReel.Size = UDim2.new(0.56, 0, 0, 72)
		bigReel.Position = UDim2.new(0.22, 0, 0.78, 0)
		bigReel.BackgroundColor3 = Color3.fromRGB(220, 160, 40)
		bigReel.Text = "🎣 REEL IN!"
		bigReel.Font = Enum.Font.GothamBlack
		bigReel.TextSize = 24
		bigReel.TextColor3 = Color3.new(1, 1, 1)
		bigReel.Selectable = true
		bigReel.ZIndex = 20
		bigReel.Parent = gui
		corner(bigReel, 14)
		local function doReel()
			if fishingState ~= "Bite" then
				return
			end
			local quality = 1 - math.abs((markerPos + 0.025) - 0.5) * 2
			quality = math.clamp(quality, 0, 1)
			reelRemote:FireServer(quality)
			fishingState = "None"
			if bigReel.Parent then
				bigReel:Destroy()
			end
			game:GetService("ContextActionService"):UnbindAction("BrainrotReel")
		end
		reelBtn.MouseButton1Click:Connect(doReel)
		bigReel.MouseButton1Click:Connect(doReel)
		local guiService = game:GetService("GuiService")
		guiService.GuiNavigationEnabled = true
		guiService.AutoSelectGuiEnabled = true
		guiService.SelectedObject = bigReel
		game:GetService("ContextActionService"):BindAction("BrainrotReel", function(_name, state)
			if state == Enum.UserInputState.Begin then
				doReel()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonL2, Enum.KeyCode.E)
	elseif fishingState == "Missed" then
		makeLabel(fishingPanel, "💨 It got away...", 16, Color3.fromRGB(180, 180, 180), order)
		order += 1
		local retryBtn = Instance.new("TextButton")
		retryBtn.Size = UDim2.new(1, 0, 0, 40)
		retryBtn.Text = "Try Again"
		retryBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
		retryBtn.TextColor3 = Color3.new(1,1,1)
		retryBtn.Font = Enum.Font.GothamBold
		retryBtn.TextSize = 14
		retryBtn.LayoutOrder = order
		retryBtn.Parent = fishingPanel
		corner(retryBtn, 8)
		retryBtn.MouseButton1Click:Connect(function()
			fishingState = "None"
			refreshFishingPanel()
		end)
		makeLabel(fishingPanel, "Use Cast Line on the dock to try again.", 13, Color3.fromRGB(180, 180, 180), order + 1)
	end
end

fishingUpdateRemote.OnClientEvent:Connect(function(payload: any)
	if payload.OpenPanel then
		hideAllPanels()
		fishingPanel.Visible = true
	end
	if payload.State then
		fishingState = payload.State
		if fishingPanel.Visible then
			refreshFishingPanel()
		end
	end
	if payload.Reward then
		local r = payload.Reward
		local msg = ""
		if r.Kind == "Fish" then
			msg = "🐟 Caught " .. tostring(r.Amount) .. " Fish!"
		elseif r.Kind == "Coins" then
			msg = "Found " .. tostring(r.Amount) .. " coins!"
		elseif r.Kind == "Material" then
			msg = "💎 Got " .. tostring(r.Amount) .. "x " .. tostring(r.Name) .. "!"
		elseif r.Kind == "Brainrot" then
			msg = "🎉 CAUGHT A BRAINROT: " .. (r.BrainrotName or "?") .. "!"
			if r.Shiny then msg ..= " ✨ SHINY!" end
		elseif r.Kind == "Miss" then
			msg = r.Message or "It got away..."
		end
		if r.Message and r.Kind ~= "Miss" then
			msg ..= " (" .. r.Message .. ")"
		end
		showBanner(msg, 4)
		fishingState = "None"
		if fishingPanel.Visible then
			refreshFishingPanel()
		end
	end
end)

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

local assignWorkerRemote = remotes:WaitForChild("AssignWorker")
local collectRemote = remotes:WaitForChild("CollectStation")
local workUpdateRemote = remotes:WaitForChild("WorkUpdate")

local jobsByInstance: { [string]: string } = {}
local pickingForWorkId: string? = nil

local function pips(level: number): string
	return string.rep("●", level) .. string.rep("○", 3 - level)
end

workPanel = Instance.new("ScrollingFrame")
workPanel.Size = UDim2.new(0, 500, 0, 460)
workPanel.Position = UDim2.new(0.5, -250, 0.5, -230)
fitLegacyPanel(workPanel)
workPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
workPanel.BackgroundTransparency = 0.05
workPanel.BorderSizePixel = 0
workPanel.Visible = false
workPanel.ScrollBarThickness = 6
workPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
workPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
workPanel.Parent = gui
corner(workPanel, 12)

local workLayout = Instance.new("UIListLayout")
workLayout.Padding = UDim.new(0, 10)
workLayout.SortOrder = Enum.SortOrder.LayoutOrder
workLayout.Parent = workPanel
pad(workPanel, 12)

pickerPanel = Instance.new("ScrollingFrame")
pickerPanel.Size = UDim2.new(0, 460, 0, 440)
pickerPanel.Position = UDim2.new(0.5, -230, 0.5, -220)
pickerPanel.CanvasSize = UDim2.new(0, 0, 0, 440)
pickerPanel.ScrollBarThickness = 6
pickerPanel.ScrollingDirection = Enum.ScrollingDirection.Y
fitLegacyPanel(pickerPanel)
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
pickerList.CanvasSize = UDim2.new(0, 0, 0, 0)
pickerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
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

	local candidates = {}
	for _, inst in ipairs(ownedInstances) do
		if not jobsByInstance[inst.InstanceId] then
			local def = lookupDef(inst.BrainrotId)
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
				local def = lookupDef(w.BrainrotId)
				local suit = def and BrainrotData.GetWorkSuitability(def, w.Variant, workId) or 0
				local nameLabel = Instance.new("TextLabel")
				nameLabel.Size = UDim2.new(1, -120, 1, 0)
				nameLabel.Position = UDim2.new(0, 10, 0, 0)
				nameLabel.BackgroundTransparency = 1
				nameLabel.Text = (def and BrainrotData.GetDisplayName(def, w.Variant, w.Shiny) or tostring(w.BrainrotId)) .. "  " .. pips(suit)
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

local hintLabel = Instance.new("TextLabel")
hintLabel.Size = UDim2.new(0, 500, 0, 44)
hintLabel.Position = UDim2.new(0.5, -250, 1, -290)
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
			local def = lookupDef(payload.BrainrotId)
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

local upgradeTiers = { Speed = 0, Jump = 0, Reach = 0, Luck = 0 }
local currentCoins = 0

collectionRemote.OnClientEvent:Connect(function(payload: any)
	ownedInstances = payload.Brainrots or {}
	showcaseIds = {}
	for _, id in ipairs(payload.Showcase or {}) do
		showcaseIds[id] = true
	end
	workingIds = payload.Working or {}
	coinsLabel.Text = "Coins: " .. tostring(payload.Coins or 0)
	currentCoins = payload.Coins or 0
	if payload.Upgrades then
		upgradeTiers = payload.Upgrades
		if statsPanel.Visible then
			refreshStatsPanel()
		end
	end
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

startBattleBtn.MouseButton1Click:Connect(function()
	if #selectedTeam ~= 3 then
		hintLabel.Text = "Pick 3 fighters first!"
		hintLabel.Visible = true
		task.delay(3, function()
			hintLabel.Visible = false
		end)
		return
	end
	if selectedPvpUserId then
		challengePvpRemote:FireServer(selectedPvpUserId, selectedTeam)
		return
	end
	if not selectedRivalId then
		hintLabel.Text = "Pick a player or an NPC gate!"
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
	nearbyPlayers = payload.Players or {}
	hideAllPanels()
	selectedTeam = {}
	selectedRivalId = nil
	selectedPvpUserId = nil
	startBattleBtn.Text = "Start Battle"
	teamLabel.Text = "Your team (0/3):"
	refreshArenaPanel()
	arenaPanel.Visible = true
end)

do
	local inviteBar = Instance.new("Frame")
	inviteBar.Name = "PvpInvite"
	inviteBar.Size = UDim2.new(0, 420, 0, 88)
	inviteBar.Position = UDim2.new(0.5, -210, 0, 120)
	inviteBar.BackgroundColor3 = Color3.fromRGB(70, 40, 20)
	inviteBar.Visible = false
	inviteBar.Parent = gui
	corner(inviteBar, 12)
	local inviteText = Instance.new("TextLabel")
	inviteText.Size = UDim2.new(1, -16, 0, 40)
	inviteText.Position = UDim2.new(0, 8, 0, 4)
	inviteText.BackgroundTransparency = 1
	inviteText.Text = "PvP challenge"
	inviteText.Font = Enum.Font.GothamBold
	inviteText.TextSize = 16
	inviteText.TextColor3 = Color3.fromRGB(255, 230, 160)
	inviteText.TextWrapped = true
	inviteText.Parent = inviteBar
	local acceptBtn = Instance.new("TextButton")
	acceptBtn.Size = UDim2.new(0, 190, 0, 32)
	acceptBtn.Position = UDim2.new(0, 12, 1, -40)
	acceptBtn.BackgroundColor3 = Color3.fromRGB(40, 140, 70)
	acceptBtn.Text = "Accept"
	acceptBtn.Font = Enum.Font.GothamBold
	acceptBtn.TextSize = 16
	acceptBtn.TextColor3 = Color3.new(1, 1, 1)
	acceptBtn.Parent = inviteBar
	corner(acceptBtn, 8)
	local declineBtn = Instance.new("TextButton")
	declineBtn.Size = UDim2.new(0, 190, 0, 32)
	declineBtn.Position = UDim2.new(1, -202, 1, -40)
	declineBtn.BackgroundColor3 = Color3.fromRGB(140, 40, 40)
	declineBtn.Text = "Decline"
	declineBtn.Font = Enum.Font.GothamBold
	declineBtn.TextSize = 16
	declineBtn.TextColor3 = Color3.new(1, 1, 1)
	declineBtn.Parent = inviteBar
	corner(declineBtn, 8)
	pvpInviteRemote.OnClientEvent:Connect(function(info: any)
		inviteText.Text = tostring(info.HostName or "A player") .. " challenged you to PvP!\nPick 3 in Arena, then Accept."
		inviteBar.Visible = true
		hideAllPanels()
		refreshArenaPanel()
		arenaPanel.Visible = true
	end)
	acceptBtn.MouseButton1Click:Connect(function()
		if #selectedTeam ~= 3 then
			hintLabel.Text = "Pick 3 fighters first, then Accept."
			hintLabel.Visible = true
			return
		end
		respondPvpRemote:FireServer(true, selectedTeam)
		inviteBar.Visible = false
	end)
	declineBtn.MouseButton1Click:Connect(function()
		respondPvpRemote:FireServer(false, {})
		inviteBar.Visible = false
	end)
end

fusionResultRemote.OnClientEvent:Connect(function(payload: any)
	local text: string
	if payload.Kind == "Cache" then
		text = "📦 Brainrot Cache! "
	else
		text = "⚗ Fusion complete! "
	end
	if payload.BrainrotId then
		local def = lookupDef(payload.BrainrotId)
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
		if payload.Events and #payload.Events > 0 then
			applyTurn(payload)
		end
	elseif payload.Phase == "Turn" then
		applyTurn(payload)
	elseif payload.Phase == "End" then
		battlePanel.Visible = false
		battleActive = false
	end
end)

local expeditionData: any = { Expeditions = {}, UnlockedZones = {} }
local dailyData: any = { Quests = {} }
local eggData: any = { Eggs = {}, Slots = 3 }
local passiveBanked: number = 0
local passiveBrainrotRate: number = 0
local customizeData: any = { Theme = "default", UnlockedThemes = {}, Decorations = {} }

refreshExpeditionPanel = function()
	for _, c in ipairs(expeditionPanel:GetChildren()) do
		if c:IsA("GuiObject") and (c :: GuiObject).LayoutOrder > 0 then
			c:Destroy()
		end
	end
	local order = 1
	local expeditions: any = expeditionData.Expeditions or {}
	local unlockedZones: any = expeditionData.UnlockedZones or {}
	if #expeditions > 0 then
		makeLabel(expeditionPanel, "Active Expeditions:", 15, Color3.fromRGB(255, 255, 255), order)
		order += 1
		for _, exp in ipairs(expeditions) do
			local row = makeRow(expeditionPanel, order, 56)
			order += 1
			local mins = math.floor(exp.RemainingSecs / 60)
			local secs = exp.RemainingSecs % 60
			local status = exp.Complete and "✅ Complete!" or string.format("⏳ %d:%02d left", mins, secs)
			makeLabel(row, exp.ZoneName .. " — " .. table.concat(exp.TeamNames, ", "), 13, Color3.new(1,1,1), 1).Position = UDim2.new(0, 8, 0, 4)
			makeLabel(row, status, 12, Color3.fromRGB(170, 255, 170), 2).Position = UDim2.new(0, 8, 0, 28)
		end
	end
	makeLabel(expeditionPanel, "Zones (use an Expedition Gate portal to discover):", 15, Color3.fromRGB(255, 255, 255), order)
	order += 1
	for _, zoneId in ipairs(BrainrotData.ZONE_ORDER) do
		local zone = BrainrotData.ZONES[zoneId]
		local unlocked = unlockedZones[zoneId]
		local row = makeRow(expeditionPanel, order, 72)
		order += 1
		if unlocked then
			row.BackgroundColor3 = zone.Color
			makeLabel(row, "📍 " .. zone.Name, 14, Color3.new(1,1,1), 1).Position = UDim2.new(0, 8, 0, 4)
			makeLabel(row, "Best: " .. zone.FavoredType .. " | Drops: " .. table.concat(zone.Materials, ", "), 11, Color3.fromRGB(230, 230, 230), 2).Position = UDim2.new(0, 8, 0, 26)
			makeLabel(row, zone.Description, 11, Color3.fromRGB(210, 210, 210), 3).Position = UDim2.new(0, 8, 0, 44)
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
	if selectedZone then
		makeLabel(expeditionPanel, "Team (tap brainrots to add, max 3):", 15, Color3.fromRGB(255, 255, 255), order)
		order += 1
		local teamRow = makeRow(expeditionPanel, order, 40)
		order += 1
		local names = {}
		for _, iid in ipairs(expeditionTeam) do
			for _, inst in ipairs(ownedInstances) do
				if inst.InstanceId == iid then
					local def = lookupDef(inst.BrainrotId)
					table.insert(names, def and def.Name or "?")
					break
				end
			end
		end
		makeLabel(teamRow, if #names == 0 then "No brainrots selected" else table.concat(names, ", "), 13, Color3.new(1,1,1), 1).Position = UDim2.new(0, 8, 0, 8)
		local availCount = 0
		for _, inst in ipairs(ownedInstances) do
			local iid = inst.InstanceId
			if not workingIds[iid] and not showcaseIds[iid] and lookupDef(inst.BrainrotId) then
				availCount += 1
				if availCount > 12 then break end
				local def = lookupDef(inst.BrainrotId)
				local picked = table.find(expeditionTeam, iid) ~= nil
				local bBtn = Instance.new("TextButton")
				bBtn.Size = UDim2.new(0, 160, 0, 28)
				bBtn.Text = (def and def.Name or "?") .. (if picked then " ✓" else "")
				bBtn.BackgroundColor3 = if picked then Color3.fromRGB(60, 140, 60) else Color3.fromRGB(50, 50, 70)
				bBtn.TextColor3 = Color3.new(1,1,1)
				bBtn.Font = Enum.Font.Gotham
				bBtn.TextSize = 11
				bBtn.LayoutOrder = order
				bBtn.Parent = expeditionPanel
				corner(bBtn, 6)
				order += 1
				bBtn.MouseButton1Click:Connect(function()
					local idx = table.find(expeditionTeam, iid)
					if idx then
						table.remove(expeditionTeam, idx)
					elseif #expeditionTeam < 3 then
						table.insert(expeditionTeam, iid)
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
			if selectedZone and #expeditionTeam > 0 then
				startExpeditionRemote:FireServer(selectedZone, expeditionTeam)
				expeditionTeam = {}
			end
		end)
	end
end

refreshDailyPanel = function()
	for _, c in ipairs(dailyPanel:GetChildren()) do
		if c:IsA("GuiObject") and (c :: GuiObject).LayoutOrder > 0 then
			c:Destroy()
		end
	end
	local order = 1
	for _, q in ipairs(dailyData.Quests or {}) do
		local row = makeRow(dailyPanel, order, 88)
		order += 1
		row.BackgroundColor3 = q.TierColor
		makeLabel(row, q.TierName .. ": " .. q.Text, 14, Color3.new(1,1,1), 1).Position = UDim2.new(0, 8, 0, 4)
		makeLabel(row, string.format("Progress: %d/%d", q.Progress, q.Target), 12, Color3.new(1,1,1), 2).Position = UDim2.new(0, 8, 0, 26)
		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(1, -16, 0, 10)
		barBg.Position = UDim2.new(0, 8, 0, 48)
		barBg.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
		barBg.Parent = row
		corner(barBg, 5)
		local dailyFill = Instance.new("Frame")
		dailyFill.Size = UDim2.new(math.clamp(q.Progress / q.Target, 0, 1), 0, 1, 0)
		dailyFill.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
		dailyFill.Parent = barBg
		corner(dailyFill, 5)
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

refreshEggPanel = function()
	for _, c in ipairs(eggPanel:GetChildren()) do
		if c:IsA("GuiObject") and (c :: GuiObject).LayoutOrder > 0 then
			c:Destroy()
		end
	end
	local order = 1
	makeLabel(eggPanel, string.format("Incubator: %d/%d slots used", eggData.UsedSlots or 0, eggData.Slots or 3), 14, Color3.new(1,1,1), order)
	order += 1
	for _, egg in ipairs(eggData.Eggs or {}) do
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
		local eggFill = Instance.new("Frame")
		eggFill.Size = UDim2.new(egg.Percent, 0, 1, 0)
		eggFill.BackgroundColor3 = Color3.fromRGB(255, 220, 100)
		eggFill.Parent = barBg
		corner(eggFill, 4)
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

refreshMinePanel = function()
	for _, c in ipairs(minePanel:GetChildren()) do
		if c:IsA("GuiObject") and (c :: GuiObject).LayoutOrder > 0 then
			c:Destroy()
		end
	end
	local order = 1
	makeLabel(minePanel, "Your gold mine and the brainrots on your pedestals earn coins while you play!", 14, Color3.new(1,1,1), order)
	order += 1
	makeLabel(minePanel, "🧠 Displayed brainrots earn about " .. tostring(passiveBrainrotRate) .. " coins/min", 13, Color3.fromRGB(180, 255, 170), order)
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

-- The original file called this but never defined it, so the Style panel was always empty.
-- It shows your current theme and, if BrainrotData lists themes/decorations under one of
-- the names below, buttons to unlock/buy them. Adjust the names to match your data module.
refreshCustomizePanel = function()
	for _, c in ipairs(customizePanel:GetChildren()) do
		if c:IsA("GuiObject") and (c :: GuiObject).LayoutOrder > 0 then
			c:Destroy()
		end
	end
	local order = 1
	makeLabel(customizePanel, "Current theme: " .. tostring(customizeData.Theme or "default"), 15, Color3.new(1, 1, 1), order)
	order += 1

	local data: any = BrainrotData
	local themes: any = data.PLOT_THEMES or data.THEMES
	local unlocked: any = customizeData.UnlockedThemes or {}
	if type(themes) == "table" then
		makeLabel(customizePanel, "Themes:", 15, Color3.fromRGB(220, 180, 255), order)
		order += 1
		for themeId, theme in pairs(themes) do
			local id = tostring(themeId)
			local themeName = if type(theme) == "table" and theme.Name then tostring(theme.Name) else id
			local cost = if type(theme) == "table" and theme.Cost then tonumber(theme.Cost) else nil
			local owned = unlocked[id] == true or table.find(unlocked, id) ~= nil
			local row = makeRow(customizePanel, order, 44)
			order += 1
			makeLabel(row, themeName .. (if owned then "  (owned)" elseif cost then ("  (" .. tostring(cost) .. " coins)") else ""), 14, Color3.new(1, 1, 1), 1).Position = UDim2.new(0, 8, 0, 10)
			if not owned then
				local buy = Instance.new("TextButton")
				buy.Size = UDim2.new(0, 90, 0, 30)
				buy.Position = UDim2.new(1, -98, 0.5, -15)
				buy.Text = "Unlock"
				buy.BackgroundColor3 = Color3.fromRGB(60, 140, 60)
				buy.TextColor3 = Color3.new(1, 1, 1)
				buy.Font = Enum.Font.GothamBold
				buy.TextSize = 13
				buy.Parent = row
				corner(buy, 6)
				buy.MouseButton1Click:Connect(function()
					unlockThemeRemote:FireServer(id)
				end)
			end
		end
	else
		makeLabel(customizePanel, "No theme list found in BrainrotData yet.", 13, Color3.fromRGB(180, 180, 180), order)
		order += 1
	end

	local decos: any = data.DECORATIONS
	if type(decos) == "table" then
		makeLabel(customizePanel, "Decorations:", 15, Color3.fromRGB(220, 180, 255), order)
		order += 1
		for decoId, deco in pairs(decos) do
			local id = tostring(decoId)
			local decoName = if type(deco) == "table" and deco.Name then tostring(deco.Name) else id
			local cost = if type(deco) == "table" and deco.Cost then tonumber(deco.Cost) else nil
			local row = makeRow(customizePanel, order, 44)
			order += 1
			makeLabel(row, decoName .. (if cost then ("  (" .. tostring(cost) .. " coins)") else ""), 14, Color3.new(1, 1, 1), 1).Position = UDim2.new(0, 8, 0, 10)
			local buy = Instance.new("TextButton")
			buy.Size = UDim2.new(0, 90, 0, 30)
			buy.Position = UDim2.new(1, -98, 0.5, -15)
			buy.Text = "Buy"
			buy.BackgroundColor3 = Color3.fromRGB(60, 100, 160)
			buy.TextColor3 = Color3.new(1, 1, 1)
			buy.Font = Enum.Font.GothamBold
			buy.TextSize = 13
			buy.Parent = row
			corner(buy, 6)
			buy.MouseButton1Click:Connect(function()
				buyDecorationRemote:FireServer(id)
			end)
		end
	end
end

do
	local STAT_DEFS = {
		Speed = { Name = "🏃 Speed", MaxTier = 5, Costs = { 2000, 6000, 16000, 40000, 100000 }, Desc = "+4 movement speed per tier" },
		Jump = { Name = "🦘 Jump", MaxTier = 5, Costs = { 2000, 6000, 16000, 40000, 100000 }, Desc = "+10 jump power per tier" },
		Reach = { Name = "🧲 Catcher's Reach", MaxTier = 3, Costs = { 4000, 12000, 32000 }, Desc = "Much bigger catch radius for wild brainrots" },
		Luck = { Name = "🍀 Lucky Charm", MaxTier = 3, Costs = { 8000, 24000, 60000 }, Desc = "Much better odds for Rare+ wild spawns" },
	}

	refreshStatsPanel = function()
		local savedScroll = statsPanel.CanvasPosition
		task.defer(function()
			statsPanel.CanvasPosition = savedScroll
		end)
		for _, c in ipairs(statsPanel:GetChildren()) do
			if c:IsA("GuiObject") and (c :: GuiObject).LayoutOrder > 0 then
				c:Destroy()
			end
		end
		local order = 1
		makeLabel(statsPanel, "Trainer shop  —  coins: " .. tostring(currentCoins) .. "  —  walk here to buy boosts", 15, Color3.fromRGB(255, 200, 100), order)
		order += 1

		for _, statKey in ipairs({ "Speed", "Jump", "Reach", "Luck" }) do
			local def = STAT_DEFS[statKey]
			local tier = (upgradeTiers :: any)[statKey] or 0
			local isMax = tier >= def.MaxTier

			local row = makeRow(statsPanel, order, 80)
			order += 1

			local pipStr = ""
			for i = 1, def.MaxTier do
				pipStr ..= if i <= tier then "●" else "○"
			end

			local info = makeLabel(row, def.Name .. "\n" .. def.Desc .. "\n" .. pipStr .. "  Tier " .. tostring(tier) .. "/" .. tostring(def.MaxTier), 13, Color3.new(1,1,1), 1)
			info.Size = UDim2.new(0.65, 0, 1, 0)

			if not isMax then
				local cost = def.Costs[tier + 1]
				local buyBtn = Instance.new("TextButton")
				buyBtn.Size = UDim2.new(0.32, 0, 0, 44)
				buyBtn.Position = UDim2.new(0.66, 0, 0.5, -22)
				buyBtn.BackgroundColor3 = if currentCoins >= cost then Color3.fromRGB(50, 150, 60) else Color3.fromRGB(95, 60, 60)
				buyBtn.Text = "Buy\n" .. tostring(cost) .. " coins"
				buyBtn.Font = Enum.Font.GothamBold
				buyBtn.TextSize = 13
				buyBtn.TextColor3 = Color3.new(1, 1, 1)
				buyBtn.Parent = row
				corner(buyBtn, 8)
				buyBtn.MouseButton1Click:Connect(function()
					remotes:WaitForChild("BuyUpgrade"):FireServer(statKey)
					task.wait(0.3)
					refreshStatsPanel()
				end)
			else
				local maxLbl = makeLabel(row, "MAX", 14, Color3.fromRGB(255, 200, 100), 1)
				maxLbl.Size = UDim2.new(0.32, 0, 1, 0)
				maxLbl.Position = UDim2.new(0.66, 0, 0, 0)
			end
		end
	end
end

do
	local openStatsRemote = remotes:WaitForChild("OpenStats", 5)
	if openStatsRemote then
		local openStatsEvent = openStatsRemote :: RemoteEvent
		openStatsEvent.OnClientEvent:Connect(function()
			hideAllPanels()
			refreshStatsPanel()
			statsPanel.Visible = true
		end)
	end
end

expeditionUpdateRemote.OnClientEvent:Connect(function(payload: any)
	expeditionData = payload
	if payload and type(payload.SelectZone) == "string" then
		selectedZone = payload.SelectZone
	end
	if payload and payload.OpenPanel then
		hideAllPanels()
		refreshExpeditionPanel()
		expeditionPanel.Visible = true
	elseif expeditionPanel.Visible then
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
	if payload.BrainrotRate ~= nil then
		passiveBrainrotRate = payload.BrainrotRate
	end
	if minePanel.Visible then
		refreshMinePanel()
	end
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

do
	-- // One red close button that sits in the corner of whichever panel is open ---------------
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "ClosePanel"
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 20
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.ZIndex = 100
	closeBtn.Visible = false
	closeBtn.Parent = gui
	corner(closeBtn, 10)
	closeBtn.MouseButton1Click:Connect(function()
		hideAllPanels()
	end)

	local closablePanels: { GuiObject } = {
		collectionPanel, editorPanel, workPanel, fusionPanel, expeditionPanel, dailyPanel,
		eggPanel, minePanel, customizePanel, statsPanel, leaderboardPanel, fishingPanel,
	}
	RunService.RenderStepped:Connect(function()
		local openPanel: GuiObject? = nil
		for _, panel in ipairs(closablePanels) do
			if panel.Visible then
				openPanel = panel
				break
			end
		end
		if openPanel then
			local origin = gui.AbsolutePosition
			local abs = openPanel.AbsolutePosition
			local size = openPanel.AbsoluteSize
			closeBtn.Position = UDim2.fromOffset(abs.X - origin.X + size.X - 48, abs.Y - origin.Y + 8)
			closeBtn.Visible = true
		else
			closeBtn.Visible = false
		end
	end)
end

local function buildMobileBar()
	for _, btn in ipairs({ collectionBtn, workBtn, fusionBtn, arenaBtn, showcaseBtn,
		exploreBtn, dailyBtn, eggBtn, mineBtn, styleBtn, statsBtn }) do
		btn.Visible = false
	end

	local mobileBar = Instance.new("ScrollingFrame")
	mobileBar.Name = "MobileBar"
	mobileBar.Size = UDim2.new(1, 0, 0, 72)
	mobileBar.Position = UDim2.new(0, 0, 1, -72)
	mobileBar.BackgroundColor3 = THEME.Background
	mobileBar.BackgroundTransparency = 0.1
	mobileBar.BorderSizePixel = 0
	mobileBar.ScrollBarThickness = 0
	mobileBar.ScrollingDirection = Enum.ScrollingDirection.X
	mobileBar.CanvasSize = UDim2.new(0, 0, 0, 0)
	mobileBar.AutomaticCanvasSize = Enum.AutomaticSize.X
	mobileBar.Parent = gui
	corner(mobileBar, 0)

	local mobileLayout = Instance.new("UIListLayout")
	mobileLayout.FillDirection = Enum.FillDirection.Horizontal
	mobileLayout.Padding = UDim.new(0, 8)
	mobileLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	mobileLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	mobileLayout.Parent = mobileBar
	local mobilePad = Instance.new("UIPadding")
	mobilePad.PaddingLeft = UDim.new(0, 8)
	mobilePad.PaddingRight = UDim.new(0, 8)
	mobilePad.Parent = mobileBar

	local function toggleMobilePanel(panel: GuiObject, refreshFn: (() -> ())?)
		local was = panel.Visible
		hideAllPanels()
		if not was then
			if refreshFn then refreshFn() end
			panel.Visible = true
		end
	end

	local mobileButtons: { any } = {
		{ Icon = "🧠", Label = "Pets", Panel = collectionPanel, Refresh = refreshCollectionPanel },
		{ Icon = "⚒️", Label = "Work", Panel = workPanel, Refresh = refreshWorkPanel },
		{ Icon = "⚗️", Label = "Fuse", Panel = fusionPanel, Refresh = refreshFusionPanel },
		{ Icon = "⭐", Label = "Show", Panel = editorPanel, Refresh = refreshEditorPanel },
		{ Icon = "📅", Label = "Daily", Panel = dailyPanel, Refresh = refreshDailyPanel },
		{ Icon = "🥚", Label = "Eggs", Panel = eggPanel, Refresh = refreshEggPanel },
		{ Icon = "⛏️", Label = "Mine", Panel = minePanel, Refresh = refreshMinePanel },
		{ Icon = "🎨", Label = "Style", Panel = customizePanel, Refresh = refreshCustomizePanel },
	}
	for _, item in ipairs(mobileButtons) do
		local mBtn = Instance.new("TextButton")
		mBtn.Size = UDim2.new(0, 64, 0, 56)
		mBtn.BackgroundColor3 = THEME.Card
		mBtn.Text = item.Icon .. "\n" .. item.Label
		mBtn.Font = Enum.Font.GothamBold
		mBtn.TextSize = 11
		mBtn.TextColor3 = THEME.Text
		mBtn.Parent = mobileBar
		corner(mBtn, 12)
		styleFrame(mBtn, false)
		if item.Request then
			local request = item.Request
			mBtn.MouseButton1Click:Connect(function()
				request()
			end)
		else
			local panel = item.Panel
			local refreshFn = item.Refresh
			mBtn.MouseButton1Click:Connect(function()
				toggleMobilePanel(panel, refreshFn)
			end)
		end
	end
end

if isMobile then
	buildMobileBar()
end

-- Nested function: ClientUI's main chunk is already at Luau's 200-local cap.
task.defer(function()
	local soundRemote = remotes:WaitForChild("PlaySound")
	soundRemote.OnClientEvent:Connect(function(soundName: string, position: Vector3?)
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://3926305904"
		sound.Volume = 0.5
		if position then
			local part = Instance.new("Part")
			part.Anchored = true
			part.CanCollide = false
			part.Transparency = 1
			part.Position = position
			part.Parent = workspace
			sound.Parent = part
			sound:Play()
			task.delay(3, function()
				if part and part.Parent then part:Destroy() end
			end)
		else
			sound.Parent = gui
			sound:Play()
			task.delay(2, function()
				if sound and sound.Parent then sound:Destroy() end
			end)
		end
	end)

	local tracks = {
		Normal = {
			"rbxassetid://1848354536",
			"rbxassetid://1837879082",
			"rbxassetid://1837464237",
			"rbxassetid://1837425213",
			"rbxassetid://1837849285",
		},
		Event = {
			"rbxassetid://1837768517",
			"rbxassetid://1841647093",
			"rbxassetid://1838457437",
		},
	}
	local playlist = tracks.Normal
	local currentTrack = 1
	local musicSound = Instance.new("Sound")
	musicSound.Name = "BackgroundMusic"
	musicSound.SoundId = playlist[1]
	musicSound.Volume = 0.28
	musicSound.Looped = false
	musicSound.Parent = gui

	local function playNextTrack()
		if #playlist == 0 then
			return
		end
		currentTrack = currentTrack % #playlist + 1
		musicSound.SoundId = playlist[currentTrack]
		musicSound.Volume = if playlist == tracks.Event then 0.42 else 0.28
		pcall(function()
			musicSound:Play()
		end)
	end

	local function setPlaylist(nextTracks: { string }, startNow: boolean)
		playlist = nextTracks
		currentTrack = 0
		if startNow then
			playNextTrack()
		end
	end

	musicSound.Ended:Connect(playNextTrack)
	task.spawn(function()
		task.wait(2)
		playNextTrack()
		while true do
			task.wait(2)
			if not musicSound.IsPlaying then
				playNextTrack()
			end
		end
	end)

	task.spawn(function()
		local musicRemote = remotes:WaitForChild("MusicUpdate", 20)
		if musicRemote then
			musicRemote.OnClientEvent:Connect(function(mode: any)
				if tostring(mode) == "Event" then
					setPlaylist(tracks.Event, true)
				else
					setPlaylist(tracks.Normal, true)
				end
			end)
		end
	end)

	task.spawn(function()
		local worldEvent = remotes:WaitForChild("WorldEvent", 20)
		if not worldEvent then
			return
		end
		local banner = Instance.new("TextLabel")
		banner.Name = "WorldEventBanner"
		banner.Size = UDim2.new(0, 520, 0, 48)
		banner.Position = UDim2.new(0.5, -260, 0, 108)
		banner.BackgroundColor3 = Color3.fromRGB(80, 20, 40)
		banner.BackgroundTransparency = 0.15
		banner.Visible = false
		banner.Font = Enum.Font.GothamBlack
		banner.TextSize = 20
		banner.TextColor3 = Color3.fromRGB(255, 210, 90)
		banner.Text = "LEGENDARY RUSH"
		banner.Parent = gui
		corner(banner, 12)
		worldEvent.OnClientEvent:Connect(function(info: any)
			if type(info) ~= "table" then
				return
			end
			if info.Active then
				banner.Visible = true
				banner.Text = "⚡ LEGENDARY RUSH — legendaries and epics nearby"
				setPlaylist(tracks.Event, true)
			else
				banner.Visible = false
				setPlaylist(tracks.Normal, true)
			end
		end)
	end)

	local weatherRemote = remotes:WaitForChild("WeatherUpdate")
	local weatherLabel = Instance.new("TextLabel")
	weatherLabel.Name = "WeatherDisplay"
	weatherLabel.Size = if isMobile then UDim2.new(0, 120, 0, 36) else UDim2.new(0, 180, 0, 40)
	weatherLabel.Position = if isMobile then UDim2.new(1, -128, 0, 56) else UDim2.new(0.5, -90, 0, 62)
	weatherLabel.BackgroundColor3 = THEME.Panel
	weatherLabel.BackgroundTransparency = 0.15
	weatherLabel.Text = "☀️ Clear"
	weatherLabel.Font = Enum.Font.GothamBold
	weatherLabel.TextSize = 14
	weatherLabel.TextColor3 = THEME.Text
	weatherLabel.Parent = gui
	corner(weatherLabel, 10)
	styleFrame(weatherLabel, false)

	weatherRemote.OnClientEvent:Connect(function(info: any)
		local weather = tostring(info.Current or info.CurrentWeather or info.Weather or "Clear")
		local icon = if weather == "Rain" then "🌧️"
			elseif weather == "Storm" then "⛈️"
			elseif weather == "Fog" then "🌫️"
			else "☀️"
		weatherLabel.Text = icon .. " " .. weather
	end)

	local achRemote = remotes:WaitForChild("AchievementUnlocked")
	achRemote.OnClientEvent:Connect(function(data: any)
		local popup = Instance.new("Frame")
		popup.Size = UDim2.new(0, 320, 0, 80)
		popup.Position = UDim2.new(0.5, -160, 0, -90)
		popup.BackgroundColor3 = Color3.fromRGB(40, 35, 20)
		popup.BorderSizePixel = 0
		popup.Parent = gui
		corner(popup, 12)
		styleFrame(popup, true)

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -20, 0, 30)
		title.Position = UDim2.new(0, 10, 0, 8)
		title.BackgroundTransparency = 1
		title.Text = "🏆 " .. (data.Name or "Achievement!")
		title.Font = Enum.Font.GothamBold
		title.TextSize = 16
		title.TextColor3 = Color3.fromRGB(255, 210, 100)
		title.Parent = popup

		local desc = Instance.new("TextLabel")
		desc.Size = UDim2.new(1, -20, 0, 30)
		desc.Position = UDim2.new(0, 10, 0, 40)
		desc.BackgroundTransparency = 1
		desc.Text = data.Desc or ""
		desc.Font = Enum.Font.Gotham
		desc.TextSize = 13
		desc.TextColor3 = THEME.Text
		desc.TextWrapped = true
		desc.Parent = popup

		popup:TweenPosition(UDim2.new(0.5, -160, 0, 20), Enum.EasingDirection.Out, Enum.EasingStyle.Back, 0.5, true)
		task.wait(3)
		popup:TweenPosition(UDim2.new(0.5, -160, 0, -90), Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.5, true)
		task.wait(0.6)
		if popup and popup.Parent then popup:Destroy() end
	end)

	local lbRemote = remotes:WaitForChild("LeaderboardUpdate")

	local function refreshLeaderboard(data: any)
		for _, c in ipairs(leaderboardPanel:GetChildren()) do
			if c:IsA("GuiObject") and (c :: GuiObject).LayoutOrder > 0 then
				c:Destroy()
			end
		end
		local order = 1

		if data.MyWins then
			makeLabel(leaderboardPanel, "Your wins: " .. tostring(data.MyWins), 15, Color3.fromRGB(255, 210, 100), order)
			order += 1
		end

		makeLabel(leaderboardPanel, "Top Battlers:", 15, THEME.Text, order)
		order += 1

		local top = data.Top or {}
		if #top == 0 then
			makeLabel(leaderboardPanel, "No battles recorded yet. Be the first!", 14, THEME.TextDim, order)
		else
			for i, entry in ipairs(top) do
				local medal = if i == 1 then "🥇" elseif i == 2 then "🥈" elseif i == 3 then "🥉" else tostring(i) .. "."
				local row = makeRow(leaderboardPanel, order, 40)
				order += 1
				makeLabel(row, medal .. " " .. (entry.Name or "?") .. " - " .. tostring(entry.Wins) .. " wins", 14, THEME.Text, 1)
			end
		end
	end

	lbRemote.OnClientEvent:Connect(function(data: any)
		refreshLeaderboard(data)
	end)

	-- Ranks UI removed: the champion board lives at the arena.
end)

