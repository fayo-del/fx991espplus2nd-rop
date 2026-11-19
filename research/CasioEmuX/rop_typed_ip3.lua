-- input_path3.lua EXACT typed sequence (SetClockSpeed(8), long settles, primer
-- chords, 91 '1'-fillers at the original position) + TYPED digit payload:
-- 50x('8','5') = bytes 38 35 x50 = the 0x3538 gadget word repeated, typed, then
-- AC, LEFT, EXE trigger. Measures blen() per key + @0x3538/@0x4D20 hit classes.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

emu:SetClockSpeed(8)

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x00, 0x10, 0x22, 0x62
local K8, K5 = 0x12, 0x11

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local logs, phase, final_t, snap = {}, "type", 0, {}
local maxlen, len_at_f91, len_at_payload = 0, nil, nil
local g3538, g4d20 = 0, 0

local function blen()
	for i = 0, 99 do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 100
end
local function bdump(n)
	local s = ""
	for i = 0, (n or 24) - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end
	return s
end
local function push(code, label, expect, hold, gap)
	keys[#keys + 1] = { code = code, label = label, expect = expect, hold = hold or 16000, gap = gap or 16000 }
end
local function chord(mod, code, label, expect, primer)
	if primer then
		push(mod, label .. "/primer-mod", nil, 12000, 8000)
		push(code, label .. "/primer-key", nil, 16000, 16000)
	end
	push(mod, label .. "/mod", nil, 16000, 16000)
	push(code, label, expect, 16000, 16000)
end

-- === SETUP: SHIFT MODE 2 (LineIO), long settles ===
push(SHIFT, "SHIFT", nil, 16000, 20000)
push(MODE, "MODE", nil, 16000, 40000)
push(K2, "LineIO-2", nil, 16000, 40000)
-- === Sigma test (boxes = LineIO failed) ===
chord(SHIFT, 0x56, "Sigma(", { { 0xDF } })
-- === formula (with primers where templates occurred) ===
chord(ALPHA, 0x33, "X1", { { 0x58 } }, true)
chord(ALPHA, CALC, "eq=", { { 0x3D } })
chord(SHIFT, 0x56, "Sigma2", { { 0xDF } }, true)
chord(ALPHA, 0x33, "X2", { { 0x58 } }, true)
chord(SHIFT, 0x33, "comma1", { { 0x2C } }, true)
push(K1, "one", { { 0x31 } })
chord(SHIFT, 0x33, "comma2", { { 0x2C } })
push(K1, "one2", { { 0x31 } })
push(KX10, "x10", { { 0x74 } })
push(K9, "nine", { { 0x39 } })
-- === CALC = AC LEFT ===
push(CALC, "CALC", nil, 16000, 24000)
push(EXE, "EXE", nil, 20000, 30000)
push(AC, "AC", nil, 16000, 24000)
push(LEFT, "LEFT", nil, 16000, 16000)
-- === DEL x3, 2 ===
push(DEL, "DEL1", nil, 16000, 12000)
push(DEL, "DEL2", nil, 16000, 12000)
push(DEL, "DEL3", nil, 16000, 12000)
push(K2, "two", { { 0x32 } })
-- === CALC = LEFT ===
push(CALC, "CALC2", nil, 16000, 24000)
push(EXE, "EXE2", nil, 20000, 30000)
push(LEFT, "LEFT2", nil, 16000, 16000)
-- === probe: 1 must NOT insert ===
push(K1, "PROBE1", {}, 16000, 16000)
-- === 91 fillers (input_path3 placement, unchanged) ===
for i = 1, 91 do push(K1, "F" .. i, nil, 12000, 14000) end
-- === TYPED payload: 50x ('8','5') = 38 35 x50 (0x3538 words), appended ===
for i = 1, 50 do
	push(K8, "P8-" .. i, nil, 12000, 14000)
	push(K5, "P5-" .. i, nil, 12000, 14000)
end
-- === trigger: AC, LEFT, EXE ===
push(AC, "AC-f", nil, 16000, 24000)
push(LEFT, "LEFT-f", nil, 16000, 16000)
push(EXE, "EXE-f", nil, 20000, 30000)

local function check_expect(k)
	if not k.expect or #k.expect == 0 then return true end
	local now = blen()
	local lastb = (data[0x8154 + now - 1] or 0)
	for _, ref0 in ipairs(k.expect) do
		local ref = (type(ref0) == "number") and { ref0 } or ref0
		if #ref == 1 then
			if now > 0 and lastb == ref[1] then return true end
		else
			local ok = now >= #ref
			if ok then
				for i = 1, #ref do
					if (data[0x8154 + now - #ref + i - 1] or 0) ~= ref[i] then ok = false; break end
				end
			end
			if ok then return true end
		end
	end
	return false
end

break_at(0x3538, function()
	g3538 = g3538 + 1
	if g3538 <= 8 or g3538 % 100 == 0 then
		print(string.format("HIT-3538: #%d sp=%04X ER2=%04X r0=%02X lr=%04X", g3538, cpu.sp,
			(cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF), cpu.r0 & 0xFF, cpu.lr))
	end
	emu:set_paused(false)
end)
break_at(0x4D20, function()
	g4d20 = g4d20 + 1
	if g4d20 <= 8 or g4d20 % 100 == 0 then
		print(string.format("HIT-4D20: #%d sp=%04X ER0=%04X lr=%04X", g4d20, cpu.sp,
			(cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF), cpu.lr))
	end
	emu:set_paused(false)
end)

addposttick(function()
	T = T + 1

	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "final"
				print("INPUT: typing done len=" .. blen() .. " buf=" .. bdump(48))
				print(string.format("INPUT: len@F91=%s len@payload=%s maxlen=%d", tostring(len_at_f91),
					tostring(len_at_payload), maxlen))
				for _, l in ipairs(logs) do print("INPUT: " .. l) end
				return
			end
			cur = keys[ki]
			Keyboard:PressKey(cur.code)
			state = "press"; hold_t = cur.hold
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then
				Keyboard:ReleaseAll()
				state = "rel"; gap_t = cur.gap
			end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then
				local n = blen()
				if n > maxlen then maxlen = n end
				if cur.label == "F91" then len_at_f91 = n; print(string.format("CHECKPOINT: after F91 len=%d buf=%s", n, bdump(24))) end
				if cur.label == "P5-50" then len_at_payload = n; print(string.format("CHECKPOINT: payload-end len=%d buf=%s", n, bdump(48))) end
				if n ~= blen() and blen() > n then print("ORDER-NOTE: grew during processing") end
				if not check_expect(cur) then
					-- only log for non-filler keys to keep output bounded
					if cur.label:sub(1, 1) ~= "F" and cur.label:sub(1, 1) ~= "P" then
						logs[#logs + 1] = string.format("%-16s MISMATCH len=%d tail=%s", cur.label, n, bdump(8))
					elseif cur.label == "F1" or cur.label == "P8-1" or cur.label == "P5-1" then
						logs[#logs + 1] = string.format("%-16s first-of-run len=%d", cur.label, n)
					end
				end
				state = "idle"
			end
		end

	elseif phase == "final" then
		final_t = final_t + 1
		if final_t == 1 then
			print("INPUT: final baseline len=" .. blen() .. " buf=" .. bdump(48))
			print(string.format("INPUT: final pc=%04X sp=%04X", cpu.pc, cpu.sp))
			Keyboard:PressKey(AC)
		elseif final_t == 16001 then
			Keyboard:ReleaseAll()
		elseif final_t == 20001 then
			Keyboard:PressKey(LEFT)
		elseif final_t == 36001 then
			Keyboard:ReleaseAll()
		elseif final_t == 40001 then
			Keyboard:PressKey(0x60)   -- EXE
		elseif final_t == 60001 then
			Keyboard:ReleaseAll()
		elseif final_t > 60001 then
			if final_t % 200000 == 0 then
				local tiles = 0
				for a = 0x8240, 0x8DF8 do
					if (data[a] or 0) == 0x35 and (data[a - 1] or 0) == 0x38 then tiles = tiles + 1 end
				end
				print(string.format("WATCH: t=%d pc=%04X sp=%04X tiles(38 35)=%d h3538=%d h4d20=%d",
					final_t, cpu.pc, cpu.sp, tiles, g3538, g4d20))
			end
			if final_t > 3000000 then
				print(string.format("PROTO: END pc=%04X sp=%04X h3538=%d h4d20=%d maxlen=%d",
					cpu.pc, cpu.sp, g3538, g4d20, maxlen))
				emu:set_paused(true)
				phase = "done"
			end
		end
	end
end)
