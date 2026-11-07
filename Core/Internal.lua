-- !RothDevLib/Core/Internal.lua
-- Guarded internal calls that report faults without leaking Doctor scopes.

local RDL = _G.RothDevLib
RDL.Internal = RDL.Internal or {}
local Internal = RDL.Internal

Internal._depth = 0
Internal._maxDepth = 3

local Unpack = table.unpack or unpack

local function Pack(...)
  return { n = select("#", ...), ... }
end

local function SafeText(value, fallback, maxBytes)
  fallback = fallback or "<error>"
  maxBytes = tonumber(maxBytes) or 4096

  local util = RDL.Util
  if util and type(util.SafeToString) == "function" then
    local ok, text = pcall(util.SafeToString, util, value)
    if ok and type(text) == "string" then
      if #text > maxBytes then text = text:sub(1, maxBytes) end
      return text
    end
  end

  if type(value) == "string" then
    if #value > maxBytes then return value:sub(1, maxBytes) end
    return value
  end
  return fallback
end

local function SafeDebugStack(level)
  if type(_G.debugstack) ~= "function" then return "" end
  local ok, stack = pcall(_G.debugstack, level or 2, 40, 40)
  if not ok then return "" end

  local util = RDL.Util
  if util and type(util.FilterSecretEscapes) == "function" then
    local okFilter, filtered = pcall(util.FilterSecretEscapes, util, stack)
    if okFilter and type(filtered) == "string" then return filtered end
  end
  return type(stack) == "string" and stack or ""
end

local function EnterDoctor(addonHint, funcName)
  local doctor = RDL.Doctor
  if not (doctor and type(doctor.Enter) == "function") then return nil end

  local ok, token = pcall(doctor.Enter, doctor, RDL.addonName, funcName, {
    internal = true,
    hint = addonHint,
  })
  if ok then return token end
  return nil
end

local function LeaveDoctor(token)
  if token == nil then return end
  local doctor = RDL.Doctor
  if doctor and type(doctor.Leave) == "function" then
    pcall(doctor.Leave, doctor, token)
  end
end

function Internal:Call(addonHint, funcName, fn, ...)
  if type(fn) ~= "function" then
    return false, "Internal.Call: fn is not a function"
  end
  funcName = SafeText(funcName, "Internal", 256)

  if (self._depth or 0) >= (self._maxDepth or 3) then
    return pcall(fn, ...)
  end

  self._depth = (self._depth or 0) + 1
  local doctorToken = EnterDoctor(addonHint, funcName)
  local args = Pack(...)

  local function ErrorHandler(err)
    local stack = SafeDebugStack(3)
    local locals, localsMeta

    if RDL.Locals and type(RDL.Locals.CaptureBest) == "function" then
      local ok, captured, meta = pcall(RDL.Locals.CaptureBest, RDL.Locals, {
        addon = addonHint or RDL.addonName,
        stack = stack,
        baseLevel = 2,
      })
      if ok then
        locals = captured
        localsMeta = meta
      end
    end

    local safeError = SafeText(err, "<error>", 4096)
    if RDL.Capture and type(RDL.Capture.OnSuppressedError) == "function" then
      pcall(RDL.Capture.OnSuppressedError, RDL.Capture, safeError, stack, locals,
        addonHint, funcName, {
          internal = true,
          source = "internal",
          localsProbe = localsMeta,
        })
    elseif _G.DEFAULT_CHAT_FRAME and type(_G.DEFAULT_CHAT_FRAME.AddMessage) == "function" then
      pcall(_G.DEFAULT_CHAT_FRAME.AddMessage, _G.DEFAULT_CHAT_FRAME,
        "|cffff3333RothDevLib|r internal error: " .. safeError)
    end

    return safeError
  end

  -- Keep xpcall portable: explicit packed arguments preserve nils without
  -- relying on runtime-specific xpcall vararg forwarding.
  local function InvokeTarget()
    return fn(Unpack(args, 1, args.n))
  end

  -- The outer pcall contains failures in the profiling layer itself. Target
  -- failures are represented by the inner xpcall boolean.
  local result = Pack(pcall(function()
    local cpu = RDL.CPU
    if cpu and type(cpu.Measure) == "function" then
      return cpu:Measure(addonHint or RDL.addonName, funcName, function()
        return xpcall(InvokeTarget, ErrorHandler)
      end, { sampleRate = 1.0 })
    end
    return xpcall(InvokeTarget, ErrorHandler)
  end))

  LeaveDoctor(doctorToken)
  self._depth = math.max(0, (self._depth or 1) - 1)

  if not result[1] then
    return false, SafeText(result[2], "Internal.Call infrastructure failure", 4096)
  end

  local targetOK = result[2]
  if targetOK then
    return true, Unpack(result, 3, result.n)
  end
  return false, result[3]
end
