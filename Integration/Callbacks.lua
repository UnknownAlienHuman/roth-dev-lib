-- !RothDevLib/Integration/Callbacks.lua
-- Small callback registry with detached payloads and defined mutation semantics.

local RDL = _G.RothDevLib
if not RDL then return end

RDL._callbacks = RDL._callbacks or {}

local Unpack = table.unpack or unpack
local MAX_CALLBACK_ARGS = 32

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

local function SnapshotValue(value)
  local util = RDL.Util
  if util and type(util.CopyDiagnosticValue) == "function" then
    local ok, copy = pcall(util.CopyDiagnosticValue, util, value, {
      maxDepth = 5,
      maxEntries = 160,
      maxStringBytes = 8192,
    })
    if ok then return copy end
  end

  if util and type(util.Scrub) == "function" then
    local ok, ordinary = pcall(util.Scrub, util, value)
    if ok then return ordinary end
  end
  return "<unavailable>"
end

local function SnapshotArgs(...)
  local count = select("#", ...)
  if count > MAX_CALLBACK_ARGS then count = MAX_CALLBACK_ARGS end

  local args = { n = count }
  for index = 1, count do
    args[index] = SnapshotValue(select(index, ...))
  end
  return args
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

local function CallCallback(eventName, key, fn, args)
  if RDL.Internal and type(RDL.Internal.Call) == "function" then
    return RDL.Internal:Call(nil,
      ("Callback:%s:%s"):format(eventName, key), fn, Unpack(args, 1, args.n))
  end
  return pcall(fn, Unpack(args, 1, args.n))
end

function RDL:Fire(eventName, ...)
  eventName = OrdinaryString(eventName, 128)
  if not eventName then return 0 end

  local callbacks = self._callbacks and self._callbacks[eventName]
  if type(callbacks) ~= "table" then return 0 end

  -- Snapshot the current registrations. New callbacks wait for the next Fire;
  -- callbacks unregistered or replaced before their turn are skipped.
  local pending = {}
  for key, fn in next, callbacks do
    if type(key) == "string" and Callable(fn) then
      pending[#pending + 1] = { key = key, fn = fn }
    end
  end
  table.sort(pending, function(a, b) return a.key < b.key end)

  local invoked = 0
  for index = 1, #pending do
    local record = pending[index]
    if callbacks[record.key] == record.fn then
      -- Every callback gets its own detached copy. One consumer cannot mutate
      -- the payload observed by another callback or the source DB/bus state.
      local args = SnapshotArgs(...)
      local ok = CallCallback(eventName, record.key, record.fn, args)
      invoked = invoked + 1

      if ok == false and callbacks[record.key] == record.fn then
        callbacks[record.key] = nil
        if self.Log then
          pcall(self.Log, self, "ERROR", "CALLBACK", "Callback disabled after error", {
            event = eventName,
            key = record.key,
          })
        end
      end
    end
  end

  if next(callbacks) == nil then self._callbacks[eventName] = nil end
  return invoked
end
