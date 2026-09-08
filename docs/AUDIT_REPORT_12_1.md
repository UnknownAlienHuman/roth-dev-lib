# Retail 12.1 Audit & Pull Request Report: `!RothDevLib`

**Target Addon:** `!RothDevLib`  
**Location:** `C:\Development\WoWDevAddons\_Addons\!RothDevLib`  
**Remote:** `github-roth-dev-lib` (`https://github.com/UnknownAlienHuman/roth-dev-lib.git`)  
**Target Retail Version:** 12.1 (Interface `120100`, build `69497`)  
**Audit Date:** 2026-09-08  
**Auditor:** AntiGravity WoW Addon Audit Subagent  

---

## 1. Executive Summary & Current State

`!RothDevLib` is the central developer diagnostics, error capture, and feedback framework within the Neomorph suite. It is designed to run earliest in the load chain (indicated by the `!` directory prefix) to establish error interception, Doctor execution context, and cross-addon communication ring buffers.

### Architecture & Load Hierarchy
- **Vendored Embeds:** Loaded in `.toc` before any addon code:
  - `libs/LibStub`
  - `libs/CallbackHandler-1.0`
  - `libs/LibDataBroker-1.1`
  - `libs/LibDBIcon-1.0`
- **Core Subsystems:**
  - `Core/Core.lua`: Global singleton `_G.RothDevLib` (`RDL`), API fingerprints, and safe execution wrappers (`SafeCall`, `SafeCallCtx`, `WrapSafe`, `WrapUnsafe`).
  - `Core/DB.lua`: SavedVariables manager for `RothDevLibDB` (sessions, error groups, ignore lists, trimming).
  - `Core/Internal.lua`: Protected internal caller protecting framework operations.
  - `Core/Events.lua`: Lifecycle bootstrap (`ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_LOGOUT`, `PLAYER_REGEN_ENABLED`).
- **Capture Pipeline:**
  - `Capture/ErrorHandler.lua`: Global error handler ownership (`geterrorhandler` / `seterrorhandler`), chain and exclusive modes, fallback capture via Blizzard `ScriptErrorsFrame` and `BugGrabberDB`.
  - `Capture/Locals.lua`: Heuristic `debuglocals` level calibration and filtering.
  - `Capture/ChatTap.lua`: Reconstructs error stacks from addons that swallow errors in custom xpcall blocks and print to chat.
  - `Capture/Storm.lua`: Token-bucket rate limiter for flood protection.
  - `Capture/Warnings.lua`: LUA_WARNING interception with multi-signature support.
  - `Capture/Taint.lua`: Traps `ADDON_ACTION_BLOCKED`, `ADDON_ACTION_FORBIDDEN`, and `ADDON_RESTRICTION_STATE_CHANGED`.
  - `Capture/Suppress.lua`: Hides Blizzard error dialogs and popups.
- **Diagnostics & Context:**
  - `Doctor/Doctor.lua`, `Doctor/Breadcrumbs.lua`, `Doctor/Validation.lua`: Correlation stack tracking what addon function was executing when a failure occurred.
  - `Integration/Bus.lua`, `Integration/API.lua`: Ring-buffer bus and public integration APIs (`RDL:InitAddon`, `Breadcrumb`, `Metric`, `Alert`, `Assert`).
  - `Export/Export.lua`, `Export/Packer.lua`: Bounded JSON, packed share strings, and GitHub issue exports.
  - `UI/*`: Blizzard `ButtonFrameTemplate` and `DropdownButton` UI, minimap icon, and `/rdev` slash command dispatch.

---

## 2. Remote GitHub Synchronization Analysis

A comparison between local monorepo HEAD (`HEAD:_Addons/!RothDevLib`) and the upstream remote (`remotes/github-roth-dev-lib/main`) was conducted:

```powershell
git diff --stat "HEAD:_Addons/!RothDevLib" "remotes/github-roth-dev-lib/main"
```

### Differences Discovered:
- **`docs/TODO_LEGACY_alpha19.md`**:
  - Upstream commit `9f1e2bbfe1b7bcf33a28d7981605f80d1977ca64` (*"Retire obsolete legacy planning dump"*, Sat Aug 29 2026) truncated this 1,767-line document down to a 5-line pointer referencing Git history.
  - The local repository still retains the unpruned 1,767 lines.
- **Codebase Parity**:
  - All core Lua files (`Core/*`, `Capture/*`, `Doctor/*`, `Integration/*`, `UI/*`, `Util/*`, `Perf/*`, `Export/*`) are identical between the local tree and upstream GitHub.
  - **Neither upstream nor local has yet implemented Retail 12.1 updates.**

---

## 3. Retail 12.1 Audit Findings & Risk Analysis

### 3.1. Interface Version Compatibility
- **Issue:** `!RothDevLib.toc` specifies:
  ```toc
  ## Interface: 120001, 120005
  ```
- **Risk:** In Retail 12.1 (Interface `120100`), the client marks the addon as out of date unless loaded with outdated addons enabled.
- **Remediation:** Update TOC to include `120100`.

### 3.2. Broken Chat Hyperlink Dispatch in Modern Retail (`LinkUtil` vs `SetItemRef`)
- **Location:** `UI/Hyperlink.lua:30-45`
- **Issue:** In `UI/Hyperlink.lua`, the addon registers:
  ```lua
  _G.SetItemRef_rothdevlib = function(link, text, button, chatFrame)
  ```
  In Retail 11.x and 12.x, Blizzard re-architected hyperlink processing in `ItemRef.lua` using `LinkUtil.ProcessLink(link, text, contextData)`. Blizzard's `SetItemRef` **no longer calls** `_G["SetItemRef_" .. linkType]`. When an unhandled link type is clicked, Blizzard routes the link into `ItemRefTooltip:ItemRefSetHyperlink(link)`!
- **Impact:** Clicking `[open]` in error notifications (e.g. `RothDevLib captured Lua error. [open] Use /rdev`) completely fails to open `!RothDevLib`. Instead, an empty or broken `ItemRefTooltip` is displayed.
- **Remediation:** Register with `LinkUtil.RegisterLinkHandler("rothdevlib", handler)` when `LinkUtil` is present, while preserving `_G.SetItemRef_rothdevlib` for backwards compatibility.

### 3.3. RT-AUDIT-001: SavedVariables Default Mutation by Reference
- **Location:** `Core/DB.lua:118-156`
- **Issue:**
  ```lua
  for k, v in pairs(DEFAULTS.settings) do
    if db.settings[k] == nil then db.settings[k] = v end
  end
  ```
  When `db.settings[k]` is missing, table values (e.g., `minimap = { hide = false, ... }`, `uiGroupGridCols = { ... }`, `uiFrames = {}`) are assigned directly by reference from `DEFAULTS.settings`. Any subsequent in-game setting modification (such as moving the minimap button or dragging grid columns) directly mutates the master `DEFAULTS` table.
  Additionally, `deepCopy` implements a shallow cutoff: `if depth > 3 then return {} end`, which truncates any complex nested structures beyond depth 3 into empty tables.
- **Remediation:** Ensure all table default insertions use a robust deep copy (`type(v) == "table" and deepCopy(v) or v`) and expand recursion depth to 10.

### 3.4. RT-AUDIT-002: Single Runtime Owner & Redundant Event Frames
- **Location:** `Capture/ErrorHandler.lua:708-720` vs `Core/Events.lua:84-112`
- **Issue:**
  In `Capture/ErrorHandler.lua`, when fallback hooks are installed, an ad-hoc event frame is created:
  ```lua
  local waiter = CreateFrame("Frame")
  waiter:RegisterEvent("ADDON_LOADED")
  waiter:SetScript("OnEvent", function(_, _, addon)
    if addon == "Blizzard_DebugTools" or addon == "Blizzard_ScriptErrorsFrame" or addon == "Blizzard_ScriptErrors" then ...
  ```
  Meanwhile, `Core/Events.lua` is already the central event listener for `ADDON_LOADED`, but only invokes `Suppress:SuppressAll()` without notifying `Capture:InstallFallbackHooks()`. This creates competing `ADDON_LOADED` listeners across different files.
- **Remediation:** Consolidate `ADDON_LOADED` dispatch in `Core/Events.lua` to notify both `Suppress` and `Capture:InstallFallbackHooks()`, eliminating the anonymous `waiter` frame.

### 3.5. Security & UI Taint Risk in Frame Suppression
- **Location:** `Capture/Suppress.lua:37-42`
- **Issue:**
  ```lua
  if not f._RDLWrapped then
    f._RDL_OrigShow = f.Show
    f.Show = function(self, ...) self:Hide() end
    f:HookScript("OnShow", function(self) self:Hide() end)
    f._RDLWrapped = true
  end
  ```
  Overwriting `ScriptErrorsFrame.Show` with a custom Lua closure directly mutates the Blizzard frame method table, causing taint contamination across Blizzard UI code whenever `Show()` is called.
- **Remediation:** Remove the destructive `f.Show` method override; rely purely on `f:HookScript("OnShow", f.Hide)` and `f:Hide()`, which is standard, safe, and taint-free.

### 3.6. Lua 5.1 `math.atan` vs `math.atan2` Coordinate Calculation Bug
- **Location:** `UI/MinimapButton.lua:277`
- **Issue:**
  ```lua
  local angle = math.deg(math.atan(dy, dx))
  ```
  In WoW's Lua 5.1 environment, `math.atan` takes exactly 1 argument; the second argument `dx` is completely ignored! This causes manual minimap dragging calculations to produce incorrect angular positions.
- **Remediation:** Use `(math.atan2 or math.atan)(dy, dx)`.

### 3.7. 12.1 Aura API & Secret Value Review
- **UnitAura / AuraContainer:** `!RothDevLib` does not inspect player or target auras. It acts strictly as an execution observer and diagnostic bus. No direct `UnitAura` migration is required.
- **Secret Values & Restrictions:** `Util/SecretGuard.lua` correctly guards calls using `issecretvalue()` and `canaccessvalue()`. `InCombatLockdown()` is strictly honored before emitting chat notifications or modifying UI elements.

---

## 4. Proposed Pull Request Patches

### Patch 1: TOC Interface Update (`!RothDevLib.toc`)
```diff
--- a/_Addons/!RothDevLib/!RothDevLib.toc
+++ b/_Addons/!RothDevLib/!RothDevLib.toc
@@ -1,4 +1,4 @@
-## Interface: 120001, 120005
+## Interface: 120100, 120001, 120005
 ## Title: !RothDevLib
 ## Notes: LLM-oriented feedback bus for WoW addon development. Error capture + Doctor context + breadcrumbs + structured export.
 ## Author: Neomorph
```

---

### Patch 2: RT-AUDIT-001 SavedVariables Default Deep Copy (`Core/DB.lua`)
```diff
--- a/_Addons/!RothDevLib/Core/DB.lua
+++ b/_Addons/!RothDevLib/Core/DB.lua
@@ -120,7 +120,7 @@ function DB:Init()
   local function deepCopy(v, depth)
     depth = depth or 0
     if type(v) ~= "table" then return v end
-    if depth > 3 then return {} end
+    if depth > 10 then return {} end
     local t = {}
     for k2, v2 in pairs(v) do t[k2] = deepCopy(v2, depth + 1) end
     return t
@@ -151,7 +151,9 @@ function DB:Init()
   merge(db.settings, DEFAULTS.settings)
 
   for k, v in pairs(DEFAULTS.settings) do
-    if db.settings[k] == nil then db.settings[k] = v end
+    if db.settings[k] == nil then
+      db.settings[k] = (type(v) == "table" and deepCopy(v) or v)
+    end
   end
 
   -- Schema version
```

---

### Patch 3: RT-AUDIT-002 Centralize Fallback Event Dispatch (`Core/Events.lua` & `Capture/ErrorHandler.lua`)
```diff
--- a/_Addons/!RothDevLib/Core/Events.lua
+++ b/_Addons/!RothDevLib/Core/Events.lua
@@ -103,9 +103,12 @@ frame:SetScript("OnEvent", function(_, event, ...)
         ICall("Capture:FlushBootQueue", RDL.Capture.FlushBootQueue, RDL.Capture)
       end
 
-    elseif name == "Blizzard_DebugTools" then
+    elseif name == "Blizzard_DebugTools" or name == "Blizzard_ScriptErrorsFrame" or name == "Blizzard_ScriptErrors" then
       -- ScriptErrorsFrame becomes available when DebugTools loads.
       if RDL.Suppress and RDL.Suppress.SuppressAll then
         ICall("Suppress:SuppressAll", RDL.Suppress.SuppressAll, RDL.Suppress)
       end
+      if RDL.Capture and RDL.Capture.InstallFallbackHooks then
+        ICall("Capture:InstallFallbackHooks", RDL.Capture.InstallFallbackHooks, RDL.Capture)
+      end
     end
```

```diff
--- a/_Addons/!RothDevLib/Capture/ErrorHandler.lua
+++ b/_Addons/!RothDevLib/Capture/ErrorHandler.lua
@@ -706,17 +706,6 @@ function Capture:InstallFallbackHooks()
     if hooked then
       self._fallback.scriptErrorsHooked = true
     elseif not self._fallback.waitingScriptErrors then
-      -- If ScriptErrors modules are not loaded yet, retry after they load.
       self._fallback.waitingScriptErrors = true
-      local waiter = CreateFrame("Frame")
-      waiter:RegisterEvent("ADDON_LOADED")
-      waiter:SetScript("OnEvent", function(_, _, addon)
-        if addon == "Blizzard_DebugTools" or addon == "Blizzard_ScriptErrorsFrame" or addon == "Blizzard_ScriptErrors" then
-          waiter:UnregisterEvent("ADDON_LOADED")
-          waiter:SetScript("OnEvent", nil)
-          if Capture and Capture.InstallFallbackHooks then
-            pcall(function() Capture:InstallFallbackHooks() end)
-          end
-        end
-      end)
     end
   end
```

---

### Patch 4: Remove Destructive Method Overwrite in Frame Suppression (`Capture/Suppress.lua`)
```diff
--- a/_Addons/!RothDevLib/Capture/Suppress.lua
+++ b/_Addons/!RothDevLib/Capture/Suppress.lua
@@ -35,9 +35,7 @@ function Suppress:SuppressScriptErrorsFrame()
   local f = _G.ScriptErrorsFrame
   if not f then return end
   f:Hide()
   if not f._RDLWrapped then
-    f._RDL_OrigShow = f.Show
-    f.Show = function(self, ...) self:Hide() end
     f:HookScript("OnShow", function(self) self:Hide() end)
     f._RDLWrapped = true
   end
```

---

### Patch 5: Modern Retail `LinkUtil` Hyperlink Registration (`UI/Hyperlink.lua`)
```diff
--- a/_Addons/!RothDevLib/UI/Hyperlink.lua
+++ b/_Addons/!RothDevLib/UI/Hyperlink.lua
@@ -28,8 +28,29 @@ local function ParseSig(link)
   return nil
 end
 
--- Handler entry point used by Blizzard hyperlink dispatch.
--- SetItemRef() will call SetItemRef_<linkType> if it exists.
+local function OnHyperlinkActivated(sig)
+  if not sig or sig == "" then return end
+  if UI and UI.OpenToSig then
+    pcall(function() UI:OpenToSig(sig) end)
+  elseif UI and UI.Open then
+    pcall(function() UI:Open() end)
+  end
+end
+
+-- Modern Retail (11.0+, 12.0+) LinkUtil registration
+if _G.LinkUtil and type(_G.LinkUtil.RegisterLinkHandler) == "function" then
+  pcall(function()
+    if not _G.LinkUtil.IsLinkHandlerRegistered or not _G.LinkUtil.IsLinkHandlerRegistered("rothdevlib") then
+      _G.LinkUtil.RegisterLinkHandler("rothdevlib", function(link, text, linkData, contextData)
+        local sig = ParseSig(link)
+        OnHyperlinkActivated(sig)
+        return _G.LinkProcessorResponse and _G.LinkProcessorResponse.Handled or 2
+      end)
+    end
+  end)
+end
+
+-- Legacy fallback for pre-11.0 environments or unhandled fallthrough
 _G.SetItemRef_rothdevlib = function(link, text, button, chatFrame)
   local sig = ParseSig(link)
-  if not sig or sig == "" then return end
-
-  if UI and UI.OpenToSig then
-    pcall(function() UI:OpenToSig(sig) end)
-  elseif UI and UI.Open then
-    pcall(function() UI:Open() end)
-  end
+  OnHyperlinkActivated(sig)
 
   -- Avoid showing item-ref tooltip for our links.
   if _G.ItemRefTooltip and _G.ItemRefTooltip:IsShown() then
```

---

### Patch 6: Fix `math.atan` Angle Calculation in Minimap Dragging (`UI/MinimapButton.lua`)
```diff
--- a/_Addons/!RothDevLib/UI/MinimapButton.lua
+++ b/_Addons/!RothDevLib/UI/MinimapButton.lua
@@ -274,7 +274,8 @@ local function InitManual(self)
       local scale = UIParent:GetScale()
       cx, cy = cx / scale, cy / scale
       local dx, dy = cx - mx, cy - my
-      local angle = math.deg(math.atan(dy, dx))
+      local atan2 = math.atan2 or math.atan
+      local angle = math.deg(atan2(dy, dx))
       local s = EnsureMinimapSettings()
       s.minimap.minimapPos = ClampAngle(angle)
       s.minimapAngle = s.minimap.minimapPos
```

---

### Patch 7: Align with Upstream Legacy Pruning (`docs/TODO_LEGACY_alpha19.md`)
```diff
--- a/_Addons/!RothDevLib/docs/TODO_LEGACY_alpha19.md
+++ b/_Addons/!RothDevLib/docs/TODO_LEGACY_alpha19.md
@@ -1,1767 +1,5 @@
-# !RothDevLib — Legacy TODO Dump (alpha.19)
-
-> Archived planning dump from pre-alpha.19 iterations.
-> Canonical work-in-progress is in `todo.md`.
-
-Use Git history only for regression archaeology.
```

---

## 5. Verification Plan & Test Commands

1. **Manifest & Static Consistency:**
   ```powershell
   pwsh -File .\tools\audit-addon-architecture.ps1 -Check
   pwsh -File .\tools\test-addon-architecture-docs.ps1
   ```
2. **In-Game Functionality Matrix:**
   - Run `/rdev status` -> Verify database readiness and error handler ownership (`owned` / `chain`).
   - Run `/rdev test error` -> Verify hard error is captured, throttled, and clickable link `[open]` is emitted into chat.
   - Click `[open]` link in chat -> Confirm `!RothDevLib` main window opens directly to the newly generated signature.
   - Drag manual minimap button -> Verify smooth circular positioning around minimap edge.
   - Run `/rdev gate` -> Ensure release gate reports `PASS` with 0 self-taint blocked/forbidden actions.
