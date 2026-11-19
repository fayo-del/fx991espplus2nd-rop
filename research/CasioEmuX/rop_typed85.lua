-- TYPED '85'-sled test: e2e head (warm-up, SETUP, formula, dance, probe) then a
-- TYPED 100-char fill of digits '8','5' alternating (= bytes 38 35 38 35 ... =
-- the 0x3538 gadget word repeated), then AC, LEFT, EXE. NO data[] injection.
-- Watches break_at(0x3538) hits (each = one gadget step executed from the stack) --
-- filtered: log sp/ER2/LR so the app's own 0x3538 calls are distinguishable.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT, UP, DOWN, K1, K2, K8, K5, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37, 0x27, 0x36, 0x00, 0x10, 0x12, 0x11, 0x22, 0x62

local seq, si = {}, 0
local function push(code, label) seq[#seq + 1] = { code = code, label = label } end
local function chord(mod, code, label)
	push(mod, label .. "/mod"); push(code, label)
end

-- e2e-identical head (Session-15-verified delivery)
push(SHIFT, "w1"); push(AC, "w2")
chord(SHIFT, MODE, "setup1"); push(K2, "setup1-2")
chord(SHIFT, 0x56, "sigv1")
chord(SHIFT, MODE, "setup2"); push(K2, "setup2-2")
chord(SHIFT, 0x56, "sigv2"); push(AC, "AC-clear")
chord(ALPHA, 0x33, "X1"); chord(ALPHA, CALC, "eq"); chord(SHIFT, 0x56, "Sigma")
chord(ALPHA, 0x33, "X2"); chord(SHIFT, 0x33, "comma1"); push(K1, "one")
chord(SHIFT, 0x33, "comma2"); push(K1, "one2"); push(KX10, "x10"); push(K9, "nine")
-- 90-digit fill FIRST (pre-dance): formula(10) + 90 digits = 100-byte typed buffer
for i = 0, 89 do push(i % 2 == 0 and K8 or K5, i % 2 == 0 and "d8" or "d5") end
push(CALC, "CALC"); push(EXE, "EXE"); push(AC, "AC"); push(LEFT, "LEFT")
push(DEL, "DEL1"); push(DEL, "DEL2"); push(DEL, "DEL3"); push(K2, "two")
push(CALC, "CALC2"); push(EXE, "EXE2"); push(LEFT, "LEFT2"); push(K1, "PROBE1")
-- trigger: AC, then LEFT, then EXE (payload already typed pre-dance)
push(AC, "AC-f"); push(LEFT, "LEFT-f"); push(EXE, "EXE-f")

local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local T, si_done, g3538, g4d20 = 0, false, 0, 0
local function blen()
	for i = 0, 100 do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 101
end
local function buf_bytes(n)
	local s = ""
	for i = 0, (n or 24) - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end
	return s
end

break_at(0x3538, function()
	g3538 = g3538 + 1
	if g3538 <= 10 or g3538 % 50 == 0 then
		print(string.format("HIT-3538: #%d sp=%04X ER2=%04X r0=%02X lr=%04X", g3538, cpu.sp,
			(cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF), cpu.r0 & 0xFF, cpu.lr))
	end
	emu:set_paused(false)
end)
break_at(0x4D20, function()
	g4d20 = g4d20 + 1
	emu:set_paused(false)
end)

addposttick(function()
	T = T + 1
	if not si_done then
		if state == "idle" then
			si = si + 1
			if si > #seq then
				si_done = true
				print(string.format("TYPED: done len=%d buf=%s hits3538=%d", blen(), buf_bytes(24), g3538))
				return
			end
			cur = seq[si]
			Keyboard:PressKey(cur.code)
			state = "press"; hold_t = 16000
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:ReleaseAll(); state = "rel"; gap_t = 20000 end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then state = "idle"; end
			if cur and cur.label == "PROBE1" and gap_t == 19999 then
				print(string.format("PROBE1: len=%d buf=%s", blen(), buf_bytes(12)))
			end
		end
	else
		-- post-EXE accelerated watch
		if T % 100000 == 0 then
			local tiles = 0
			for a = 0x8240, 0x8DF8 do
				if (data[a] or 0) == 0x35 and (data[a - 1] or 0) == 0x38 then tiles = tiles + 1 end
			end
			print(string.format("WATCH: t=%d pc=%04X sp=%04X tiles(3835)=%d hits3538=%d hits4d20=%d buf=%s",
				T, cpu.pc, cpu.sp, tiles, g3538, g4d20, buf_bytes(12)))
		end
		if T > 2000000 then
			print(string.format("PROTO: END pc=%04X sp=%04X tiles=%d h3538=%d h4d20=%d",
				cpu.pc, cpu.sp, tiles or -1, g3538, g4d20))
			emu:set_paused(true)
		end
	end
end)
