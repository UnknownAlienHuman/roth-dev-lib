-- !RothDevLib/Doctor/Doctor.lua
-- Bounded correlation context stack with token-aware cleanup.

local RDL = _G.RothDevLib
local Doctor = {}
RDL.Doctor = Doctor

local MAX_SCOPE_DEPTH = 64

Doctor.stack = Doctor.stack or {}
Doctor.lastSnapshot = nil
Doctor._droppedScopes = 0

local Unpack = table.unpack or unpack

local function Pack(...)
    return { n = select("#", ...), ... }
end

local function Now()
    if type(_G.time) ~= "function" then return 0 end
    local ok, value = pcall(_G.time)
    return ok and type(value) == "number" and value or 0
end

local function SafeText(value, fallback, maximum)
    local text
    local util = RDL and RDL.Util
    if util and type(util.SafeToString) == "function" then
        local ok, rendered = pcall(util.SafeToString, util, value)
        if ok and type(rendered) == "string" then text = rendered end
    else
        local valueType = type(value)
        if valueType == "string" then
            text = value
        elseif valueType == "number" or valueType == "boolean" then
            text = tostring(value)
        end
    end
    if type(text) ~= "string" or text == "" then text = fallback end
    if #text > maximum then text = text:sub(1, maximum) end
    return text
end

local function SafeContext(value)
    if value == nil then return nil end
    local util = RDL and RDL.Util
    if util and type(util.CopyDiagnosticValue) == "function" then
        local ok, copy = pcall(util.CopyDiagnosticValue, util, value, {
            maxDepth = 4,
            maxEntries = 80,
            maxNodes = 500,
            maxStringBytes = 4096,
            maxTotalBytes = 64 * 1024,
        })
        if ok then return copy end
    end

    local valueType = type(value)
    if valueType == "string" then return SafeText(value, "", 4096) end
    if valueType == "number" or valueType == "boolean" then return value end
    return "<unavailable>"
end

function Doctor:Init()
    self.stack = self.stack or {}
    wipe(self.stack)
    self.lastSnapshot = nil
    self._droppedScopes = 0
end

function Doctor:Enter(addonName, funcName, ctx)
    self.stack = self.stack or {}
    while #self.stack >= MAX_SCOPE_DEPTH do
        table.remove(self.stack, 1)
        self._droppedScopes = (tonumber(self._droppedScopes) or 0) + 1
    end

    local item = {
        ts = Now(),
        addon = SafeText(addonName, "<?>" , 128),
        func = SafeText(funcName, "<?>" , 256),
        ctx = SafeContext(ctx),
    }
    self.stack[#self.stack + 1] = item
    self.lastSnapshot = item
    return item
end

-- Leave the newest scope by default. When an expected token is supplied, remove
-- exactly that scope and leave newer scopes intact. This lets delayed cleanup
-- retire a failed wrapper without popping an unrelated later context.
function Doctor:Leave(expected)
    local stack = self.stack
    if type(stack) ~= "table" or #stack == 0 then
        self.lastSnapshot = nil
        return false
    end

    local index
    if expected == nil then
        index = #stack
    else
        for i = #stack, 1, -1 do
            if stack[i] == expected then
                index = i
                break
            end
        end
    end

    if not index then
        self.lastSnapshot = stack[#stack]
        return false
    end

    table.remove(stack, index)
    self.lastSnapshot = stack[#stack]
    return true
end

function Doctor:EnterSelf(funcName, ctx)
    local addonName = (RDL and RDL.addonName) or "!RothDevLib"
    return self:Enter(addonName, funcName, ctx)
end

-- Run a function within a Doctor scope. Errors remain returned through pcall;
-- this helper does not turn them into RothDevLib capture entries.
function Doctor:Scope(addonName, funcName, ctx, fn, ...)
    local token = self:Enter(addonName, funcName, ctx)
    local result = Pack(pcall(fn, ...))
    self:Leave(token)
    return Unpack(result, 1, result.n)
end

function Doctor:ScopeSelf(funcName, ctx, fn, ...)
    local addonName = (RDL and RDL.addonName) or "!RothDevLib"
    return self:Scope(addonName, funcName, ctx, fn, ...)
end

function Doctor:TryLeaveAll(maxDepth)
    maxDepth = tonumber(maxDepth) or MAX_SCOPE_DEPTH
    if maxDepth ~= maxDepth then maxDepth = MAX_SCOPE_DEPTH end
    maxDepth = math.max(0, math.min(MAX_SCOPE_DEPTH, math.floor(maxDepth)))
    if not self.stack then self.stack = {} end
    local n = 0
    while #self.stack > 0 and n < maxDepth do
        table.remove(self.stack)
        n = n + 1
    end
    self.lastSnapshot = self.stack[#self.stack]
    return n
end

function Doctor:Reset()
    self.stack = self.stack or {}
    wipe(self.stack)
    self.lastSnapshot = nil
end

function Doctor:GetSnapshotChain()
    if not self.stack or #self.stack == 0 then return nil end
    local chain = {}
    for i = 1, #self.stack do
        local scope = self.stack[i]
        chain[i] = {
            addon = scope.addon,
            func = scope.func,
            ctx = SafeContext(scope.ctx),
        }
    end
    return chain
end

function Doctor:GetTop()
    if not self.stack or #self.stack == 0 then return nil end
    return self.stack[#self.stack]
end

function Doctor:GetStats()
    return {
        depth = type(self.stack) == "table" and #self.stack or 0,
        maximum = MAX_SCOPE_DEPTH,
        dropped = tonumber(self._droppedScopes) or 0,
    }
end
