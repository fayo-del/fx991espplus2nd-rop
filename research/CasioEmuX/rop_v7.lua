-- V7: DEL-dance variant matrix. For each variant: fresh head formula ->
-- CALC EXE AC LEFT -> [variant tail] -> probe-1 -> one fill round (12 digits
-- + 2 Sigma chords) -> extra fill round -> report probe-land, len, maxlen,
-- cache bytes. Variants change the post-dance editor state (cursor/lock).
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37
local K1, K2, K9, KX10 = 0x00, 0x10, 0x22, 0x62
local K8, K5 = 0x12, 0x11

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase = "type"
local last_len, max_len = -1, 0
local variant, base_len, filled = "?", 0, false
local results = {}

local function blen() for i = 0, 299 do if (data[0x8154 + i] or 0) == 0 then return i end end return 300 end
local function push(code, label, hold, gap) keys[#keys + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 16000 } end
local function chord(mod, code, label) push(mod, label .. "/mod"); push(code, label) end

local function head()  -- X=Sigma(X,1,1x10^9 + CALC EXE AC LEFT
	chord(ALPHA, 0x33, "X1"); chord(ALPHA, CALC, "eq"); chord(SHIFT, 0x56, "Sigma")
	chord(ALPHA, 0x33, "X2"); chord(SHIFT, 0x33, "comma1"); push(K1, "one")
	chord(SHIFT, 0x33, "comma2"); push(K1, "one2"); push(KX10, "x10"); push(K9, "nine")
	push(CALC, "CALC", 16000, 24000); push(EXE, "EXE", 24000, 30000)
	push(AC, "AC", 16000, 24000); push(LEFT, "LEFT", 16000, 16000)
end

local function fillround(r)
	for i = 1, 12 do push(r % 2 == 1 and K8 or K5, "d" .. r .. "-" .. i) end
	for i = 1, 2 do chord(SHIFT, 0x56, "s" .. r .. "-" .. i) end
end

-- V1 baseline: DEL x3, 2
push(AC, "AC-f", 16000, 24000); push(LEFT, "LEFT-f", 16000, 20000)
push(DEL, "v1-DEL1"); push(DEL, "v1-DEL2"); push(DEL, "v1-DEL3")
push(K2, "v1-two"); push(CALC, "v1-CALC", 16000, 24000); push(EXE, "v1-EXE", 24000, 30000)
push(LEFT, "v1-LEFT", 16000, 20000)
push(K1, "v1-PROBE", 16000, 16000)
fillround(1); fillround(2)
keys[#keys + 1] = { report = "V1-del3-2" }

-- V2: DEL x4 (one more), 2 (fresh state restored by re-dance)
push(AC, "AC-f2", 16000, 24000); push(LEFT, "LEFT-f2", 16000, 20000)
push(DEL, "v2-DEL1"); push(DEL, "v2-DEL2"); push(DEL, "v2-DEL3"); push(DEL, "v2-DEL4")
push(K2, "v2-two"); push(CALC, "v2-CALC", 16000, 24000); push(EXE, "v2-EXE", 24000, 30000)
push(LEFT, "v2-LEFT", 16000, 20000)
push(K1, "v2-PROBE", 16000, 16000)
fillround(3); fillround(4)
keys[#keys + 1] = { report = "V2-del4-2" }

-- V3: DEL x3, then DEL the resulting '2' entirely (len 0), probe from empty
push(AC, "AC-f3", 16000, 24000); push(LEFT, "LEFT-f3", 16000, 20000)
push(DEL, "v3-DEL1"); push(DEL, "v3-DEL2"); push(DEL, "v3-DEL3"); push(DEL, "v3-DEL-2")
push(K1, "v3-PROBE", 16000, 16000)
fillround(5); fillround(6)
keys[#keys + 1] = { report = "V3-del3-empty" }

-- V4: baseline then extra LEFT walk x3 before probe
push(AC, "AC-f4", 16000, 24000); push(LEFT, "LEFT-f4a", 16000, 20000)
push(DEL, "v4-DEL1"); push(DEL, "v4-DEL2"); push(DEL, "v4-DEL3")
push(K2, "v4-two"); push(CALC, "v4-CALC", 16000, 24000); push(EXE, "v4-EXE", 24000, 30000)
push(LEFT, "v4-LEFT1", 16000, 20000); push(LEFT, "v4-LEFT2"); push(LEFT, "v4-LEFT3")
push(K1, "v4-PROBE", 16000, 16000)
fillround(7); fillround(8)
keys[#keys + 1] = { report = "V4-walk3" }

-- V5: double dance (baseline dance then the whole dance again incl head re-dance)
push(AC, "AC-f5", 16000, 24000); push(LEFT, "LEFT-f5", 16000, 20000)
push(DEL, "v5-DEL1"); push(DEL, "v5-DEL2"); push(DEL, "v5-DEL3")
push(K2, "v5-two"); push(CALC, "v5-CALC", 16000, 24000); push(EXE, "v5-EXE", 24000, 30000)
push(LEFT, "v5-LEFT", 16000, 20000)
-- second cycle: retype the head on top and re-dance
head()  -- typed on the existing buffer? the dance state may reject typing; do with AC first
push(AC, "AC-f5b", 16000, 24000); push(LEFT, "LEFT-f5b", 16000, 20000)
chord(ALPHA, 0x33, "X1b"); chord(ALPHA, CALC, "eq2"); chord(SHIFT, 0x56, "Sigma2")
chord(ALPHA, 0x33, "X2b"); chord(SHIFT, 0x33, "comma1b"); push(K1, "oneb")
chord(SHIFT, 0x33, "comma2b"); push(K1, "one2b"); push(KX10, "x10b"); push(K9, "nine2b")
push(CALC, "CALC-b", 16000, 24000); push(EXE, "EXE-b", 24000, 30000)
push(AC, "AC-b", 16000, 24000); push(LEFT, "LEFT-b", 16000, 16000)
push(DEL, "DEL-b1"); push(DEL, "DEL-b2"); push(DEL, "DEL-b3")
push(K2, "two-b"); push(CALC, "CALC2-b", 16000, 24000); push(EXE, "EXE2-b", 24000, 30000)
push(LEFT, "LEFT2-b", 16000, 20000)
push(K1, "v5-PROBE", 16000, 16000)
fillround(9); fillround(10)
keys[#keys + 1] = { report = "V5-double-dance" }

-- V6: baseline + '2' typed TWICE (22 as the dance tail)
push(AC, "AC-f6", 16000, 24000); push(LEFT, "LEFT-f6", 16000, 20000)
push(DEL, "v6-DEL1"); push(DEL, "v6-DEL2"); push(DEL, "v6-DEL3")
push(K2, "v6-two1"); push(K2, "v6-two2"); push(CALC, "v6-CALC", 16000, 24000); push(EXE, "v6-EXE", 24000, 30000)
push(LEFT, "v6-LEFT", 16000, 20000)
push(K1, "v6-PROBE", 16000, 16000)
fillround(11); fillround(12)
keys[#keys + 1] = { report = "V6-tail22" }

-- V7: after dance, LEFT then RIGHT (roundtrip) before probe
push(AC, "AC-f7", 16000, 24000); push(LEFT, "LEFT-f7", 16000, 20000)
push(DEL, "v7-DEL1"); push(DEL, "v7-DEL2"); push(DEL, "v7-DEL3")
push(K2, "v7-two"); push(CALC, "v7-CALC", 16000, 24000); push(EXE, "v7-EXE", 24000, 30000)
push(LEFT, "v7-LEFT", 16000, 20000); push(RIGHT, "v7-RIGHT", 16000, 16000)
push(K1, "v7-PROBE", 16000, 16000)
fillround(13); fillround(14)
keys[#keys + 1] = { report = "V7-LR-roundtrip" }

-- V8: no DEL dance at all (formula intact, = produced result): AC LEFT probe
push(AC, "AC-f8", 16000, 24000); push(LEFT, "LEFT-f8", 16000, 20000)
push(DEL, "v8-DEL1"); push(DEL, "v8-DEL2"); push(DEL, "v8-DEL3")
push(K2, "v8-two"); push(CALC, "v8-CALC", 16000, 24000); push(EXE, "v8-EXE", 24000, 30000)
push(LEFT, "v8-LEFT", 16000, 20000)
push(K1, "v8-PROBE", 16000, 16000)
fillround(15); fillround(16)
keys[#keys + 1] = { report = "V8-dance-noheadAC" }

local function cursorvars() return string.format("%02X%02X%02X%02X", data[0x8113] or 0, data[0x8114] or 0, data[0x8115] or 0, data[0x8116] or 0) end
local function cacheb() return string.format("%02X %02X%02X %02X%02X", data[0x81B7] or 0, data[0x81B8] or 0, data[0x81B9] or 0, data[0x81C0] or 0, data[0x81C8] or 0) end

addposttick(function()
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				print("V7-DONE maxlen=" .. max_len)
				emu:set_paused(true)
				phase = "done"
				return
			end
			cur = keys[ki]
			if cur.report then
				results[#results + 1] = string.format("%s: base_probe=%d fill_len=%d maxlen=%d curv=%s cache={%s}",
					cur.report, base_len, blen(), max_len, cursorvars(), cacheb())
				print(results[#results])
				last_len, max_len = -1, 0
				variant, filled = cur.report, false
			else
				if cur.mod then Keyboard:PressKey(cur.mod); state = "mod"; hold_t = 6000
				else Keyboard:PressKey(cur.code); state = "press"; hold_t = cur.hold end
			end
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
				local n = blen()
				if n > max_len then max_len = n end
				if cur.label and cur.label:match("PROBE") then
					base_len = max_len  -- len at probe time (before fill)
				end
			end
		end
	end
end)
