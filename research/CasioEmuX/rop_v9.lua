-- V9: full tiling trace. Typed fill to 99, then inject the e2e-verified
-- sled+chain payload (0E 4D x50 + 0x3538/0xF801/0x35BE/0x8154 words), then
-- [AC][<-][EXE] with Right held. strcpy logger budget 3000, no cap prints.
-- Expected: KEYSCAN chain executes (proof) + complete copy trace.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37
local K1, K2, K9, KX10 = 0x00, 0x10, 0x22, 0x62
local K8, K5 = 0x12, 0x11

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase = "type"
local no_grow, last_len, max_len = 0, -1, 0

local function blen() for i = 0, 299 do if (data[0x8154 + i] or 0) == 0 then return i end end return 300 end
local function bdump(lo, n) local s = "" for i = lo, lo + n - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end return s end
local function push(code, label, hold, gap) keys[#keys + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 16000 } end
local function chord(mod, code, label) push(mod, label .. "/mod"); push(code, label) end

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

local hit = {}
local function note(a) hit[a] = (hit[a] or 0) + 1 end
local strcpy_logs = 0
local function er(hi, lo) return ((hi & 0xFF) << 8) | (lo & 0xFF) end
local function slen(base, max)
	local n = 0
	while n < (max or 400) and (data[base + n] or 0) ~= 0 do n = n + 1 end
	return n
end
local function arm_strcpy_logger()
	break_at(0x6B62, function()
		strcpy_logs = strcpy_logs + 1
		if strcpy_logs <= 40 then
			local d, s = er(cpu.r1, cpu.r0), er(cpu.r3, cpu.r2)
			print(string.format("S1: dst=%04X src=%04X lr=%04X sp=%04X srclen=%d", d, s, cpu.lr, cpu.sp, slen(s)))
		else
			local d, s = er(cpu.r1, cpu.r0), er(cpu.r3, cpu.r2)
			-- aggregate only
			hit["c" .. string.format("%04X-%04X", d, 0)] = (hit["c" .. string.format("%04X-%04X", d, 0)] or 0) + 1
		end
		if strcpy_logs >= 3000 then unbreak_at(0x6B62) end
		emu:set_paused(false)
	end)
end
break_at(0x4D20, function()
	note("k4d20")
	if (hit.k4d20 or 0) <= 8 then
		print(string.format("KEYSCAN-HIT #%d sp=%04X", hit.k4d20, cpu.sp))
	end
	emu:set_paused(false)
end)
break_at(0x3538, function() note("k3538"); emu:set_paused(false) end)
break_at(0x35BE, function() note("k35be"); emu:set_paused(false) end)
break_at(0x2B1E, function() note("k2b1e"); emu:set_paused(false) end)

local final_t, fill_done = 0, false
addposttick(function()
	if phase == "type" then
		if state == "idle" and not fill_done then
			local n = blen()
			if n > max_len then max_len = n end
			if last_len >= 0 then
				if n ~= last_len then no_grow = 0 else no_grow = no_grow + 1 end
			end
			last_len = n
			if no_grow >= 60 then
				fill_done = true
				print(string.format("FILL: len=%d maxlen=%d", blen(), max_len))
				for e = 0, 49 do
					data[0x8154 + e * 2] = 0x0E
					data[0x8154 + e * 2 + 1] = 0x4D
				end
				local function W(off, v) data[0x8154 + off] = v & 0xFF; data[0x8154 + off + 1] = (v >> 8) & 0xFF end
				W(60, 0x3538); W(62, 0x3538); W(64, 0xF801); W(66, 0x35BE); W(68, 0x8154)
				print("INJECT: e2e sled, strlen=" .. slen(0x8154))
				push(AC, "TRIG-AC", 16000, 24000); push(LEFT, "TRIG-LEFT", 16000, 20000)
				push(EXE, "TRIG-EXE", 24000, 30000); push(EXE, "TRIG-EXE2", 24000, 30000)
				ki = ki - 1
			end
		end
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "watch"; final_t = 0
				emu:SetClockSpeed(8)
				print("WATCH: exhausted no trigger")
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
				if cur.label and cur.label:sub(1, 4) == "TRIG" then
					if cur.label == "TRIG-AC" then
						arm_strcpy_logger()
						Keyboard:PressKey(RIGHT)
					end
					print(string.format("TRIGKEY: %s len=%d", cur.label, blen()))
					if cur.label == "TRIG-EXE2" then
						phase = "watch"; final_t = 0
						emu:SetClockSpeed(8)
						print("WATCH: 8x trigger done")
						return
					end
				end
			end
		end
	elseif phase == "watch" then
		final_t = final_t + 1
		if final_t % 100000 == 0 then
			local tiled = 0
			for a = 0x8240, 0x8DFB do if (data[a] or 0) > 0x30 then tiled = tiled + 1 end end
			print(string.format("WATCH: t=%d pc=%04X sp=%04X len=%d tiles=%d h={2b1e:%d 3538:%d 35be:%d 4d20:%d str:%d}",
				final_t, cpu.pc, cpu.sp, blen(), tiled,
				hit.k2b1e or 0, hit.k3538 or 0, hit.k35be or 0, hit.k4d20 or 0, hit.strcpy or 0))
			if (hit.k4d20 or 0) >= 50 then
				local agg = {}
				for k, v in pairs(hit) do
					if k:sub(1, 1) == "c" and v > 3 then agg[#agg + 1] = k .. "x" .. v end
				end
				print("STRCPY-AGG(dst): " .. table.concat(agg, " "))
				print(string.format("END-TRIGGERED: pc=%04X sp=%04X", cpu.pc, cpu.sp))
				emu:set_paused(true); phase = "done"
			end
		end
		if final_t >= 3000000 then
			local agg = {}
			for k, v in pairs(hit) do
				if k:sub(1, 1) == "c" and v > 3 then agg[#agg + 1] = k .. "x" .. v end
			end
			print("STRCPY-AGG(dst): " .. table.concat(agg, " "))
			print(string.format("END: pc=%04X sp=%04X h={2b1e:%d 3538:%d 35be:%d 4d20:%d str:%d}",
				cpu.pc, cpu.sp, hit.k2b1e or 0, hit.k3538 or 0, hit.k35be or 0, hit.k4d20 or 0, hit.strcpy or 0))
			emu:set_paused(true)
			phase = "done"
		end
	end
end)
