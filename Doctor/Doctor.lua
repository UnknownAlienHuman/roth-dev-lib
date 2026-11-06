-- !RothDevLib/Doctor/Doctor.lua
-- Correlation context stack with token-aware cleanup.

local RDL = _G.RothDevLib
local Doctor = {}
RDL.Doctor = Doctor

Doctor.stack = Doctor.stack or {}
Doctor.lastSnapshot = nil

local Unpack = table.unpack or unpack

local function Pack(...)
    return { n = select("#", ...), ... }
end

function Doctor:Init()
    self.stack = self.stack or {}
    wipe(self.stack)
    self.lastSnapshot = nil
end

function Doctor:Enter(addonName, funcName, ctx)
    self.stack = self.stack or {}
    local item = {
        ts    = time(),
        addon = addonName,
        func  = funcName,
        ctx   = ctx,
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
    maxDepth = tonumber(maxDepth) or 100
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
        chain[i] = { addon = scope.addon, func = scope.func, ctx = scope.ctx }
    end
    return chain
end

function Doctor:GetTop()
    if not self.stack or #self.stack == 0 then return nil end
    return self.stack[#self.stack]
end
