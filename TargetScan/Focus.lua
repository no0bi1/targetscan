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
    frame:SetHeight(46)
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

    frame:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        SaveFramePosition(this, this.unit == "focus" and "focusPos" or "focusTargetPos")
    end)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -5)
    label:SetText(title)
    frame.label = label

    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    nameText:SetWidth(166)
    nameText:SetJustifyH("LEFT")
    nameText:SetText("")
    frame.nameText = nameText

    local health = CreateFrame("StatusBar", nil, frame)
    health:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 7, 7)
    health:SetWidth(166)
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
    power:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, 2)
    power:SetWidth(166)
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

RestoreFramePosition(focus, "focusPos", "BOTTOMLEFT", UIParent, "BOTTOM", 220, 220)
RestoreFramePosition(focusTarget, "focusTargetPos", "BOTTOMLEFT", focus, "TOP", 0, 10)

local function RefreshFocusFrames()
    UpdateFocusFrame(focus)
    UpdateFocusFrame(focusTarget)
end

-- SavedVariables are not populated until VARIABLES_LOADED.
local focusLoader = CreateFrame("Frame")
focusLoader:RegisterEvent("VARIABLES_LOADED")
focusLoader:SetScript("OnEvent", function()
    RestoreFramePosition(focus, "focusPos", "BOTTOMLEFT", UIParent, "BOTTOM", 220, 220)
    RestoreFramePosition(focusTarget, "focusTargetPos", "BOTTOMLEFT", focus, "TOP", 0, 10)
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
