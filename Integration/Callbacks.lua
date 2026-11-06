-- !RothDevLib/Integration/Callbacks.lua
-- Small callback registry with guarded registration and fail-closed dispatch.

local RDL = _G.RothDevLib
if not RDL then return end

RDL._callbacks = RDL._callbacks or {}

local function OrdinaryString(value, maxBytes)
  local guard = RDL.SecretGuard
  if guard and guard.CanAccess and not guard:CanAccess(value) then return nil end
  if guard and guard.IsSecret and guard:IsSecret(value) then return nil end
  if type(value) ~= "string" or value == "" then return nil end
  if #value > maxBytes then return nil end
  return value
end

local function Callable(value)
  local guard = RDL.SecretGuard
  if guard and guard.CanAccess and not guard:CanAccess(value) then return false end
  if guard and guard.IsSecret and guard:IsSecret(value) then return false end
  return type(value) == "function"
end

function RDL:RegisterCallback(eventName, key, fn)
  eventName = OrdinaryString(eventName, 128)
  key = OrdinaryString(key, 128)
  if not eventName or not key or not Callable(fn) then return false end

  local callbacks = self._callbacks[eventName]
  if type(callbacks) ~= "table" then
    callbacks = {}
    self._callbacks[eventName] = callbacks
  end
  callbacks[key] = fn
  return true
end

function RDL:UnregisterCallback(eventName, key)
  eventName = OrdinaryString(eventName, 128)
  key = OrdinaryString(key, 128)
  if not eventName or not key then return false end

  local callbacks = self._callbacks and self._callbacks[eventName]
  if type(callbacks) ~= "table" then return false end
  callbacks[key] = nil
  if next(callbacks) == nil then self._callbacks[eventName] = nil end
  return true
end

local function CallCallback(eventName, key, fn, ...)
  if RDL.Internal and type(RDL.Internal.Call) == "function" then
    return RDL.Internal:Call(nil, ("Callback:%s:%s"):format(eventName, key), fn, ...)
  end
  return pcall(fn, ...)
end

function RDL:Fire(eventName, ...)
  eventName = OrdinaryString(eventName, 128)
  if not eventName then return end

  local callbacks = self._callbacks and self._callbacks[eventName]
  if type(callbacks) ~= "table" then return end

  for key, fn in pairs(callbacks) do
    local ok
    if self.Util and self.Util.ScrubVarargs then
      ok = CallCallback(eventName, key, fn, self.Util:ScrubVarargs(...))
    else
      ok = CallCallback(eventName, key, fn, ...)
    end

    if ok == false then
      callbacks[key] = nil
      if self.Log then
        pcall(self.Log, self, "ERROR", "CALLBACK", "Callback disabled after error", {
          event = eventName,
          key = key,
        })
      end
    end
  end

  if next(callbacks) == nil then self._callbacks[eventName] = nil end
end
