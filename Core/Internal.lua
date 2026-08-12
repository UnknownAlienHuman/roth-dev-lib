-- !RothDevLib/Core/Internal.lua
-- Internal self-diagnostics helpers.
-- Goal: NEVER silently swallow errors inside !RothDevLib itself.
-- We still protect execution (no hard crash), but report failures into the Capture pipeline.

local RDL = _G.RothDevLib
RDL.Internal = RDL.Internal or {}
local I = RDL.Internal

I._depth = 0
I._maxDepth = 3

local function SafeDebugStack(level)
  local ok, s = pcall(debugstack, level or 2, 40, 40)
  if ok then return s end
  return ""
end

-- Guarded call for internal code paths.
-- addonHint: if nil, let Capture infer addon from stack.
-- funcName: string label shown in Doctor/UI.
function I:Call(addonHint, funcName, fn, ...)
  if type(fn) ~= "function" then return false, "Internal.Call: fn is not a function" end
  funcName = tostring(funcName or "Internal")

  -- Avoid recursive reporting loops.
  if (self._depth or 0) >= (self._maxDepth or 3) then
    return pcall(fn, ...)
  end

  self._depth = (self._depth or 0) + 1

  -- Doctor context for self-debug.
  if RDL.Doctor and RDL.Doctor.Enter then
    pcall(function()
      RDL.Doctor:Enter(RDL.addonName, funcName, { internal = true, hint = addonHint })
    end)
  end

  local function ErrHandler(err)
    local stack = SafeDebugStack(2)

    local locals, lmeta = nil, nil
    if RDL.Locals and RDL.Locals.CaptureBest then
      local ok2, l, m = pcall(function()
        return RDL.Locals:CaptureBest({ addon = addonHint or RDL.addonName, stack = stack, baseLevel = 2 })
      end)
      if ok2 then locals, lmeta = l, m end
    end

    if RDL.Capture and RDL.Capture.OnSuppressedError then
      -- NOTE: pass addonHint through; nil means "infer from stack".
      pcall(function()
        RDL.Capture:OnSuppressedError(err, stack, locals, addonHint, funcName, {
          internal = true,
          source = "internal",
          localsProbe = lmeta,
        })
      end)
    else
      -- Last resort: do not hard error.
      pcall(function()
        DEFAULT_CHAT_FRAME:AddMessage("|cffff3333RothDevLib|r internal error: " .. tostring(err))
      end)
    end

    return err
  end

  -- Optional CPU profiling: record internal call costs so Monitor is never empty.
  local cpu = RDL.CPU
  local ok, r1, r2, r3, r4, r5
  if cpu and cpu.Measure then
    ok, r1, r2, r3, r4, r5 = cpu:Measure(addonHint or RDL.addonName, tostring(funcName), function(...)
      return xpcall(fn, ErrHandler, ...)
    end, { sampleRate = 1.0 }, ...)
  else
    ok, r1, r2, r3, r4, r5 = xpcall(fn, ErrHandler, ...)
  end

  if RDL.Doctor and RDL.Doctor.Leave then
    pcall(function() RDL.Doctor:Leave() end)
  end

  self._depth = (self._depth or 1) - 1

  if ok then
    return true, r1, r2, r3, r4, r5
  end
  return false, r1
end

