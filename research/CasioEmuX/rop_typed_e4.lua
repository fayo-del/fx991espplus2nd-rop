-- E4 FINAL: typed-only payload to len>=100, then EXE trigger, then walk watch.
-- No data[] injection anywhere. Typing = '8'/'5' pairs + Sigma( chords
-- (E3-calibrated growth profile), sampled every keystroke, stop at len>=100
-- (budget 260 keystrokes). Then EXE trigger. Heavy walk instrumentation:
-- break_at on 0x3538/0x3536/0x35BE/0x2B1E/0x4D20 + periodic pc/sp/lr sampler
-- + final pc-class histogram + LCD row dump.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x00, 0x10, 0x22, 0x62
local K8, K5 = 0x12, 0x11

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t = "type", 0
local hit = {}
local function note(a) hit[a] = (hit[a] or 0) + 1 end

local function blen() for i = 0, 299 do if (data[0x8154 + i] or 0) == 0 then return i end end return 300 end
local function bdump(lo, n) local s = "" for i = lo, lo + n - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end return s end
local function push(code, label, hold, gap) keys[#keys + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 16000 } end
local function chord(mod, code, label) push(mod, label .. "/m"); push(code, label) end

-- ===== head: e2e-verbatim =====
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
-- ===== typed fill: 12 digits then 4 Sigma chords, repeated; adaptive stop in sampler =====
for round = 1, 16 do
	for i = 1, 12 do push(round % 2 == 1 and K8 or K5, "d" .. round .. "-" .. i) end
	for i = 1, 4 do chord(SHIFT, 0x56, "s" .. round .. "-" .. i) end
end

local pc_hist, hist_t, walk_logs = {}, 0, 0
local function bump() end

break_at(0x4D20, function() note("k4d20"); emu:set_paused(false) end)
break_at(0x3538, function()
	note("k3538")
	if phase == "final" then
		walk_logs = walk_logs + 1
		if walk_logs <= 20 or walk_logs % 100 == 0 then
			local w = {}
			for i = 0, 9, 2 do w[#w + 1] = string.format("%04X", data[cpu.sp + i] | (data[cpu.sp + i + 1] << 8)) end
			print(string.format("W3538 #%d sp=%04X lr=%04X r0=%02X w=%s", walk_logs, cpu.sp, cpu.lr, cpu.r0 & 0xFF, table.concat(w, " ")))
		end
	end
	emu:set_paused(false)
end)
break_at(0x3536, function() note("k3536"); emu:set_paused(false) end)
break_at(0x35BE, function() note("k35be"); emu:set_paused(false) end)
break_at(0x2B1E, function() note("k2b1e"); emu:set_paused(false) end)

local stopped_typing = false
local typeticks = 0
addposttick(function()
	if phase == "type" then
		typeticks = typeticks + 1
		if state == "idle" then
			ki = ki + 1
			if ki > #keys or stopped_typing then
				-- dynamic trigger insertion: AC already part of head's post-AC? we stop right after typing and press EXE
				phase = "trigger"
				print(string.format("INPUT: stop len=%d maxseen=%d", blen(), 0))
				print("INPUT: buf " .. bdump(0, 112))
				Keyboard:PressKey(0x60)   -- EXE trigger
				print("TRIG: EXE pressed at T=" .. typeticks)
				return
			end
			-- adaptive stop: if len>=100 while a digit press pending, stop now
			if blen() >= 100 and cur and cur.label and cur.label:sub(1, 1) == "d" then
				stopped_typing = true
				print(string.format("TYPE-STOP: len=%d at key#%d", blen(), ki))
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
				state = "idle"
			end
		end
	elseif phase == "trigger" then
		final_t = final_t + 1
		if final_t == 24000 then
			Keyboard:ReleaseAll()
			emu:SetClockSpeed(8)
			print("WATCH: 8x")
		elseif final_t > 24000 then
			if (final_t - 24000) % 100000 == 0 then
				hist_t = hist_t + 1
				pc_hist[cpu.pc] = (pc_hist[cpu.pc] or 0) + 1
			end
			if (final_t - 24000) > 0 and (final_t - 24000) % 1000000 == 0 then
				local tiled = 0
				for a = 0x8240, 0x8DF8 do
					if (data[a] or 0) > 0x30 then tiled = tiled + 1 end
				end
				local w = {}
				for i = 0, 9, 2 do w[#w + 1] = string.format("%04X", data[cpu.sp + i] | (data[cpu.sp + i + 1] << 8)) end
				print(string.format("WATCH: pc=%04X sp=%04X lr=%04X h={2b1e:%d 3538:%d 3536:%d 35be:%d 4d20:%d} w=%s",
					cpu.pc, cpu.sp, cpu.lr, hit.k2b1e or 0, hit.k3538 or 0, hit.k3536 or 0, hit.k35be or 0, hit.k4d20 or 0,
					table.concat(w, " ")))
			end
			if (final_t - 24000) > 6000000 or (hit.k3538 or 0) > 500 then
				print(string.format("END: pc=%04X sp=%04X lr=%04X h={2b1e:%d 3538:%d 3536:%d 35be:%d 4d20:%d}",
					cpu.pc, cpu.sp, cpu.lr, hit.k2b1e or 0, hit.k3538 or 0, hit.k3536 or 0, hit.k35be or 0, hit.k4d20 or 0))
				local rnd = {}
				for pcx, c in pairs(pc_hist) do rnd[#rnd + 1] = { pcx, c } end
				table.sort(rnd, function(a, b) return a[2] > b[2] end)
				local top = {}
				for i = 1, math.min(12, #rnd) do top[#top + 1] = string.format("%04X:%d", rnd[i][1], rnd[i][2]) end
				print("PC-HIST(top): " .. table.concat(top, " "))
				local rows = {}
				for rr = 0, 7 do
					local s2 = ""
					for i = 0, 11 do s2 = s2 .. string.format("%02X", data[0xF800 + rr * 16 + i]) end
					rows[#rows + 1] = s2
				end
				print("LCD: " .. table.concat(rows, " | "))
				emu:set_paused(true)
				phase = "done"
			end
		end
	end
end)
