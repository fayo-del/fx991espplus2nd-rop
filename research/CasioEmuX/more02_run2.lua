-- MB02 run2: attacker-CHOSEN values in unflooded RAM 0x8000-0x8153?
-- Type 123456789012345 EXE (Ans store into eval area), then rop_e2e tail, STO attempts,
-- then fire the flood; dumps A/B/B1/B2/B3/B4 pre-trigger and C post-flood (hop #1).
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, K1, K2, K9 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x00, 0x10, 0x22
local D0, D1, D2, D3, D4, D5, D6, D7, D8, D9 =
	0x05, 0x00, 0x10, 0x20, 0x01, 0x11, 0x21, 0x02, 0x12, 0x22
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
local function push(code, label, expect, hold, gap)
	keys[#keys + 1] = { code = code, label = label, expect = expect, hold = hold or 16000, gap = gap or 20000 }
end
local function act(a) keys[#keys + 1] = a end
local function chord(mod, code, label, expect)
	push(mod, label .. "/mod", nil, 16000, 16000)
	push(code, label, expect, 16000, 16000)
end
local function digits(seq) for _, d in ipairs(seq) do push(d, "d" .. string.format("%02X", d), nil, 16000, 18000) end end

local function hexrange(lo, hi)
	local s = ""
	for a = lo, hi do s = s .. string.format("%02X", (data[a] or 0) & 0xFF) end
	return s
end
local function dump_low(tag)
	local f = io.open(OUT .. "mb02_r2_" .. tag .. "_low.bin", "wb")
	for a = LOW_LO, LOW_HI do f:write(string.char((data[a] or 0) & 0xFF)) end
	f:close()
	print(string.format("DUMP %s low=%s", tag, hexrange(LOW_LO, LOW_HI)))
	print(string.format("     %s buf(len=%d)=%s", tag, blen(), bdump(40)))
end
local function sfr(tag)
	print(string.format("SFR %s: 8E00-02=%s F040-4F=%s F000-0F=%s", tag,
		hexrange(0x8E00, 0x8E02), hexrange(0xF040, 0xF04F), hexrange(0xF000, 0xF00F)))
	print("PN " .. tag .. ":"); pn(0x8000); pn(0x8009); pn(0x8010); pn(0x801E); pn(0x8020); pn(0x8030)
end

-- warm-up
push(SHIFT, "w1", nil, 12000, 12000); push(AC, "w2", nil, 12000, 24000)
act { dump = "A" }; act { sfr = "A" }
-- type 123456789012345
digits { D1, D2, D3, D4, D5, D6, D7, D8, D9, D0, D1, D2, D3, D4, D5 }
act { dump = "B" }
-- CALC EXE -> Ans = 123456789012345
push(CALC, "CALC", nil, 16000, 24000)
push(EXE, "EXE", nil, 24000, 30000)
act { dump = "B1" }; act { sfr = "B1" }
-- rop_e2e proven tail: AC LEFT DEL DEL DEL 2 CALC EXE LEFT PROBE1
push(AC, "AC", nil, 16000, 24000)
push(LEFT, "LEFT", nil, 16000, 16000)
push(DEL, "DEL1", nil, 16000, 12000)
push(DEL, "DEL2", nil, 16000, 12000)
push(DEL, "DEL3", nil, 16000, 12000)
push(K2, "two", nil, 16000, 20000)
push(CALC, "CALC2", nil, 16000, 24000)
push(EXE, "EXE2", nil, 24000, 30000)
act { dump = "B2" }   -- Ans now = eval of remaining buffer
-- STO attempt 1: 6789 ->A via SHIFT+0x03
push(AC, "AC2", nil, 16000, 20000)
digits { D6, D7, D8, D9 }
chord(SHIFT, 0x03, "sto?")
chord(ALPHA, 0x04, "varA")
push(EXE, "EXE3", nil, 24000, 30000)
act { dump = "B3" }
-- STO attempt 2: 4321 ->B via SHIFT+0x30
push(AC, "AC3", nil, 16000, 20000)
digits { D4, D3, D2, D1 }
chord(SHIFT, 0x30, "sto2?")
chord(ALPHA, 0x14, "varB")
push(EXE, "EXE4", nil, 24000, 30000)
act { dump = "B4" }; act { sfr = "B4" }
push(LEFT, "LEFT2", nil, 16000, 20000)
push(K1, "PROBE1", nil, 16000, 16000)

break_at(0x4D20, function()
	scan_hits = scan_hits + 1
	if scan_hits == 1 then
		print(string.format("TRIGGER: hop #1 pc=%04X sp=%04X KID(r2)=%02X r0=%02X", cpu.pc, cpu.sp, cpu.r2 & 0xFF, cpu.r0 & 0xFF))
		dump_low("C")
		sfr("C")
	end
	parked = true
	cpu.csr = 0
	cpu.pc = 0x4EF2
	cpu.lr = 0x4EF2
	emu:set_paused(false)
end)

local len_before_probe = nil
addposttick(function()
	T = T + 1
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "final"
				print("INPUT: typing done len=" .. blen() .. " buf=" .. bdump(48))
				return
			end
			cur = keys[ki]
			if cur.code then
				Keyboard:PressKey(cur.code)
				state = "press"; hold_t = cur.hold
			elseif cur.dump then dump_low(cur.dump)
			elseif cur.sfr then sfr(cur.sfr)
			end
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:ReleaseAll(); state = "rel"; gap_t = cur.gap end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then
				if cur.label == "PROBE1" then
					len_before_probe = len_before_probe or blen()
					print(string.format("PROBE1: before=%d after=%d %s", len_before_probe, blen(),
						blen() > len_before_probe and "GREW(bad)" or "NOT-INSERTED(good)"))
				end
				state = "idle"
			end
		end
	elseif phase == "final" then
		final_t = final_t + 1
		if final_t == 1 then
			dump_low("B5"); sfr("B5")
			Keyboard:PressKey(0x37); Keyboard:PressKey(AC)
		elseif final_t == 8000 then
			sfr("held")
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
				print("MB02-R2: done"); emu:set_paused(true); phase = "done"
			elseif final_t > 2500000 then
				print(string.format("NO-TRIGGER hits=%d pc=%04X sp=%04X", scan_hits, cpu.pc, cpu.sp))
				emu:set_paused(true); phase = "done"
			end
		end
	end
end)
