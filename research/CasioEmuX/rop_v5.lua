-- V5: differential tiling mechanism. Same as V1 fill->99, then inject the
-- e2e zero-free 100-byte payload (25x [0E 4D 11 11]) at 0x8154, then
-- [AC][<-][EXE][EXE]. strcpy logger armed BEFORE AC so we capture every copy
-- with true srclen (uncapped) - compare with V1's len=99 trace to find the
-- exact tiling copy and its length source.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26
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
for round = 1, 30 do
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
		if strcpy_logs < 300 then
			local d, s = er(cpu.r1, cpu.r0), er(cpu.r3, cpu.r2)
			local dd = {}
			for i = 0, 11 do dd[#dd + 1] = string.format("%02X", data[d + i] or 0) end
			local ss = {}
			for i = 0, 11 do ss[#ss + 1] = string.format("%02X", data[s + i] or 0) end
			print(string.format("STRCPY: dst=%04X src=%04X lr=%04X sp=%04X srclen=%d dsthead=%s srchead=%s",
				d, s, cpu.lr, cpu.sp, slen(s), table.concat(dd), table.concat(ss)))
			strcpy_logs = strcpy_logs + 1
		end
		note("strcpy")
		if strcpy_logs >= 300 then unbreak_at(0x6B62) end
		emu:set_paused(false)
	end)
end
break_at(0x4D20, function()
	note("k4d20")
	if (hit.k4d20 or 0) <= 6 then
		print(string.format("KEYSCAN-HIT #%d sp=%04X words=%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X", hit.k4d20, cpu.sp,
			data[cpu.sp] or 0, data[cpu.sp + 1] or 0, data[cpu.sp + 2] or 0, data[cpu.sp + 3] or 0,
			data[cpu.sp + 4] or 0, data[cpu.sp + 5] or 0, data[cpu.sp + 6] or 0, data[cpu.sp + 7] or 0,
			data[cpu.sp + 8] or 0))
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
				print(string.format("FILL: done len=%d maxlen=%d keys=%d", blen(), max_len, ki))
				print("FILL: buf " .. bdump(0, 112))
				-- inject zero-free e2e-style payload at 0x8154 (100 bytes)
				for e = 0, 24 do
					data[0x8154 + e * 4] = 0x0E
					data[0x8154 + e * 4 + 1] = 0x4D
					data[0x8154 + e * 4 + 2] = 0x11
					data[0x8154 + e * 4 + 3] = 0x11
				end
				print("INJECT: payload 0E 4D 11 11 x25 at 0x8154, strlen=" .. slen(0x8154))
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
				if cur.label == "PROBE1" then print(string.format("PROBE1: len=%d", blen())) end
				if cur.label and cur.label:sub(1, 4) == "TRIG" then
					if cur.label == "TRIG-AC" then arm_strcpy_logger() end
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
				print(string.format("END-TRIGGERED: pc=%04X sp=%04X h=%s", cpu.pc, cpu.sp, "chain runs"))
				emu:set_paused(true); phase = "done"
			end
		end
		if final_t >= 2500000 then
			print(string.format("END: pc=%04X sp=%04X lr=%04X h={2b1e:%d 3538:%d 35be:%d 4d20:%d str:%d}",
				cpu.pc, cpu.sp, cpu.lr, hit.k2b1e or 0, hit.k3538 or 0, hit.k35be or 0, hit.k4d20 or 0, hit.strcpy or 0))
			emu:set_paused(true)
			phase = "done"
		end
	end
end)
