-- !RothDevLib/UI/MinimapButton.lua
-- Minimap launcher. Prefers LibDataBroker/LibDBIcon, with a bounded manual fallback.

local RDL = _G.RothDevLib
RDL.UI = RDL.UI or {}
local UI = RDL.UI

local ICON_PATH = "Interface\\AddOns\\!RothDevLib\\Media\\bug"
local hookedLDBButtons = setmetatable({}, { __mode = "k" })

local function SafeError(value)
  local U = RDL.Util
  if U and type(U.SafeToString) == "function" then
    local ok, text = pcall(U.SafeToString, U, value)
    if ok and type(text) == "string" then return text end
  end
  return "<error>"
end

local function GetActiveIssueCount()
  if RDL.DB and RDL.DB.GetActiveGroupCount then
    return tonumber(RDL.DB:GetActiveGroupCount()) or 0
  end
  if RDL.DB and RDL.DB.GetGroupCount then
    return tonumber(RDL.DB:GetGroupCount()) or 0
  end
  return 0
end

local function GetIconColor(activeIssues)
  if (tonumber(activeIssues) or 0) > 0 then
    return 1, 0.20, 0.20
  end
  return 1, 1, 1
end

local function FormatCount(value)
  local count = tonumber(value) or 0
  if count <= 0 then return "" end
  if count >= 100 then return "99+" end
  return tostring(count)
end

local function EnsureCountText(button)
  if not button or button.countText then return end
  local text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  text:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
  text:SetJustifyH("RIGHT")
  text:SetJustifyV("BOTTOM")
  text:SetText("")
  text:SetTextColor(1, 1, 1)
  text:SetShadowOffset(1, -1)
  text:SetShadowColor(0, 0, 0, 1)
  button.countText = text
end

local function SetCountText(button, value)
  if not button then return end
  EnsureCountText(button)
  if not button.countText then return end

  local text = FormatCount(value)
  button.countText:SetText(text)
  if text == "" then
    button.countText:Hide()
  else
    button.countText:Show()
    button.countText:SetTextColor(1, 0.3, 0.3)
  end
end

local fallbackSettings = { minimap = { hide = false, minimapPos = 225 } }

local function GetSettings()
  local settings = (RDL.DB and RDL.DB:GetSettings())
    or (_G.RothDevLibDB and _G.RothDevLibDB.settings)
  if type(settings) ~= "table" then return fallbackSettings end
  return settings
end

local function EnsureMinimapSettings()
  local settings = GetSettings()
  if type(settings.minimap) ~= "table" then
    settings.minimap = { hide = false, minimapPos = 225 }
  end

  if RDL.DB and RDL.DB.GetSettings then
    local dbSettings = RDL.DB:GetSettings()
    if dbSettings and dbSettings.minimapForceShowOnNextLogin then
      settings.minimap.hide = false
      dbSettings.minimapForceShowOnNextLogin = false
    end
  end

  if settings.minimap.hide == nil and settings.minimapHide ~= nil then
    settings.minimap.hide = settings.minimapHide
  end
  if settings.minimap.minimapPos == nil then
    settings.minimap.minimapPos = settings.minimapAngle or 225
  end

  settings.minimapHide = settings.minimap.hide == true
  settings.minimapAngle = settings.minimap.minimapPos
  return settings
end

local function TooltipLines(tooltip)
  tooltip:AddLine("RothDevLib", 1, 1, 1)
  local count = GetActiveIssueCount()
  if count > 0 then
    tooltip:AddLine(string.format("Active issues: %d", count), 1, 0.3, 0.3)
  else
    tooltip:AddLine("No issues", 0.5, 1, 0.5)
  end
  tooltip:AddLine("Left click: open bag", 0.8, 0.8, 0.8)
  tooltip:AddLine("Right click: export all", 0.8, 0.8, 0.8)
  tooltip:AddLine("Shift+Right: open log", 0.8, 0.8, 0.8)
  local owned = RDL.Capture and RDL.Capture.ownsHandler and "owned" or "not-owned"
  tooltip:AddLine("Errorhandler: " .. owned, 0.8, 0.8, 0.8)
end

local function GetLDBButton(self)
  if self and self._ldbIcon and type(self._ldbIcon.GetMinimapButton) == "function" then
    local ok, button = pcall(self._ldbIcon.GetMinimapButton, self._ldbIcon, "RothDevLib")
    if ok and button then return button end
  end
  return _G.LibDBIcon10_RothDevLib
end

function UI:UpdateMinimapIconState()
  local count = GetActiveIssueCount()
  local red, green, blue = GetIconColor(count)

  if self._ldbInited then
    local button = GetLDBButton(self)
    if button and button.icon then
      button.icon:SetTexture(ICON_PATH)
      button.icon:SetVertexColor(red, green, blue)
      SetCountText(button, count)
    end
    if self._ldbObj then
      self._ldbObj.iconR, self._ldbObj.iconG, self._ldbObj.iconB = red, green, blue
    end
  end

  if self.minimapButton and self.minimapButton.icon then
    self.minimapButton.icon:SetTexture(ICON_PATH)
    self.minimapButton.icon:SetVertexColor(red, green, blue)
    SetCountText(self.minimapButton, count)
  end
end

local function InitLDB(self)
  if self._ldbInited then return true end
  if not _G.LibStub then return false end

  local LDB = LibStub("LibDataBroker-1.1", true)
  local LDBIcon = LibStub("LibDBIcon-1.0", true)
  if not LDB or not LDBIcon then return false end

  local settings = EnsureMinimapSettings()

  if not self._ldbObj then
    self._ldbObj = LDB:NewDataObject("RothDevLib", {
      type = "launcher",
      text = "RothDevLib",
      icon = ICON_PATH,
      OnClick = function(_, button)
        if button == "LeftButton" then
          if UI and UI.Toggle then UI:Toggle() end
          return
        end
        if button == "RightButton" then
          if IsShiftKeyDown() then
            if UI and UI.OpenLog then UI:OpenLog() end
          elseif UI and UI.OpenExportAll then
            UI:OpenExportAll()
          end
        end
      end,
      OnTooltipShow = function(tooltip)
        TooltipLines(tooltip)
      end,
    })
  end

  if not self._ldbRegistered then
    LDBIcon:Register("RothDevLib", self._ldbObj, settings.minimap)
    self._ldbRegistered = true
  end

  self._ldbIcon = LDBIcon
  self._ldbInited = true

  local button = GetLDBButton(self)
  if button and not hookedLDBButtons[button] then
    button:HookScript("OnShow", function()
      if UI and UI.UpdateMinimapIconState then UI:UpdateMinimapIconState() end
    end)
    hookedLDBButtons[button] = true
  end

  if settings.minimap.hide then
    LDBIcon:Hide("RothDevLib")
  else
    LDBIcon:Show("RothDevLib")
  end

  if UI and UI.UpdateMinimapIconState then
    UI:UpdateMinimapIconState()
  end
  return true
end

local function ClampAngle(value)
  if type(value) ~= "number" then return 225 end
  while value < 0 do value = value + 360 end
  while value >= 360 do value = value - 360 end
  return value
end

local function ManualUpdatePosition(self)
  local button = self.minimapButton
  local minimap = _G.Minimap
  if not button or not minimap then return end

  local settings = EnsureMinimapSettings()
  local angle = ClampAngle(settings.minimap.minimapPos or 225)
  local radians = math.rad(angle)
  local radius = 78
  button:ClearAllPoints()
  button:SetPoint("CENTER", minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end

local function StopManualDrag(button)
  if button then button:SetScript("OnUpdate", nil) end
end

local function InitManual(self)
  if self.minimapButton or not _G.Minimap then return true end

  local button = CreateFrame("Button", "RothDevLibMinimapButton", _G.Minimap)
  self.minimapButton = button
  button:SetSize(31, 31)
  button:SetFrameStrata("HIGH")
  button:SetFrameLevel(20)
  button:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")

  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetAllPoints()
  icon:SetTexture(ICON_PATH)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button.icon = icon
  SetCountText(button, GetActiveIssueCount())

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetAllPoints()
  border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
  button.border = border

  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:SetScript("OnClick", function(_, clickButton)
    if clickButton == "LeftButton" then
      if UI and UI.Toggle then UI:Toggle() end
    elseif clickButton == "RightButton" then
      if IsShiftKeyDown() then
        if UI and UI.OpenLog then UI:OpenLog() end
      elseif UI and UI.OpenExportAll then
        UI:OpenExportAll()
      end
    end
  end)

  button:SetScript("OnEnter", function(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    TooltipLines(GameTooltip)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function(owner)
    if GameTooltip:GetOwner() == owner then GameTooltip:Hide() end
  end)
  button:SetScript("OnHide", function(owner)
    StopManualDrag(owner)
    if GameTooltip:GetOwner() == owner then GameTooltip:Hide() end
  end)

  button:RegisterForDrag("LeftButton")
  button:SetMovable(true)
  button:SetScript("OnDragStart", function(owner)
    owner:SetScript("OnUpdate", function()
      local minimapX, minimapY = _G.Minimap:GetCenter()
      if not minimapX or not minimapY then return end

      local cursorX, cursorY = GetCursorPosition()
      local scale
      if UIParent.GetEffectiveScale then
        scale = UIParent:GetEffectiveScale()
      elseif UIParent.GetScale then
        scale = UIParent:GetScale()
      end
      if not scale or scale <= 0 then return end
      cursorX, cursorY = cursorX / scale, cursorY / scale

      local deltaX, deltaY = cursorX - minimapX, cursorY - minimapY
      local angle = math.deg(math.atan2(deltaY, deltaX))
      local settings = EnsureMinimapSettings()
      settings.minimap.minimapPos = ClampAngle(angle)
      settings.minimapAngle = settings.minimap.minimapPos
      ManualUpdatePosition(UI)
    end)
  end)
  button:SetScript("OnDragStop", StopManualDrag)

  local settings = EnsureMinimapSettings()
  if settings.minimap.hide then
    button:Hide()
  else
    button:Show()
  end
  ManualUpdatePosition(UI)

  if UI and UI.UpdateMinimapIconState then
    UI:UpdateMinimapIconState()
  end
  return true
end

function UI:InitMinimapButton()
  if self._minimapInited then return end
  self._minimapInited = true

  local ldbCallOK, ldbInitialized = pcall(InitLDB, self)
  if not ldbCallOK then
    RDL:Log("WARN", "MINIMAP", "LDB minimap init failed", { error = SafeError(ldbInitialized) })
  end
  if not ldbCallOK or not ldbInitialized then
    local manualOK, manualError = pcall(InitManual, self)
    if not manualOK then
      RDL:Log("ERROR", "MINIMAP", "Manual minimap init failed", { error = SafeError(manualError) })
    end
  end

  local settings = EnsureMinimapSettings()
  RDL:Log("INFO", "MINIMAP", "Minimap init", {
    usedLDB = self._ldbInited == true,
    hide = settings.minimap.hide,
    pos = settings.minimap.minimapPos,
  })

  if type(_G.C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(1.0, function()
      local currentSettings = EnsureMinimapSettings()

      if UI._ldbInited then
        local button = GetLDBButton(UI)

        if not button and UI._ldbIcon and not currentSettings.minimap.hide then
          local showOK, showError = pcall(UI._ldbIcon.Show, UI._ldbIcon, "RothDevLib")
          button = GetLDBButton(UI)
          local showFailure
          if not showOK then showFailure = SafeError(showError) end
          RDL:Log(button and "INFO" or "WARN", "MINIMAP", "LDB button recovery", {
            buttonNow = button ~= nil,
            error = showFailure,
          })
        end

        if button and not currentSettings.minimap.hide and UI._ldbIcon then
          local shown = true
          if type(button.IsShown) == "function" then
            local ok, value = pcall(button.IsShown, button)
            shown = ok and value == true
          end
          if not shown then pcall(UI._ldbIcon.Show, UI._ldbIcon, "RothDevLib") end
        end

        if not button and not UI.minimapButton then
          local manualOK, manualError = pcall(InitManual, UI)
          local manualFailure
          if not manualOK then manualFailure = SafeError(manualError) end
          RDL:Log(manualOK and "WARN" or "ERROR", "MINIMAP", "Fell back to manual minimap button", {
            error = manualFailure,
          })
        end
      end
    end)
  end

  if self.UpdateMinimapIconState then
    self:UpdateMinimapIconState()
  end
end

function UI:SetMinimapButtonShown(shown)
  shown = shown == true
  local settings = EnsureMinimapSettings()
  settings.minimap.hide = not shown
  settings.minimapHide = settings.minimap.hide

  if self._ldbIcon then
    if shown then
      pcall(self._ldbIcon.Show, self._ldbIcon, "RothDevLib")
    else
      pcall(self._ldbIcon.Hide, self._ldbIcon, "RothDevLib")
    end

    if self.UpdateMinimapIconState then self:UpdateMinimapIconState() end
    return
  end

  local button = self.minimapButton
  if not button then return end
  if shown then
    button:Show()
    ManualUpdatePosition(self)
  else
    StopManualDrag(button)
    button:Hide()
  end

  if self.UpdateMinimapIconState then self:UpdateMinimapIconState() end
end
