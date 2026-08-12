-- !RothDevLib/Integration/Callbacks.lua
-- Minimal callback system (no external lib dependency).
-- IMPORTANT: callbacks MUST NOT be allowed to silently fail.
-- We keep execution safe (no hard crash), but capture any callback errors.

local RDL = _G.RothDevLib
RDL._callbacks = RDL._callbacks or {}

function RDL:RegisterCallback(eventName, key, fn)
    if type(eventName) ~= "string" or eventName == "" then return end
    if type(key) ~= "string" or key == "" then return end
    if type(fn) ~= "function" then return end
    self._callbacks[eventName] = self._callbacks[eventName] or {}
    self._callbacks[eventName][key] = fn
end

function RDL:UnregisterCallback(eventName, key)
    if not self._callbacks or not self._callbacks[eventName] then return end
    self._callbacks[eventName][key] = nil
end

local function CallCallback(eventName, key, fn, ...)
    -- Let Capture infer the addon from stack (addonHint=nil): callbacks often belong to other addons.
    if RDL and RDL.Internal and RDL.Internal.Call then
        return RDL.Internal:Call(nil, ("Callback:%s:%s"):format(tostring(eventName), tostring(key)), fn, ...)
    end
    return pcall(fn, ...)
end

function RDL:Fire(eventName, ...)
    local ev = self._callbacks and self._callbacks[eventName]
    if not ev then return end

    -- If a callback throws, disable it to prevent infinite loops (e.g., UI callback error -> capture -> callback again).
    for key, fn in pairs(ev) do
        local ok = CallCallback(eventName, key, fn, ...)
        if ok == false then
            -- Disable failing callback.
            ev[key] = nil
            if self.Log then
                pcall(function()
                    self:Log("ERROR", "CALLBACK", "Callback disabled after error", { event = eventName, key = key })
                end)
            end
        end
    end
end
