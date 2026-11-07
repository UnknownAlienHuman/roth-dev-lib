-- !RothDevLib/Integration/Callbacks.lua
-- Small bounded callback registry with detached payloads and defined mutation semantics.

local RDL = _G.RothDevLib
if not RDL then return end

RDL._callbacks = RDL._callbacks or {}

local Unpack = table.unpack or unpack
local MAX_CALLBACK_ARGS = 32
local MAX_CALLBACK_EVENTS = 128
local MAX_CALLBACKS_PER_EVENT = 128
local MAX_CALLBACKS_TOTAL = 512
local MAX_CALLBACK_PAYLOAD_BYTES = 64 * 1024

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

local function Registry(self)
  local callbacks = type(self._callbacks) == "table" and self._callbacks or {}
  self._callbacks = callbacks

  local registry = self._callbackRegistry
  if type(registry) == "table" and registry.owner == callbacks then return registry end

  registry = {
    owner = callbacks,
    events = 0,
    total = 0,
    perEvent = {},
    dropped = 0,
  }
  for eventName, eventCallbacks in next, callbacks do
    if type(eventName) == "string" and type(eventCallbacks) == "table" then
      local count = 0
      for _, fn in next, eventCallbacks do
        if Callable(fn) then count = count + 1 end
      end
      if count > 0 then
        registry.events = registry.events + 1
        registry.total = registry.total + count
        registry.perEvent[eventName] = count
      end
    end
  end
  self._callbackRegistry = registry
  return registry
end

local function Drop(registry)
  registry.dropped = (tonumber(registry.dropped) or 0) + 1
  return false
end

local function SnapshotFallback(value)
  local util = RDL.Util
  if util and type(util.Scrub) == "function" then
    local ok, ordinary = pcall(util.Scrub, util, value)
    if ok then
      local valueType = type(ordinary)
      if valueType == "string" then
        if #ordinary > 8192 then return ordinary:sub(1, 8192) .. "<truncated>" end
        return ordinary
      end
      if ordinary == nil or valueType == "number" or valueType == "boolean" then
        return ordinary
      end
      return "<" .. valueType .. ">"
    end
  end
  return "<unavailable>"
end

local function SnapshotArgs(...)
  local count = select("#", ...)
  if count > MAX_CALLBACK_ARGS then count = MAX_CALLBACK_ARGS end

  -- Copy the complete argument tuple through one budget. A per-argument budget
  -- lets 32 independently large values multiply retained allocation before a
  -- callback even begins.
  local source = { n = count }
  for index = 1, count do source[index] = select(index, ...) end

  local util = RDL.Util
  if util and type(util.CopyDiagnosticValue) == "function" then
    local ok, copy = pcall(util.CopyDiagnosticValue, util, source, {
      maxDepth = 6,
      maxEntries = 256,
      maxNodes = 1500,
      maxStringBytes = 8192,
      maxTotalBytes = MAX_CALLBACK_PAYLOAD_BYTES,
    })
    if ok and type(copy) == "table" then
      copy.n = count
      return copy
    end
  end

  local args = { n = count }
  for index = 1, count do args[index] = SnapshotFallback(select(index, ...)) end
  return args
end

function RDL:RegisterCallback(eventName, key, fn)
  eventName = OrdinaryString(eventName, 128)
  key = OrdinaryString(key, 128)
  if not eventName or not key or not Callable(fn) then return false end

  local registry = Registry(self)
  local callbacks = self._callbacks[eventName]
  local existing = type(callbacks) == "table" and callbacks[key] or nil
  if Callable(existing) then
    callbacks[key] = fn
    return true
  end

  if type(callbacks) ~= "table" then
    if registry.events >= MAX_CALLBACK_EVENTS or registry.total >= MAX_CALLBACKS_TOTAL then
      return Drop(registry)
    end
    callbacks = {}
    self._callbacks[eventName] = callbacks
    registry.events = registry.events + 1
    registry.perEvent[eventName] = 0
  end

  local perEvent = tonumber(registry.perEvent[eventName]) or 0
  if perEvent >= MAX_CALLBACKS_PER_EVENT or registry.total >= MAX_CALLBACKS_TOTAL then
    if next(callbacks) == nil then
      self._callbacks[eventName] = nil
      registry.events = math.max(0, registry.events - 1)
      registry.perEvent[eventName] = nil
    end
    return Drop(registry)
  end

  callbacks[key] = fn
  registry.perEvent[eventName] = perEvent + 1
  registry.total = registry.total + 1
  return true
end

function RDL:UnregisterCallback(eventName, key)
  eventName = OrdinaryString(eventName, 128)
  key = OrdinaryString(key, 128)
  if not eventName or not key then return false end

  local callbacks = self._callbacks and self._callbacks[eventName]
  if type(callbacks) ~= "table" or callbacks[key] == nil then return false end

  local registry = Registry(self)
  local wasCallable = Callable(callbacks[key])
  callbacks[key] = nil
  if wasCallable then
    registry.total = math.max(0, registry.total - 1)
    registry.perEvent[eventName] = math.max(0,
      (tonumber(registry.perEvent[eventName]) or 1) - 1)
  end

  if next(callbacks) == nil then
    self._callbacks[eventName] = nil
    registry.events = math.max(0, registry.events - 1)
    registry.perEvent[eventName] = nil
  end
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
        local registry = Registry(self)
        registry.total = math.max(0, registry.total - 1)
        registry.perEvent[eventName] = math.max(0,
          (tonumber(registry.perEvent[eventName]) or 1) - 1)
        if self.Log then
          pcall(self.Log, self, "ERROR", "CALLBACK", "Callback disabled after error", {
            event = eventName,
            key = record.key,
          })
        end
      end
    end
  end

  if next(callbacks) == nil then
    self._callbacks[eventName] = nil
    local registry = Registry(self)
    registry.events = math.max(0, registry.events - 1)
    registry.perEvent[eventName] = nil
  end
  return invoked
end

function RDL:GetCallbackRegistryStats()
  local registry = Registry(self)
  return {
    events = registry.events,
    maxEvents = MAX_CALLBACK_EVENTS,
    callbacks = registry.total,
    maxCallbacks = MAX_CALLBACKS_TOTAL,
    maxPerEvent = MAX_CALLBACKS_PER_EVENT,
    maxPayloadBytes = MAX_CALLBACK_PAYLOAD_BYTES,
    dropped = registry.dropped,
  }
end
