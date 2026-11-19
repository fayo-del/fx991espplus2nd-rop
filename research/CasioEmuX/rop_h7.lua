-- Hack #7 test (unstable byte / unsupported-symbol entry) on CY-845.
-- Phase A: exact rop_e2e.lua head through PROBE1 (the basic-overflow state,
--   1x clock -- PROBE1 NOT-INSERTED expected).
-- Phase B: "repeatedly type characters to advance the cursor": type 12 more
--   '1's (matching the S6-class free advance), sampling 0x8154+index window
--   after each to measure where bytes actually land = the empirical cursor.
-- Phase C: unstable-byte symbol test: enter Σ( (69 B8), wait-for-flash
--   (settle), then press ◀ repeatedly, sampling the byte at the insert site
--   after each move = measure the symbol-table advance. Also try starting
--   from '5' (0x35, typable) walking toward 0x4D if per-move advance works.
-- All typed; no data[] modification of the buffer.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x00, 0x10, 0x22, 0x62

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase = "type"
local samples = {}

local function blen()
	for i = 0, 100 do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 101
end
local function bdump(a0, n)
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02X", data[a0 + i] or 0) end
	return s
end
local function push(code, label)
	keys[#keys + 1] = { code = code, label = label }
end
local function chord(mod, code, label)
	push(mod, label .. "/mod"); push(code, label)
end

-- ============== Phase A: exact e2e head (1x clock, T~1) ==============
push(SHIFT, "w1"); push(AC, "w2")
chord(SHIFT, MODE, "setup1"); push(K2, "setup1-2")
chord(SHIFT, 0x56, "sigv1")
chord(SHIFT, MODE, "setup2"); push(K2, "setup2-2")
chord(SHIFT, 0x56, "sigv2"); push(AC, "AC-clear")
chord(ALPHA, 0x33, "X1"); chord(ALPHA, CALC, "eq"); chord(SHIFT, 0x56, "Sigma")
chord(ALPHA, 0x33, "X2"); chord(SHIFT, 0x33, "comma1"); push(K1, "one")
chord(SHIFT, 0x33, "comma2"); push(K1, "one2"); push(KX10, "x10"); push(K9, "nine")
push(CALC, "CALC"); push(EXE, "EXE"); push(AC, "AC"); push(LEFT, "LEFT")
push(DEL, "DEL1"); push(DEL, "DEL2"); push(DEL, "DEL3"); push(K2, "two")
push(CALC, "CALC2"); push(EXE, "EXE2"); push(LEFT, "LEFT2"); push(K1, "PROBE1")
-- ============== Phase B: 12 advance-typing '1's ==============
for i = 1, 12 do push(K1, "ADV" .. i) end
-- ============== Phase C: unstable-byte walk ==============
-- C1: enter '5' (0x35) with retries (typed inserts drop ~1-in-6)
for i = 1, 6 do push(0x11, "SYM5." .. i) end
-- C2: 8 cursor-moves RIGHT (each should advance the symbol per hack #7)
for i = 1, 8 do push(0x37, "MOV-R" .. i) end
-- C3: 2 moves LEFT
push(0x26, "MOV-L1"); push(0x26, "MOV-L2")
-- C4: enter Σ( (69 B8 2-byte template) with retries, then walk RIGHT 6, LEFT 2
for i = 1, 3 do push(0x07, "S6.m" .. i); push(0x56, "SYM6." .. i) end
for i = 1, 6 do push(0x37, "M6-R" .. i) end
push(0x26, "M6-L1"); push(0x26, "M6-L2")

addposttick(function()
	T = T + 1
	if phase ~= "type" then
		return
	end
	if state == "idle" then
		ki = ki + 1
		if ki > #keys then
			print("HDR7: typing done len=" .. blen() .. " buf=" .. bdump(0x8154, 64))
			print("HDR7: extended=" .. bdump(0x8194, 64))
			for _, sm in ipairs(samples) do print("HDR7: " .. sm) end
			emu:set_paused(true)
			return
		end
		cur = keys[ki]
		Keyboard:PressKey(cur.code)
		state = "press"; hold_t = 16000
	elseif state == "press" then
		hold_t = hold_t - 1
		if hold_t <= 0 then
			Keyboard:ReleaseAll()
			state = "rel"; gap_t = 20000
		end
	elseif state == "rel" then
		if gap_t == 19999 and (cur.label:match("^ADV") or cur.label:match("^SYM") or cur.label:match("^MOV")) then
			samples[#samples + 1] = string.format("%-8s len=%d buf=%s ext=%s",
				cur.label, blen(), bdump(0x8154, 16), bdump(0x8194, 24))
		end
		gap_t = gap_t - 1
		if gap_t <= 0 then state = "idle" end
	end
end)
