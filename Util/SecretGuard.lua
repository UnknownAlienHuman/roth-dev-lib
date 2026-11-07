-- !RothDevLib/Util/SecretGuard.lua
-- Ordinary-value boundary for WoW 12.x Secret Values and constrained objects.

local RDL = _G.RothDevLib
local SG = {}
RDL.SecretGuard = SG

local function CallPredicate(fn, ...)
  local ok, result = pcall(fn, ...)
  if not ok then return nil end
  return result == true
end

function SG:IsSecret(value)
  local fn = _G.issecretvalue
  if type(fn) ~= "function" then return false end
  return CallPredicate(fn, value) == true
end

function SG:CanAccess(value)
  local canAccess = _G.canaccessvalue
  if type(canAccess) == "function" then
    return CallPredicate(canAccess, value) == true
  end

  local isSecret = _G.issecretvalue
  if type(isSecret) == "function" then
    local secret = CallPredicate(isSecret, value)
    return secret == false
  end

  return true
end

function SG:CanAccessTable(value)
  if not self:CanAccess(value) then return false end
  if value == nil or type(value) ~= "table" then return false end

  local fn = _G.canaccesstable
  if type(fn) ~= "function" then return true end
  return CallPredicate(fn, value) == true
end

function SG:CanAccessAllValues(...)
  local fn = _G.canaccessallvalues
  if type(fn) == "function" then
    return CallPredicate(fn, ...) == true
  end

  for i = 1, select("#", ...) do
    if not self:CanAccess(select(i, ...)) then
      return false
    end
  end
  return true
end

local function CheckObjectContext(self, obj)
  local ok, accessMethod = pcall(function()
    return obj.CanBeAccessedInContext
  end)
  if not ok then return false end
  if not self:CanAccess(accessMethod) then return false end
  if type(accessMethod) ~= "function" then return true end

  local callOK, allowed = pcall(accessMethod, obj)
  if not callOK or not self:CanAccess(allowed) then return false end
  return allowed == true
end

function SG:SafeGet(obj, method, ...)
  if not self:CanAccessAllValues(obj, method, ...) then
    return nil, "inaccessible-argument"
  end
  if obj == nil then return nil, "nil-object" end

  local objType = type(obj)
  if objType ~= "table" and objType ~= "userdata" then
    return nil, "not-indexable"
  end
  if objType == "table" and not self:CanAccessTable(obj) then
    return nil, "inaccessible-table"
  end
  if type(method) ~= "string" or method == "" then
    return nil, "invalid-method"
  end
  if not CheckObjectContext(self, obj) then
    return nil, "object-inaccessible"
  end

  local readOK, fn = pcall(function()
    return obj[method]
  end)
  if not readOK or not self:CanAccess(fn) then
    return nil, "method-inaccessible"
  end
  if type(fn) ~= "function" then return nil, "not-function" end

  local ok, r1, r2 = pcall(fn, obj, ...)
  if not ok then return nil, "call-failed" end
  if not self:CanAccessAllValues(r1, r2) then
    return nil, "inaccessible-result"
  end
  if self:IsSecret(r1) or self:IsSecret(r2) then
    return nil, "secret-result"
  end
  return r1, nil, r2
end

function SG:SafeCall(fn, ...)
  if not self:CanAccessAllValues(fn, ...) then
    return nil, "inaccessible-argument"
  end
  if type(fn) ~= "function" then return nil, "not-function" end

  local ok, r1, r2 = pcall(fn, ...)
  if not ok then return nil, "call-failed" end
  if not self:CanAccessAllValues(r1, r2) then
    return nil, "inaccessible-result"
  end
  if self:IsSecret(r1) or self:IsSecret(r2) then
    return nil, "secret-result"
  end
  return r1, nil, r2
end

function SG:FormatValue(value)
  if not self:CanAccess(value) then return "<inaccessible>" end
  if self:IsSecret(value) then return "<secret>" end

  local U = RDL.Util
  if U and U.SafeToString then return U:SafeToString(value) end
  return tostring(value)
end

-- Filter |K escape sequences from already-readable diagnostic strings.
function SG:FilterLocals(localsStr)
  if not self:CanAccess(localsStr) then return "<inaccessible>" end
  if self:IsSecret(localsStr) then return "<secret>" end
  if type(localsStr) ~= "string" then return localsStr end
  return localsStr:gsub("|K[^|]*|k", "<filtered>")
end
