-- STO-combo probe: double-modifier chords (SHIFT+ALPHA+key and ALPHA+SHIFT+key) on
-- the variable keys — the GYX decomp maps tokens 0x47..0x4D (sto_a..sto_y) to this
-- class; target = byte 0x4D (sto_y) or 0x0E (cs14) in ANY variant.
-- Same typed scheduler as rop_enum.lua (no data[] injection).
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT, UP, DOWN, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37, 0x27, 0x36, 0x00, 0x10, 0x22, 0x62
local HOLD, GAP = 16000, 20000

-- the six variable-ish keys (X/Y/M/:/e/%/A..F candidates) + a couple extras
local keys = {
	{ 0x33, "X" }, { 0x43, "Y" }, { 0x53, "M" }, { 0x63, "D" },
	{ 0x62, "E" }, { 0x61, "F" }, { 0x31, "mul" }, { 0x41, "div" },
}

local seq, si = {}, 0
local function push(code, label, sample)
	seq[#seq + 1] = { code = code, label = label, sample = sample }
end

push(SHIFT, "warm:SHIFT"); push(AC, "warm:AC"); push(AC, "warm:AC2")
push(SHIFT, "setup1/mod"); push(MODE, "setup1"); push(K2, "setup1-digit2")
push(AC, "setup-clear")

for _, k in ipairs(keys) do
	push(SHIFT, "sm:" .. k[2] .. "/m1"); push(ALPHA, "sm:" .. k[2] .. "/m2"); push(k[1], "shift+alpha:" .. k[2], true)
	push(AC, "AC:sa:" .. k[2])
	push(ALPHA, "am:" .. k[2] .. "/m1"); push(SHIFT, "am:" .. k[2] .. "/m2"); push(k[1], "alpha+shift:" .. k[2], true)
	push(AC, "AC:as:" .. k[2])
end

local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local T, samples = 0, {}
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
			print(string.format("ENUM: DONE pressed=%d samples=%d", #seq, #samples))
			for _, sm in ipairs(samples) do
				print(string.format("ENUM-SAMPLE: %s len=%d buf=%s", sm.label, sm.len, sm.buf))
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
			local sm = { label = cur.label, len = blen(), buf = buf_bytes(24) }
			samples[#samples + 1] = sm
			print(string.format("ENUM: %s len=%d buf=%s", sm.label, sm.len, sm.buf))
		end
		gap_t = gap_t - 1
		if gap_t <= 0 then state = "idle" end
	end
end)
