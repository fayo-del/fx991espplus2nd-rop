-- E3 v2: post-AC typing archaeology (no trigger, no data[] injection).
-- e2e head -> PROBE1 -> AC -> LEFT, then typed bursts:
--   A: 12x '8','5'   L: LEFT x3   B: 12x '8','5'
--   C: Sigma() x12   L2: LEFT x3  D: 12x '8','5'
--   E: Sigma() x12   F: 24x '8','5'
-- Prints len after every keystroke + burst summaries.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x00, 0x10, 0x22, 0x62
local K8, K5 = 0x12, 0x11

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase = "type"
local burst_keys = 0

local function blen() for i = 0, 299 do if (data[0x8154 + i] or 0) == 0 then return i end end return 300 end
local function bdump(lo, n) local s = "" for i = lo, lo + n - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end return s end
local last_len, burst_id, burst_from
local function press(code, label, mod)
	keys[#keys + 1] = { code = code, label = label, mod = mod }
end
local function push(code, label)
	keys[#keys + 1] = { code = code, label = label }
end
local function chord(mod, code, label) push(mod, label .. "/mod"); push(code, label) end
local function burst(name) keys[#keys + 1] = { burst = name } end

push(SHIFT, "w1"); push(AC, "w2")
chord(SHIFT, MODE, "setup1"); push(K2, "setup1-2"); 
chord(SHIFT, 0x56, "sigv")
chord(SHIFT, MODE, "setup2"); push(K2, "setup2-2")
chord(SHIFT, 0x56, "sigv2"); push(AC, "AC-clear")
chord(ALPHA, 0x33, "X1"); chord(ALPHA, CALC, "eq"); chord(SHIFT, 0x56, "Sigma")
chord(ALPHA, 0x33, "X2"); chord(SHIFT, 0x33, "comma1"); push(K1, "one")
chord(SHIFT, 0x33, "comma2"); push(K1, "one2"); push(KX10, "x10"); push(K9, "nine")
push(CALC, "CALC"); push(EXE, "EXE", 24000, 30000)
push(AC, "AC"); push(LEFT, "LEFT")
push(DEL, "DEL1"); push(DEL, "DEL2"); push(DEL, "DEL3")
push(K2, "two"); push(CALC, "CALC2"); push(EXE, "EXE2", 24000, 30000)
push(LEFT, "LEFT2")
push(K1, "PROBE1")
push(AC, "AC-f"); push(LEFT, "LEFT-f")
burst("A85");      for i = 1, 12 do press(i % 2 == 1 and K8 or K5, "A" .. i) end
burst("L");        for i = 1, 3 do push(LEFT, "L" .. i) end
burst("B85");      for i = 1, 12 do press(i % 2 == 1 and K8 or K5, "B" .. i) end
burst("C-Sigma");  for i = 1, 12 do chord(SHIFT, 0x56, "C" .. i) end
burst("L2");       for i = 1, 3 do push(LEFT, "L2-" .. i) end
burst("D85");      for i = 1, 12 do press(i % 2 == 1 and K8 or K5, "D" .. i) end
burst("E-Sigma");  for i = 1, 12 do chord(SHIFT, 0x56, "E" .. i) end
burst("F85");      for i = 1, 24 do press(i % 2 == 1 and K8 or K5, "F" .. i) end

addposttick(function()
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "done"
				print(string.format("DONE: len=%d buf=%s", blen(), bdump(0, 120)))
				return
			end
			cur = keys[ki]
			if cur.burst then
				if burst_id then print(string.format("BURST %s: %d keys, len %d -> %d", burst_id, burst_keys, burst_from, blen())) end
				burst_id, burst_keys, burst_from = cur.burst, 0, blen()
				state = "idle"; return
			end
			if cur.mod then Keyboard:PressKey(cur.mod); state = "mod"; hold_t = 6000
			else Keyboard:PressKey(cur.code); state = "press"; hold_t = cur.hold or 16000 end
		elseif state == "mod" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:PressKey(cur.code); state = "press"; hold_t = cur.hold or 16000 end
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:ReleaseAll(); state = "rel"; gap_t = cur.gap or 16000 end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then
				if cur.code then burst_keys = burst_keys + 1 end
				if cur.label == "PROBE1" then print("PROBE1: len=" .. blen()) end
				state = "idle"
			end
		end
	end
end)
