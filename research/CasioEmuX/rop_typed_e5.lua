-- E5 WALK-PROOF: identical typed fill/trigger as E4 but the proof instrumensation
-- is hits at ROM addresses THE FIRMWARE NEVER EXECUTES normally (mid-instruction
-- junk-codes): 0x21BA, 0x21B9, 0x69B8, 0xB921, 0xBAB9 (the Sigma-template word
-- stream) vs. gadget words. Baselines for these = 0 (verified: firmware flow never
-- touches those PCs). Plus W3538 trace prints, L guarded to stop digits at >=100,
-- walk window limited to the first 4M post-trigger ticks, then state freeze.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x00, 0x10, 0x22, 0x62
local K8, K5 = 0x12, 0x11

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t = "type", 0
local hit = {}
local function note(k) hit[k] = (hit[k] or 0) + 1 end

local function blen() for i = 0, 299 do if (data[0x8154 + i] or 0) == 0 then return i end end return 300 end
local function bdump(lo, n) local s = "" for i = lo, lo + n - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end return s end
local function push(code, label, hold, gap) keys[#keys + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 16000 } end
local function chord(mod, code, label) push(mod, label .. "/m"); push(code, label) end

push(SHIFT, "w1", 12000, 12000); push(AC, "w2", 12000, 24000)
chord(SHIFT, MODE, "setup1"); push(K2, "setup1-2", 30000, 40000)
chord(SHIFT, 0x56, "sigv1")
chord(SHIFT, MODE, "setup2"); push(K2, "setup2-2", 30000, 40000)
chord(SHIFT, 0x56, "sigv2"); push(AC, "AC-clear", 16000, 24000)
chord(ALPHA, 0x33, "X1"); chord(ALPHA, CALC, "eq"); chord(SHIFT, 0x56, "Sigma")
chord(ALPHA, 0x33, "X2"); chord(SHIFT, 0x33, "comma1"); push(K1, "one")
chord(SHIFT, 0x33, "comma2"); push(K1, "one2"); push(KX10, "x10"); push(K9, "nine")
push(CALC, "CALC", 16000, 24000); push(EXE, "EXE", 24000, 30000)
push(AC, "AC", 16000, 24000); push(LEFT, "LEFT", 16000, 16000)
push(DEL, "DEL1"); push(DEL, "DEL2"); push(DEL, "DEL3")
push(K2, "two"); push(CALC, "CALC2", 16000, 24000); push(EXE, "EXE2", 24000, 30000)
push(LEFT, "LEFT2", 16000, 20000)
push(K1, "PROBE1", 16000, 16000)
push(AC, "AC-f", 16000, 24000); push(LEFT, "LEFT-f", 16000, 20000)
for round = 1, 20 do
	for i = 1, 12 do push(round % 2 == 1 and K8 or K5, "d" .. round .. "-" .. i) end
	for i = 1, 4 do chord(SHIFT, 0x56, "s" .. round .. "-" .. i) end
end

-- proof breakpoints: junk-code addresses = firmware-flow-zero baseline
for _, a in ipairs({ 0x21BA, 0x21B9, 0x69B8, 0xB921, 0xBAB9, 0x3536, 0x3538, 0x35BE, 0x2B1E, 0x4D20 }) do
	local key = string.format("k%04X", a)
	break_at(a, function()
		hit[key] = (hit[key] or 0) + 1
		if a == 0x3538 and phase == "trigger" and (hit[key] <= 12 or hit[key] % 500 == 0) then
			local w = {}
			for i = 0, 9, 2 do w[#w + 1] = string.format("%04X", data[cpu.sp + i] | (data[cpu.sp + i + 1] << 8)) end
			print(string.format("W3538 #%d pc01=%04X sp=%04X lr=%04X r0=%02X w=%s", hit[key], cpu.pc, cpu.sp, cpu.lr,
				cpu.r0 & 0xFF, table.concat(w, " ")))
		end
		emu:set_paused(false)
	end)
end

local stopped, trig = false, false
addposttick(function()
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys or stopped then
				phase = "trigger"
				local n = blen()
				print(string.format("TYPE-STOP: len=%d bytes@0x8154=%s", n, n > 80 and "" or bdump(0, n)))
				Keyboard:PressKey(0x60)
				print("TRIG: EXE pressed, len=" .. n)
				return
			end
			if blen() >= 100 and cur and cur.label and cur.label:sub(1, 1) == "s" then
				-- crossed 100 during a Sigma chord: stop typing now (L may be >100; fine)
				stopped = true
				print(string.format("CROSSSTOP: len=%d", blen()))
				return
			end
			if blen() >= 100 and cur and cur.label and cur.label:sub(1, 1) == "d" then
				stopped = true
				print(string.format("HUNDRED: len=%d at key#%d", blen(), ki))
				return
			end
			cur = keys[ki]
			if cur.mod then Keyboard:PressKey(cur.mod); state = "mod"; hold_t = 6000
			else Keyboard:PressKey(cur.code); state = "press"; hold_t = cur.hold end
		elseif state == "mod" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:PressKey(cur.code); state = "press"; hold_t = cur.hold end
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:ReleaseAll(); state = "rel"; gap_t = cur.gap end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then state = "idle" end
		end
	elseif phase == "trigger" then
		final_t = final_t + 1
		if final_t == 24000 then
			Keyboard:ReleaseAll()
			emu:SetClockSpeed(8)
			print("WATCH: 8x")
		elseif final_t > 24000 then
			local wt = final_t - 24000
			if wt % 2000000 == 0 then
				print(string.format("WATCH: pc=%04X sp=%04X proofs={21BA:%d 21B9:%d 69B8:%d B921:%d BAB9:%d} gadgets={3536:%d 3538:%d 35BE:%d 2B1E:%d 4d20:%d}",
					cpu.pc, cpu.sp, hit.k21BA or 0, hit.k21B9 or 0, hit.k69B8 or 0, hit.kB921 or 0, hit.kBAB9 or 0,
					hit.k3536 or 0, hit.k3538 or 0, hit.k35BE or 0, hit.k2B1E or 0, hit.k4D20 or 0))
			end
			if wt > 8000000 then
				print(string.format("END: pc=%04X sp=%04X lr=%04X", cpu.pc, cpu.sp, cpu.lr))
				print(string.format("PROOFS: 21BA=%d 21B9=%d 69B8=%d B921=%d BAB9=%d 3536=%d 3538=%d 35BE=%d 2B1E=%d 4D20=%d",
					hit.k21BA or 0, hit.k21B9 or 0, hit.k69B8 or 0, hit.kB921 or 0, hit.kBAB9 or 0,
					hit.k3536 or 0, hit.k3538 or 0, hit.k35BE or 0, hit.k2B1E or 0, hit.k4D20 or 0))
				print("FINAL-BUF: " .. bdump(0, 120) .. " len=" .. blen())
				emu:set_paused(true)
				phase = "done"
			end
		end
	end
end)
