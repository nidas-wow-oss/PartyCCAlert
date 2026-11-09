local GetTime, UnitDebuff, UnitExists = GetTime, UnitDebuff, UnitExists
local UnitCastingInfo, UnitIsUnit, UnitCanAttack = UnitCastingInfo, UnitIsUnit, UnitCanAttack

local CC_IDS = {

    [853]=4, [8643]=4, [1833]=4, [5211]=4, [9005]=4, [22570]=4, [30283]=4,
    [12809]=4, [19577]=4, [47481]=4, [44572]=4, [12355]=4, [7922]=4, [20253]=4,
    [49203]=4, [64044]=4, [46968]=4, [20549]=4, [2812]=4, [50518]=4, [50519]=4,
    [39796]=4, [12798]=4, [16922]=4,

    [5782]=4, [8122]=4, [5484]=4, [6789]=4, [5246]=4, [2094]=4, [33786]=4,
    [118]=4, [51514]=4, [20066]=4, [6770]=4, [1776]=4, [2637]=4, [3355]=4,
    [19386]=4, [19503]=4, [6358]=4, [605]=4, [31661]=4, [10326]=4, [9484]=4, [710]=4,
    [60210]=4, [1513]=4,

    [15487]=3, [1330]=3, [47476]=3, [19647]=3, [34490]=3, [18469]=3, [18425]=3,
    [28730]=3, [18498]=3, [63529]=3, [50479]=3,
}

local IGNORE_IDS = { [64058]=true }

local CAST_IDS = { 5782, 6358, 118, 51514, 33786, 2637, 710, 605, 10326, 9484, 1513 }

local CASTERS = {
    "target", "focus", "mouseover", "party1target", "party2target",
    "arena1", "arena2", "arena3", "arena4", "arena5",
    "arenapet1", "arenapet2", "arenapet3", "arenapet4", "arenapet5",
}

local byName = {}
local castName = {}

local DEFAULTS = {
    party1 = { "CENTER", 0, 110 },
    party2 = { "CENTER", 0, 40 },
    sound = true,
    casts = true,
    silences = true,
    scale = 1,
    timerFont = "continuum",
}

local COLORS = {
    celeste = { 0.4, 0.85, 1 },
    rojo    = { 1, 0.15, 0.15 },
    agua    = { 0.25, 1, 0.8 },
}
local DEFAULT_COLOR = "celeste"
local CAST_COLOR = { 1, 0.85, 0.1 }

local alerts = {}
local unlocked = false

local function FormatTime(t)
    if t >= 10 then return string.format("%d", t) end
    return string.format("%.1f", t)
end

local function CreateAlert(unit, label)
    local f = CreateFrame("Frame", "PartyCCAlert_" .. unit, UIParent)
    f:SetSize(190, 58)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if unlocked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()

        self:SetUserPlaced(false)
        local point, _, _, x, y = self:GetPoint()
        PartyCCAlertDB[unit] = { point, x, y }
    end)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetTexture(0, 0, 0, 0.55)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(50, 50)
    f.icon:SetPoint("LEFT", 4, 0)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f.icon)

    f.border = CreateFrame("Frame", nil, f)
    f.border:SetPoint("TOPLEFT", f.icon, "TOPLEFT", -3, 3)
    f.border:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", 3, -3)
    f.border:SetFrameLevel(f.cd:GetFrameLevel() + 2)
    f.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 3 })

    f.who = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.who:SetPoint("LEFT", f.icon, "RIGHT", 10, 0)
    f.who:SetText(label)
    f.who:SetTextColor(1, 0.3, 0.3)

    f.what = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.what:SetPoint("TOPLEFT", f.who, "BOTTOMLEFT", 0, -2)
    f.what:SetText("INCOMING")
    f.what:SetTextColor(CAST_COLOR[1], CAST_COLOR[2], CAST_COLOR[3])
    f.what:Hide()

    f.timer = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
    f.timer:SetPoint("RIGHT", f, "RIGHT", -8, 0)

    f.unit = unit
    f:Hide()
    f:SetScript("OnUpdate", function(self)
        if self.expires and self.expires > 0 then
            local left = self.expires - GetTime()
            if left <= 0 then

                if self.casting then self.timer:SetText(""); return end
                self:Hide()
                self.active = nil
                return
            end
            self.timer:SetText(FormatTime(left))
        end
    end)
    return f
end

local function BorderColor(f)
    local c = f.casting and CAST_COLOR or COLORS[PartyCCAlertDB.color] or COLORS[DEFAULT_COLOR]
    f.border:SetBackdropBorderColor(c[1], c[2], c[3], 1)
end

local function ApplyColor()
    for _, f in pairs(alerts) do BorderColor(f) end
end

local TIMER_FONTS = {
    { key = "continuum", label = "Continuum", path = "Interface\\AddOns\\PartyCCAlert\\Fonts\\ContinuumMedium.ttf" },
    { key = "friz",     label = "Friz",     path = "Fonts\\FRIZQT__.TTF" },
    { key = "arial",    label = "Arial",    path = "Fonts\\ARIALN.TTF" },
    { key = "skurri",   label = "Skurri",   path = "Fonts\\skurri.TTF" },
    { key = "morpheus", label = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { key = "number",   label = "Blizzard" },
}

local function TimerFontIndex()
    for i, t in ipairs(TIMER_FONTS) do
        if t.key == PartyCCAlertDB.timerFont then return i end
    end
    return 1
end

local function ApplyTimerFont()
    local t = TIMER_FONTS[TimerFontIndex()]
    for _, f in pairs(alerts) do
        if t.path then
            f.timer:SetFont(t.path, 24, "OUTLINE")
        else
            f.timer:SetFontObject(NumberFontNormalHuge)
        end
    end
end

local function ApplyPosition(f)
    local pos = PartyCCAlertDB[f.unit] or DEFAULTS[f.unit]
    f:SetScale(PartyCCAlertDB.scale)
    f:ClearAllPoints()
    f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
end

local function Hide(f)
    f:Hide(); f.active = nil
end

local function Show(f, icon, duration, expires, casting)
    local wasActive = f.active
    f.icon:SetTexture(icon)
    f.expires = expires
    if duration and duration > 0 and expires and expires > 0 then
        CooldownFrame_SetTimer(f.cd, expires - duration, duration, 1)
    else
        f.timer:SetText("")
        f.cd:Hide()
    end
    if f.casting ~= casting then
        f.casting = casting
        BorderColor(f)
        if casting then f.what:Show() else f.what:Hide() end
    end
    f:Show()
    f.active = true
    if not wasActive and PartyCCAlertDB.sound then
        PlaySound("RaidWarning")
    end
end

local function FindCast(unit, now)
    local bestIcon, bestDur, bestEnd
    for i = 1, #CASTERS do
        local caster = CASTERS[i]
        local name, _, _, icon, startMs, endMs = UnitCastingInfo(caster)
        if name and castName[name] and UnitCanAttack("player", caster)
           and UnitIsUnit(caster .. "target", unit) then
            local finish = endMs / 1000
            if finish > now and (not bestEnd or finish < bestEnd) then
                bestIcon, bestDur, bestEnd = icon, (endMs - startMs) / 1000, finish
            end
        end
    end
    return bestIcon, bestDur, bestEnd
end

local function Scan(f)
    local now = GetTime()
    if f.testUntil then
        if now < f.testUntil then return end
        f.testUntil = nil
    end
    local unit = f.unit
    if not UnitExists(unit) then
        Hide(f)
        return
    end

    local bestIcon, bestDur, bestExp, bestPrio
    for i = 1, 40 do
        local name, _, icon, _, _, duration, expires, _, _, _, spellId = UnitDebuff(unit, i)
        if not name then break end
        local prio = byName[name]

        if prio == 3 and not PartyCCAlertDB.silences then prio = nil end
        if prio and not IGNORE_IDS[spellId] and not (expires and expires > 0 and expires <= now) then
            if not bestPrio or prio > bestPrio
               or (prio == bestPrio and (expires or 0) > (bestExp or 0)) then
                bestIcon, bestDur, bestExp, bestPrio = icon, duration, expires, prio
            end
        end
    end
    if bestPrio then
        Show(f, bestIcon, bestDur, bestExp, nil)
        return
    end
    local cIcon, cDur, cEnd
    if PartyCCAlertDB.casts then cIcon, cDur, cEnd = FindCast(unit, now) end
    if cIcon then
        f.castGrace = cEnd + 0.4
        Show(f, cIcon, cDur, cEnd, true)
    elseif f.active and f.casting and now < (f.castGrace or 0) then

        return
    else
        Hide(f)
    end
end

local poll = CreateFrame("Frame")
local elapsedSum = 0
poll:Hide()
poll:SetScript("OnUpdate", function(self, elapsed)
    elapsedSum = elapsedSum + elapsed
    if elapsedSum < 0.1 then return end
    elapsedSum = 0
    Scan(alerts.party1); Scan(alerts.party2)
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        PartyCCAlertDB = PartyCCAlertDB or {}

        if not PartyCCAlertDB.fontV2 then
            PartyCCAlertDB.timerFont = nil
            PartyCCAlertDB.fontV2 = true
        end
        for _, k in ipairs({ "sound", "casts", "silences", "scale", "timerFont" }) do
            if PartyCCAlertDB[k] == nil then PartyCCAlertDB[k] = DEFAULTS[k] end
        end
        if not COLORS[PartyCCAlertDB.color or ""] then PartyCCAlertDB.color = DEFAULT_COLOR end
        for id, prio in pairs(CC_IDS) do
            local name = GetSpellInfo(id)
            if name then byName[name] = prio end
        end
        for _, id in ipairs(CAST_IDS) do
            local name = GetSpellInfo(id)
            if name then castName[name] = true end
        end
        alerts.party1 = CreateAlert("party1", "PARTY 1")
        alerts.party2 = CreateAlert("party2", "PARTY 2")
        ApplyPosition(alerts.party1)
        ApplyPosition(alerts.party2)
        ApplyColor()
        ApplyTimerFont()
        self:RegisterEvent("UNIT_AURA")
        self:RegisterEvent("PARTY_MEMBERS_CHANGED")
        self:RegisterEvent("RAID_ROSTER_UPDATE")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        poll:Show()
    elseif event == "UNIT_AURA" then
        local f = alerts[arg1]
        if f then Scan(f) end
    else
        Scan(alerts.party1); Scan(alerts.party2)
    end
end)

local function SetUnlocked(on)
    unlocked = on
    for _, f in pairs(alerts) do
        f:EnableMouse(on)
        if on then
            f.testUntil = GetTime() + 3600
            local casting = f.unit == "party2" or nil
            local _, _, icon = GetSpellInfo(casting and 5782 or 118)
            Show(f, icon, 0, 0, casting)

            f.timer:SetText(casting and "1.5" or "8")
        else
            f.testUntil = nil
            Hide(f)
        end
    end
end

local menu

local HDR, WHITE, GOLD, GRAY, R = "|cff4fc3f7", "|cffffffff", "|cffFFD700", "|cffaaaaaa", "|r"
local FONT = "Fonts\\FRIZQT__.TTF"
local panelBg     = { 0.00, 0.03, 0.11, 0.96 }
local panelBorder = { 0.22, 0.48, 0.90, 1.00 }
local titleBg     = { 0.02, 0.07, 0.20, 0.97 }
local titleBorder = { 0.28, 0.52, 0.92, 0.95 }

local bdPanel = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local bdTitle = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local function ApplyBackdrop(f, bd, bg, border)
    f:SetBackdrop(bd)
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    f:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
end

local function Header(parent, y, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetFont(FONT, 12, "OUTLINE")
    fs:SetText(HDR .. text .. R)
end

local function Separator(parent, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 12, y)
    line:SetPoint("TOPRIGHT", -12, y)
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetVertexColor(0.20, 0.42, 0.72, 0.55)
end

local function Btn(parent, x, y, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b:SetPoint("TOPLEFT", x, y)
    ApplyBackdrop(b, bdTitle, titleBg, titleBorder)
    b.text = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    b.text:SetFont(FONT, 12, "")
    b.text:SetPoint("CENTER")
    function b:SetLabel(label, selected)
        self.label, self.selected = label, selected
        self.text:SetText((selected and WHITE or GOLD) .. label .. R)
    end
    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.10, 0.15, 0.30, 0.90)
        self.text:SetText(WHITE .. self.label .. R)
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(titleBg[1], titleBg[2], titleBg[3], titleBg[4])
        self:SetLabel(self.label, self.selected)
    end)
    b:SetScript("OnClick", onClick)
    return b
end

local function CreateMenu()
    local m = CreateFrame("Frame", "PartyCCAlertMenu", UIParent)
    m:SetSize(250, 320)
    m:SetPoint("CENTER")
    m:SetFrameStrata("DIALOG")
    m:SetClampedToScreen(true)
    ApplyBackdrop(m, bdPanel, panelBg, panelBorder)
    m:EnableMouse(true)
    m:SetMovable(true)
    m:RegisterForDrag("LeftButton")
    m:SetScript("OnDragStart", m.StartMoving)
    m:SetScript("OnDragStop", m.StopMovingOrSizing)

    local tBar = CreateFrame("Frame", nil, m)
    tBar:SetHeight(26)
    tBar:SetPoint("LEFT", m, "TOP", -80, 0)
    tBar:SetPoint("RIGHT", m, "TOP", 80, 0)
    tBar:SetFrameLevel(m:GetFrameLevel() + 2)
    ApplyBackdrop(tBar, bdTitle, titleBg, titleBorder)
    local title = tBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("CENTER", 0, 1)
    title:SetFont(FONT, 13, "OUTLINE")
    title:SetText(GOLD .. "PartyCCAlert" .. R)

    local close = CreateFrame("Button", nil, m, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetFrameLevel(m:GetFrameLevel() + 5)

    Header(m, -24, "Alerts")
    local checks = {}
    local function Check(key, label, y)
        local cb = CreateFrame("CheckButton", "PartyCCAlertMenu_" .. key, m, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 14, y)
        local fs = _G[cb:GetName() .. "Text"]
        fs:SetFont(FONT, 12, "")
        fs:SetText(WHITE .. label .. R)
        cb:SetScript("OnClick", function(self)
            PartyCCAlertDB[key] = self:GetChecked() and true or false
        end)
        checks[key] = cb
    end
    Check("sound", "Sound", -40)
    Check("casts", "Warn incoming CC casts", -64)
    Check("silences", "Show silences", -88)

    Separator(m, -120)
    Header(m, -130, "Border color")
    local colorBtns = {}
    local function RefreshColors()
        for key, b in pairs(colorBtns) do b:SetLabel(b.label, PartyCCAlertDB.color == key) end
    end
    local function ColorButton(key, label, x)
        local b = Btn(m, x, -148, 68, 22, function()
            PartyCCAlertDB.color = key
            ApplyColor()
            RefreshColors()
        end)
        b:SetLabel(label, false)
        colorBtns[key] = b
    end
    ColorButton("celeste", "Blue", 16)
    ColorButton("rojo", "Red", 91)
    ColorButton("agua", "Aqua", 166)

    Separator(m, -182)

    local s = CreateFrame("Slider", "PartyCCAlertMenuScale", m, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", 30, -208)
    s:SetWidth(190)
    s:SetHeight(14)
    s:SetMinMaxValues(0.5, 2)
    s:SetValueStep(0.05)
    local sTitle = PartyCCAlertMenuScaleText
    sTitle:ClearAllPoints()
    sTitle:SetPoint("BOTTOM", s, "TOP", 0, 1)
    sTitle:SetFont(FONT, 11, "")
    sTitle:SetText(HDR .. "Scale" .. R)
    PartyCCAlertMenuScaleLow:SetText(GRAY .. "0.5" .. R)
    PartyCCAlertMenuScaleHigh:SetText(GRAY .. "2" .. R)
    local sVal = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sVal:SetPoint("TOP", s, "BOTTOM", 0, -1)
    sVal:SetFont(FONT, 12, "")
    local function ScaleText(v)
        sVal:SetText(WHITE .. string.format("%.2f", v) .. R)
    end

    local fontBtn
    local function FontText()
        fontBtn:SetLabel("Timer font: " .. TIMER_FONTS[TimerFontIndex()].label, false)
    end
    fontBtn = Btn(m, 16, -250, 218, 22, function()
        local i = TimerFontIndex() % #TIMER_FONTS + 1
        PartyCCAlertDB.timerFont = TIMER_FONTS[i].key
        ApplyTimerFont()
        FontText()
    end)

    local move
    local function MoveText()
        move:SetLabel(unlocked and "Lock" or "Test / Move", unlocked)
    end
    move = Btn(m, 16, -280, 218, 24, function()
        SetUnlocked(not unlocked)
        MoveText()
    end)

    m:SetScript("OnShow", function()
        for key, cb in pairs(checks) do cb:SetChecked(PartyCCAlertDB[key]) end

        s:SetScript("OnValueChanged", nil)
        s:SetValue(PartyCCAlertDB.scale)
        ScaleText(PartyCCAlertDB.scale)
        s:SetScript("OnValueChanged", function(self, v)
            v = math.floor(v * 20 + 0.5) / 20
            PartyCCAlertDB.scale = v
            ScaleText(v)
            for _, f in pairs(alerts) do ApplyPosition(f) end
        end)
        RefreshColors()
        FontText()
        MoveText()
    end)

    m:SetScript("OnHide", function()
        if unlocked then SetUnlocked(false) end
    end)
    m:Hide()
    return m
end

SLASH_PARTYCCALERT1 = "/pcc"
SlashCmdList["PARTYCCALERT"] = function()
    menu = menu or CreateMenu()
    if menu:IsShown() then menu:Hide() else menu:Show() end
end
