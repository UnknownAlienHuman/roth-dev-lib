-- !RothDevLib/UI/MinimapButton.lua
-- Minimap icon (BugSack-style entrypoint).
-- Ported from RothDevLib/UI/MinimapButton.lua (no functional changes).
-- Preferred: LibDataBroker-1.1 + LibDBIcon-1.0 (embedded in /libs).
-- Fallback: simple custom minimap button.

local RDL = _G.RothDevLib
RDL.UI = RDL.UI or {}
local UI = RDL.UI

-- NOTE: WoW texture paths are safest with backslashes.
local ICON_PATH = "Interface\\AddOns\\!RothDevLib\\Media\\bug"

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
    -- "Bug is red" state.
    return 1, 0.20, 0.20
  end
  return 1, 1, 1
end


local function FormatCount(n)
  n = tonumber(n) or 0
  if n <= 0 then return "" end
  if n >= 100 then return "99+" end
  return tostring(n)
end

local function EnsureCountText(btn)
  if not btn or btn.countText then return end
  local fs = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  fs:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
  fs:SetJustifyH("RIGHT")
  fs:SetJustifyV("BOTTOM")
  fs:SetText("")
  fs:SetTextColor(1, 1, 1)
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 1)
  btn.countText = fs
end

local function SetCountText(btn, n)
  if not btn then return end
  EnsureCountText(btn)
  if not btn.countText then return end
  local t = FormatCount(n)
  btn.countText:SetText(t)
  if t == "" then
    btn.countText:Hide()
  else
    btn.countText:Show()
    -- red-ish if there are issues, otherwise white (shouldn't show on 0 anyway)
    btn.countText:SetTextColor(1, 0.3, 0.3)
  end
end

local function GetSettings()
  return (RDL.DB and RDL.DB:GetSettings()) or (_G.RothDevLibDB and _G.RothDevLibDB.settings) or {}
end

local function EnsureMinimapSettings()
  local s = GetSettings()
  s.minimap = s.minimap or { hide = false, minimapPos = 225 }

  if RDL.DB and RDL.DB.GetSettings then
    local settings = RDL.DB:GetSettings()
    if settings and settings.minimapForceShowOnNextLogin then
      s.minimap.hide = false
      settings.minimapForceShowOnNextLogin = false
    end
  end

  if s.minimap.hide == nil and s.minimapHide ~= nil then
    s.minimap.hide = s.minimapHide
  end
  if s.minimap.minimapPos == nil then
    s.minimap.minimapPos = s.minimapAngle or 225
  end

  s.minimapHide = (s.minimap.hide == true)
  s.minimapAngle = s.minimap.minimapPos
  return s
end

local function TooltipLines(tt)
  tt:AddLine("RothDevLib", 1, 1, 1)
  local n = GetActiveIssueCount()
  if n > 0 then
    tt:AddLine(string.format("Active issues: %d", n), 1, 0.3, 0.3)
  else
    tt:AddLine("No issues", 0.5, 1, 0.5)
  end
  tt:AddLine("Left click: open bag", 0.8, 0.8, 0.8)
  tt:AddLine("Right click: export all", 0.8, 0.8, 0.8)
  tt:AddLine("Shift+Right: open log", 0.8, 0.8, 0.8)
  local owned = (RDL.Capture and RDL.Capture.ownsHandler) and "owned" or "not-owned"
  tt:AddLine("Errorhandler: " .. owned, 0.8, 0.8, 0.8)
end

-- Public: set minimap icon color based on current DB state.
function UI:UpdateMinimapIconState()
  local n = GetActiveIssueCount()
  local r, g, b = GetIconColor(n)

  -- LDB icon
  if self._ldbInited then
    local btn = _G["LibDBIcon10_RothDevLib"]
    if btn and btn.icon then
      -- Some UI packs / reload paths can lose the texture; force it.
      btn.icon:SetTexture(ICON_PATH)
      btn.icon:SetVertexColor(r, g, b)
      SetCountText(btn, n)
    end
    if self._ldbObj then
      -- Store for later button recreation
      self._ldbObj.iconR, self._ldbObj.iconG, self._ldbObj.iconB = r, g, b
    end
  end

  -- Manual icon
  if self.minimapButton and self.minimapButton.icon then
    -- Ensure texture stays valid
    self.minimapButton.icon:SetTexture(ICON_PATH)
    self.minimapButton.icon:SetVertexColor(r, g, b)
    SetCountText(self.minimapButton, n)
  end
end

local function InitLDB(self)
  if self._ldbInited then return true end
  if not _G.LibStub then return false end

  local LDB = LibStub("LibDataBroker-1.1", true)
  local LDBIcon = LibStub("LibDBIcon-1.0", true)
  if not (LDB and LDBIcon) then return false end

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
          else
            if UI and UI.OpenExportAll then UI:OpenExportAll() end
          end
        end
      end,
      OnTooltipShow = function(tt)
        TooltipLines(tt)
      end,
    })
  end

  if not self._ldbRegistered then
    LDBIcon:Register("RothDevLib", self._ldbObj, settings.minimap)
    self._ldbRegistered = true
  end

  self._ldbIcon = LDBIcon
  self._ldbInited = true

  -- Ensure the button texture exists and stays correct (some reload/UI paths lose it).
  local btn = _G["LibDBIcon10_RothDevLib"]
  if btn and not btn._rdlHooked then
    btn._rdlHooked = true
    pcall(function()
      btn:HookScript("OnShow", function()
        if UI and UI.UpdateMinimapIconState then UI:UpdateMinimapIconState() end
      end)
    end)
  end

  if settings.minimap.hide then
    LDBIcon:Hide("RothDevLib")
  else
    LDBIcon:Show("RothDevLib")
  end

  -- Apply current state color (0 issues => normal, >0 => red).
  if UI and UI.UpdateMinimapIconState then
    pcall(function() UI:UpdateMinimapIconState() end)
  end
  return true
end

local function ClampAngle(a)
  if type(a) ~= "number" then return 225 end
  while a < 0 do a = a + 360 end
  while a >= 360 do a = a - 360 end
  return a
end

local function ManualUpdatePosition(self)
  local b = self.minimapButton
  if not b or not _G.Minimap then return end
  local s = EnsureMinimapSettings()
  local angle = ClampAngle(s.minimap.minimapPos or 225)
  local rad = math.rad(angle)
  local r = 78
  local x = math.cos(rad) * r
  local y = math.sin(rad) * r
  b:ClearAllPoints()
  b:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end

local function InitManual(self)
  if self.minimapButton or not _G.Minimap then return true end

  local b = CreateFrame("Button", "RothDevLibMinimapButton", _G.Minimap)
  self.minimapButton = b
  b:SetSize(31, 31)
  b:SetFrameStrata("HIGH")
  b:SetFrameLevel(20)
  b:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")

  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetAllPoints()
  icon:SetTexture(ICON_PATH)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.icon = icon
  SetCountText(b, GetActiveIssueCount())

  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetAllPoints()
  border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
  b.border = border

  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, btn)
    if btn == "LeftButton" then
      if UI and UI.Toggle then UI:Toggle() end
    elseif btn == "RightButton" then
      if IsShiftKeyDown() then
        if UI and UI.OpenLog then UI:OpenLog() end
      else
        if UI and UI.OpenExportAll then UI:OpenExportAll() end
      end
    end
  end)

  b:SetScript("OnEnter", function(selfBtn)
    GameTooltip:SetOwner(selfBtn, "ANCHOR_LEFT")
    TooltipLines(GameTooltip)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  b:RegisterForDrag("LeftButton")
  b:SetMovable(true)
  b:SetScript("OnDragStart", function(selfBtn)
    selfBtn:SetScript("OnUpdate", function()
      local mx, my = _G.Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = UIParent:GetScale()
      cx, cy = cx / scale, cy / scale
      local dx, dy = cx - mx, cy - my
      local angle = math.deg(math.atan(dy, dx))
      local s = EnsureMinimapSettings()
      s.minimap.minimapPos = ClampAngle(angle)
      s.minimapAngle = s.minimap.minimapPos
      ManualUpdatePosition(UI)
    end)
  end)
  b:SetScript("OnDragStop", function(selfBtn)
    selfBtn:SetScript("OnUpdate", nil)
  end)

  local s = EnsureMinimapSettings()
  if s.minimap.hide then
    b:Hide()
  else
    b:Show()
  end
  ManualUpdatePosition(UI)

  if UI and UI.UpdateMinimapIconState then
    pcall(function() UI:UpdateMinimapIconState() end)
  end
  return true
end

function UI:InitMinimapButton()
  if self._minimapInited then return end
  self._minimapInited = true

  local ok = false
  local okInit, res = pcall(function() return InitLDB(self) end)
  ok = okInit and res

  if not ok then
    pcall(function() InitManual(self) end)
  end

  local s = EnsureMinimapSettings()
  RDL:Log("INFO", "MINIMAP", "Minimap init", {
    usedLDB = (self._ldbInited == true),
    hide = s.minimap.hide,
    pos = s.minimap.minimapPos,
  })

  if C_Timer then
    C_Timer.After(1.0, function()
      local settings = EnsureMinimapSettings()

      if UI._ldbInited then
        local btn = _G["LibDBIcon10_RothDevLib"]

        if not btn and UI._ldbRegistered and UI._ldbObj then
          UI._ldbRegistered = false
          local ok2 = pcall(function() InitLDB(UI) end)
          btn = _G["LibDBIcon10_RothDevLib"]
          RDL:Log(ok2 and "INFO" or "WARN", "MINIMAP", "LDB re-register", { buttonNow = (btn ~= nil) })
        end

        if btn and (not settings.minimap.hide) and (not btn:IsShown()) and UI._ldbIcon then
          pcall(function() UI._ldbIcon:Show("RothDevLib") end)
        end

        if (not btn) and (not UI.minimapButton) then
          pcall(function() InitManual(UI) end)
          RDL:Log("WARN", "MINIMAP", "Fell back to manual minimap button", {})
        end
      end
    end)
  end

  if self.UpdateMinimapIconState then
    pcall(function() self:UpdateMinimapIconState() end)
  end
end

function UI:SetMinimapButtonShown(shown)
  local s = EnsureMinimapSettings()
  s.minimap.hide = not shown
  s.minimapHide = s.minimap.hide

  if self._ldbIcon then
    if shown then
      self._ldbIcon:Show("RothDevLib")
    else
      self._ldbIcon:Hide("RothDevLib")
    end

    if self.UpdateMinimapIconState then
      pcall(function() self:UpdateMinimapIconState() end)
    end
    return
  end

  local b = self.minimapButton
  if not b then return end
  if shown then
    b:Show()
    ManualUpdatePosition(self)
  else
    b:Hide()
  end

  if self.UpdateMinimapIconState then
    pcall(function() self:UpdateMinimapIconState() end)
  end
end
