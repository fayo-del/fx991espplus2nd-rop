-- E1: the post-LOCK insert experiment + walk mechanics capture.
-- e2e-verbatim head (warm-up..PROBE1) then TYPED post-lock: '85' digits, then
-- Sigma( templates xN (8 bytes each), sampled per keystroke, until blen>=100
-- or 100 keystrokes. Then AC <- EXE trigger. NO data[] injection anywhere.
-- Watch: @4D20/@3538/@35BE/@2B1E hits + periodic pc/sp/lr/words sampler.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x00, 0x10, 0x22, 0x62
local K8, K5 = 0x12, 0x11

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t, snap = "type", 0, {}
local hits = { k4d20 = 0, k3538 = 0, k35be = 0, k2b1e = 0 }

local function blen()
	for i = 0, 199 do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 200
end
local function bdump(lo, n)
	local s = ""
	for i = lo, lo + n - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end
	return s
end
local function black(t)  -- post-lock typed insert with a sample after it
	keys[#keys + 1] = { code = t.code, label = t.label, sample = t.sample, hold = 16000, gap = 16000 }
end
local function push(code, label, hold, gap)
	keys[#keys + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 20000 }
end
local function chord(mod, code, label)
	push(mod, label .. "/mod", 16000, 16000)
	push(code, label, 16000, 16000)
end

-- ===== e2e-verbatim head =====
push(SHIFT, "w1", 12000, 12000); push(AC, "w2", 12000, 24000)
chord(SHIFT, MODE, "setup1"); push(K2, "setup1-digit2", 30000, 40000)
chord(SHIFT, 0x56, "sigv1")
chord(SHIFT, MODE, "setup2"); push(K2, "setup2-digit2", 30000, 40000)
chord(SHIFT, 0x56, "sigv2"); push(AC, "AC-clear", 16000, 24000)
chord(ALPHA, 0x33, "X1"); chord(ALPHA, CALC, "eq"); chord(SHIFT, 0x56, "Sigma")
chord(ALPHA, 0x33, "X2"); chord(SHIFT, 0x33, "comma1"); push(K1, "one")
chord(SHIFT, 0x33, "comma2"); push(K1, "one2"); push(KX10, "x10"); push(K9, "nine")
push(CALC, "CALC", 16000, 24000); push(EXE, "EXE", 24000, 30000)
push(AC, "AC", 16000, 24000); push(LEFT, "LEFT", 16000, 16000)
push(DEL, "DEL1", 16000, 12000); push(DEL, "DEL2", 16000, 12000); push(DEL, "DEL3", 16000, 12000)
push(K2, "two"); push(CALC, "CALC2", 16000, 24000); push(EXE, "EXE2", 24000, 30000)
push(LEFT, "LEFT2", 16000, 20000)
push(K1, "PROBE1", 16000, 16000)
-- ===== E1 typed post-lock =====
for i = 1, 5 do black({ code = K8, label = "d8-" .. i, sample = true }) end
for i = 1, 5 do black({ code = K5, label = "d5-" .. i, sample = true }) end
for i = 1, 20 do black({ code = 0x56, mod = SHIFT, label = "SIG" .. i, sample = true }) end
for i = 1, 10 do black({ code = K8, label = "e8-" .. i, sample = true }) end
for i = 1, 10 do black({ code = 0x56, mod = SHIFT, label = "SIGb" .. i, sample = true }) end
-- ===== trigger =====
push(AC, "AC-f"); push(LEFT, "LEFT-f"); push(EXE, "EXE-f", 24000, 30000)

local done_typing = false
local maxb, growth_log = 0, {}

for a, n in pairs(hits) do end

break_at(0x4D20, function()
	hits.k4d20 = hits.k4d20 + 1
	emu:set_paused(false)
end)
break_at(0x3538, function()
	hits.k3538 = hits.k3538 + 1
	if hits.k3538 <= 8 or hits.k3538 % 200 == 0 then
		local w = {}
		for i = 0, 7, 2 do w[#w + 1] = string.format("%04X", data[cpu.sp + i] | (data[cpu.sp + i + 1] << 8)) end
		print(string.format("HIT-3538 #%d sp=%04X lr=%04X r0=%02X w=%s", hits.k3538, cpu.sp, cpu.lr, cpu.r0 & 0xFF, table.concat(w, " ")))
	end
	emu:set_paused(false)
end)
break_at(0x35BE, function()
	hits.k35be = hits.k35be + 1
	if hits.k35be > 5 and phase ~= "final" then emu:set_paused(false) return end
	if hits.k35be <= 40 and hits.k35be % 8 == 0 then
		print(string.format("HIT-35BE #%d phase=%s sp=%04X ER2=%04X r0=%02X EA=%04X lr=%04X", hits.k35be, phase, cpu.sp,
			(cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF), cpu.r0 & 0xFF, cpu.ea, cpu.lr))
	end
	emu:set_paused(false)
end)
break_at(0x2B1E, function()
	hits.k2b1e = hits.k2b1e + 1
	if hits.k2b1e <= 8 or hits.k2b1e % 200 == 0 then
		print(string.format("HIT-2B1E #%d sp=%04X lr=%04X", hits.k2b1e, cpu.sp, cpu.lr))
	end
	emu:set_paused(false)
end)

local function sample(tag)
	local n = blen()
	maxb = math.max(maxb, n)
	print(string.format("S %s len=%3d buf[%d..]=%s", tag, n, math.max(0, n - 12), bdump(math.max(0, n - 12), 12)))
end

addposttick(function()
	T = T + 1

	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "final"
				print(string.format("INPUT: done len=%d max=%d", blen(), maxb))
				print("INPUT: buffer " .. bdump(0, 104))
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
			if gap_t <= 0 then
				if cur.label == "PROBE1" then
					print("PROBE1: len=" .. blen())
					sample("after-PROBE1")
				elseif cur.sample then
					sample(cur.label)
				end
				state = "idle"
			end
		end

	elseif phase == "final" then
		final_t = final_t + 1
		if final_t == 1 then
			for a = 0x8100, 0x8E7F do snap[a] = (data[a] or 0) & 0xFF end
			sample("pre-AC")
		elseif final_t == 20001 then      -- AC
			Keyboard:PressKey(LEFT)
		elseif final_t == 36001 then
			Keyboard:ReleaseAll()
		elseif final_t == 40001 then      -- EXE trigger
			print("TRIG: EXE pressed, len=" .. blen())
			Keyboard:PressKey(0x60)
		elseif final_t == 60001 then
			Keyboard:ReleaseAll()
			emu:SetClockSpeed(16)
			print("WATCH: 16x")
		elseif final_t > 60001 then
			if (final_t - 60001) % 50000 == 0 then
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
			if final_t > 3000001 then
				print(string.format("END: pc=%04X sp=%04X lr=%04X h={4d20:%d 3538:%d 35be:%d 2b1e:%d}",
					cpu.pc, cpu.sp, cpu.lr, hits.k4d20, hits.k3538, hits.k35be, hits.k2b1e))
				print("END: buf " .. bdump(0, 104) .. " len=" .. blen())
				emu:set_paused(true)
				phase = "done"
			end
		end
	end
end)
