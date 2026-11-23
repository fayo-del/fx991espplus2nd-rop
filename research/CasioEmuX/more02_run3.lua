-- MB02 run3: do OTHER MODES (MODE menu digits 1..8) write attacker data below 0x8154?
-- For each mode: AC, MODE, digit, then enter 2 rows of data (11 EXE 22 EXE), dump low RAM.
-- Then fire the flood and dump C post-trigger.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26
local D1, D2 = 0x00, 0x10
local PAY_IN = 0x8154
local OUT = "/home/yoxu/Projects/fx991espplus2nd/research/CasioEmuX/"
local LOW_LO, LOW_HI = 0x8000, 0x8153

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t = "type", 0
local scan_hits = 0
local parked = false

local function blen()
	for i = 0, 99 do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 100
end
local function bdump(n)
	local s = ""
	for i = 0, (n or 32) - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end
	return s
end
local function push(code, label, hold, gap)
	keys[#keys + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 20000 }
end
local function act(a) keys[#keys + 1] = a end
local function hexrange(lo, hi)
	local s = ""
	for a = lo, hi do s = s .. string.format("%02X", (data[a] or 0) & 0xFF) end
	return s
end
local function dump_low(tag)
	local f = io.open(OUT .. "mb02_r3_" .. tag .. "_low.bin", "wb")
	for a = LOW_LO, LOW_HI do f:write(string.char((data[a] or 0) & 0xFF)) end
	f:close()
	print(string.format("DUMP %s: 8000-60=%s", tag, hexrange(0x8000, 0x8060)))
	print(string.format("     %s: 8100-153=%s buf(len=%d)=%s", tag, hexrange(0x8100, 0x8153), blen(), bdump(32)))
end

-- warm-up
push(SHIFT, "w1", 12000, 12000); push(AC, "w2", 12000, 24000)
act { dump = "A" }
-- mode sweep: digits 1..8
local MD = { 0x00, 0x10, 0x20, 0x01, 0x11, 0x21, 0x02, 0x12 }
for i, d in ipairs(MD) do
	push(AC, "ac" .. i, 16000, 20000)
	push(MODE, "mode" .. i, 16000, 30000)
	push(d, "mdigit" .. i, 30000, 50000)
	-- enter two rows of data
	push(D1, "r1a" .. i, 16000, 16000); push(D1, "r1b" .. i, 16000, 16000)
	push(EXE, "r1exe" .. i, 20000, 24000)
	push(D2, "r2a" .. i, 16000, 16000); push(D2, "r2b" .. i, 16000, 16000)
	push(EXE, "r2exe" .. i, 20000, 24000)
	act { dump = "M" .. i }
end
-- back to COMP and fire the trigger (rop_e2e final phase)
push(AC, "ac-final", 16000, 20000)
push(LEFT, "LEFT-final", 16000, 20000)
push(0x00, "PROBE1", 16000, 16000)

break_at(0x4D20, function()
	scan_hits = scan_hits + 1
	if scan_hits == 1 then
		print(string.format("TRIGGER: hop #1 pc=%04X sp=%04X KID=%02X", cpu.pc, cpu.sp, cpu.r2 & 0xFF))
		dump_low("C")
		print("SFR C: 8E00-02=" .. hexrange(0x8E00, 0x8E02) .. " F040-4F=" .. hexrange(0xF040, 0xF04F))
	end
	parked = true
	cpu.csr = 0; cpu.pc = 0x4EF2; cpu.lr = 0x4EF2
	emu:set_paused(false)
end)

addposttick(function()
	T = T + 1
	if T == 2 then emu:SetClockSpeed(8) end
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "final"
				print("INPUT: typing done len=" .. blen() .. " buf=" .. bdump(32))
				return
			end
			cur = keys[ki]
			if cur.code then
				Keyboard:PressKey(cur.code)
				state = "press"; hold_t = cur.hold
			elseif cur.dump then dump_low(cur.dump)
			end
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:ReleaseAll(); state = "rel"; gap_t = cur.gap end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then state = "idle" end
		end
	elseif phase == "final" then
		final_t = final_t + 1
		if final_t == 1 then
			dump_low("B")
			Keyboard:PressKey(0x37); Keyboard:PressKey(AC)
		elseif final_t == 16001 then Keyboard:ReleaseAll()
		elseif final_t == 20001 then Keyboard:PressKey(LEFT)
		elseif final_t == 36001 then
			Keyboard:ReleaseAll()
			for e = 0, 49 do data[PAY_IN + e * 2] = 0x0E; data[PAY_IN + e * 2 + 1] = 0x4D end
			local function W(off, v) data[PAY_IN + off] = v & 0xFF; data[PAY_IN + off + 1] = (v >> 8) & 0xFF end
			W(48, 0x3538) W(50, 0x3538) W(52, 0xF801) W(54, 0x35BE) W(56, 0x8154)
			print("INPUT: payload in, len=" .. blen())
		elseif final_t == 40001 then Keyboard:PressKey(0x60)
		elseif final_t == 60001 then
			Keyboard:ReleaseAll(); emu:SetClockSpeed(16); print("WATCH: 16x")
		elseif final_t > 60001 then
			if (final_t - 60001) % 200000 == 0 then
				print(string.format("WATCH: t=%d pc=%04X sp=%04X hits=%d", final_t, cpu.pc, cpu.sp, scan_hits))
			end
			if parked and final_t > 60001 + 60000 then
				print("MB02-R3: done"); emu:set_paused(true); phase = "done"
			elseif final_t > 2500000 then
				print(string.format("NO-TRIGGER hits=%d pc=%04X sp=%04X", scan_hits, cpu.pc, cpu.sp))
				emu:set_paused(true); phase = "done"
			end
		end
	end
end)
