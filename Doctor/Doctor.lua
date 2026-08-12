-- !RothDevLib/Doctor/Doctor.lua
-- Correlation context stack.
-- Addons push "what function is running" + small context payload.
-- On error, Capture reads the stack to correlate the error with the calling function.

local RDL = _G.RothDevLib
local Doctor = {}
RDL.Doctor = Doctor

Doctor.stack = Doctor.stack or {}
Doctor.lastSnapshot = nil

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
    table.insert(self.stack, item)
    self.lastSnapshot = item
    return item
end

function Doctor:Leave()
    if not self.stack or #self.stack == 0 then
        self.lastSnapshot = nil
        return
    end
    table.remove(self.stack)
    self.lastSnapshot = self.stack[#self.stack]
end


-- Convenience helpers for self-diagnostics --------------------------------

function Doctor:EnterSelf(funcName, ctx)
    local addonName = (RDL and RDL.addonName) or "!RothDevLib"
    return self:Enter(addonName, funcName, ctx)
end

-- Run a function within a Doctor scope (Enter -> fn -> Leave).
-- This does NOT capture errors itself; use RDL:SafeCall / RDL.Internal:Call for error capture.
function Doctor:Scope(addonName, funcName, ctx, fn, ...)
    self:Enter(addonName, funcName, ctx)
    local ok, r1, r2, r3, r4, r5 = pcall(fn, ...)
    self:Leave()
    return ok, r1, r2, r3, r4, r5
end

function Doctor:ScopeSelf(funcName, ctx, fn, ...)
    local addonName = (RDL and RDL.addonName) or "!RothDevLib"
    return self:Scope(addonName, funcName, ctx, fn, ...)
end

-- Hard reset helper for defensive cleanup (e.g. after internal faults).
function Doctor:TryLeaveAll(maxDepth)
    maxDepth = tonumber(maxDepth) or 100
    if not self.stack then self.stack = {} end
    local n = 0
    while #self.stack > 0 and n < maxDepth do
        table.remove(self.stack)
        n = n + 1
    end
    self.lastSnapshot = self.stack[#self.stack]
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
        local s = self.stack[i]
        chain[i] = { addon = s.addon, func = s.func, ctx = s.ctx }
    end
    return chain
end

function Doctor:GetTop()
    if not self.stack or #self.stack == 0 then return nil end
    return self.stack[#self.stack]
end
