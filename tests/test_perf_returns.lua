_G.RothDevLib = {}
local RDL = RothDevLib

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

-- Direct profiler calls must not execute hostile __tostring metamethods when
-- producing diagnostic identities.
local hostile = setmetatable({}, {
  __tostring = function() error('hostile tostring') end,
})
assert(pcall(RDL.CPU.Measure, RDL.CPU, hostile, hostile, function() return true end, {}) == true)
assert(pcall(RDL.Mem.Measure, RDL.Mem, hostile, hostile, function() return true end, {}) == true)
assert(pcall(RDL.Mem.Sample, RDL.Mem, hostile, hostile, {}) == true)

-- Dynamic labels cannot grow long-lived telemetry maps without a hard bound.
for index = 1, 1100 do
  RDL.CPU:Measure('Addon', 'cpu-' .. index, function() return index end, {})
  RDL.Mem:Measure('Addon', 'mem-' .. index, function() return index end, {})
  RDL.Mem:Sample('Addon', 'sample-' .. index, {})
end

local cpuRegistry = RDL.CPU:GetRegistryStats()
assert(cpuRegistry.keys == cpuRegistry.maximum and cpuRegistry.maximum == 1024)
assert(cpuRegistry.dropped > 0)
local cpuCount = 0
for _ in pairs(RDL.CPU:GetStats()) do cpuCount = cpuCount + 1 end
assert(cpuCount == cpuRegistry.maximum)

local memRegistry = RDL.Mem:GetRegistryStats()
assert(memRegistry.stats == memRegistry.maxStats and memRegistry.maxStats == 1024)
assert(memRegistry.samples == memRegistry.maxSamples and memRegistry.maxSamples == 1024)
assert(memRegistry.droppedStats > 0 and memRegistry.droppedSamples > 0)
local memCount, sampleCount = 0, 0
for _ in pairs(RDL.Mem:GetStats()) do memCount = memCount + 1 end
for _ in pairs(RDL.Mem._lastSample) do sampleCount = sampleCount + 1 end
assert(memCount == memRegistry.maxStats and sampleCount == memRegistry.maxSamples)

RDL.CPU:ResetStats()
RDL.Mem:ResetStats()
assert(RDL.CPU:GetRegistryStats().keys == 0)
local resetMem = RDL.Mem:GetRegistryStats()
assert(resetMem.stats == 0 and resetMem.samples == 0)

print('performance return-tuple tests: ok')
