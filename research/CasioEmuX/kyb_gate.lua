-- Post-patch 100-byte-gate hunt (patched build):
-- A) decoupled state: type 200+ '1's; sample bytes 96..112 of the input area
--    (0x81B4..0x81C4) after every 4th key + arrows/walks (X-marker watch).
-- B) KeyInject real-ms hack-#7 test.
-- C) SETUP variants for LineIO (DOWN+EXE etc.).
-- D) if the gate fires, AC+LEFT+EXE trigger + tiles/chain watch.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
emu:SetClockSpeed(8)

local T, ops, oi = 0, {}, 0
local state, hold_t, gap_t, wait_t, cur = "idle", 0, 0, 0, nil
local g3538, g4d20 = 0, 0

break_at(0x3538, function() g3538 = g3538 + 1 emu:set_paused(false) end)
break_at(0x4D20, function() g4d20 = g4d20 + 1 emu:set_paused(false) end)

local function key(c, l, hold, gap) ops[#ops + 1] = { op = "key", code = c, label = l, hold = hold or 16000, gap = gap or 20000 } end
local function chord(m, c, l) key(m, l .. "/m"); key(c, l) end
local function waitk(n, tag) ops[#ops + 1] = { op = "wait", n = n, tag = tag } end
local function samp(tag, detail)
	ops[#ops + 1] = { op = "samp", tag = tag, detail = detail }
end
local function hex(a0, n) local s = "" for i = 0, n - 1 do s = s .. string.format("%02X", data[a0 + i] or 0) end return s end
local function blen() local n = 0 while n <= 130 and (data[0x8154 + n] or 0) ~= 0 do n = n + 1 end return n end

-- ================ C) SETUP variants first (LineIO hunt) ================
key(0x07); key(0x42)
chord(0x07, 0x47, "setup-open")
samp("setup-open")
key(0x36, "DOWN", 16000, 60000)
key(0x60, "EXE-sel", 20000, 80000)
samp("down-exe")
chord(0x07, 0x56, "SIGMA-A")
samp("sigma-A")
key(0x07); key(0x47, "setup2", 16000, 60000)
key(0x10, "digit2", 30000, 80000)
chord(0x07, 0x56, "SIGMA-B")
samp("sigma-B")
key(0x42, "clear", 16000, 24000)

-- ================ A) formula -> dance -> decoupled ================
chord(0x17, 0x33, "X1")
chord(0x17, 0x06, "eq")
chord(0x07, 0x56, "Sigma")
key(0x17); key(0x33, "X2")
chord(0x07, 0x33, "comma1")
key(0x00, "one")
chord(0x07, 0x33, "comma2")
key(0x00, "one2")
key(0x62, "x10")
key(0x22, "nine")
key(0x06, "CALC", 16000, 24000)
key(0x60, "EXE", 20000, 30000)
key(0x42, "AC", 16000, 24000)
key(0x26, "LEFT", 16000, 20000)
key(0x00, "probe1", 16000, 40000)
samp("decoupled")

-- ================ type 200 '1's, boundary sampling ================
for i = 1, 500 do
	key(0x00, "F" .. i, 12000, 14000)
	if i % 20 == 0 or i >= 490 then samp("f" .. i) end
end
-- arrows in the decoupled state
key(0x26, "Lw1", 30000, 60000) samp("walk-L")
key(0x37, "Rw1", 30000, 60000) samp("walk-R")

-- ================ B) KeyInject real-ms hack #7 ================
ops[#ops + 1] = { op = "inject" }
waitk(3000000, "inj-settle")
samp("after-inject")

-- ================ D) trigger ================
key(0x42, "trig-AC", 16000, 24000)
key(0x26, "trig-LEFT", 16000, 20000)
key(0x60, "trig-EXE", 20000, 30000)
waitk(4000000, "flood-watch")
samp("post-flood")
ops[#ops + 1] = { op = "final" }

local done = false
local injected = false
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
		elseif cur.op == "inject" then
			local f = io.open("/tmp/keyseq7.bin", "wb")
			if f then
				f:write(string.char(0x11, 0x37, 0x37, 0x37, 0x26, 0x26, 0x37))
				f:close()
			end
			Keyboard:KeyInject("/tmp/keyseq7.bin", 120, 180)
			print("FID: KeyInject started (5,R,R,R,L,L,R @120/180ms)")
			state = "idle"
		elseif cur.op == "samp" then
			local tag, detail = cur.tag, cur.detail
			if tag == "sigma-A" or tag == "sigma-B" or tag == "after-inject" or tag == "post-flood" or tag == "decoupled" or tag == "walk-L" or tag == "walk-R" or tag == "setup-open" or tag == "down-exe" then
				print(string.format("FID[%s] t=%d len=%d in=%s ext=%s",
					tag, T, blen(), hex(0x8154, 24), hex(0x81B8, 48)))
			else
				-- fill samples: boundary bytes only
				local b96 = tonumber(hex(0x8154 + 96, 1)) or 0
				print(string.format("FID[%s] t=%d len=%d b96-111=%s", tag, T, blen(), hex(0x8154 + 96, 16)))
			end
			state = "idle"
		elseif cur.op == "final" then
			print(string.format("FID[final] t=%d len=%d h3538=%d h4d20=%d", T, blen(), g3538, g4d20))
			print("FID[input]=" .. hex(0x8154, 100))
			print("FID[cache]=" .. hex(0x81B8, 100))
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
