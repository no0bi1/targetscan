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