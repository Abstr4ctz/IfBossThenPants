-- ==========================================================================
-- Addon: IfBossThenPants
-- Version: 1.2
-- Description: Automates gear switching based on Mob Death or Target Change.
--              Supports Standard Clients (Names) & SuperWoW (GUIDs).
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
local getn     = table.getn

-- WoW API
local UnitName            = UnitName
local UnitExists          = UnitExists
local UnitIsDeadOrGhost   = UnitIsDeadOrGhost
local UnitAffectingCombat = UnitAffectingCombat
local GetInventoryItemLink = GetInventoryItemLink
local GetContainerNumSlots = GetContainerNumSlots
local GetContainerItemLink = GetContainerItemLink
local PickupInventoryItem  = PickupInventoryItem
local EquipCursorItem      = EquipCursorItem
local PickupContainerItem  = PickupContainerItem
local UseContainerItem     = UseContainerItem

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
    
    -- Integrity checks
    if not IfBossThenPantsDB.onMobDeath then IfBossThenPantsDB.onMobDeath = {} end
    if not IfBossThenPantsDB.onTarget then IfBossThenPantsDB.onTarget = {} end
    if IfBossThenPantsDB.enabled == nil then IfBossThenPantsDB.enabled = true end
end

function IfBossThenPants:AddEntry(category, key, displayLabel, item, slotName, allowCombat)
    local dbTable = (category == "death") and IfBossThenPantsDB.onMobDeath or IfBossThenPantsDB.onTarget
    local label   = (category == "death") and "On Death" or "On Target"
    local dbKey   = strlower(key)
    
    -- Resolve Slot ID
    local slotID = nil
    if slotName then
        local numericSlot = tonumber(slotName)
        if numericSlot then
            slotID = numericSlot
        else
            slotID = self.slotMap[strlower(slotName)]
        end
    end

    -- Validation for Combat Swapping
    if allowCombat then
        if not slotID then
            self:Print("Error: You must specify a Slot ID (16, 17, or 18) to use the '- combat' option.")
            return
        end
        if slotID ~= 16 and slotID ~= 17 and slotID ~= 18 then
            self:Print("Error: Combat swapping is ONLY available for slots 16 (MainHand), 17 (OffHand), and 18 (Ranged).")
            return
        end
    end

    if not slotID and slotName then
        self:Print("Error: Invalid slot '" .. slotName .. "'.")
        return
    end

    if not dbTable[dbKey] then dbTable[dbKey] = {} end

    -- 1. Check for Exact Duplicates (Name + Slot)
    local itemLower = strlower(item)
    for _, v in ipairs(dbTable[dbKey]) do
        if strlower(v.name) == itemLower and v.slot == slotID then
            self:Print(label .. ": Item [" .. item .. "] already listed for [" .. displayLabel .. "]")
            return
        end
    end

    -- 2. Overwrite Check: If slot is specified, remove old item for that slot
    if slotID then
        for i, v in ipairs(dbTable[dbKey]) do
            if v.slot == slotID then
                tremove(dbTable[dbKey], i)
                break
            end
        end
    end

    -- 3. Store Entry
    tinsert(dbTable[dbKey], { name = item, slot = slotID, combat = allowCombat })
    
    local slotMsg = slotID and (" (Slot: " .. slotID .. ")") or " (Auto Slot)"
    local combatMsg = allowCombat and " |cffff0000[Combat Swap]|r" or ""
    self:Print(label .. ": Added [" .. item .. "]" .. slotMsg .. combatMsg .. " to [" .. displayLabel .. "]")
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
        self:Print(label .. ": Item [" .. item .. "] not found.")
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
                if entry.slot then s = s .. "(" .. entry.slot .. ")" end
                if entry.combat then s = s .. "|cffff0000(C)|r" end
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

-- itemObj format: { name="Sulfuras", slot=16, combat=true/false }
function IfBossThenPants:ScanAndEquip(itemObj)
    -- Safety Check: Do not attempt to swap gear if dead
    if UnitIsDeadOrGhost("player") then return false end

    local targetLower = strlower(itemObj.name)
    
    -- ============================================================
    -- PHASE 1: CHECK EQUIPPED GEAR (Priority)
    -- ============================================================
    for invSlot = 0, 19 do
        local link = GetInventoryItemLink("player", invSlot)
        if link then
            local _, _, itemName = strfind(link, "%[(.+)%]")
            if itemName and strlower(itemName) == targetLower then
                
                -- CASE A: It is currently in the requested slot
                if itemObj.slot and invSlot == itemObj.slot then
                    return true -- SUCCESS: Already done, do nothing.
                end

                -- CASE B: No specific slot requested, and it's equipped
                if not itemObj.slot then
                    return true -- SUCCESS: Already equipped, do nothing.
                end

                -- CASE C: It is equipped, but in the wrong slot -> Swap it
                PickupInventoryItem(invSlot)
                EquipCursorItem(itemObj.slot)
                self:Print("Moving " .. itemName .. " from slot " .. invSlot .. " to " .. itemObj.slot)
                return true
            end
        end
    end

    -- ============================================================
    -- PHASE 2: CHECK BAGS (Fallback)
    -- ============================================================
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
    if self.inCombat then
        -- Check if this specific item allows combat swapping (Weapons/Ranged only)
        if itemObj.combat and itemObj.slot and (itemObj.slot == 16 or itemObj.slot == 17 or itemObj.slot == 18) then
            -- Attempt immediate swap
            self:ScanAndEquip(itemObj)
        else
            -- Standard Queue logic: Avoid duplicate queueing
            for _, queued in ipairs(self.itemQueue) do
                if queued.name == itemObj.name and queued.slot == itemObj.slot then return end
            end
            tinsert(self.itemQueue, itemObj)
        end
    else
        self:ScanAndEquip(itemObj)
    end
end

function IfBossThenPants:ProcessQueue()
    if getn(self.itemQueue) == 0 then return end
    
    -- Safety: If player died during combat, do not process queue
    if UnitIsDeadOrGhost("player") then 
        self.itemQueue = {}
        return 
    end
    
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
        self:Print("Status: " .. (IfBossThenPantsDB.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        self:Print("Commands:")
        self:Print("  /ibtp toggle - Enable/Disable addon")
        self:Print("  /ibtp list")
        self:Print("  /ibtp adddeath Identifier - Item - [Slot] - [combat]")
        self:Print("  /ibtp remdeath Identifier - Item")
        self:Print("  /ibtp addtarget Identifier - Item - [Slot] - [combat]")
        self:Print("  /ibtp remtarget Identifier - Item")
        self:Print("  * Identifier can be a Name, a GUID, or 'target'")
        self:Print("  * Add '- combat' at the end to force swap in combat (Slots 16/17/18 only)")
        return
    end

    cmd  = strlower(cmd)
    
    if cmd == "toggle" then
        IfBossThenPantsDB.enabled = not IfBossThenPantsDB.enabled
        if IfBossThenPantsDB.enabled then
            self:Print("Addon is now |cff00ff00ENABLED|r.")
        else
            self:Print("Addon is now |cffff0000DISABLED|r. Events will not be scanned.")
        end
        return
    end

    rest = self:Trim(rest)

    if cmd == "list" then
        self:ListEntries()
        return
    end
    
    if cmd == "adddeath" or cmd == "remdeath" or cmd == "addtarget" or cmd == "remtarget" then
        
        -- Split arguments by hyphen
        local args = self:SplitString(rest, "-")
        for i=1, getn(args) do args[i] = self:Trim(args[i]) end

        if getn(args) < 2 then
             self:Print("Usage: /ibtp " .. cmd .. " Identifier - Item - [Slot] - [combat]")
             return
        end

        local identifier = args[1]
        local item       = args[2]
        local slot       = nil
        local allowCombat = false

        -- Parse 3rd and 4th arguments dynamically
        if getn(args) >= 3 then
            local arg3 = strlower(args[3])
            
            if arg3 == "combat" then
                allowCombat = true
                -- Slot remains nil (will trigger validation error later if combat is true)
            else
                slot = args[3]
            end
        end

        if getn(args) >= 4 then
            local arg4 = strlower(args[4])
            if arg4 == "combat" then
                allowCombat = true
            end
        end

        local finalKey = identifier
        local display  = identifier

        -- Handle 'target' keyword
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
            self:AddEntry(category, finalKey, display, item, slot, allowCombat)
        else
            self:RemoveEntry(category, finalKey, item)
        end
    else
        self:Print("Unknown command: " .. cmd)
    end
end

-- ==========================================================================
-- MAIN EVENT HANDLER
-- ==========================================================================

local function EventHandler()
    -- Global Enable/Disable Check
    -- Allow ADDON_LOADED to pass so variables get initialized
    if event ~= "ADDON_LOADED" and IfBossThenPantsDB and not IfBossThenPantsDB.enabled then
        return
    end

    -- ----------------------------------------------------------------------
    -- SCENARIO: MOB DEATH
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
            -- 1. GUID Match (SuperWoW)
            if IfBossThenPants.isSuperWoW and guid then
                local list = IfBossThenPantsDB.onTarget[strlower(guid)]
                if list then
                    for _, itemObj in ipairs(list) do IfBossThenPants:QueueItem(itemObj) end
                end
            end

            -- 2. Name Match (Standard/Fallback)
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

    elseif event == "PLAYER_ENTERING_WORLD" then
        IfBossThenPants.inCombat = UnitAffectingCombat("player") and true or false
        
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
        frame:RegisterEvent("PLAYER_TARGET_CHANGED")
        
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