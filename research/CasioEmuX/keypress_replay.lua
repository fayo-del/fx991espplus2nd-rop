-- keypress_replay.lua — TYPED-ONLY replay of a keygen.py schedule.
-- No data[] writes anywhere: every byte at 0x8154 arrives via Keyboard:PressKey.
-- Sequence: rop_e2e.lua entry recipe (T=1) -> AC, LEFT -> keygen schedule -> hold RIGHT + EXE -> watch.
-- Usage: SDL_VIDEODRIVER=dummy timeout 300 ./emulator/emulator model=models/fx991esplus2 script=keypress_replay.lua
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, DOWN, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x36, 0x00, 0x10, 0x22, 0x62
local PAY_IN = 0x8154
local SCHED = os.getenv("KEYGEN_SCHED") or "ref_payload_schedule.lua"

local function blen()
	for i = 0, 199 do if (data[PAY_IN + i] or 0) == 0 then return i end end
	return 200
end
local function bdump(n, off)
	local s = ""
	for i = 0, (n or 32) - 1 do s = s .. string.format("%02X", data[PAY_IN + (off or 0) + i] or 0) end
	return s
end

-- ===== action list: entry recipe (rop_e2e.lua typed queue, verbatim) =====
local acts = {}
local function push(code, label, hold, gap)
	acts[#acts + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 20000 }
end
local function chord(mod, code, label, hold, gap)
	push(mod, label .. "/mod", 16000, 16000)
	push(code, label, hold or 16000, gap or 16000)
end
push(SHIFT, "w1", 12000, 12000); push(AC, "w2", 12000, 24000)
chord(SHIFT, MODE, "setup1"); push(K2, "setup1-digit2", 30000, 40000)
chord(SHIFT, 0x56, "sigma-verify")
chord(SHIFT, MODE, "setup2"); push(K2, "setup2-digit2", 30000, 40000)
chord(SHIFT, 0x56, "sigma-verify2")
push(AC, "AC-clear", 16000, 24000)
chord(ALPHA, 0x33, "X1"); chord(ALPHA, CALC, "eq")
chord(SHIFT, 0x56, "Sigma"); chord(ALPHA, 0x33, "X2")
chord(SHIFT, 0x33, "comma1"); push(K1, "one", 16000, 20000)
chord(SHIFT, 0x33, "comma2"); push(K1, "one2", 16000, 20000)
push(KX10, "x10", 16000, 20000); push(K9, "nine", 16000, 20000)
push(CALC, "CALC", 16000, 24000); push(EXE, "EXE", 24000, 30000)
push(AC, "AC", 16000, 24000); push(LEFT, "LEFT", 16000, 16000)
push(DEL, "DEL1", 16000, 12000); push(DEL, "DEL2", 16000, 12000); push(DEL, "DEL3", 16000, 12000)
push(K2, "two", 16000, 20000)
push(CALC, "CALC2", 16000, 24000); push(EXE, "EXE2", 24000, 30000)
push(LEFT, "LEFT2", 16000, 20000)
push(K1, "PROBE1", 16000, 16000)
-- trigger prefix (E9 order): AC, LEFT, then the payload is typed, then EXE
push(AC, "AC-f", 16000, 24000); push(LEFT, "LEFT-f", 16000, 20000)
print("RECIPE: " .. #acts .. " presses, then schedule " .. SCHED)

-- ===== keygen schedule =====
local sched = dofile(SCHED)
for i, s in ipairs(sched) do
	if s.kind == "wait" then
		acts[#acts + 1] = { wait = s.ticks, label = "WAIT " .. s.note }
	elseif s.kind == "template" then
		for _, ch in ipairs(s.chords) do
			if ch[1] then push(ch[1], "tpl-mod", 16000, 16000) end
			push(ch[2], "TPL " .. (s.note or ""), 16000, 16000)
		end
	else
		if s.mod then push(s.mod, (s.note or s.name) .. "/mod", 8000, 8000) end
		acts[#acts + 1] = { code = s.code, label = string.format("P%03d %s%s [%s]", i, s.name or "?", s.walk and "(walk)" or "", s.note or ""),
			hold = 16000, gap = 16000, byte = s.byte, idx = i }
	end
end
print("SCHEDULE: " .. #sched .. " entries -> total actions " .. #acts)

-- ===== typing engine =====
local T, ai = 0, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t = "type", 0
local scan_hits, h3538 = 0, 0
local key_n = 0

break_at(0x4D20, function()
	scan_hits = scan_hits + 1
	if scan_hits <= 30 or scan_hits % 100 == 0 then
		print(string.format("CHAIN: KEYSCAN #%d pc=%04X sp=%04X r0=%02X%02X r2=%02X%02X", scan_hits, cpu.pc, cpu.sp,
			cpu.r1 or 0, cpu.r0 or 0, cpu.r3 or 0, cpu.r2 or 0))
	end
	emu:set_paused(false)
end)
break_at(0x3538, function()
	h3538 = h3538 + 1
	emu:set_paused(false)
end)

local function tiles()
	local t4d, t38 = 0, 0
	for a = 0x8240, 0x8DF8 do
		local b0, b1 = data[a] or 0, data[a + 1] or 0
		if b0 == 0x0E and b1 == 0x4D then t4d = t4d + 1 end
		if b0 == 0x38 and b1 == 0x35 then t38 = t38 + 1 end
	end
	return t4d, t38
end
local function floodok()
	-- period-100 check over the span
	local ok, bad = 0, 0
	for a = 0x8200, 0x8DF0, 4 do
		if (data[a] or 0) == (data[PAY_IN + (a - PAY_IN) % 100] or 0) then ok = ok + 1 else bad = bad + 1 end
	end
	return ok, bad
end

addposttick(function()
	T = T + 1
	if phase == "type" then
		if state == "idle" then
			ai = ai + 1
			if ai > #acts then
				phase = "trigger0"
				print(string.format("TYPED: all %d actions done T=%d len=%d buf100=%s", #acts, T, blen(), bdump(100)))
				return
			end
			cur = acts[ai]
			if cur.wait then state = "wait"; hold_t = cur.wait
			else Keyboard:PressKey(cur.code); state = "press"; hold_t = cur.hold; key_n = key_n + 1 end
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then
				Keyboard:ReleaseAll(); state = "rel"; gap_t = cur.gap
				if cur.label and cur.label:sub(1, 1) == "P" then
					print(string.format("KEY %s len=%d tail=%s", cur.label, blen(), bdump(12, math.max(0, blen() - 12))))
				end
			end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then state = "idle" end
		elseif state == "wait" then
			hold_t = hold_t - 1
			if hold_t <= 0 then state = "idle" end
		end
	elseif phase == "trigger0" then
		-- hold RIGHT (KEYSCAN r0=1) and press EXE = the AC,◀,EXE trigger tail
		Keyboard:PressKey(0x37)
		Keyboard:PressKey(EXE)
		phase = "watch"; final_t = 0
		print(string.format("TRIGGER: RIGHT+EXE pressed T=%d len=%d buf100=%s", T, blen(), bdump(100)))
	elseif phase == "watch" then
		final_t = final_t + 1
		if final_t == 24000 then Keyboard:ReleaseAll() end
		if final_t % 200000 == 0 then
			local t4d, t38 = tiles()
			local ok, bad = floodok()
			print(string.format("WATCH: t=%d pc=%04X sp=%04X len=%d tiles0E4D=%d tiles3835=%d floodok=%d/%d h4D20=%d h3538=%d",
				final_t, cpu.pc, cpu.sp, blen(), t4d, t38, ok, bad, scan_hits, h3538))
		end
		if scan_hits >= 50 then
			print(string.format("VERDICT: TRIGGERED-CHAIN-RUNS scan_hits=%d h3538=%d len=%d", scan_hits, h3538, blen()))
		elseif final_t > 1500000 then
			local t4d, t38 = tiles()
			local ok, bad = floodok()
			print(string.format("VERDICT: NO-TRIGGER scan_hits=%d h3538=%d len=%d tiles0E4D=%d tiles3835=%d floodok=%d/%d buf100=%s",
				scan_hits, h3538, blen(), t4d, t38, ok, bad, bdump(100)))
			phase = "done"
		end
	end
end)
