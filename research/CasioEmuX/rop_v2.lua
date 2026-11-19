-- V2: alternative-head formulas + dance + typed fill + trigger.
-- Identical to rop_v1.lua except the head formula's Σ( template is replaced
-- by TEMPLATE_KEY (SHIFT+{key}), and the template insert is dumped verbatim.
-- Queue: 2 runs expected (INT head SHIFT+0x03 / ddx head SHIFT+0x16).
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
local TEMPLATE_KEYS = { 0x03, 0x16, 0x46, 0x33 }  -- tried SHIFT+∫key, SHIFT+fn(0x16), base 0x46, base 0x33
local TEMPLATE_IDX = tonumber(os.getenv("V2IDX") or 1) or 1

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26
local K1, K9, KX10 = 0x00, 0x22, 0x62
local K8, K5 = 0x12, 0x11

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase = "type"
local no_grow, last_len, max_len, template_bytes = 0, -1, 0, ""

local function blen() for i = 0, 299 do if (data[0x8154 + i] or 0) == 0 then return i end end return 300 end
local function bdump(lo, n) local s = "" for i = lo, lo + n - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end return s end
local function push(code, label, hold, gap) keys[#keys + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 16000 } end
local function chord(mod, code, label) push(mod, label .. "/mod"); push(code, label) end

push(SHIFT, "w1", 12000, 12000); push(AC, "w2", 12000, 24000)
chord(SHIFT, MODE, "setup1"); push(K2, "setup1-2", 30000, 40000)
-- template byte signature check: press the candidate key, dump, AC
push(SHIFT, "sigv1/mod"); push(TEMPLATE_KEYS[TEMPLATE_IDX], "sigv1", 16000, 16000)
local function sigdump()
	local n = blen()
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end
	print(string.format("SIGV: key=%02X len=%d bytes=%s", TEMPLATE_KEYS[TEMPLATE_IDX], n, s))
	template_bytes = s
end
push(AC, "AC-clear", 16000, 24000)
-- head formula: X = TEMPLATE (X , 1 , 1 x10^9
chord(ALPHA, 0x33, "X1"); chord(ALPHA, CALC, "eq")
if TEMPLATE_KEYS[TEMPLATE_IDX] == 0x46 or TEMPLATE_KEYS[TEMPLATE_IDX] == 0x33 then
	push(TEMPLATE_KEYS[TEMPLATE_IDX], "tmpl-base")
else
	push(SHIFT, "tmpl/mod"); push(TEMPLATE_KEYS[TEMPLATE_IDX], "tmpl")
end
chord(ALPHA, 0x33, "X2"); chord(SHIFT, 0x33, "comma1"); push(K1, "one")
chord(SHIFT, 0x33, "comma2"); push(K1, "one2"); push(KX10, "x10"); push(K9, "nine")
push(CALC, "CALC", 16000, 24000); push(EXE, "EXE", 24000, 30000)
push(AC, "AC", 16000, 24000); push(LEFT, "LEFT", 16000, 16000)
push(DEL, "DEL1"); push(DEL, "DEL2"); push(DEL, "DEL3")
push(K2, "two"); push(CALC, "CALC2", 16000, 24000); push(EXE, "EXE2", 24000, 30000)
push(LEFT, "LEFT2", 16000, 20000)
push(K1, "PROBE1", 16000, 16000)
push(AC, "AC-f", 16000, 24000); push(LEFT, "LEFT-f", 16000, 20000)
for round = 1, 12 do
	for i = 1, 12 do push(round % 2 == 1 and K8 or K5, "d" .. round .. "-" .. i) end
	for i = 1, 4 do chord(SHIFT, 0x56, "s" .. round .. "-" .. i) end
end

local hit = {}
local function note(a) hit[a] = (hit[a] or 0) + 1 end
break_at(0x4D20, function() note("k4d20"); emu:set_paused(false) end)
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
			if cur and cur.label == "sigv1" then sigdump() end
			if n >= 100 or no_grow >= 60 then
				fill_done = true
				print(string.format("FILL: done len=%d maxlen=%d keys=%d", blen(), max_len, ki))
				print("FILL: buf " .. bdump(0, 112))
				push(AC, "TRIG-AC", 16000, 24000)
				push(LEFT, "TRIG-LEFT", 16000, 20000)
				push(EXE, "TRIG-EXE", 24000, 30000)
				push(EXE, "TRIG-EXE2", 24000, 30000)
			end
		end
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "watch"; final_t = 0
				emu:SetClockSpeed(8)
				print("WATCH: typing exhausted (no trigger)")
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
					print(string.format("TRIGKEY: %s len=%d", cur.label, blen()))
					if cur.label == "TRIG-EXE2" then
						phase = "watch"; final_t = 0
						emu:SetClockSpeed(8)
						print("WATCH: 8x trigger done len=" .. blen())
						return
					end
				end
			end
		end
	elseif phase == "watch" then
		final_t = final_t + 1
		if final_t % 200000 == 0 then
			local tiled = 0
			for a = 0x8240, 0x8DFB do if (data[a] or 0) > 0x30 then tiled = tiled + 1 end end
			print(string.format("WATCH: t=%d pc=%04X sp=%04X lr=%04X len=%d tiles=%d h={2b1e:%d 3538:%d 35be:%d 4d20:%d}",
				final_t, cpu.pc, cpu.sp, cpu.lr, blen(), tiled,
				hit.k2b1e or 0, hit.k3538 or 0, hit.k35be or 0, hit.k4d20 or 0))
		end
		if final_t >= 2000000 then
			print(string.format("END: pc=%04X sp=%04X lr=%04X h={2b1e:%d 3538:%d 35be:%d 4d20:%d} maxlen=%d tmpl=%s",
				cpu.pc, cpu.sp, cpu.lr, hit.k2b1e or 0, hit.k3538 or 0, hit.k35be or 0, hit.k4d20 or 0, max_len, template_bytes))
			emu:set_paused(true)
			phase = "done"
		end
	end
end)
