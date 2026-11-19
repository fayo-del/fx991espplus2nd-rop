-- V10: render-echo overrun census. Logger at 0x6B6E (strcpy loop exit):
-- for every copy through smart_strcpy during typed fill AND trigger, print
-- dst/src/true srclen/last-bytes-written + 0x81B7..0x81D0 state. Watch for
-- ANY copy whose write range crosses 0x81B7/0x81B8+. Plus per-tick 0x81B7
-- transition log. Typing fills to cap; then typed AC/LEFT/EXE/EXE trigger.
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
-- logger at copy-loop exit (0x6B6E): ER8=dst, ER10=src still hold their values
local echo_logs = 0
local b7_final = 0
local function arm_echo_logger()
	break_at(0x6B6E, function()
		local dst = ((cpu.r9 & 0xFF) << 8) | (cpu.r8 & 0xFF)   -- ER8
		local src = ((cpu.r11 & 0xFF) << 8) | (cpu.r10 & 0xFF) -- ER10
		-- true length: count NUL at src
		local n = 0
		while n < 260 and (data[src + n] or 0) ~= 0 do n = n + 1 end
		local cross = (dst <= 0x81B8) and (dst + n >= 0x81B7)
		local near = (dst >= 0x80F0 and dst <= 0x8700)
		local cls = string.format("%04X-%04X-%d", dst, src, n)
		hit["d" .. cls] = (hit["d" .. cls] or 0) + 1
		if n > 0 and (cross or near) and (hit["d" .. cls] or 0) <= 4 then
			local srcb = src - n
		local tail = ""
		for i = 0, 5 do tail = tail .. string.format("%02X", data[dst + n - 5 + i] or 0) end
		print(string.format("ECHO: dst=%04X srcb=%04X len=%d writes=%04X..%04X cross=%s tail=%s",
				dst, srcb, n, srcb, srcb + n, tostring(dst <= 0x81B8 and srcb + n >= 0x81B7 or dst + n >= 0x81B7 and dst <= 0x81B7), tail))
		end
		echo_logs = echo_logs + 1
		note("echo")
		if echo_logs >= 400 then unbreak_at(0x6B6E) end
		emu:set_paused(false)
	end)
end

local function er(hi, lo) return ((hi & 0xFF) << 8) | (lo & 0xFF) end
local function slen(base, max)
	local n = 0
	while n < (max or 400) and (data[base + n] or 0) ~= 0 do n = n + 1 end
	return n
end
local strcpy_logs = 0
break_at(0x4D20, function() note("k4d20"); emu:set_paused(false) end)
break_at(0x3538, function() note("k3538"); emu:set_paused(false) end)
break_at(0x35BE, function() note("k35be"); emu:set_paused(false) end)
break_at(0x2B1E, function() note("k2b1e"); emu:set_paused(false) end)

local final_t, fill_done = 0, false
local b7 = 0
addposttick(function()
	-- 0x81B7 transition watcher
	local v = data[0x81B7] or 0
	if v ~= b7 then
		print(string.format("B7CHANGE: t=%d %02X->%02X pc=%04X phase=%s len=%d", final_t, b7, v, cpu.pc, phase, blen()))
		b7 = v
		b7_final = v
	end
	if phase == "type" then
		final_t = final_t + 1
		if state == "idle" and not fill_done then
			local n = blen()
			if n > max_len then max_len = n end
			if last_len >= 0 then
				if n ~= last_len then no_grow = 0 else no_grow = no_grow + 1 end
			end
			last_len = n
			if not fill_done and no_grow == 40 then
				fill_done = true
				print(string.format("FILL: len=%d maxlen=%d keys=%d", blen(), max_len, ki))
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
			if cur.label == "LEFT-f" then arm_echo_logger() end
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
					print(string.format("TRIGKEY: %s len=%d b7=%02X", cur.label, blen(), data[0x81B7] or 0))
					local dmp = ""
					for i = 0, 17 do dmp = dmp .. string.format("%02X", data[0x81B7 + i] or 0) end
					print(string.format("REGION81B7: %s", dmp))
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
			print(string.format("WATCH: t=%d pc=%04X sp=%04X len=%d str8154=%d b7=%02X tiles=%d h={2b1e:%d 3538:%d 35be:%d 4d20:%d echo:%d}",
				final_t, cpu.pc, cpu.sp, blen(), slen(0x8154), data[0x81B7] or 0, tiled,
				hit.k2b1e or 0, hit.k3538 or 0, hit.k35be or 0, hit.k4d20 or 0, hit.echo or 0))
			if (hit.k4d20 or 0) >= 3 then
				print(string.format("END-FLOOD: pc=%04X sp=%04X h4d20=%d", cpu.pc, cpu.sp, hit.k4d20 or 0))
				emu:set_paused(true); phase = "done"
			end
		end
		if final_t >= 2500000 then
			print(string.format("END: pc=%04X sp=%04X h={2b1e:%d 3538:%d 35be:%d 4d20:%d echo:%d} str8154=%d b7=%02X maxlen=%d",
				cpu.pc, cpu.sp, hit.k2b1e or 0, hit.k3538 or 0, hit.k35be or 0, hit.k4d20 or 0, hit.echo or 0,
				slen(0x8154), data[0x81B7] or 0, max_len))
			emu:set_paused(true)
			phase = "done"
		end
	end
end)
