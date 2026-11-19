-- TYPED token enumeration for CY-845 (fx-991esplus2): every key, base + SHIFT/ALPHA
-- chords, typed via Keyboard:PressKey (NO data[] injection). Samples the inserted
-- token bytes at the input buffer 0x8154 right after each key settles (BEFORE the
-- separating AC clears it). Timing = the Session-15-verified rop_e2e.lua template
-- (1x clock, 16000 hold / 20000 gap, typing from T=1, SETUP-menu head).
-- Runs: ENUM_MODE=base|shift|alpha (default base); shift/alpha prepend the modifier.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT, UP, DOWN, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37, 0x27, 0x36, 0x00, 0x10, 0x22, 0x62
local HOLD, GAP = 16000, 20000

local base = {
	{ 0x02, "7" }, { 0x12, "8" }, { 0x22, "9" }, { 0x32, "DEL" }, { 0x42, "AC" },
	{ 0x01, "4" }, { 0x11, "5" }, { 0x21, "6" }, { 0x31, "mul" }, { 0x41, "div" },
	{ 0x00, "1" }, { 0x10, "2" }, { 0x20, "3" }, { 0x30, "plus" }, { 0x40, "minus" },
	{ 0x64, "0" }, { 0x63, "dot" }, { 0x62, "x10" }, { 0x61, "ans" }, { 0x60, "EXE" },
	{ 0x06, "CALC" }, { 0x16, "intdx" }, { 0x46, "fn1" }, { 0x56, "fn2" },
	{ 0x26, "LEFT" }, { 0x27, "UP" }, { 0x36, "DOWN" }, { 0x37, "RIGHT" },
	{ 0x07, "SHIFT" }, { 0x17, "ALPHA" }, { 0x47, "MODE" },
	-- 6-col function block (model.lua rows 3; sessions-4 map: 0x03=( 0x33=) ...)
	{ 0x05, "r05" }, { 0x15, "r15" }, { 0x25, "r25" }, { 0x35, "r35" }, { 0x45, "r45" }, { 0x55, "r55" },
	{ 0x04, "r04" }, { 0x14, "r14" }, { 0x24, "r24" }, { 0x34, "r34" }, { 0x44, "r44" }, { 0x54, "r54" },
	{ 0x03, "r03" }, { 0x13, "r13" }, { 0x23, "r23" }, { 0x33, "r33" }, { 0x43, "r43" }, { 0x53, "r53" },
}

local mode = os.getenv("ENUM_MODE") or "base"

local seq, si = {}, 0
local function push(code, label, sample)
	seq[#seq + 1] = { code = code, label = label, sample = sample }
end

-- warm-up + SETUP head: the exact Session-15-verified opening (first SHIFT of the
-- boot can be eaten; the input line only accepts typing after the SETUP menu opens)
push(SHIFT, "warm:SHIFT"); push(AC, "warm:AC"); push(AC, "warm:AC2")
push(SHIFT, "setup1/mod"); push(MODE, "setup1"); push(K2, "setup1-digit2")
push(AC, "setup-clear")

-- sample set: keys that could insert an ordinary token
local enumset
if mode == "base" then
	enumset = base
elseif mode == "shift" then
	enumset = base
	for _, k in ipairs(enumset) do push(SHIFT, "s:" .. k[2] .. "/mod") end -- placeholder, rebuilt below
	-- rebuild properly: mod + key per entry
	seq, si = {}, 0
	push(SHIFT, "warm:SHIFT"); push(AC, "warm:AC"); push(AC, "warm:AC2")
	push(SHIFT, "setup1/mod"); push(MODE, "setup1"); push(K2, "setup1-digit2")
	push(AC, "setup-clear")
	for _, k in ipairs(base) do
		push(SHIFT, "s:" .. k[2] .. "/mod"); push(k[1], "shift:" .. k[2], true); push(AC, "AC:shift:" .. k[2])
	end
	enumset = nil
elseif mode == "alpha" then
	seq, si = {}, 0
	push(SHIFT, "warm:SHIFT"); push(AC, "warm:AC"); push(AC, "warm:AC2")
	push(SHIFT, "setup1/mod"); push(MODE, "setup1"); push(K2, "setup1-digit2")
	push(AC, "setup-clear")
	for _, k in ipairs(base) do
		push(ALPHA, "a:" .. k[2] .. "/mod"); push(k[1], "alpha:" .. k[2], true); push(AC, "AC:alpha:" .. k[2])
	end
	enumset = nil
else
	error("bad ENUM_MODE")
end
-- base mode: key + AC per entry (sampler attached to the KEY, not the AC)
if enumset then
	for _, k in ipairs(base) do
		local skip = k[1] == 0x07 or k[1] == 0x17 or k[1] == 0x47 -- modifiers insert nothing
		if skip then
			push(k[1], "base:" .. k[2]); push(AC, "AC:base:" .. k[2])
		else
			push(k[1], "base:" .. k[2], true); push(AC, "AC:base:" .. k[2])
		end
	end
end

local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local T, samples = 0, {}
local hits = {}
local function buf_bytes(n)
	local s = ""
	for i = 0, (n or 24) - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end
	return s
end
local function blen()
	for i = 0, 100 do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 101
end

addposttick(function()
	T = T + 1
	if state == "idle" then
		si = si + 1
		if si > #seq then
			print(string.format("ENUM[%s]: DONE pressed=%d samples=%d", mode, #seq, #samples))
			for _, sm in ipairs(samples) do
				print(string.format("ENUM-SAMPLE[%s]: %s len=%d buf=%s", mode, sm.label, sm.len, sm.buf))
			end
			emu:set_paused(true)
			return
		end
		cur = seq[si]
		Keyboard:PressKey(cur.code)
		state = "press"; hold_t = HOLD
	elseif state == "press" then
		hold_t = hold_t - 1
		if hold_t <= 0 then
			Keyboard:ReleaseAll()
			state = "rel"; gap_t = GAP
		end
	elseif state == "rel" then
		if gap_t == GAP - 1 and cur.sample then
			-- sample fires 1 tick into THIS key's settle gap: its token has landed,
			-- the following AC has not run yet
			local sm = { label = cur.label, len = blen(), buf = buf_bytes(24) }
			samples[#samples + 1] = sm
			print(string.format("ENUM[%s]: %s len=%d buf=%s", mode, sm.label, sm.len, sm.buf))
			for b = 0, sm.len - 1 do
				local v = data[0x8154 + b] or 0
				if v == 0x0E or v == 0x4D then hits[#hits + 1] = string.format("%s@%d=%02X", cur.label, b, v) end
			end
		end
		gap_t = gap_t - 1
		if gap_t <= 0 then state = "idle" end
	end
end)
