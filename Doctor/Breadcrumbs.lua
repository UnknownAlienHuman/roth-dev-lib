-- !RothDevLib/Doctor/Breadcrumbs.lua
-- Bridge between Doctor (correlation stack) and Bus (breadcrumb ring buffers).
-- When an error is captured, this module provides the last N breadcrumbs
-- for the offending addon, giving LLM/human context about what happened.

local RDL = _G.RothDevLib
local Breadcrumbs = {}
RDL.Breadcrumbs = Breadcrumbs

-- Get recent breadcrumbs for an addon at the moment of error.
-- Called by Capture/ErrorHandler during BuildEntry().
-- @param addonName string  Addon that errored
-- @param n number|nil       Max breadcrumbs to return (default from DB settings)
-- @return table|nil          Array of breadcrumb items, newest first
function Breadcrumbs:GetForError(addonName, n)
  if not RDL.Bus or not RDL.Bus.GetErrorContext then return nil end
  if n then
    return RDL.Bus:GetBreadcrumbSnapshot(addonName, n)
  end
  return RDL.Bus:GetErrorContext(addonName)
end

-- Get full snapshot for an addon (all breadcrumbs, no limit from error settings).
-- Used by Report/Export for comprehensive dump.
-- @param addonName string
-- @param n number|nil  Max items (default 80)
-- @return table|nil
function Breadcrumbs:GetFull(addonName, n)
  if not RDL.Bus or not RDL.Bus.GetBreadcrumbSnapshot then return nil end
  return RDL.Bus:GetBreadcrumbSnapshot(addonName, n or 80)
end

-- Format breadcrumbs as text for export/display.
-- @param crumbs table  Array from GetForError/GetFull
-- @return string
function Breadcrumbs:Format(crumbs)
  if not crumbs or #crumbs == 0 then return "" end
  local lines = {}
  for i, c in ipairs(crumbs) do
    local ts = c.ts and date("%H:%M:%S", c.ts) or "?"
    local line = string.format("[%s] [%s] %s", ts, tostring(c.cat or "?"), tostring(c.msg or ""))
    if c.data then
      line = line .. " " .. tostring(c.data)
    end
    lines[i] = line
  end
  return table.concat(lines, "\n")
end
