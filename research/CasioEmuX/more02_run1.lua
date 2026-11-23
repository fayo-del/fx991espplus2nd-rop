-- MB02 run1: how many bytes in UNFLOODED RAM (0x8000-0x8153) does typing control,
-- and do they survive the AC,<-,EXE flood?  Standard rop_e2e typed recipe + trigger.
-- Dumps: A=pristine(after warmup AC)  B=after formula typed  B2=after full typed queue
--        (pre-trigger, final_t==1)   C=post-flood (first KEYSCAN hop 0x4D20)
-- SFR window 0xF000-0xF0FF + 0x8E00-0x8E02 sampled at A/B/B2/C and while keys held.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, DOWN, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x36, 0x00, 0x10, 0x22, 0x62
local PAY_IN = 0x8154
local OUT = "/home/yoxu/Projects/fx991espplus2nd/research/CasioEmuX/"
local LOW_LO, LOW_HI = 0x8000, 0x8153   -- unflooded RAM

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
local function act(a) keys[#keys + 1] = a end   -- {dump=tag} / {sfr=tag} pseudo-entry
local function chord(mod, code, label, expect)
	push(mod, label .. "/mod", nil, 16000, 16000)
	push(code, label, expect, 16000, 16000)
end

local function hexrange(lo, hi)
	local s = ""
	for a = lo, hi do s = s .. string.format("%02X", (data[a] or 0) & 0xFF) end
	return s
end
local function dump_low(tag)
	local f = io.open(OUT .. "mb02_r1_" .. tag .. "_low.bin", "wb")
	for a = LOW_LO, LOW_HI do f:write(string.char((data[a] or 0) & 0xFF)) end
	f:close()
	print(string.format("DUMP %s low[%04X-%04X]=%s", tag, LOW_LO, LOW_HI, hexrange(LOW_LO, LOW_HI)))
end
local function sfr(tag)
	local f = io.open(OUT .. "mb02_r1_" .. tag .. "_sfr.bin", "wb")
	for a = 0xF000, 0xF0FF do f:write(string.char((data[a] or 0) & 0xFF)) end
	f:close()
	print(string.format("SFR %s: 8E00-02=%s  F040-4F=%s  F000-0F=%s  F0F0-FF=%s", tag,
		hexrange(0x8E00, 0x8E02), hexrange(0xF040, 0xF04F), hexrange(0xF000, 0xF00F), hexrange(0xF0F0, 0xF0FF)))
	-- try reading calculator numbers at candidate eval/Ans slots
	local ok, e = pcall(function()
		print(string.format("PN %s: 8000=%s 8009=%s 8010=%s 801E=%s", tag,
			tostring(pn(0x8000)), tostring(pn(0x8009)), tostring(pn(0x8010)), tostring(pn(0x801E))))
	end)
	if not ok then print("PN " .. tag .. " failed: " .. tostring(e)) end
end

-- warm-up
push(SHIFT, "w1", nil, 12000, 12000); push(AC, "w2", nil, 12000, 24000)
act { dump = "A" }   -- pristine low-RAM snapshot (post-boot, after warm-up AC)
act { sfr = "A" }
-- SETUP open + digit-2 (LineIO select) — same as rop_e2e
chord(SHIFT, MODE, "setup1")
push(K2, "setup1-digit2", nil, 30000, 40000)
chord(SHIFT, 0x56, "sigma-verify")
chord(SHIFT, MODE, "setup2")
push(K2, "setup2-digit2", nil, 30000, 40000)
chord(SHIFT, 0x56, "sigma-verify2")
push(AC, "AC-clear", nil, 16000, 24000)
-- formula: X = Sigma(X,1,1x10^9
chord(ALPHA, 0x33, "X1", { { 0x58 } })
chord(ALPHA, CALC, "eq", { { 0x3D } })
chord(SHIFT, 0x56, "Sigma", { { 0x69, 0xB8 } })
chord(ALPHA, 0x33, "X2", { { 0x58 } })
chord(SHIFT, 0x33, "comma1", { { 0x2C } })
push(K1, "one", { { 0x31 } })
chord(SHIFT, 0x33, "comma2", { { 0x2C } })
push(K1, "one2", { { 0x31 } })
push(KX10, "x10", { { 0x74 } })
push(K9, "nine", { { 0x39 } })
act { dump = "B" }   -- after formula typed
act { sfr = "B" }
-- calc = ac <-
push(CALC, "CALC", nil, 16000, 24000)
push(EXE, "EXE", nil, 24000, 30000)      -- evaluates -> Ans store lands in 0x80xx?
act { dump = "B1" }  -- after first EXE (Ans evaluated)
act { sfr = "B1" }
push(AC, "AC", nil, 16000, 24000)
push(LEFT, "LEFT", nil, 16000, 16000)
-- del del del 2
push(DEL, "DEL1", nil, 16000, 12000)
push(DEL, "DEL2", nil, 16000, 12000)
push(DEL, "DEL3", nil, 16000, 12000)
push(K2, "two", { { 0x32 } })
-- calc = <-
push(CALC, "CALC2", nil, 16000, 24000)
push(EXE, "EXE2", nil, 24000, 30000)
push(LEFT, "LEFT2", nil, 16000, 20000)
push(K1, "PROBE1", nil, 16000, 16000)

break_at(0x4D20, function()
	scan_hits = scan_hits + 1
	if scan_hits == 1 then
		print(string.format("TRIGGER: KEYSCAN hop #1 pc=%04X sp=%04X KID(r2)=%02X r0=%02X dsr=%02X",
			cpu.pc, cpu.sp, cpu.r2 & 0xFF, cpu.r0 & 0xFF, cpu.dsr))
		dump_low("C")   -- post-flood unflooded RAM
		sfr("C")
		print("DUMP C: buf=" .. bdump(48))
	end
	-- park the chain immediately after measurement
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
			elseif cur.dump then
				dump_low(cur.dump)
			elseif cur.sfr then
				sfr(cur.sfr)
			else
				print("?? unknown entry")
			end
		elseif state == "press" then
			hold_t = hold_t - 1
			if cur.label == "PROBE1" and hold_t == 8000 then
				sfr("probe1hold")   -- SFR while a key is held
			end
			if hold_t <= 0 then
				Keyboard:ReleaseAll()
				state = "rel"; gap_t = cur.gap
			end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then
				local lb = cur.label
				if lb == "sigma-verify" or lb == "sigma-verify2" then
					local n = blen()
					local bare = n >= 2 and (data[0x8154 + n - 2] == 0x69) and (data[0x8154 + n - 1] == 0xB8)
					print(string.format("SIGMA: %s len=%d bare=%s", lb, n, tostring(bare)))
				elseif lb == "PROBE1" then
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
			dump_low("B2")   -- after FULL typed queue, pre-trigger
			sfr("B2")
			Keyboard:PressKey(0x37)   -- Right held: KEYSCAN sees a key
			Keyboard:PressKey(AC)
		elseif final_t == 8000 then
			sfr("held-right-ac")     -- SFR while trigger keys held
		elseif final_t == 16001 then
			Keyboard:ReleaseAll()
		elseif final_t == 20001 then
			Keyboard:PressKey(LEFT)
		elseif final_t == 36001 then
			Keyboard:ReleaseAll()
			for e = 0, 49 do data[PAY_IN + e * 2] = 0x0E; data[PAY_IN + e * 2 + 1] = 0x4D end
			local function W(off, v) data[PAY_IN + off] = v & 0xFF; data[PAY_IN + off + 1] = (v >> 8) & 0xFF end
			W(48, 0x3538) W(50, 0x3538) W(52, 0xF801) W(54, 0x35BE) W(56, 0x8154)
			print("INPUT: payload in, len=" .. blen())
		elseif final_t == 40001 then
			Keyboard:PressKey(0x60)   -- EXE: fire the flood
		elseif final_t == 60001 then
			Keyboard:ReleaseAll()
			emu:SetClockSpeed(16)
			print("WATCH: 16x")
		elseif final_t > 60001 then
			if (final_t - 60001) % 200000 == 0 then
				print(string.format("WATCH: t=%d pc=%04X sp=%04X hits=%d parked=%s",
					final_t, cpu.pc, cpu.sp, scan_hits, tostring(parked)))
			end
			if parked and final_t > 60001 + 60000 then
				print("MB02-R1: parked after trigger, done")
				emu:set_paused(true)
				phase = "done"
			elseif final_t > 2500000 then
				print(string.format("NO-TRIGGER hits=%d pc=%04X sp=%04X", scan_hits, cpu.pc, cpu.sp))
				emu:set_paused(true)
				phase = "done"
			end
		end
	end
end)
