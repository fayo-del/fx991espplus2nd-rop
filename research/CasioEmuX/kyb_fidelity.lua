-- Fidelity verification on the matrix-drive patch (emulator.patched):
-- 1) SHIFT-MODE-2 -> Sigma( bare-vs-boxed check (LineIO)
-- 2) wiki basic overflow: formula, CALC=, AC, LEFT, probe-1 no-insert
-- 3) hack #7: type symbol, long waits (10M-tick class), arrows, byte delta
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local ops, oi = {}, 0
local state, hold_t, gap_t, wait_t, cur = "idle", 0, 0, 0, nil

local function key(code, label, hold, gap)
	ops[#ops + 1] = { op = "key", code = code, label = label, hold = hold or 16000, gap = gap or 20000 }
end
local function chord(m, c, label)
	key(m, label .. "/m"); key(c, label)
end
local function waitk(n, tag) ops[#ops + 1] = { op = "wait", n = n, tag = tag } end
local function samp(tag) ops[#ops + 1] = { op = "samp", tag = tag } end
local function hex(a0, n) local s = "" for i = 0, n - 1 do s = s .. string.format("%02X", data[a0 + i] or 0) end return s end
local function blen() local n = 0 while n <= 130 and (data[0x8154 + n] or 0) ~= 0 do n = n + 1 end return n end
local done = false

-- ==== 1) menu + LineIO ====
key(0x07); key(0x42)                       -- warm SHIFT AC
key(0x07, "S"); key(0x47, "MODE", 16000, 120000)
key(0x10, "digit2", 30000, 120000)
key(0x07, "S2"); key(0x10, "digit2b", 30000, 120000)
samp("setup-done")
chord(0x07, 0x56, "SIGMA")                 -- Sigma( LineIO tell
samp("sigma-1")
-- ==== 2) basic overflow, no DEL dance ====
key(0x17); key(0x33, "X1")                 -- ALPHA X
chord(0x17, 0x06, "eq")                    -- ALPHA CALC  ( = 3D )
chord(0x07, 0x56, "Sigma2")                -- Sigma
key(0x17); key(0x33, "X2")
chord(0x07, 0x33, "comma1")
key(0x00, "one")
chord(0x07, 0x33, "comma2")
key(0x00, "one2")
key(0x62, "x10")
key(0x22, "nine")
samp("formula")
key(0x06, "CALC", 16000, 24000)
key(0x60, "EXE", 20000, 30000)
key(0x42, "AC", 16000, 24000)
key(0x26, "LEFT", 16000, 20000)
samp("after-dance")
key(0x00, "probe1", 16000, 40000)
samp("probe1")                             -- len must NOT grow
-- ==== 3) hack #7 with long real-time waits ====
key(0x11, "sym5")                          -- type 5
samp("sym5")
waitk(10000000, "long-flash-a")            -- ~4s of 8MS clock, real flash scale
key(0x37, "goR1", 30000, 60000)
samp("goR1")
waitk(10000000, "long-flash-b")
key(0x37, "goR2", 30000, 60000)
samp("goR2")
waitk(10000000, "long-flash-c")
key(0x26, "goL1", 30000, 60000)
samp("goL1")
waitk(10000000, "long-flash-d")
key(0x37, "goR3", 30000, 60000)
samp("goR3")
waitk(10000000, "final")
ops[#ops + 1] = { op = "final" }

addposttick(function()
	T = T + 1
	if done then return end
	if state == "idle" then
		oi = oi + 1
		if oi > #ops then done = true emu:set_paused(true) return end
		cur = ops[oi]
		if cur.op == "key" then
			Keyboard:PressKey(cur.code)
			state = "press"; hold_t = cur.hold
		elseif cur.op == "wait" then
			state = "wait"; wait_t = cur.n
		elseif cur.op == "samp" then
			print(string.format("FID[%s] t=%d len=%d in=%s ext=%s",
				cur.tag, T, blen(), hex(0x8154, 20), hex(0x81B8, 40)))
			state = "idle"
		elseif cur.op == "final" then
			print("FID[final] len=" .. blen() .. " in=" .. hex(0x8154, 24) .. " ext=" .. hex(0x81B8, 64))
			done = true
			emu:set_paused(true)
			return
		end
	elseif state == "press" then
		hold_t = hold_t - 1
		if hold_t <= 0 then Keyboard:ReleaseAll() state = "rel" gap_t = cur.gap end
	elseif state == "rel" then
		gap_t = gap_t - 1
		if gap_t <= 0 then state = "idle" end
	elseif state == "wait" then
		wait_t = wait_t - 1
		if wait_t <= 0 then state = "idle" end
	end
end)
