-- more06_postinput.lua: post-trigger key-input probe (agent MB06PostInput)
-- Q: while the chain runs post AC,<-,EXE, do key presses modify ANY RAM/SFR byte,
--    and can the chain read those bytes?
-- Run 1: rop_e2e trigger + K9 held through the chain hops (per-hop KID/KO log)
--        + post-park sweep: 13 keys, full RAM+SFR diff per key, drift-calibrated.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, DOWN, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x36, 0x00, 0x10, 0x22, 0x62
local UP, RIGHT = 0x27, 0x37
local PAY_IN = 0x8154

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t = "type", 0
local scan_hits = 0

local function blen()
	for i = 0, 99 do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 100
end
local function push(code, label, hold, gap)
	keys[#keys + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 20000 }
end
local function chord(mod, code, label)
	push(mod, label .. "/mod", 16000, 16000)
	push(code, label, 16000, 16000)
end

-- identical typed queue to rop_e2e.lua (verified trigger pipeline)
push(SHIFT, "w1", 12000, 12000); push(AC, "w2", 12000, 24000)
chord(SHIFT, MODE, "setup1")
push(K2, "setup1-digit2", 30000, 40000)
chord(SHIFT, 0x56, "sigma-verify")
chord(SHIFT, MODE, "setup2")
push(K2, "setup2-digit2", 30000, 40000)
chord(SHIFT, 0x56, "sigma-verify2")
push(AC, "AC-clear", 16000, 24000)
chord(ALPHA, 0x33, "X1")
chord(ALPHA, CALC, "eq")
chord(SHIFT, 0x56, "Sigma")
chord(ALPHA, 0x33, "X2")
chord(SHIFT, 0x33, "comma1")
push(K1, "one")
chord(SHIFT, 0x33, "comma2")
push(K1, "one2")
push(KX10, "x10")
push(K9, "nine")
push(CALC, "CALC", 16000, 24000)
push(EXE, "EXE", 24000, 30000)
push(AC, "AC", 16000, 24000)
push(LEFT, "LEFT", 16000, 16000)
push(DEL, "DEL1", 16000, 12000)
push(DEL, "DEL2", 16000, 12000)
push(DEL, "DEL3", 16000, 12000)
push(K2, "two")
push(CALC, "CALC2", 16000, 24000)
push(EXE, "EXE2", 24000, 30000)
push(LEFT, "LEFT2", 16000, 20000)
push(K1, "PROBE1", 16000, 16000)

local len_before_probe = nil

-- per-hop KEYSCAN log: r0 (presence), r2 (KID byte), SFR KID/KO at RT
break_at(0x4D20, function()
	scan_hits = scan_hits + 1
	print(string.format("HOP %d pc=%04X sp=%04X lr=%04X r0=%02X r2=%02X KID=%02X KO=%02X%02X IM=%02X",
		scan_hits, cpu.pc, cpu.sp, cpu.lr, cpu.r0 & 0xFF, cpu.r2 & 0xFF,
		data[0xF040] or 0, data[0xF047] or 0, data[0xF046] or 0, data[0xF041] or 0))
	emu:set_paused(false)
end)

-- ---------- snapshot / diff helpers ----------
local RAM_LO, RAM_HI, SFR_LO, SFR_HI = 0x8000, 0x8DFF, 0xF000, 0xF2FF
local function snap()
	local s = {}
	for a = RAM_LO, RAM_HI do s[a] = (data[a] or 0) & 0xFF end
	for a = SFR_LO, SFR_HI do s[a] = (data[a] or 0) & 0xFF end
	s[0x8E00] = (data[0x8E00] or 0) & 0xFF
	s[0x8E01] = (data[0x8E01] or 0) & 0xFF
	s[0x8E02] = (data[0x8E02] or 0) & 0xFF
	return s
end
local function diffstr(a, b, drift)
	local out = {}
	for k, v in pairs(b) do
		if a[k] ~= v and not (drift and drift[k]) then
			table.insert(out, k)
		end
	end
	table.sort(out)
	local parts = {}
	for _, k in ipairs(out) do
		parts[#parts + 1] = string.format("%04X:%02X->%02X", k, a[k] & 0xFF, b[k] & 0xFF)
	end
	return table.concat(parts, " ")
end
local function keyregs(tag)
	print(string.format("  [%s] KID=%02X IM=%02X KO=%02X%02X KIemu=%02X KOemu=%02X RDY=%02X pc=%04X sp=%04X hits=%d",
		tag, data[0xF040] or 0, data[0xF041] or 0, data[0xF047] or 0, data[0xF046] or 0,
		data[0x8E01] or 0, data[0x8E02] or 0, data[0x8E00] or 0, cpu.pc, cpu.sp, scan_hits))
end

-- sweep: keys pressed one at a time post-park; AC last (known to derail)
local TESTS = { 0x26, 0x37, 0x27, 0x36, 0x00, 0x10, 0x22, 0x60, 0x32, 0x07, 0x17, 0x47, 0x42 }
local NAMES = { ["26"]="LEFT", ["37"]="RIGHT", ["27"]="UP", ["36"]="DOWN", ["00"]="K1",
	["10"]="K2", ["22"]="K9", ["60"]="EXE", ["32"]="DEL", ["07"]="SHIFT", ["17"]="ALPHA",
	["47"]="MODE", ["42"]="AC" }
local sweep = nil  -- {stage, t, idx, drift, sA, sC}

function finish(tag)
	print(string.format("PROTO: %s hits=%d pc=%04X sp=%04X T=%d", tag, scan_hits, cpu.pc, cpu.sp, T))
	phase = "done"
end

addposttick(function()
	T = T + 1
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "final"
				print("INPUT: typing done len=" .. blen())
				return
			end
			cur = keys[ki]
			Keyboard:PressKey(cur.code)
			state = "press"; hold_t = cur.hold
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then
				Keyboard:ReleaseAll()
				state = "rel"; gap_t = cur.gap
			end
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
			Keyboard:PressKey(0x37)   -- Right held: KEYSCAN sees a key
			Keyboard:PressKey(AC)
		elseif final_t == 16001 then
			Keyboard:ReleaseAll()
		elseif final_t == 20001 then
			Keyboard:PressKey(LEFT)
		elseif final_t == 36001 then
			Keyboard:ReleaseAll()
			for e = 0, 49 do data[PAY_IN + e * 2] = 0x0E; data[PAY_IN + e * 2 + 1] = 0x4D end
			local function W(off, v) data[PAY_IN + off] = v & 0xFF; data[PAY_IN + off + 1] = (v >> 8) & 0xFF end
			W(36, 0x4EF2) W(38, 0x4EF2)
			W(48, 0x3538) W(50, 0x3538) W(52, 0xF801) W(54, 0x35BE) W(56, 0x8154)
			print("INPUT: payload 0E4D-flood in, len=" .. blen())
		elseif final_t == 40001 then
			Keyboard:PressKey(0x60)   -- EXE: triggers strcpy flood + chain
			Keyboard:PressKey(0x22)   -- K9 held THROUGH the hops: is it visible in KID/r2 per hop?
		elseif final_t == 60001 then
			emu:SetClockSpeed(16)
			print("WATCH: 16x")
		elseif final_t == 70001 then
			Keyboard:ReleaseAll()
		elseif final_t > 70001 then
			local ft = final_t - 70001
			if sweep == nil then
				if ft >= 100000 and (cpu.pc == 0x4B96 or (cpu.pc >= 0x8500 and cpu.pc <= 0x8700)) then
					sweep = { stage = "calib", t = 0, idx = 1, drift = nil }
					print(string.format("SWEEP: parked ft=%d pc=%04X sp=%04X hits=%d -> drift calib + %d keys",
						ft, cpu.pc, cpu.sp, scan_hits, #TESTS))
				end
			elseif sweep.stage == "calib" then
				sweep.t = sweep.t + 1
				if sweep.t == 1 then
					sweep.s0 = snap()
				elseif sweep.t == 60000 then
					sweep.s1 = snap()
					local d = {}
					for k, v in pairs(sweep.s1) do if sweep.s0[k] ~= v then d[k] = true end end
					sweep.drift = d
					print("DRIFT(no-key 60k): " .. diffstr(sweep.s0, sweep.s1, nil))
					sweep.stage = "press"; sweep.t = 0
				end
			elseif sweep.stage == "press" then
				sweep.t = sweep.t + 1
				local code = TESTS[sweep.idx]
				if sweep.t == 1 then
					sweep.sA = snap()
					Keyboard:PressKey(code)
					sweep.sB = snap()
					print(string.format("KEY %02X(%s) PRESS imm: %s", code, NAMES[string.format("%02X", code)] or "?",
						diffstr(sweep.sA, sweep.sB, sweep.drift)))
					keyregs("held+0")
				elseif sweep.t == 20000 then
					sweep.sC = snap()
					print(string.format("KEY %02X(%s) HELD 20k: %s", code, NAMES[string.format("%02X", code)] or "?",
						diffstr(sweep.sA, sweep.sC, sweep.drift)))
					keyregs("held+20k")
					Keyboard:ReleaseAll()
					sweep.stage = "rel"; sweep.t = 0
				end
			elseif sweep.stage == "rel" then
				sweep.t = sweep.t + 1
				if sweep.t == 8000 then
					local sD = snap()
					local code = TESTS[sweep.idx]
					print(string.format("KEY %02X(%s) RELEASED 8k: %s", code, NAMES[string.format("%02X", code)] or "?",
						diffstr(sweep.sC, sD, sweep.drift)))
					keyregs("rel+8k")
					sweep.idx = sweep.idx + 1
					if sweep.idx > #TESTS then
						print(string.format("SWEEP: COMPLETE %d keys, final pc=%04X sp=%04X hits=%d",
							#TESTS, cpu.pc, cpu.sp, scan_hits))
						finish("SWEEP-DONE")
					else
						sweep.stage = "press"; sweep.t = 0
					end
				end
			end
			if final_t > 2500000 and phase ~= "done" then finish("TIMEOUT") end
		end
	end
end)
