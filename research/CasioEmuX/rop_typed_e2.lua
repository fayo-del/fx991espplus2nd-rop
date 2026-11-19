-- E2: post-AC typing experiments.
-- Phase 1: fresh-input atlas extension: '0', ALPHA+digit vars (A..F hunt),
--          SHIFT variants on digits, 'M', 'Ans' -- measure inserted bytes.
-- Phase 2: e2e head verbatim -> PROBE1 -> AC -> LEFT -> typed fill with
--          adaptive per-keystroke measurement, cursor-exit retries:
--            24x('8','5'), RIGHT, 30x('8','5'), SIG templates x6,
--            20x('8','5') ... until blen>=100 (or keystroke budget).
--          settle-sample, then EXE trigger WITHOUT any data[] injection.
-- Heavy post-trigger instrumentation: pc/sp/lr sampler + gadget hits.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT, K0, K1, K2, K4, K5, K6, K8, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37, 0x64, 0x00, 0x10, 0x01, 0x11, 0x21, 0x12, 0x22, 0x62

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t = "type", 0
local hits = { k4d20 = 0, k3538 = 0, k35be = 0, k2b1e = 0, other = {} }

local function blen()
	for i = 0, 299 do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 300
end
local function bdump(lo, n)
	local s = ""
	for i = lo, lo + n - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end
	return s
end
local function push(code, label, hold, gap, sample)
	keys[#keys + 1] = { code = code, label = label, sample = sample, hold = hold or 16000, gap = gap or 16000 }
end
local function chord(mod, code, label, sample)
	push(mod, label .. "/mod", nil, false)
	push(code, label, nil, nil, sample)
end

-- ===== phase 1: atlas extension (fresh input after boot warm-up) =====
push(SHIFT, "w1", 12000, 12000); push(AC, "w2", 12000, 12000)
push(SHIFT, "setup1/mod"); push(MODE, "setup1"); push(K2, "setup1-2", 30000, 40000)
push(AC, "p1-clear", 16000, 24000)
-- the fresh-input probes
push(K0, "z0", nil, nil, true)                    -- digit 0
push(AC, "p1c0", 16000, 24000)
chord(ALPHA, K4,  "A4", true)                     -- ALPHA+4 = ?
push(AC, "p1c1", 16000, 24000)
chord(ALPHA, K5,  "A5", true)                     -- ALPHA+5 = ?
push(AC, "p1c2", 16000, 24000)
chord(ALPHA, K6,  "A6", true)
push(AC, "p1c3", 16000, 24000)
chord(ALPHA, K1,  "A1", true)
push(AC, "p1c4", 16000, 24000)
chord(ALPHA, K2,  "A2", true)
push(AC, "p1c5", 16000, 24000)
chord(SHIFT, K4,  "S4", true)                     -- SHIFT+4
push(AC, "p1c6", 16000, 24000)
chord(SHIFT, K0,  "S0", true)                     -- SHIFT+0
push(AC, "p1c7", 16000, 24000)

-- ===== phase 2: e2e head =====
chord(SHIFT, MODE, "setup2"); push(K2, "setup2-digit2", 30000, 40000)
chord(SHIFT, 0x56, "sigv1")
push(AC, "AC-clear", 16000, 24000)
chord(ALPHA, 0x33, "X1"); chord(ALPHA, CALC, "eq"); chord(SHIFT, 0x56, "Sigma")
chord(ALPHA, 0x33, "X2"); chord(SHIFT, 0x33, "comma1"); push(K1, "one")
chord(SHIFT, 0x33, "comma2"); push(K1, "one2"); push(KX10, "x10"); push(K9, "nine")
push(CALC, "CALC", 16000, 24000); push(EXE, "EXE", 24000, 30000)
push(AC, "AC", 16000, 24000); push(LEFT, "LEFT", 16000, 16000)
push(DEL, "DEL1", 16000, 12000); push(DEL, "DEL2", 16000, 12000); push(DEL, "DEL3", 16000, 12000)
push(K2, "two"); push(CALC, "CALC2", 16000, 24000); push(EXE, "EXE2", 24000, 30000)
push(LEFT, "LEFT2", 16000, 20000)
push(K1, "PROBE1", 16000, 16000)
-- ===== post-AC typed fill ===== (e2e order: AC,LEFT first, THEN payload)
push(AC, "AC-f", 16000, 24000); push(LEFT, "LEFT-f", 16000, 20000)
for i = 1, 24 do push(i % 2 == 1 and K8 or K5, "p-" .. i, nil, nil, true) end
push(RIGHT, "EXIT1", 16000, 20000)
for i = 25, 60 do push(i % 2 == 1 and K8 or K5, "p-" .. i, nil, nil, true) end
push(RIGHT, "EXIT2", 16000, 20000)
chord(SHIFT, 0x56, "SIGx1"); chord(SHIFT, 0x56, "SIGx2"); chord(SHIFT, 0x56, "SIGx3")
for i = 61, 80 do push(i % 2 == 1 and K8 or K5, "p-" .. i, nil, nil, true) end
push(RIGHT, "EXIT3", 16000, 20000)
chord(SHIFT, 0x56, "SIGx4"); chord(SHIFT, 0x56, "SIGx5"); chord(SHIFT, 0x56, "SIGx6")
for i = 81, 100 do push(i % 2 == 1 and K8 or K5, "p-" .. i, nil, nil, true) end
-- (NOTE: EXE trigger is appended dynamically below if len>=100)

local settle = 0
local function sample(tag)
	local n = blen()
	print(string.format("S %-8s len=%3d tail=%s", tag, n, bdump(math.max(0, n - 10), 10)))
	return n
end

break_at(0x4D20, function() hits.k4d20 = hits.k4d20 + 1; emu:set_paused(false) end)
break_at(0x3538, function()
	hits.k3538 = hits.k3538 + 1
	if hits.k3538 <= 12 then
		local w = {}
		for i = 0, 9, 2 do w[#w + 1] = string.format("%04X", data[cpu.sp + i] | (data[cpu.sp + i + 1] << 8)) end
		print(string.format("HIT-3538 #%d sp=%04X lr=%04X r0=%02X w=%s", hits.k3538, cpu.sp, cpu.lr, cpu.r0 & 0xFF, table.concat(w, " ")))
	end
	emu:set_paused(false)
end)
break_at(0x35BE, function()
	hits.k35be = hits.k35be + 1
	if phase == "final" and hits.k35be % 50 == 0 then
		print(string.format("HIT-35BE #%d sp=%04X ER2=%04X r0=%02X EA=%04X lr=%04X", hits.k35be, cpu.sp,
			(cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF), cpu.r0 & 0xFF, cpu.ea, cpu.lr))
	end
	emu:set_paused(false)
end)
break_at(0x2B1E, function()
	hits.k2b1e = hits.k2b1e + 1
	if hits.k2b1e > 30 then emu:set_paused(false) return end
	print(string.format("HIT-2B1E #%d sp=%04X lr=%04X", hits.k2b1e, cpu.sp, cpu.lr))
	emu:set_paused(false)
end)

addposttick(function()
	T = T + 1
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "settle"
				print(string.format("INPUT: done len=%d buf0=%s", blen(), bdump(0, 64)))
				return
			end
			cur = keys[ki]
			if cur.code then
				if keys[ki - 1] and keys[ki - 1].label == cur.label .. "/mod" then
					-- modifier still held? modifier released during its own gap; press plain
				end
				Keyboard:PressKey(cur.code); state = "press"; hold_t = cur.hold
			end
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:ReleaseAll(); state = "rel"; gap_t = cur.gap end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then
				if cur.label == "PROBE1" then
					print("PROBE1: len=" .. blen())
				elseif cur.sample then
					sample(cur.label)
				elseif cur.label == "SIGx1" or cur.label == "SIGx2" or cur.label == "SIGx3"
					or cur.label == "SIGx4" or cur.label == "SIGx5" or cur.label == "SIGx6" then
					sample(cur.label)
				end
				state = "idle"
			end
		end
	elseif phase == "settle" then
		settle = settle + 1
		if settle == 2000 then print("SETTLE: len=" .. blen()) end
		if settle == 20000 then
			print(string.format("SETTLE2: len=%d pc=%04X sp=%04X", blen(), cpu.pc, cpu.sp))
			phase = "final"
		end
	elseif phase == "final" then
		final_t = final_t + 1
		if final_t == 1 then
			Keyboard:PressKey(0x60)   -- EXE trigger
		elseif final_t == 20001 then
			Keyboard:ReleaseAll()
			emu:SetClockSpeed(16)
			print("WATCH: 16x len=" .. blen() .. " buf=" .. bdump(0, 40))
		elseif final_t > 20001 then
			if (final_t - 20001) % 50000 == 0 then
				local tiled = 0
				for a = 0x8240, 0x8DF8 do
					if (data[a] or 0) == 0x38 and (data[a + 1] or 0) == 0x35 then tiled = tiled + 1 end
				end
				local w = {}
				for i = 0, 9, 2 do w[#w + 1] = string.format("%04X", data[cpu.sp + i] | (data[cpu.sp + i + 1] << 8)) end
				print(string.format("WATCH: t=%d pc=%04X sp=%04X lr=%04X tiles=%d h={%d,%d,%d,%d} w=%s",
					final_t, cpu.pc, cpu.sp, cpu.lr, tiled, hits.k4d20, hits.k3538, hits.k35be, hits.k2b1e,
					table.concat(w, " ")))
			end
			if final_t > 3202001 then
				print(string.format("END: pc=%04X sp=%04X lr=%04X h={4d20:%d 3538:%d 35be:%d 2b1e:%d}",
					cpu.pc, cpu.sp, cpu.lr, hits.k4d20, hits.k3538, hits.k35be, hits.k2b1e))
				emu:set_paused(true)
				phase = "done"
			end
		end
	end
end)
