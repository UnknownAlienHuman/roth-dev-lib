-- !RothDevLib/Util/SecretGuard.lua
-- Safe wrapper for WoW 12.x Midnight Secret Values (gap #7).
-- Graceful degradation on pre-12.x clients.

local RDL = _G.RothDevLib
local SG = {}
RDL.SecretGuard = SG

function SG:IsSecret(value)
  if type(_G.issecretvalue) ~= "function" then return false end
  local ok, result = pcall(_G.issecretvalue, value)
  return ok and result == true
end

function SG:CanAccess(value)
  if type(_G.canaccessvalue) ~= "function" then return true end
  local ok, result = pcall(_G.canaccessvalue, value)
  return ok and result == true
end

function SG:SafeGet(obj, method, ...)
  if type(obj) ~= "table" and type(obj) ~= "userdata" then return nil, "not-indexable" end
  local fn = obj[method]
  if type(fn) ~= "function" then return nil, "not-function" end
  local ok, r1, r2 = pcall(fn, obj, ...)
  if not ok then return nil, tostring(r1) end
  if self:IsSecret(r1) then return "<secret>", "secret" end
  return r1, nil
end

function SG:SafeCall(fn, ...)
  if type(fn) ~= "function" then return nil, "not-function" end
  local ok, r1 = pcall(fn, ...)
  if not ok then return nil, tostring(r1) end
  if self:IsSecret(r1) then return "<secret>", "secret" end
  return r1, nil
end

function SG:FormatValue(value)
  if self:IsSecret(value) then return "<secret>" end
  if not self:CanAccess(value) then return "<denied>" end
  local U = RDL.Util
  if U and U.SafeToString then return U:SafeToString(value) end
  return tostring(value)
end

-- Filter |K escape sequences from locals/stack strings
function SG:FilterLocals(localsStr)
  if type(localsStr) ~= "string" then return localsStr end
  return localsStr:gsub("|K[^|]*|k", "<filtered>")
end
