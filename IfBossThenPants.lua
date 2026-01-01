-- ==========================================================================
-- Addon: IfBossThenPants
-- Version: 1.3.4
-- Description: Automates gear switching based on Mob Death or Target Change.
--              Supports Standard Clients (Names) & SuperWoW (GUIDs).
--              Supports Individual Items and External Gear Sets (Outfitter/ItemRack).
--              Handles Combat Queueing and Post-Resurrection Swapping.
-- ==========================================================================

-- Namespace Definition
IfBossThenPants = {}
local frame = CreateFrame("Frame")

-- ==========================================================================
-- LOCALIZATIONS & OPTIMIZATIONS
-- Localizing global functions prevents hash table lookups every frame.
-- ==========================================================================
local _G = getfenv(0)

-- String & Table
local strlower = string.lower
local strfind  = string.find
local strsub   = string.sub
local gsub     = string.gsub
local tinsert  = table.insert
local tremove  = table.remove
local tsort    = table.sort
local getn     = table.getn

-- WoW API
local UnitName             = UnitName
local UnitExists           = UnitExists
local UnitIsDeadOrGhost    = UnitIsDeadOrGhost
local UnitAffectingCombat  = UnitAffectingCombat
local GetInventoryItemLink = GetInventoryItemLink
local GetContainerNumSlots = GetContainerNumSlots
local GetContainerItemLink = GetContainerItemLink
local PickupInventoryItem  = PickupInventoryItem
local EquipCursorItem      = EquipCursorItem
local PickupContainerItem  = PickupContainerItem
local UseContainerItem     = UseContainerItem
local IsAddOnLoaded        = IsAddOnLoaded

-- ==========================================================================
-- CONSTANTS & STATE
-- ==========================================================================
local EVT_DEATH  = "CHAT_MSG_COMBAT_HOSTILE_DEATH"
local EVT_TARGET = "PLAYER_TARGET_CHANGED"
local EVT_RAW    = "RAW_COMBATLOG"

IfBossThenPants.itemQueue  = {}
IfBossThenPants.inCombat   = false
IfBossThenPants.isSuperWoW = (SUPERWOW_VERSION ~= nil)

-- Inventory Slot Mapping (Alias -> ID)
IfBossThenPants.slotMap = {
    ["head"] = 1,      ["neck"] = 2,      ["shoulder"] = 3,  ["shirt"] = 4,
    ["chest"] = 5,     ["waist"] = 6,     ["legs"] = 7,      ["feet"] = 8,
    ["wrist"] = 9,     ["hands"] = 10,
    ["finger1"] = 11,  ["ring1"] = 11,    ["finger2"] = 12,  ["ring2"] = 12,
    ["trinket1"] = 13, ["trinket2"] = 14,
    ["back"] = 15,     ["cloak"] = 15,
    ["mainhand"] = 16, ["mh"] = 16,
    ["offhand"] = 17,  ["oh"] = 17,       ["shield"] = 17,
    ["ranged"] = 18,   ["tabard"] = 19
}

-- ==========================================================================
-- HELPER FUNCTIONS
-- ==========================================================================

function IfBossThenPants:Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[IfBoss]|r " .. msg)
    end
end

function IfBossThenPants:Trim(s)
    if not s then return nil end
    return gsub(s, "^%s*(.-)%s*$", "%1")
end

function IfBossThenPants:SplitString(str, delim)
    local res = {}
    local start = 1
    local delim_from, delim_to = strfind(str, delim, start)
    while delim_from do
        tinsert(res, strsub(str, start, delim_from - 1))
        start = delim_to + 1
        delim_from, delim_to = strfind(str, delim, start)
    end
    tinsert(res, strsub(str, start))
    return res
end

-- ==========================================================================
-- EXTERNAL ADDON INTEGRATION HANDLERS
-- ==========================================================================

local IntegrationHandlers = {
    ["itemrack"] = function(setName)
        -- Method 1: Direct API
        if type(ItemRack_EquipSet) == "function" then
            ItemRack_EquipSet(setName)
            return true
        end
        -- Method 2: Slash Command Fallback
        if SlashCmdList["ITEMRACK"] then
            SlashCmdList["ITEMRACK"]("equip " .. setName)
            return true
        end
        return false
    end,

    ["outfitter"] = function(setName)
        -- Method 1: Direct API
        if _G["Outfitter"] and _G["Outfitter"].FindOutfitByName and _G["Outfitter"].WearOutfit then
            local outfit = _G["Outfitter"]:FindOutfitByName(setName)
            if outfit then
                _G["Outfitter"]:WearOutfit(outfit)
                return true
            end
        end
        -- Method 2: Slash Command Fallback
        if SlashCmdList["OUTFITTER"] then
            SlashCmdList["OUTFITTER"]("wear " .. setName)
            return true
        end
        return false
    end
}

-- ==========================================================================
-- DATABASE MANAGEMENT
-- ==========================================================================

function IfBossThenPants:InitializeDB()
    if not IfBossThenPantsDB then
        IfBossThenPantsDB = {
            onMobDeath = {}, -- Key: Name or GUID
            onTarget   = {}, -- Key: Name or GUID
            enabled    = true
        }
    end
    
    if not IfBossThenPantsDB.onMobDeath then IfBossThenPantsDB.onMobDeath = {} end
    if not IfBossThenPantsDB.onTarget then IfBossThenPantsDB.onTarget = {} end
    if IfBossThenPantsDB.enabled == nil then IfBossThenPantsDB.enabled = true end
end

-- objType: "item" or "set"
-- addonName: "itemrack" or "outfitter" (only if objType is set)
function IfBossThenPants:AddEntry(category, key, displayLabel, item, slotName, allowCombat, objType, addonName)
    local dbTable = (category == "death") and IfBossThenPantsDB.onMobDeath or IfBossThenPantsDB.onTarget
    local label   = (category == "death") and "On Death" or "On Target"
    local dbKey   = strlower(key)
    local slotID  = nil
    
    -- 1. Validate Inputs
    if objType == "item" then
        if slotName then
            local numericSlot = tonumber(slotName)
            if numericSlot then
                slotID = numericSlot
            else
                slotID = self.slotMap[strlower(slotName)]
            end
        end

        -- Validation for Combat Swapping (Items only)
        if allowCombat then
            if not slotID then
                self:Print("Error: You must specify a Slot ID (16, 17, or 18) to use the '- combat' option.")
                return
            end
            if slotID ~= 16 and slotID ~= 17 and slotID ~= 18 then
                self:Print("Error: Combat swapping is ONLY available for slots 16, 17, and 18.")
                return
            end
        end

        if not slotID and slotName then
            self:Print("Error: Invalid slot '" .. slotName .. "'.")
            return
        end
    elseif objType == "set" then
        if allowCombat then
            self:Print("Error: External Gear Sets cannot be swapped in combat.")
            return
        end
        slotID = nil
    end

    if not dbTable[dbKey] then dbTable[dbKey] = {} end

    -- 2. Duplicate & Conflict Check
    local itemLower = strlower(item)
    local mixedTypesDetected = false

    for i, v in ipairs(dbTable[dbKey]) do
        local entryType = v.type or "item" -- Backward compatibility
        
        if entryType == objType and strlower(v.name) == itemLower and v.slot == slotID then
            self:Print(label .. ": [" .. item .. "] already listed for [" .. displayLabel .. "]")
            return
        end

        if entryType ~= objType then
            mixedTypesDetected = true
        end

        -- Overwrite Check (Only for Items sharing a slot)
        if objType == "item" and entryType == "item" and slotID and v.slot == slotID then
            tremove(dbTable[dbKey], i)
            break
        end
    end

    -- 3. Store Entry
    tinsert(dbTable[dbKey], { 
        name   = item, 
        slot   = slotID, 
        combat = allowCombat,
        type   = objType,
        addon  = addonName
    })
    
    -- 4. Feedback
    local extraInfo = ""
    if objType == "item" then
        extraInfo = slotID and (" (Slot: " .. slotID .. ")") or " (Auto Slot)"
        if allowCombat then extraInfo = extraInfo .. " |cffff0000[Combat]|r" end
    else
        extraInfo = " |cffFFFF00[Set: " .. addonName .. "]|r"
    end

    self:Print(label .. ": Added [" .. item .. "]" .. extraInfo .. " to [" .. displayLabel .. "]")

    if mixedTypesDetected then
        self:Print("|cffff0000Warning:|r You are mixing a Gear Set with individual items for this target.")
        self:Print("The Set will be equipped first, followed by items.")
    end
end

function IfBossThenPants:RemoveEntry(category, key, item)
    local dbTable = (category == "death") and IfBossThenPantsDB.onMobDeath or IfBossThenPantsDB.onTarget
    local label   = (category == "death") and "On Death" or "On Target"
    local dbKey   = strlower(key)

    if not dbTable[dbKey] then
        self:Print(label .. ": Entry [" .. key .. "] not found.")
        return
    end

    local itemLower = strlower(item)
    local removed   = false

    -- Reverse loop for safe removal
    for i = getn(dbTable[dbKey]), 1, -1 do
        if strlower(dbTable[dbKey][i].name) == itemLower then
            tremove(dbTable[dbKey], i)
            removed = true
        end
    end

    if removed then
        self:Print(label .. ": Removed [" .. item .. "]")
        if getn(dbTable[dbKey]) == 0 then dbTable[dbKey] = nil end
    else
        self:Print(label .. ": Item/Set [" .. item .. "] not found.")
    end
end

function IfBossThenPants:ListEntries()
    local status = IfBossThenPantsDB.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    self:Print("--- Configuration (Status: " .. status .. ") ---")
    
    local function PrintTable(tbl, title)
        self:Print(title)
        local found = false
        for key, items in pairs(tbl) do
            local itemStr = ""
            for _, entry in ipairs(items) do
                local s = entry.name
                local eType = entry.type or "item"
                
                if eType == "item" then
                    if entry.slot then s = s .. "(" .. entry.slot .. ")" end
                    if entry.combat then s = s .. "|cffff0000(C)|r" end
                else
                    s = s .. "|cffFFFF00(Set)|r"
                end
                
                itemStr = itemStr .. "[" .. s .. "] "
            end
            self:Print("  " .. key .. " -> " .. itemStr)
            found = true
        end
        if not found then self:Print("  (None)") end
    end

    PrintTable(IfBossThenPantsDB.onMobDeath, "Scenario 1: On Mob Death")
    PrintTable(IfBossThenPantsDB.onTarget,   "Scenario 2: On Target Change")
end

-- ==========================================================================
-- CORE LOGIC: EQUIPMENT SWAPPING
-- ==========================================================================

function IfBossThenPants:EquipSet(addon, setName)
    local handler = IntegrationHandlers[addon]
    if handler then
        if handler(setName) then
            self:Print("Equipping " .. addon .. " set: " .. setName)
            return true
        end
    end
    self:Print("Error: Failed to equip " .. addon .. " set '" .. setName .. "'.")
    return false
end

function IfBossThenPants:ScanAndEquip(itemObj)
    -- Safety: Do not attempt to physically swap if dead (Queue handles this, but this is a failsafe)
    if UnitIsDeadOrGhost("player") then return false end

    -- 1. Handle SETS
    if itemObj.type == "set" then
        return self:EquipSet(itemObj.addon, itemObj.name)
    end

    -- 2. Handle ITEMS
    local targetLower = strlower(itemObj.name)
    
    -- Phase A: Check Currently Equipped
    for invSlot = 0, 19 do
        local link = GetInventoryItemLink("player", invSlot)
        if link then
            local _, _, itemName = strfind(link, "%[(.+)%]")
            if itemName and strlower(itemName) == targetLower then
                
                -- It is in the requested slot
                if itemObj.slot and invSlot == itemObj.slot then return true end

                -- No slot requested, and it is equipped
                if not itemObj.slot then return true end

                -- It is equipped, but wrong slot -> Swap
                PickupInventoryItem(invSlot)
                EquipCursorItem(itemObj.slot)
                self:Print("Moving " .. itemName .. " from slot " .. invSlot .. " to " .. itemObj.slot)
                return true
            end
        end
    end

    -- Phase B: Check Bags
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        if slots > 0 then
            for slot = 1, slots do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local _, _, itemName = strfind(link, "%[(.+)%]")
                    if itemName and strlower(itemName) == targetLower then
                        
                        if itemObj.slot then
                            PickupContainerItem(bag, slot)
                            EquipCursorItem(itemObj.slot)
                            self:Print("Equipping " .. itemName .. " to slot " .. itemObj.slot)
                        else
                            UseContainerItem(bag, slot)
                            self:Print("Equipping " .. itemName .. " (Auto)")
                        end
                        return true
                    end
                end
            end
        end
    end

    return false
end

function IfBossThenPants:QueueItem(itemObj)
    local itemType = itemObj.type or "item"
    local isDead   = UnitIsDeadOrGhost("player")

    -- Trigger Queue if: In Combat OR Player is Dead/Ghost
    if self.inCombat or isDead then
        
        -- 1. Sets: ALWAYS queue in restricted states
        if itemType == "set" then
             -- Prevent duplicates
             for _, queued in ipairs(self.itemQueue) do
                if (queued.type == "set") and (queued.name == itemObj.name) then return end
            end
            tinsert(self.itemQueue, itemObj)
            return
        end

        -- 2. Items:
        -- If Dead: Must Queue (Cannot swap weapons while ghost)
        -- If Alive (Combat): Check for Weapon Swap capability
        if not isDead and itemObj.combat and itemObj.slot and (itemObj.slot == 16 or itemObj.slot == 17 or itemObj.slot == 18) then
            self:ScanAndEquip(itemObj)
        else
            -- Standard Queue logic
            for _, queued in ipairs(self.itemQueue) do
                if queued.name == itemObj.name and queued.slot == itemObj.slot then return end
            end
            tinsert(self.itemQueue, itemObj)
        end
    else
        -- Safe State -> Immediate Swap
        self:ScanAndEquip(itemObj)
    end
end

function IfBossThenPants:ProcessQueue()
    if getn(self.itemQueue) == 0 then return end
    
    -- If still dead/ghost, do NOT clear the queue. Return and wait for PLAYER_UNGHOST.
    if UnitIsDeadOrGhost("player") then 
        return 
    end

    -- SORTING: Sets must execute before Individual Items
    tsort(self.itemQueue, function(a, b)
        local aIsSet = (a.type == "set")
        local bIsSet = (b.type == "set")
        if aIsSet and not bIsSet then return true end
        return false
    end)
    
    for _, itemObj in ipairs(self.itemQueue) do
        self:ScanAndEquip(itemObj)
    end
    self.itemQueue = {}
end

-- ==========================================================================
-- SLASH COMMAND HANDLER
-- ==========================================================================

function IfBossThenPants:SlashHandler(msg)
    if not msg then return end
    
    local _, _, cmd, rest = strfind(msg, "^%s*(%w+)%s*(.*)$")
    
    if not cmd then
        local status = IfBossThenPantsDB.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        self:Print("--- IfBossThenPants Help ---")
        self:Print("Status: " .. status)
        self:Print("Usage: /ibtp [command] [args]")
        self:Print("  toggle : Enable/Disable event scanning.")
        self:Print("  list   : Show all active rules.")
        self:Print("  adddeath / addtarget Identifier - Content - [Slot] - [combat]")
        self:Print("  remdeath / remtarget Identifier - Content")
        self:Print("Definitions:")
        self:Print("  * Identifier : Mob Name, GUID, or 'target'.")
        self:Print("  * Content    : Item Name OR 'ItemRack(SetName)' OR 'Outfitter(SetName)'.")
        self:Print("  * combat     : Add '- combat' at the end to force immediate swap in combat.")
        self:Print("                 (Only valid for items in slots 16, 17, 18).")
        return
    end

    cmd = strlower(cmd)
    
    if cmd == "toggle" then
        IfBossThenPantsDB.enabled = not IfBossThenPantsDB.enabled
        if IfBossThenPantsDB.enabled then
            self:Print("Addon is now |cff00ff00ENABLED|r.")
        else
            self:Print("Addon is now |cffff0000DISABLED|r.")
        end
        return
    end

    rest = self:Trim(rest)

    if cmd == "list" then
        self:ListEntries()
        return
    end
    
    if cmd == "adddeath" or cmd == "remdeath" or cmd == "addtarget" or cmd == "remtarget" then
        
        -- Split arguments
        local rawArgs = self:SplitString(rest, "-")
        local args = {}
        for _, v in ipairs(rawArgs) do
            local trimmed = self:Trim(v)
            if trimmed and trimmed ~= "" then tinsert(args, trimmed) end
        end

        if getn(args) < 2 then
             self:Print("Usage: /ibtp " .. cmd .. " Identifier - Content")
             return
        end

        local identifier = args[1]
        local itemString = args[2]
        local slot       = nil
        local allowCombat = false

        -- Validation
        local itemLower = strlower(itemString)
        if itemLower == "itemrack" or itemLower == "outfitter" then
             self:Print("Error: Missing set name. Usage: " .. args[2] .. "(SetName)")
             return
        end

        -- Parse Type
        local _, _, addonName, setName = strfind(itemString, "^(%a+)%((.+)%)$")
        local objType = "item"
        local finalName = itemString

        if addonName then
            addonName = strlower(addonName)
            if addonName == "itemrack" or addonName == "outfitter" then
                local realAddonName = (addonName == "itemrack") and "ItemRack" or "Outfitter"
                if not IsAddOnLoaded(realAddonName) then
                    self:Print("Error: Addon '" .. realAddonName .. "' is not loaded.")
                    return
                end
                objType = "set"
                finalName = setName
            else
                objType = "item" 
            end
        end

        if getn(args) >= 3 then
            local arg3 = strlower(args[3])
            if arg3 == "combat" then allowCombat = true else slot = args[3] end
        end
        if getn(args) >= 4 then
            local arg4 = strlower(args[4])
            if arg4 == "combat" then allowCombat = true end
        end

        local finalKey = identifier
        local display  = identifier

        if strlower(identifier) == "target" then
            if not UnitExists("target") then
                self:Print("Error: No target selected.")
                return
            end
            if self.isSuperWoW then
                local _, guid = UnitExists("target")
                if guid then
                    finalKey = guid
                    display  = "GUID:" .. finalKey .. " (" .. UnitName("target") .. ")"
                else
                    finalKey = UnitName("target")
                    display  = finalKey .. " (Fallback)"
                end
            else
                finalKey = UnitName("target")
                display  = finalKey
            end
        end

        local category = (strfind(cmd, "death")) and "death" or "target"
        local isAdd    = (strfind(cmd, "add"))   and true    or false
        
        if isAdd then
            self:AddEntry(category, finalKey, display, finalName, slot, allowCombat, objType, addonName)
        else
            self:RemoveEntry(category, finalKey, finalName)
        end
    else
        self:Print("Unknown command: " .. cmd)
    end
end

-- ==========================================================================
-- MAIN EVENT HANDLER
-- ==========================================================================

local function EventHandler()
    if event ~= "ADDON_LOADED" and IfBossThenPantsDB and not IfBossThenPantsDB.enabled then
        return
    end

    -- ----------------------------------------------------------------------
    -- SCENARIO: MOB DEATH (SuperWoW GUID)
    -- ----------------------------------------------------------------------
    if event == EVT_RAW then
        if arg1 == EVT_DEATH then
            local _, _, guid = strfind(arg2, "(0x%x+)")
            if guid then
                local list = IfBossThenPantsDB.onMobDeath[strlower(guid)]
                if list then
                    for _, itemObj in ipairs(list) do IfBossThenPants:QueueItem(itemObj) end
                end
            end
        end
        return
    end

    -- ----------------------------------------------------------------------
    -- SCENARIO: TARGET CHANGE
    -- ----------------------------------------------------------------------
    if event == EVT_TARGET then
        local exists, guid = UnitExists("target")
        if exists then
            if IfBossThenPants.isSuperWoW and guid then
                local list = IfBossThenPantsDB.onTarget[strlower(guid)]
                if list then
                    for _, itemObj in ipairs(list) do IfBossThenPants:QueueItem(itemObj) end
                end
            end
            local targetName = UnitName("target")
            if targetName then
                local list = IfBossThenPantsDB.onTarget[strlower(targetName)]
                if list then
                    for _, itemObj in ipairs(list) do IfBossThenPants:QueueItem(itemObj) end
                end
            end
        end
        return
    end

    -- ----------------------------------------------------------------------
    -- SCENARIO: MOB DEATH (Standard Chat Fallback)
    -- ----------------------------------------------------------------------
    if event == EVT_DEATH then
        local _, _, mobName = strfind(arg1, "^(.+) dies")
        if mobName then
            local list = IfBossThenPantsDB.onMobDeath[strlower(mobName)]
            if list then
                for _, itemObj in ipairs(list) do IfBossThenPants:QueueItem(itemObj) end
            end
        end
        return
    end

    -- ----------------------------------------------------------------------
    -- SYSTEM STATE EVENTS
    -- ----------------------------------------------------------------------
    if event == "PLAYER_REGEN_ENABLED" then
        IfBossThenPants.inCombat = false
        IfBossThenPants:ProcessQueue()

    elseif event == "PLAYER_REGEN_DISABLED" then
        IfBossThenPants.inCombat = true
    
    elseif event == "PLAYER_UNGHOST" then
        IfBossThenPants:ProcessQueue()

    elseif event == "PLAYER_ENTERING_WORLD" then
        IfBossThenPants.inCombat = UnitAffectingCombat("player") and true or false
        
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
        frame:RegisterEvent("PLAYER_TARGET_CHANGED")
        frame:RegisterEvent("PLAYER_UNGHOST")
        
    elseif event == "ADDON_LOADED" and arg1 == "IfBossThenPants" then
        IfBossThenPants:InitializeDB()
        frame:UnregisterEvent("ADDON_LOADED")
        
        SLASH_IFBOSSTHENPANTS1 = "/ibtp"
        SlashCmdList["IFBOSSTHENPANTS"] = function(msg) IfBossThenPants:SlashHandler(msg) end
        
        if IfBossThenPants.isSuperWoW then
            IfBossThenPants:Print("SuperWoW detected: GUID tracking enabled.")
            frame:RegisterEvent("RAW_COMBATLOG")
        else
            IfBossThenPants:Print("Standard Client: Name tracking only.")
        end
    end
end

-- ==========================================================================
-- EVENT REGISTRATION
-- ==========================================================================
frame:SetScript("OnEvent", EventHandler)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")