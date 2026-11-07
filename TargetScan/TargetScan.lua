-- TargetScan for WoW 1.12 (Lua 5.0)
-- Saved: default raid marker and window position.
-- TOC must contain:  ## SavedVariables: TargetScanDB

local scanName = nil
local scanExact = false -- true when the name ends with *
local found = false
local trackedTarget = nil
local timer = 0
local SCAN_INTERVAL = 0.25
local editHasFocus = false
local TargetMatches
local rescan -- Rescan button, created below
local SetRescanShown -- shows/hides Rescan and adjusts the layout
local isRescan = false -- true while a rescan is pending (skips raid marker)

-- Real value is loaded on VARIABLES_LOADED (saved vars are not available yet).
local selectedRaidIcon = 5

---------------------------------------------------------------
-- Main frame
---------------------------------------------------------------

local f = CreateFrame("Frame", "TargetScanFrame", UIParent)
f:SetWidth(240)
f:SetHeight(175)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
f:SetFrameStrata("DIALOG")
f:SetMovable(true)
f:EnableMouse(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")

f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})

f:SetScript("OnDragStart", function()
    this:StartMoving()
end)

f:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()

    local point, _, relPoint, x, y = this:GetPoint()

    if type(TargetScanDB) ~= "table" then
        TargetScanDB = {}
    end

    TargetScanDB.pos = { point, relPoint, x, y }
end)

f:Hide()
tinsert(UISpecialFrames, "TargetScanFrame")

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", f, "TOP", 0, -14)
title:SetText("Target Scan")

local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

---------------------------------------------------------------
-- Name edit box
---------------------------------------------------------------

local eb = CreateFrame("EditBox", "TargetScanEditBox", f)
eb:SetWidth(190)
eb:SetHeight(24)
eb:SetPoint("TOP", f, "TOP", 0, -34)
eb:SetAutoFocus(false)
eb:SetMaxLetters(80)
eb:SetFontObject(ChatFontNormal)
eb:SetTextInsets(6, 6, 0, 0)

eb:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})

eb:SetBackdropColor(0, 0, 0, 0.8)

---------------------------------------------------------------
-- Click catcher
---------------------------------------------------------------

local catcher = CreateFrame("Button", nil, UIParent)
catcher:SetAllPoints(UIParent)
catcher:SetFrameStrata("BACKGROUND")
catcher:EnableMouse(true)
catcher:Hide()

catcher:SetScript("OnMouseDown", function()
    eb:ClearFocus()
end)

---------------------------------------------------------------
-- Status
---------------------------------------------------------------

local status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
status:SetPoint("TOP", eb, "BOTTOM", 0, -8)
status:SetText("Idle")

---------------------------------------------------------------
-- Clear button
---------------------------------------------------------------

local clear = CreateFrame("Button", "TargetScanClearButton", f, "UIPanelButtonTemplate")

clear:SetWidth(70)
clear:SetHeight(22)
clear:SetPoint("TOP", status, "BOTTOM", 0, -5)
clear:SetText("Clear")

clear:SetScript("OnClick", function()
    eb:SetText("")
    timer = 0
    found = false
    isRescan = false
    SetRescanShown(false)

    if UnitExists("target") then
        SetRaidTarget("target", 0)
        ClearTarget()
    end

    if type(TargetScanDB) ~= "table" then
        TargetScanDB = {}
    end

    TargetScanDB.raidIcon = selectedRaidIcon
end)

---------------------------------------------------------------
-- Rescan button (only visible once a target is found)
---------------------------------------------------------------

rescan = CreateFrame("Button", "TargetScanRescanButton", f, "UIPanelButtonTemplate")

rescan:SetWidth(60)
rescan:SetHeight(22)
rescan:SetPoint("TOP", clear, "BOTTOM", 0, -3)
rescan:SetText("Rescan")
rescan:Hide()

rescan:SetScript("OnClick", function()
    if not scanName then
        return
    end

    -- Drop the current target so the scan has to pick one again
    if UnitExists("target") and TargetMatches() then
        ClearTarget()
    end

    found = false
    isRescan = true
    trackedTarget = nil
    timer = SCAN_INTERVAL -- scan on the very next update

    status:SetText("|cffffff00Rescanning...|r")
    SetRescanShown(false)
end)

---------------------------------------------------------------
-- Raid target marker selector
---------------------------------------------------------------

local iconLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
iconLabel:SetPoint("TOP", clear, "BOTTOM", 0, -7)
iconLabel:SetText("Default raid marker")

local raidIconButtons = {}

local function UpdateRaidIconSelection()
    local i

    for i = 1, 8 do
        if selectedRaidIcon == i then
            raidIconButtons[i]:SetBackdropBorderColor(1, 0.82, 0, 1)
        else
            raidIconButtons[i]:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        end
    end
end

local i

for i = 1, 8 do
    local button = CreateFrame("Button", nil, f)
    raidIconButtons[i] = button

    button:SetID(i)
    button:SetWidth(24)
    button:SetHeight(24)
    button:SetPoint("TOP", f, "TOP", -87.5 + (i - 1) * 25, -137)

    button:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })

    local texture = button:CreateTexture(nil, "ARTWORK")
    texture:SetWidth(20)
    texture:SetHeight(20)
    texture:SetPoint("CENTER", button, "CENTER", 0, 0)
    texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")

    local col = math.mod(i - 1, 4)
    local row = math.floor((i - 1) / 4)

    texture:SetTexCoord(
        col * 0.25,
        (col + 1) * 0.25,
        row * 0.25,
        (row + 1) * 0.25
    )

    button:SetScript("OnClick", function()
        selectedRaidIcon = this:GetID()

        if type(TargetScanDB) ~= "table" then
            TargetScanDB = {}
        end

        TargetScanDB.raidIcon = selectedRaidIcon

        UpdateRaidIconSelection()

        if trackedTarget and UnitExists("target") then
            if UnitName("target") == trackedTarget then
                SetRaidTarget("target", selectedRaidIcon)
            end
        end
    end)
end

UpdateRaidIconSelection()

-- Shows/hides the Rescan button (under Clear) and moves the marker
-- selector down / resizes the window to make room for it.
SetRescanShown = function(show)
    local off = 0

    if show then
        rescan:Show()
        off = 25
    else
        rescan:Hide()
    end

    iconLabel:ClearAllPoints()
    iconLabel:SetPoint("TOP", clear, "BOTTOM", 0, -7 - off)

    local n

    for n = 1, 8 do
        raidIconButtons[n]:ClearAllPoints()
        raidIconButtons[n]:SetPoint("TOP", f, "TOP", -87.5 + (n - 1) * 25, -137 - off)
    end

    f:SetHeight(175 + off)
end

---------------------------------------------------------------
-- Load saved settings (saved vars exist only after VARIABLES_LOADED)
---------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("VARIABLES_LOADED")

loader:SetScript("OnEvent", function()
    if type(TargetScanDB) ~= "table" then
        TargetScanDB = {}
    end

    -- Raid marker
    local n = tonumber(TargetScanDB.raidIcon)

    if n and n >= 1 and n <= 8 then
        selectedRaidIcon = math.floor(n)
    else
        selectedRaidIcon = 5
    end

    TargetScanDB.raidIcon = selectedRaidIcon

    -- Window position
    local p = TargetScanDB.pos

    if type(p) == "table" and p[1] and p[2] and p[3] and p[4] then
        f:ClearAllPoints()
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end

    UpdateRaidIconSelection()
end)

---------------------------------------------------------------
-- Name handling
---------------------------------------------------------------

local function CleanName(text)
    if not text then
        return ""
    end

    local _, _, inner = string.find(text, "%[(.-)%]")

    if inner then
        text = inner
    end

    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|H.-|h", "")
    text = string.gsub(text, "|h", "")
    text = string.gsub(text, "|r", "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")

    return text
end

local function UpdateScanName()
    local name = CleanName(eb:GetText())

    found = false
    isRescan = false
    timer = 0
    SetRescanShown(false)

    -- Name* (asterisk at the end) = exact match only
    local _, _, starred = string.find(name, "^(.*)%*$")

    scanExact = false

    if starred then
        scanExact = true
        name = string.gsub(starred, "%s+$", "")
    end

    if name == "" then
        scanName = nil
        scanExact = false
        status:SetText("Idle")
    else
        scanName = string.lower(name)

        if scanExact then
            status:SetText("|cffffff00Scanning (exact):|r " .. name)
        else
            status:SetText("|cffffff00Scanning for:|r " .. name)
        end
    end
end

eb:SetScript("OnTextChanged", UpdateScanName)

eb:SetScript("OnEnterPressed", function()
    this:ClearFocus()
end)

eb:SetScript("OnEscapePressed", function()
    this:ClearFocus()
end)

eb:SetScript("OnEditFocusGained", function()
    editHasFocus = true
    catcher:Show()
end)

eb:SetScript("OnEditFocusLost", function()
    editHasFocus = false
    catcher:Hide()
end)

---------------------------------------------------------------
-- Shift-click support
---------------------------------------------------------------

local origIsVisible = ChatFrameEditBox.IsVisible

ChatFrameEditBox.IsVisible = function(self)
    if editHasFocus then
        return true
    end

    return origIsVisible(self)
end

local origInsert = ChatFrameEditBox.Insert

ChatFrameEditBox.Insert = function(self, text)
    if editHasFocus then
        eb:SetText("")
        eb:Insert(CleanName(text))
    else
        origInsert(self, text)
    end
end

local origSetItemRef = SetItemRef

SetItemRef = function(link, text, button)
    if editHasFocus and IsShiftKeyDown() then
        eb:SetText("")
        eb:Insert(CleanName(text))
        return
    end

    origSetItemRef(link, text, button)
end

---------------------------------------------------------------
-- Target matching
---------------------------------------------------------------

TargetMatches = function()
    if not scanName then
        return false
    end

    if UnitExists("target") then
        local name = UnitName("target")

        if name then
            if scanExact then
                if string.lower(name) == scanName then
                    return true
                end
            elseif string.find(string.lower(name), scanName, 1, true) then
                return true
            end
        end
    end

    return false
end

---------------------------------------------------------------
-- Scanning
---------------------------------------------------------------

f:SetScript("OnUpdate", function()
    if not scanName or found then
        return
    end

    timer = timer + arg1

    if timer < SCAN_INTERVAL then
        return
    end

    timer = 0

    if not TargetMatches() then
        local hadTarget = UnitExists("target")

        -- second arg requests exact match on clients that support it;
        -- ignored harmlessly on clients that don't
        TargetByName(scanName, scanExact)

        if scanExact and not TargetMatches() then
            -- Exact mode: partial match (or other unit) got targeted, undo it
            if UnitExists("target") then
                if hadTarget then
                    TargetLastTarget()
                else
                    ClearTarget()
                end
            end
        end
    end

    if TargetMatches() then
        found = true
        trackedTarget = UnitName("target")
        SetRescanShown(true)

        status:SetText(
            "|cff00ff00Found and targeted:|r " .. trackedTarget
        )

        PlaySound("RaidWarning")
        if not isRescan then
            SetRaidTarget("target", selectedRaidIcon)
        end
    end
end)

---------------------------------------------------------------
-- Show / hide
---------------------------------------------------------------

f:SetScript("OnShow", function()
    UpdateScanName()
    UpdateRaidIconSelection()
end)

f:SetScript("OnHide", function()
    eb:ClearFocus()
end)



---------------------------------------------------------------
-- Native /tar and /target hook
---------------------------------------------------------------

local origTARGET = SlashCmdList["TARGET"]

SlashCmdList["TARGET"] = function(msg)
    if origTARGET then
        origTARGET(msg)
    end

    if msg and msg ~= "" then
        eb:SetText(msg)
        f:Show()
    end
end

---------------------------------------------------------------
-- Focus support (ClassicAPI)
---------------------------------------------------------------

-- Focus support for ClassicAPI.
-- Standalone equivalents of the focus functionality in pfUI/modules/focus.lua.
-- Uses ClassicAPI's focus/focustarget unit tokens and event stream.

local focusFrames = {}

local function SaveFramePosition(frame, key)
    if type(TargetScanDB) ~= "table" then TargetScanDB = {} end
    local point, _, relativePoint, x, y = frame:GetPoint()
    TargetScanDB[key] = { point, relativePoint, x, y }
end

local function RestoreFramePosition(frame, key, defaultPoint, relativeTo, relativePoint, x, y)
    local p = type(TargetScanDB) == "table" and TargetScanDB[key]
    frame:ClearAllPoints()
    if type(p) == "table" and p[1] and p[2] and p[3] and p[4] then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint(defaultPoint, relativeTo, relativePoint, x, y)
    end
end

local function CreateFocusFrame(name, unit, title)
    local frame = CreateFrame("Button", name, UIParent)
    frame.unit = unit
    frame:SetWidth(180)
    frame:SetHeight(62)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)

    -- Only the main focus frame is draggable; the focus target pane is
    -- anchored to its right edge and follows it.
    if unit == "focus" then
        frame:SetScript("OnDragStart", function()
            this:StartMoving()
        end)
        frame:SetScript("OnDragStop", function()
            this:StopMovingOrSizing()
            SaveFramePosition(this, "focusPos")
        end)
    end

    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            ClearFocus()
        elseif arg1 == "LeftButton" and UnitExists(this.unit) then
            TargetUnit(this.unit)
        end
    end)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -5)
    label:SetText(title)
    frame.label = label

    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    if unit == "focus" then
        nameText:SetWidth(166)
    end
    nameText:SetJustifyH("LEFT")
    nameText:SetText("")
    frame.nameText = nameText

    local health = CreateFrame("StatusBar", nil, frame)
    health:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 7, 14)
    health:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -7, 14)
    health:SetHeight(10)
    health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    health:SetStatusBarColor(0.15, 0.75, 0.15)
    health:SetMinMaxValues(0, 1)
    health:SetValue(1)
    frame.health = health

    local healthBg = health:CreateTexture(nil, "BACKGROUND")
    healthBg:SetAllPoints(health)
    healthBg:SetTexture(0.15, 0.15, 0.15, 0.9)

    local healthText = health:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    healthText:SetPoint("CENTER", health, "CENTER", 0, 0)
    frame.healthText = healthText

    local power = CreateFrame("StatusBar", nil, frame)
    power:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 7, 7)
    power:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -7, 7)
    power:SetHeight(5)
    power:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    power:SetStatusBarColor(0.1, 0.35, 0.9)
    power:SetMinMaxValues(0, 1)
    power:SetValue(1)
    frame.power = power

    local powerBg = power:CreateTexture(nil, "BACKGROUND")
    powerBg:SetAllPoints(power)
    powerBg:SetTexture(0.15, 0.15, 0.15, 0.9)

    frame:SetScript("OnUpdate", nil)
    frame:Hide()
    return frame
end

local function UpdateFocusFrame(frame)
    local unit = frame.unit
    if not UnitExists(unit) then
        frame:Hide()
        return
    end

    local name = UnitName(unit) or UNKNOWN
    local level = UnitLevel(unit)
    if level and level > 0 then
        name = name .. "  (" .. level .. ")"
    end
    frame.nameText:SetText(name)

    local health, healthMax = UnitHealth(unit), UnitHealthMax(unit)
    healthMax = healthMax and healthMax > 0 and healthMax or 1
    frame.health:SetMinMaxValues(0, healthMax)
    frame.health:SetValue(health or 0)
    frame.healthText:SetText(tostring(health or 0) .. " / " .. tostring(healthMax))

    -- Focus target pane: width follows the longest of name / title / hp text,
    -- and the hp/power bars stretch with it.
    if unit == "focustarget" then
        local w = frame.nameText:GetStringWidth()
        local lw = frame.label:GetStringWidth()
        local hw = frame.healthText:GetStringWidth()
        if lw > w then w = lw end
        if hw > w then w = hw end
        frame:SetWidth(math.max(w + 14 + 4, 70))
    end

    local power, powerMax = UnitMana(unit), UnitManaMax(unit)
    powerMax = powerMax and powerMax > 0 and powerMax or 1
    frame.power:SetMinMaxValues(0, powerMax)
    frame.power:SetValue(power or 0)

    local powerType = UnitPowerType and UnitPowerType(unit) or 0
    if powerType == 1 then
        frame.power:SetStatusBarColor(1, 0, 0)
    elseif powerType == 2 then
        frame.power:SetStatusBarColor(1, 0.5, 0.25)
    elseif powerType == 3 then
        frame.power:SetStatusBarColor(1, 0.8, 0)
    else
        frame.power:SetStatusBarColor(0.1, 0.35, 0.9)
    end

    frame:Show()
end

local focus = CreateFocusFrame("TargetScanFocusFrame", "focus", "Focus")
local focusTarget = CreateFocusFrame("TargetScanFocusTargetFrame", "focustarget", "Focus Target")
focusFrames.focus = focus
focusFrames.focustarget = focusTarget

-- Focus target pane sits flush against the right edge of the focus frame.
-- Tweak the x/y offsets here (negative x overlaps the border slightly).
local function AnchorFocusTarget()
    focusTarget:ClearAllPoints()
    focusTarget:SetPoint("TOPLEFT", focus, "TOPRIGHT", -2, 0)
end

RestoreFramePosition(focus, "focusPos", "BOTTOMLEFT", UIParent, "BOTTOM", 220, 220)
AnchorFocusTarget()

local function RefreshFocusFrames()
    UpdateFocusFrame(focus)
    UpdateFocusFrame(focusTarget)
end

-- SavedVariables are not populated until VARIABLES_LOADED.
local focusLoader = CreateFrame("Frame")
focusLoader:RegisterEvent("VARIABLES_LOADED")
focusLoader:SetScript("OnEvent", function()
    RestoreFramePosition(focus, "focusPos", "BOTTOMLEFT", UIParent, "BOTTOM", 220, 220)
    AnchorFocusTarget()
    RefreshFocusFrames()
end)


local focusEvents = CreateFrame("Frame")
focusEvents:RegisterEvent("PLAYER_FOCUS_CHANGED")
focusEvents:RegisterEvent("UNIT_HEALTH")
focusEvents:RegisterEvent("UNIT_MAXHEALTH")
focusEvents:RegisterEvent("UNIT_MANA")
focusEvents:RegisterEvent("UNIT_MAXMANA")
focusEvents:RegisterEvent("UNIT_ENERGY")
focusEvents:RegisterEvent("UNIT_MAXENERGY")
focusEvents:RegisterEvent("UNIT_RAGE")
focusEvents:RegisterEvent("UNIT_MAXRAGE")
focusEvents:RegisterEvent("UNIT_AURA")
focusEvents:RegisterEvent("UNIT_LEVEL")
focusEvents:RegisterEvent("UNIT_NAME_UPDATE")
focusEvents:RegisterEvent("UNIT_TARGET")
focusEvents:SetScript("OnEvent", function()
    if event == "PLAYER_FOCUS_CHANGED" then
        RefreshFocusFrames()
        return
    end

    local unit = arg1
    if unit == "focus" then
        UpdateFocusFrame(focus)
        -- Focus target identity can change without a separate event. Recheck
        -- its visibility whenever ClassicAPI reports UNIT_TARGET for focus.
        UpdateFocusFrame(focusTarget)
    elseif unit == "focustarget" then
        UpdateFocusFrame(focusTarget)
    end
end)

-- Initial state, including after /reload where ClassicAPI may already hold focus.
RefreshFocusFrames()

-- ClassicAPI owns /focus and /clearfocus. These commands add the pfUI-style
-- exact-name helper and focus casting / swapping without replacing native commands.
local function FocusNameCommand(msg)
    if not msg or msg == "" then return end
    local unit = UnitTokenFromName(msg, true) or UnitTokenFromName(msg)
    if unit then FocusUnit(unit) end
end

SLASH_TARGETSCANFOCUSNAME1 = "/focusname"
SLASH_TARGETSCANFOCUSNAME2 = "/tsfocusname"
SlashCmdList["TARGETSCANFOCUSNAME"] = FocusNameCommand

-- pfUI accepts either a spell name or a Lua function expression for
-- /castfocus. Cache compiled function expressions so repeated casts do not
-- compile the same string every time.
local focusCastFunctions = {}

local function GetFocusCastFunction(message)
    local cached = focusCastFunctions[message]
    if cached ~= nil then
        return cached or nil
    end

    local chunk = loadstring("return " .. message)
    if not chunk then
        focusCastFunctions[message] = false
        return nil
    end

    local ok, value = pcall(chunk)
    if ok and type(value) == "function" then
        focusCastFunctions[message] = value
        return value
    end

    focusCastFunctions[message] = false
    return nil
end

local function RestorePreviousTarget(previousGUID, previousPlayer)
    if previousGUID and previousGUID ~= "0x0000000000000000" then
        TargetUnit(previousGUID)
    elseif previousPlayer then
        TargetUnit("player")
    else
        TargetLastTarget()
    end
end

local function CastFocusCommand(msg)
    if not msg or msg == "" then return end

    local focusGUID = UnitGUID("focus")
    if not focusGUID or focusGUID == "0x0000000000000000" then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
        end
        return
    end

    local func = GetFocusCastFunction(msg)

    -- Spell casts use ClassicAPI's GUID-targeted path and never swap target.
    if not func then
        CastSpellByName(msg, focusGUID)
        return
    end

    -- Lua-function casts need a brief target swap, matching pfUI's behavior.
    local previousGUID = UnitGUID("target")
    local previousPlayer = UnitIsUnit("target", "player")

    TargetUnit(focusGUID)
    if UnitGUID("target") ~= focusGUID then
        RestorePreviousTarget(previousGUID, previousPlayer)
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
        end
        return
    end

    func()
    RestorePreviousTarget(previousGUID, previousPlayer)
end

SLASH_TARGETSCANCASTFOCUS1 = "/castfocus"
SLASH_TARGETSCANCASTFOCUS2 = "/tscastfocus"
SlashCmdList["TARGETSCANCASTFOCUS"] = CastFocusCommand

local function SwapFocusCommand()
    local targetGUID = UnitGUID("target")
    local oldFocusGUID = UnitGUID("focus")

    if targetGUID and targetGUID ~= "0x0000000000000000" then
        FocusUnit("target")
        if oldFocusGUID and oldFocusGUID ~= "0x0000000000000000" then
            TargetUnit(oldFocusGUID)
        end
    end
end

SLASH_TARGETSCANSWAPFOCUS1 = "/swapfocus"
SLASH_TARGETSCANSWAPFOCUS2 = "/tsswapfocus"
SlashCmdList["TARGETSCANSWAPFOCUS"] = SwapFocusCommand
