_G.RothDevLib = {}
local RDL = RothDevLib

local secret = setmetatable({}, {
  __tostring = function() error('secret tostring') end,
  __index = function() error('secret index') end,
})
function _G.canaccessvalue(value) return value ~= secret end
function _G.issecretvalue(value) return value == secret end
function _G.canaccesstable(value) return value ~= secret end
function _G.issecrettable(value) return value == secret end

local settings = {
  enablePerfProfiling = true,
  cpuSampleRate = 1,
  cpuSpikeMs = 999999,
  memSpikeKB = 999999,
  metricMinInterval = 0,
}
RDL.DB = { GetSettings = function() return settings end }
RDL.Bus = { Metric = function() error('metric sink failed') end }
RDL.Alert = function() error('alert sink failed') end

local clock = 0
_G.debugprofilestop = function() clock = clock + 1; return clock end
_G.GetTime = function() return clock / 1000 end
_G.time = function() return 1 end
local memory = 100
_G.collectgarbage = function(command)
  assert(command == 'count')
  memory = memory + 10
  return memory
end

assert(loadfile('Util/SecretGuard.lua'))()
assert(loadfile('Util/Util.lua'))()
assert(loadfile('Perf/CPU.lua'))()
assert(loadfile('Perf/Mem.lua'))()

local function ManyReturns()
  return 1, nil, 3, 4, nil, 6, 7, 8
end

local cpu = table.pack(RDL.CPU:Measure('Addon', 'many', ManyReturns, { sampleRate = 1 }))
assert(cpu.n == 8 and cpu[1] == 1 and cpu[2] == nil and cpu[8] == 8)
local cpuWrapped = table.pack(RDL.CPU:Wrap('Addon', 'many', ManyReturns, {})())
assert(cpuWrapped.n == 8 and cpuWrapped[8] == 8)
assert(pcall(RDL.CPU.Measure, RDL.CPU, 'Addon', 'boom', function() error('boom') end, {}) == false)

local mem = table.pack(RDL.Mem:Measure('Addon', 'many', ManyReturns, {}))
assert(mem.n == 8 and mem[1] == 1 and mem[2] == nil and mem[8] == 8)
local memWrapped = table.pack(RDL.Mem:Wrap('Addon', 'many', ManyReturns, {})())
assert(memWrapped.n == 8 and memWrapped[8] == 8)
assert(pcall(RDL.Mem.Measure, RDL.Mem, 'Addon', 'boom', function() error('boom') end, {}) == false)

-- Direct profiler calls must gate inaccessible values before type/rawget or
-- identity formatting. A secret callable/options value is rejected, not invoked.
assert(pcall(RDL.CPU.Measure, RDL.CPU, secret, secret, function() return true end, secret) == true)
assert(pcall(RDL.Mem.Measure, RDL.Mem, secret, secret, function() return true end, secret) == true)
assert(pcall(RDL.Mem.Sample, RDL.Mem, secret, secret, secret) == true)
assert(RDL.CPU:Measure('Addon', 'secret-fn', secret, {}) == nil)
assert(RDL.CPU:Wrap('Addon', 'secret-fn', secret, {}) == nil)
assert(RDL.Mem:Measure('Addon', 'secret-fn', secret, {}) == nil)
assert(RDL.Mem:Wrap('Addon', 'secret-fn', secret, {}) == nil)

local hostileOptions = setmetatable({ sampleRate = 1, spikeMs = 999999, spikeKB = 999999 }, {
  __index = function() error('option __index must not run') end,
  __pairs = function() error('option __pairs must not run') end,
})
assert(RDL.CPU:Measure('Addon', 'hostile-options', function() return true end, hostileOptions) == true)
assert(RDL.Mem:Measure('Addon', 'hostile-options', function() return true end, hostileOptions) == true)

-- Wrapper construction must detach identities/options from mutable caller state.
RDL.CPU:ResetStats()
RDL.Mem:ResetStats()
local cpuDisabledOptions = { sampleRate = 0 }
local cpuDisabled = assert(RDL.CPU:Wrap('Snapshot', 'cpu-off', function() return true end,
  cpuDisabledOptions))
cpuDisabledOptions.sampleRate = 1
assert(cpuDisabled() == true)
assert(next(RDL.CPU:GetStats()) == nil)

local cpuEnabledOptions = { sampleRate = 1 }
local cpuEnabled = assert(RDL.CPU:Wrap('Snapshot', 'cpu-on', function() return true end,
  cpuEnabledOptions))
cpuEnabledOptions.sampleRate = 0
assert(cpuEnabled() == true)
assert(RDL.CPU:GetStats()['Snapshot:cpu-on'] ~= nil)

local alerts = 0
RDL.Alert = function() alerts = alerts + 1 end
local memQuietOptions = { spikeKB = 999999, alertMinIntervalMs = 0 }
local memQuiet = assert(RDL.Mem:Wrap('Snapshot', 'mem-quiet', function() return true end,
  memQuietOptions))
memQuietOptions.spikeKB = 1
assert(memQuiet() == true and alerts == 0)
local memAlertOptions = { spikeKB = 1, alertMinIntervalMs = 0 }
local memAlert = assert(RDL.Mem:Wrap('Snapshot', 'mem-alert', function() return true end,
  memAlertOptions))
memAlertOptions.spikeKB = 999999
assert(memAlert() == true and alerts == 1)
RDL.Alert = function() error('alert sink failed') end
RDL.CPU:ResetStats()
RDL.Mem:ResetStats()

-- Dynamic labels cannot grow long-lived telemetry maps without a hard bound.
for index = 1, 1100 do
  RDL.CPU:Measure('Addon', 'cpu-' .. index, function() return index end, {})
  RDL.Mem:Measure('Addon', 'mem-' .. index, function() return index end, {})
  RDL.Mem:Sample('Addon', 'sample-' .. index, {})
end

local cpuRegistry = RDL.CPU:GetRegistryStats()
assert(cpuRegistry.keys == cpuRegistry.maximum and cpuRegistry.maximum == 1024)
assert(cpuRegistry.dropped > 0)
local cpuStats = RDL.CPU:GetStats()
local cpuCount, cpuKey = 0, nil
for key in pairs(cpuStats) do cpuCount = cpuCount + 1; cpuKey = cpuKey or key end
assert(cpuCount == cpuRegistry.maximum and cpuKey)
local originalCpuN = cpuStats[cpuKey].n
cpuStats[cpuKey].n = 999999
cpuStats.injected = { n = 1 }
local freshCpu = RDL.CPU:GetStats()
assert(freshCpu[cpuKey].n == originalCpuN and freshCpu.injected == nil)

local memRegistry = RDL.Mem:GetRegistryStats()
assert(memRegistry.stats == memRegistry.maxStats and memRegistry.maxStats == 1024)
assert(memRegistry.samples == memRegistry.maxSamples and memRegistry.maxSamples == 1024)
assert(memRegistry.droppedStats > 0 and memRegistry.droppedSamples > 0)
local memStats = RDL.Mem:GetStats()
local memCount, memKey, sampleCount = 0, nil, 0
for key in pairs(memStats) do memCount = memCount + 1; memKey = memKey or key end
for _ in pairs(RDL.Mem._lastSample) do sampleCount = sampleCount + 1 end
assert(memCount == memRegistry.maxStats and sampleCount == memRegistry.maxSamples and memKey)
local originalMemN = memStats[memKey].n
memStats[memKey].n = 999999
memStats.injected = { n = 1 }
local freshMem = RDL.Mem:GetStats()
assert(freshMem[memKey].n == originalMemN and freshMem.injected == nil)

RDL.CPU:ResetStats()
RDL.Mem:ResetStats()
assert(RDL.CPU:GetRegistryStats().keys == 0)
local resetMem = RDL.Mem:GetRegistryStats()
assert(resetMem.stats == 0 and resetMem.samples == 0)

print('performance return-tuple tests: ok')
