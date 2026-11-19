-- V6: the ORIGINAL basic-overflow entry: type formula, press = directly
-- (expect Syntax ERROR page), AC, LEFT - no CALC step. Then probe/fill/trigger.
-- The Syntax-ERROR page state was never tested as the CY-845 fill entry
-- (all prior runs used the CALC-EXE-AC-LEFT dance).
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
-- head formula X=Sigma(X,1,1x10^9 (MathIO boxed - as in every working run)
chord(ALPHA, 0x33, "X1"); chord(ALPHA, CALC, "eq"); chord(SHIFT, 0x56, "Sigma")
chord(ALPHA, 0x33, "X2"); chord(SHIFT, 0x33, "comma1"); push(K1, "one")
chord(SHIFT, 0x33, "comma2"); push(K1, "one2"); push(KX10, "x10"); push(K9, "nine")
-- V6 variant A: plain = (Syntax ERROR expected), no CALC
push(EXE, "EXE-err", 24000, 40000)
push(AC, "AC-err", 16000, 24000)
push(LEFT, "LEFT-err", 16000, 20000)
push(K1, "PROBE1", 16000, 16000)
-- fill rounds
for round = 1, 30 do
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
local function cursorvars() return string.format("%02X%02X%02X%02X", data[0x8113] or 0, data[0x8114] or 0, data[0x8115] or 0, data[0x8116] or 0) end
addposttick(function()
	if phase == "type" then
		if state == "idle" then
			local n = blen()
			if n > max_len then max_len = n end
			if last_len >= 0 then
				if n ~= last_len then no_grow = 0 else no_grow = no_grow + 1 end
			end
			last_len = n
			if not fill_done and (n >= 100 or no_grow >= 60) then
				fill_done = true
				print(string.format("FILL: len=%d maxlen=%d curv=%s", blen(), max_len, cursorvars()))
				print("FILL: buf " .. bdump(0, 112))
				push(AC, "TRIG-AC", 16000, 24000); push(LEFT, "TRIG-LEFT", 16000, 20000)
				push(EXE, "TRIG-EXE", 24000, 30000); push(EXE, "TRIG-EXE2", 24000, 30000)
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
				if cur.label == "PROBE1" then print(string.format("PROBE1: len=%d curv=%s", blen(), cursorvars())) end
				if cur.label == "EXE-err" then print(string.format("EXE-ERR: len=%d curv=%s", blen(), cursorvars())) end
				if cur.label and cur.label:sub(1, 4) == "TRIG" then
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
		if final_t % 200000 == 0 then
			local tiled = 0
			for a = 0x8240, 0x8DFB do if (data[a] or 0) > 0x30 then tiled = tiled + 1 end end
			print(string.format("WATCH: t=%d pc=%04X sp=%04X len=%d tiles=%d h={2b1e:%d 3538:%d 35be:%d 4d20:%d}",
				final_t, cpu.pc, cpu.sp, blen(), tiled,
				hit.k2b1e or 0, hit.k3538 or 0, hit.k35be or 0, hit.k4d20 or 0))
		end
		if final_t >= 1500000 then
			print(string.format("END: pc=%04X sp=%04X h={2b1e:%d 3538:%d 35be:%d 4d20:%d} maxlen=%d",
				cpu.pc, cpu.sp, hit.k2b1e or 0, hit.k3538 or 0, hit.k35be or 0, hit.k4d20 or 0, max_len))
			emu:set_paused(true)
			phase = "done"
		end
	end
end)
