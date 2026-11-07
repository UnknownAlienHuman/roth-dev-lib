-- !RothDevLib/Doctor/Doctor.lua
-- Bounded correlation context stack with opaque tokens and detached snapshots.

local RDL = _G.RothDevLib
if not RDL then return end

local Doctor = {}
RDL.Doctor = Doctor

local MAX_STACK_DEPTH = 64
local MAX_CONTEXT_BYTES = 64 * 1024
local scopeStack = {}

Doctor.lastSnapshot = nil
Doctor._droppedScopes = 0

local Unpack = table.unpack or unpack

local function Pack(...)
  return { n = select("#", ...), ... }
end

local function CanAccess(value)
  local guard = RDL.SecretGuard
  if guard and type(guard.CanAccess) == "function" then
    local ok, allowed = pcall(guard.CanAccess, guard, value)
    if not ok or allowed ~= true then return false end
  elseif type(_G.canaccessvalue) == "function" then
    local ok, allowed = pcall(_G.canaccessvalue, value)
    if not ok or allowed ~= true then return false end
  end

  if guard and type(guard.IsSecret) == "function" then
    local ok, secret = pcall(guard.IsSecret, guard, value)
    if not ok or secret == true then return false end
  elseif type(_G.issecretvalue) == "function" then
    local ok, secret = pcall(_G.issecretvalue, value)
    if not ok or secret == true then return false end
  end
  return true
end

local function CanAccessTable(value)
  if not CanAccess(value) or type(value) ~= "table" then return false end
  local guard = RDL.SecretGuard
  if guard and type(guard.CanAccessTable) == "function" then
    local ok, allowed = pcall(guard.CanAccessTable, guard, value)
    return ok and allowed == true
  end
  if type(_G.canaccesstable) == "function" then
    local ok, allowed = pcall(_G.canaccesstable, value)
    return ok and allowed == true
  end
  return true
end

local function Finite(value)
  return CanAccess(value) and type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
end

local function Now()
  if type(_G.time) ~= "function" then return 0 end
  local ok, value = pcall(_G.time)
  return ok and Finite(value) and value or 0
end

local function SafeText(value, fallback, maximum)
  if not CanAccess(value) then return "<inaccessible>" end
  local text
  local util = RDL.Util
  if util and type(util.SafeToString) == "function" then
    local ok, rendered = pcall(util.SafeToString, util, value)
    if ok and type(rendered) == "string" then text = rendered end
  elseif type(value) == "string" then
    text = value
  elseif type(value) == "number" or type(value) == "boolean" then
    text = tostring(value)
  end

  if type(text) ~= "string" or text == "" then text = fallback end
  if #text > maximum then text = text:sub(1, maximum) end
  return text
end

local function SafeContext(value)
  if not CanAccess(value) then return "<inaccessible>" end
  if value == nil then return nil end

  local util = RDL.Util
  if util and type(util.CopyDiagnosticValue) == "function" then
    local ok, copy = pcall(util.CopyDiagnosticValue, util, value, {
      maxDepth = 5,
      maxEntries = 120,
      maxNodes = 800,
      maxStringBytes = 4096,
      maxTotalBytes = MAX_CONTEXT_BYTES,
    })
    if ok then return copy end
  end

  local valueType = type(value)
  if valueType == "string" then return SafeText(value, "", 4096) end
  if valueType == "number" and Finite(value) then return value end
  if valueType == "boolean" then return value end
  return "<unavailable>"
end

local function Snapshot(item)
  if type(item) ~= "table" then return nil end
  return {
    ts = item.ts,
    addon = item.addon,
    func = item.func,
    ctx = SafeContext(item.ctx),
  }
end

local function RefreshLast(self)
  self.lastSnapshot = Snapshot(scopeStack[#scopeStack])
end

local function Callable(value)
  return CanAccess(value) and type(value) == "function"
end

local function MaximumDepth(value)
  if not CanAccess(value) or not Finite(value) then return MAX_STACK_DEPTH end
  value = math.floor(value)
  if value < 0 then return 0 end
  if value > MAX_STACK_DEPTH then return MAX_STACK_DEPTH end
  return value
end

function Doctor:Init()
  wipe(scopeStack)
  self.lastSnapshot = nil
  self._droppedScopes = 0
end

function Doctor:Enter(addonName, funcName, ctx)
  local token = {}
  local item = {
    token = token,
    ts = Now(),
    addon = SafeText(addonName, "<?>" , 128),
    func = SafeText(funcName, "<?>" , 256),
    ctx = SafeContext(ctx),
  }

  scopeStack[#scopeStack + 1] = item
  if #scopeStack > MAX_STACK_DEPTH then
    table.remove(scopeStack, 1)
    self._droppedScopes = (tonumber(self._droppedScopes) or 0) + 1
  end
  RefreshLast(self)
  return token
end

-- Leave the newest scope by default. An expected token is opaque and identifies
-- exactly one stored scope; callers cannot mutate retained metadata through it.
function Doctor:Leave(expected)
  if not CanAccess(expected) then return false end
  if #scopeStack == 0 then
    self.lastSnapshot = nil
    return false
  end

  local index
  if expected == nil then
    index = #scopeStack
  else
    for candidate = #scopeStack, 1, -1 do
      if scopeStack[candidate].token == expected then
        index = candidate
        break
      end
    end
  end

  if not index then
    RefreshLast(self)
    return false
  end

  table.remove(scopeStack, index)
  RefreshLast(self)
  return true
end

function Doctor:EnterSelf(funcName, ctx)
  local addonName = RDL.addonName or "!RothDevLib"
  return self:Enter(addonName, funcName, ctx)
end

-- Run a function within a Doctor scope. Errors remain returned through pcall;
-- this helper does not turn them into RothDevLib capture entries.
function Doctor:Scope(addonName, funcName, ctx, fn, ...)
  if not Callable(fn) then return false, "Doctor.Scope: fn is not callable" end
  local token = self:Enter(addonName, funcName, ctx)
  local result = Pack(pcall(fn, ...))
  self:Leave(token)
  return Unpack(result, 1, result.n)
end

function Doctor:ScopeSelf(funcName, ctx, fn, ...)
  local addonName = RDL.addonName or "!RothDevLib"
  return self:Scope(addonName, funcName, ctx, fn, ...)
end

function Doctor:TryLeaveAll(maxDepth)
  maxDepth = MaximumDepth(maxDepth)
  local removed = 0
  while #scopeStack > 0 and removed < maxDepth do
    table.remove(scopeStack)
    removed = removed + 1
  end
  RefreshLast(self)
  return removed
end

function Doctor:Reset()
  wipe(scopeStack)
  self.lastSnapshot = nil
end

function Doctor:GetSnapshotChain()
  if #scopeStack == 0 then return nil end
  local chain = {}
  for index = 1, #scopeStack do chain[index] = Snapshot(scopeStack[index]) end
  return chain
end

function Doctor:GetTop()
  return Snapshot(scopeStack[#scopeStack])
end

function Doctor:GetStats()
  return {
    depth = #scopeStack,
    maximum = MAX_STACK_DEPTH,
    dropped = tonumber(self._droppedScopes) or 0,
    maxContextBytes = MAX_CONTEXT_BYTES,
  }
end
