--!strict
--[[
	XSFUnpack — one-time installer for the XSF kit.

	Paste this as a Script into ServerScriptService of the XSF Shooter Arena
	PLACE (Edit mode is fine; then press Play once, or run via Command Bar).

	What it does:
	  Workspace.XSF_Release/ReplicatedStorage/XSF     → ReplicatedStorage.XSF
	  Workspace.XSF_Release/ServerScriptService/XSF   → ServerScriptService.XSF
	  Workspace.XSF_Release/StarterPlayerScripts/...  → StarterPlayer.StarterPlayerScripts
	  optional ServerStorage / Workspace map pieces
	  then deletes the empty XSF_Release package folder

	Safe to re-run: if things are already installed, it skips and prints OK.
	Do NOT put the XSF kit itself on GitHub — only this unpacker lives in git.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local function log(msg: string)
	print("[XSFUnpack] " .. msg)
end

local function warnLog(msg: string)
	warn("[XSFUnpack] " .. msg)
end

local function ensureFolder(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function moveChild(fromParent: Instance?, childName: string, toParent: Instance): boolean
	if not fromParent then
		return false
	end
	local child = fromParent:FindFirstChild(childName)
	if not child then
		return false
	end
	local clash = toParent:FindFirstChild(childName)
	if clash and clash ~= child then
		warnLog(toParent:GetFullName() .. "." .. childName .. " already exists — leaving packaged copy alone. Delete the old one if you want a reinstall.")
		return false
	end
	child.Parent = toParent
	log("moved " .. childName .. " → " .. toParent:GetFullName())
	return true
end

local function moveAllChildren(fromParent: Instance?, toParent: Instance): number
	if not fromParent then
		return 0
	end
	local n = 0
	for _, child in ipairs(fromParent:GetChildren()) do
		local clash = toParent:FindFirstChild(child.Name)
		if clash and clash ~= child then
			warnLog("skip " .. child.Name .. " — already in " .. toParent:GetFullName())
		else
			child.Parent = toParent
			log("moved " .. child.Name .. " → " .. toParent:GetFullName())
			n += 1
		end
	end
	return n
end

local function isEmptyDeep(inst: Instance): boolean
	return #inst:GetChildren() == 0
end

local function cleanupPackage(pkg: Instance)
	-- Remove empty service-named folders, then the package if empty.
	for _, child in ipairs(pkg:GetChildren()) do
		if child:IsA("Folder") and isEmptyDeep(child) then
			child:Destroy()
		end
	end
	-- Keep README / ABOUT so user can read; remove only if everything else is gone
	local leftovers = {}
	for _, child in ipairs(pkg:GetChildren()) do
		local n = string.lower(child.Name)
		if n ~= "_readme" and n ~= "_about_this_model" and not string.find(n, "readme", 1, true) then
			table.insert(leftovers, child.Name)
		end
	end
	if #leftovers == 0 then
		pkg:Destroy()
		log("removed empty XSF_Release package")
	else
		warnLog("XSF_Release still has: " .. table.concat(leftovers, ", ") .. " — move those manually or delete the package when done")
	end
end

local function alreadyInstalled(): boolean
	local rs = ReplicatedStorage:FindFirstChild("XSF")
	local sss = ServerScriptService:FindFirstChild("XSF")
	local sps = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	local boot = sps and sps:FindFirstChild("XSF_Boot")
	return rs ~= nil and sss ~= nil and boot ~= nil
end

local function unpack()
	if alreadyInstalled() and not workspace:FindFirstChild("XSF_Release") then
		log("already installed — ReplicatedStorage.XSF + ServerScriptService.XSF + XSF_Boot present")
		return true
	end

	local pkg = workspace:FindFirstChild("XSF_Release")
	if not pkg then
		if alreadyInstalled() then
			log("already installed (no XSF_Release package left)")
			return true
		end
		warnLog("No Workspace.XSF_Release found. Insert the XSF .rbxmx first (drag into the 3D view), then run this script again.")
		return false
	end

	log("unpacking " .. pkg:GetFullName() .. " ...")

	local sps = ensureFolder(StarterPlayer, "StarterPlayerScripts")

	-- Preferred layout from XSF docs: service-named folders inside the package.
	local moved = 0
	if moveChild(pkg:FindFirstChild("ReplicatedStorage"), "XSF", ReplicatedStorage) then
		moved += 1
	end
	if moveChild(pkg:FindFirstChild("ServerScriptService"), "XSF", ServerScriptService) then
		moved += 1
	end
	moved += moveAllChildren(pkg:FindFirstChild("StarterPlayerScripts"), sps)
	moved += moveAllChildren(pkg:FindFirstChild("ServerStorage"), ServerStorage)

	-- Optional test map / workspace pieces — only if not already present
	local wsFolder = pkg:FindFirstChild("Workspace")
	if wsFolder then
		for _, child in ipairs(wsFolder:GetChildren()) do
			if workspace:FindFirstChild(child.Name) then
				warnLog("skip Workspace." .. child.Name .. " — already exists")
			else
				child.Parent = workspace
				log("moved " .. child.Name .. " → Workspace")
				moved += 1
			end
		end
	end

	-- Fallback: kit dumped flat (XSF / XSF_Boot sitting directly under XSF_Release)
	if moveChild(pkg, "XSF", ReplicatedStorage) then
		moved += 1
	end
	-- If a second XSF was meant for SSS and is named differently, docs use two XSF folders
	-- inside service folders — flat kits rarely have two. Try Server XSF already handled.

	if pkg:FindFirstChild("XSF_Boot") then
		moveChild(pkg, "XSF_Boot", sps)
		moved += 1
	end

	cleanupPackage(pkg)

	if alreadyInstalled() then
		log("SUCCESS — XSF is installed. Press Play. Guns come from GameConfig.Loadout (default HK416).")
		log("Keep XSFReturn + XSFArenaBoot in ServerScriptService for Arena return + loadout.")
		return true
	end

	warnLog("Unpack finished but install still incomplete. Check Explorer:")
	warnLog("  need ReplicatedStorage.XSF")
	warnLog("  need ServerScriptService.XSF")
	warnLog("  need StarterPlayer.StarterPlayerScripts.XSF_Boot")
	warnLog("Moved count: " .. tostring(moved))
	return false
end

unpack()
-- Stay enabled: Play sessions revert Workspace moves, so Unpack must run every start.
