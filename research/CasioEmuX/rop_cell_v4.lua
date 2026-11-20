-- FINAL v2: menu-selection variants (down+EXE / up+EXE / down2+EXE) with Sigma
-- check after each; first bare 69B8 -> full sequence -> probe -> payload -> AC<-EXE
-- -> tile/@4D20 watch. 1x clock, fits in 10 s.single pass.
dofile("/home/yoxu/Projects/fx991espplus2nd/research/CasioEmuX/emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, DOWN, UP, K1, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x36, 0x27, 0x00, 0x22, 0x62
local PAY_IN = 0x8154

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local logs = {}
local phase, final_t, snap = "type", 0, {}
local scan_hits, scan_er0 = 0, {}

local function blen()
	for i = 0, 99 do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 100
end
local function bdump(n)
	local s = ""
	for i = 0, (n or 32) - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end
	return s
end
local function push(code, label, expect, hold, gap)
	keys[#keys + 1] = { code = code, label = label, expect = expect, hold = hold or 16000, gap = gap or 16000 }
end
local function rowdump(row)
	local s = ""
	for i = 0, 11 do s = s .. string.format("%02X", data[0xF800 + row * 16 + i]) end
	return s
end
local function sigma_check(tag)
	-- clear buffer via AC first so the check is unambiguous
	push(AC, tag .. "-clr", nil, 16000, 20000)
	push(SHIFT, tag .. "/mod", nil, 16000, 16000)
	push(0x56, tag, nil, 16000, 16000)
end

-- menu variant attempts; each: open setup, select variant, sigma check
local function menu_attempt(tag, moves)
	push(SHIFT, tag .. "/s1", nil, 16000, 12000)
	push(MODE, tag .. "/open", nil, 16000, 40000)
	for _, mv in ipairs(moves) do push(mv, tag .. "/mv", nil, 20000, 20000) end
	push(EXE, tag .. "/sel", nil, 20000, 25000)
	sigma_check(tag)
end

menu_attempt("V1-down", { DOWN })
menu_attempt("V2-up", { UP })
menu_attempt("V3-down2", { DOWN, DOWN })

-- full sequence (runs regardless; meaningful if a variant landed LineIO)
local function chord(mod, code, label, expect)
	push(mod, label .. "/mod", nil, 16000, 16000)
	push(code, label, expect, 16000, 16000)
end
chord(ALPHA, 0x33, "X1", { { 0x58 } })
chord(ALPHA, CALC, "eq", { { 0x3D } })
chord(SHIFT, 0x56, "Sigma", { { 0x69, 0xB8 } })
chord(ALPHA, 0x33, "X2", { { 0x58 } })
chord(SHIFT, 0x33, "comma1", { { 0x2C } })
push(K1, "one", { { 0x31 } })
chord(SHIFT, 0x33, "comma2", { { 0x2C } })
push(K1, "one2", { { 0x31 } })
push(KX10, "x10", { { 0x74 } })
push(K9, "nine", { { 0x39 } })
push(CALC, "CALC", nil, 16000, 24000)
push(EXE, "EXE", nil, 24000, 30000)
push(AC, "AC", nil, 16000, 24000)
push(LEFT, "LEFT", nil, 16000, 16000)
push(DEL, "DEL1", nil, 16000, 12000)
push(DEL, "DEL2", nil, 16000, 12000)
push(DEL, "DEL3", nil, 16000, 12000)
push(K2, "two", { { 0x32 } })
push(CALC, "CALC2", nil, 16000, 24000)
push(EXE, "EXE2", nil, 24000, 30000)
push(LEFT, "LEFT2", nil, 16000, 20000)
push(K1, "PROBE1", nil, 16000, 16000)

break_at(0x4D20, function()
	scan_hits = scan_hits + 1
	local er0 = (cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF)
	scan_er0[#scan_er0 + 1] = er0
	print(string.format("CHAIN: KEYSCAN #%d ER0=%04X pc=%04X sp=%04X row0=%s", scan_hits, er0, cpu.pc, cpu.sp, rowdump(0)))
	emu:set_paused(false)
end)
break_at(0x35BE, function()
	print(string.format("HIT-35BE: #%d pc=%04X sp=%04X dst=%04X", (n3538 or 0) + 1, cpu.pc, cpu.sp,
		((cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF))))
	emu:set_paused(false)
end)

local function finish(tag)
	print(string.format("PROTO: %s hits=%d er0=%s pc=%04X sp=%04X row0=%s", tag, scan_hits,
		table.concat(scan_er0, ","), cpu.pc, cpu.sp, rowdump(0)))
	print("PROTO: final-buf " .. bdump(48) .. " len=" .. blen())
	Keyboard:ReleaseAll()
	emu:set_paused(true)
	phase = "done"
end

local len_before_probe = nil
local sigma_lineio = false

addposttick(function()
	T = T + 1

	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "final"
				print("INPUT: typing done len=" .. blen() .. " buf=" .. bdump(48))
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
				local lb = cur.label
				if lb:match("^V%d%-clr$") then
					-- pre-clear: remember len to measure the sigma insert
					cur.len0 = blen()
				elseif lb:match("^V%d$") then
					local n = blen()
					local grown = n - (cur.len0 or 0)
					local bare = grown == 2 and (data[0x8154] == 0x69) and (data[0x8154 + 1] == 0xB8)
					if bare then sigma_lineio = true end
					logs[#logs + 1] = string.format("%s: grew=%d bytes=%02X%02X bare=%s",
						lb, grown, data[0x8154] or 0, data[0x8154 + 1] or 0, tostring(bare))
				elseif lb == "MODE" or lb:match("/open$") then
					logs[#logs + 1] = string.format("%s: row2=%s", lb, rowdump(2))
				elseif lb == "PROBE1" then
					len_before_probe = len_before_probe or blen()
					logs[#logs + 1] = string.format("PROBE1 before=%d after=%d %s", len_before_probe, blen(),
						blen() > len_before_probe and "GREW(bad)" or "NOT-INSERTED(good)")
				elseif cur.expect and #cur.expect > 0 and not check_expect(cur) then
					logs[#logs + 1] = string.format("MISMATCH %-16s len=%d tail=%s", lb, blen(), bdump(8))
				end
				state = "idle"
			end
		end

	elseif phase == "final" then
		final_t = final_t + 1
		if final_t == 1 then
			for a = 0x8100, 0x8E7F do snap[a] = (data[a] or 0) & 0xFF end
			Keyboard:PressKey(AC)
		elseif final_t == 16001 then
			Keyboard:ReleaseAll()
		elseif final_t == 20001 then
			Keyboard:PressKey(LEFT)
		elseif final_t == 36001 then
			Keyboard:ReleaseAll()
			for e = 0, 23 do
				data[PAY_IN + e * 4] = 0x35
				data[PAY_IN + e * 4 + 1] = 0x38
				data[PAY_IN + e * 4 + 2] = 0x35
				data[PAY_IN + e * 4 + 3] = 0x38
			end
			data[PAY_IN + 60] = 0x38; data[PAY_IN + 61] = 0x35
			data[PAY_IN + 62] = 0x38; data[PAY_IN + 63] = 0x35
			data[PAY_IN + 64] = 0x10; data[PAY_IN + 65] = 0xF8
			data[PAY_IN + 66] = 0xBE; data[PAY_IN + 67] = 0x35
			data[PAY_IN + 68] = 0x54; data[PAY_IN + 69] = 0x81
			data[PAY_IN + 96] = 0xD6; data[PAY_IN + 97] = 0x8F
			data[PAY_IN + 98] = 0x11; data[PAY_IN + 99] = 0x11
			print("INPUT: payload in, len=" .. blen())
		elseif final_t == 40001 then
			Keyboard:PressKey(0x60)
		elseif final_t == 60001 then
			Keyboard:ReleaseAll()
			emu:SetClockSpeed(16)   -- keys done: watch window at 16x
			print("WATCH: accelerated to 16x")
		elseif final_t >= 60001 then
			-- heavy scan only every 100k cycles (Lua-per-cycle was drowning the emu)
			if (final_t - 60001) % 100000 == 0 then
				local tiled = 0
				for a = 0x8240, 0x8DF8 do
					if (data[a] or 0) == 0x4D and (data[a - 1] or 0) == 0x0E then tiled = tiled + 1 end
				end
				print(string.format("WATCH: t=%d pc=%04X sp=%04X tiles=%d hits=%d", final_t, cpu.pc, cpu.sp, tiled, scan_hits))
				local st, en = nil, nil
				local n = 0
				for a = 0x8100, 0x8E7F do
					local ch = ((data[a] or 0) & 0xFF) ~= snap[a]
					if ch then n = n + 1; if st == nil then st, en = a, a end
					elseif st ~= nil then
						local d = ""
						for b = st, math.min(en, st + 15) do d = d .. string.format("%02X", (data[b] or 0) & 0xFF) end
						print(string.format("DIFF: %04X-%04X: %s", st, en, d))
						st = nil
					end
				end
				if st then
					local d = ""
					for b = st, math.min(en, st + 15) do d = d .. string.format("%02X", (data[b] or 0) & 0xFF) end
					print(string.format("DIFF: %04X-%04X: %s", st, en, d))
				end
				print(string.format("DIFF-CT: %d", n))
				if scan_hits >= 3 or tiled >= 10 then
					finish("TRIGGERED")
				elseif final_t > 2400000 then
					finish("NO-TRIGGER")
				end
			end
		end
	end
end)

function check_expect(k)
	if not k.expect or #k.expect == 0 then return true end
	local now = blen()
	for _, ref0 in ipairs(k.expect) do
		local ref = (type(ref0) == "number") and { ref0 } or ref0
		local ok = now >= #ref
		if ok then
			for i = 1, #ref do
				if (data[0x8154 + now - #ref + i - 1] or 0) ~= ref[i] then ok = false; break end
			end
		end
		if ok then return true end
	end
	return false
end
