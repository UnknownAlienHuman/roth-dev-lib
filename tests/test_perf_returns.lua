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

print('performance return-tuple tests: ok')
