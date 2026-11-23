-- more07_alt.lua — MB07AltTrigger: alternative trigger keys & longer copies for the
-- 0x8154 strcpy flood. Scenario via more07_scn.txt (base|long|alt|typemore).
-- Instruments: strcpy wrapper 0x2B10 (per call, site=lr), the inner copy loop 0x6B62
-- (per word — the journal stamps jump straight into it; call runs reconstructed by
-- ER12/ER10 +2 strides), strcat 0xCB5E, memmove 0x5108, memcpy12 0x35BE, POP PC 0x2B1E,
-- KEYSCAN 0x4D20. Typed queue = rop_e2e verbatim; only final phase/payload differ.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local SCN = nil
do
	local f = io.open("more07_scn.txt", "r")
	if f then SCN = f:read("*l"); f:close() end
end
SCN = SCN or "base"
print("MB07 scenario: " .. SCN)

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT, DOWN, ON, RCL =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37, 0x36, 0xFF, 0x03
local K1, K2, K9, KX10 = 0x00, 0x10, 0x22, 0x62
local PAY = 0x8154

-- ===== typed queue (rop_e2e verbatim) =====
local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t = "type", 0
local function push(code, label, hold, gap)
	keys[#keys + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 20000 }
end
local function chord(mod, code, label)
	push(mod, label .. "/mod", 16000, 16000); push(code, label, 16000, 16000)
end
push(SHIFT, "w1", 12000, 12000); push(AC, "w2", 12000, 24000)
chord(SHIFT, MODE, "setup1"); push(K2, "setup1-digit2", 30000, 40000)
chord(SHIFT, 0x56, "sigma-verify")
chord(SHIFT, MODE, "setup2"); push(K2, "setup2-digit2", 30000, 40000)
chord(SHIFT, 0x56, "sigma-verify2")
push(AC, "AC-clear", 16000, 24000)
chord(ALPHA, 0x33, "X1"); chord(ALPHA, CALC, "eq"); chord(SHIFT, 0x56, "Sigma")
chord(ALPHA, 0x33, "X2"); chord(SHIFT, 0x33, "comma1"); push(K1, "one")
chord(SHIFT, 0x33, "comma2"); push(K1, "one2"); push(KX10, "x10"); push(K9, "nine")
push(CALC, "CALC", 16000, 24000); push(EXE, "EXE", 24000, 30000)
push(AC, "AC", 16000, 24000); push(LEFT, "LEFT", 16000, 16000)
push(DEL, "DEL1", 16000, 12000); push(DEL, "DEL2", 16000, 12000); push(DEL, "DEL3", 16000, 12000)
push(K2, "two", 16000, 20000)
push(CALC, "CALC2", 16000, 24000); push(EXE, "EXE2", 24000, 30000)
push(LEFT, "LEFT2", 16000, 20000)
push(K1, "PROBE1", 16000, 16000)

-- ===== helpers =====
local function blen()
	for i = 0, 399 do if (data[PAY + i] or 0) == 0 then return i end end
	return 400
end
local function bdump(lo, n)
	local s = ""
	for i = lo, lo + n - 1 do s = s .. string.format("%02X", data[PAY + i] or 0) end
	return s
end
local function er(hi, lo) return ((hi & 0xFF) << 8) | (lo & 0xFF) end
local function slen(base)
	local n = 0
	while n < 600 and (data[base + n] or 0) ~= 0 do n = n + 1 end
	return n
end
local payload = {}
local plen = 0
local function plant(n)
	for i = 1, n do payload[i] = i; data[PAY + i - 1] = i end
	plen = n
	print(string.format("PLANT: %d distinct bytes at %04X..%04X strlen=%d", n, PAY, PAY + n - 1, slen(PAY)))
end

-- ===== loggers =====
local c_str, c_cat, c_mov, c_m12, pops, hops = 0, 0, 0, 0, 0, 0
local h62 = 0
local hist = {}          -- dst histogram of 0x6B62 word writes
local maxdst62, maxlen62, maxend62, stack62 = 0, 0, 0, 0
local last_d, last_s, cur_dst, cur_src, cur_lr, cur_len = -1, -1, 0, 0, 0, 0
local calls62 = {}       -- reconstructed calls {dst,src,lr,len}
local sitew = {}         -- wrapper (0x2B10) per-site aggregate
local function store_call()
	if cur_len > 0 then
		if #calls62 < 4000 then
			calls62[#calls62 + 1] = { dst = cur_dst, src = cur_src, lr = cur_lr & 0xFFFF, len = cur_len }
		end
		if cur_len > maxlen62 then maxlen62 = cur_len end
		if cur_dst + cur_len > maxend62 then maxend62 = cur_dst + cur_len end
		if cur_dst >= 0x8C60 or cur_dst + cur_len > 0x8C60 then stack62 = stack62 + 1 end
	end
end
local function arm()
	break_at(0x2B10, function()
		c_str = c_str + 1
		local d, s, lr = er(cpu.r1, cpu.r0), er(cpu.r3, cpu.r2), cpu.lr & 0xFFFF
		local l = slen(s)
		local k = string.format("S@%04X", lr)
		local t = sitew[k]
		if not t then t = { n = 0, mind = 0xFFFF, maxe = 0, maxl = 0 }; sitew[k] = t end
		t.n = t.n + 1
		if d < t.mind then t.mind = d end
		if d + l > t.maxe then t.maxe = d + l end
		if l > t.maxl then t.maxl = l end
		if c_str <= 60 then
			print(string.format("WRAP site=%04X dst=%04X src=%04X len=%d end=%04X sp=%04X", lr, d, s, l, d + l, cpu.sp))
		end
		if c_str >= 4000 then unbreak_at(0x2B10) end
		emu:set_paused(false)
	end)
	break_at(0x6B62, function()
		local d = er(cpu.r13, cpu.r12)
		local s = er(cpu.r11, cpu.r10)
		h62 = h62 + 1
		hist[d] = (hist[d] or 0) + 1
		if d > maxdst62 then maxdst62 = d end
		if d == last_d + 1 and s == last_s + 1 then
			cur_len = cur_len + 1
		else
			store_call()
			cur_dst, cur_src, cur_lr, cur_len = d, s, cpu.lr, 1
		end
		last_d, last_s = d, s
		if h62 >= 150000 then unbreak_at(0x6B62) end
		emu:set_paused(false)
	end)
	break_at(0xCB5E, function()
		c_cat = c_cat + 1
		local d, s = er(cpu.r1, cpu.r0), er(cpu.r3, cpu.r2)
		local l = slen(d) + slen(s)
		if c_cat <= 40 then
			print(string.format("CAT site=%04X dst=%04X src=%04X totallen=%d sp=%04X", cpu.lr & 0xFFFF, d, s, l, cpu.sp))
		end
		if d >= 0x8C00 or d + l > 0x8C00 then
			print(string.format("CAT-STACK site=%04X dst=%04X src=%04X totallen=%d", cpu.lr & 0xFFFF, d, s, l))
		end
		if c_cat >= 3000 then unbreak_at(0xCB5E) end
		emu:set_paused(false)
	end)
	break_at(0x5108, function()
		c_mov = c_mov + 1
		if c_mov <= 30 then
			print(string.format("MOV site=%04X ER0=%04X ER2=%04X sp=%04X w[sp]=%04X w[sp+2]=%04X",
				cpu.lr & 0xFFFF, er(cpu.r1, cpu.r0), er(cpu.r3, cpu.r2), cpu.sp,
				data[cpu.sp] or 0, data[cpu.sp + 2] or 0))
		end
		if c_mov >= 2000 then unbreak_at(0x5108) end
		emu:set_paused(false)
	end)
	break_at(0x35BE, function()
		c_m12 = c_m12 + 1
		local d = er(cpu.r3, cpu.r2)
		if c_m12 <= 10 or (d >= 0x8000 and d < 0xF000) then
			print(string.format("M12 #%d r0=%02X ER2=%04X sp=%04X lr=%04X", c_m12, cpu.r0 & 0xFF, d, cpu.sp, cpu.lr & 0xFFFF))
		end
		if c_m12 >= 400 then unbreak_at(0x35BE) end
		emu:set_paused(false)
	end)
	break_at(0x2B1E, function() pops = pops + 1; emu:set_paused(false) end)
	break_at(0x4D20, function() hops = hops + 1; emu:set_paused(false) end)
end

-- ===== analysis =====
local function analyze(tag)
	local lo, hi = 0x8154, 0x8DFF
	local n = hi - lo + 1
	local set = {}
	for a = lo, hi do set[data[a] or 0] = true end
	local nd = 0; for _ in pairs(set) do nd = nd + 1 end
	local ok, firstbad = 0, -1
	for i = 0, n - 1 do
		if (data[lo + i] or 0) == payload[(i % plen) + 1] then ok = ok + 1
		elseif firstbad < 0 then firstbad = i end
	end
	local function minper(a0, a1)
		for p = 1, plen do
			local good = true
			for i = a0, a1 - p do
				if (data[i] or 0) ~= (data[i + p] or 0) then good = false; break end
			end
			if good then return p end
		end
		return 0
	end
	local st, stn = 0, 0x8DFF - 0x8C60 + 1
	for i = 0, stn - 1 do
		if (data[0x8C60 + i] or 0) == payload[((0x8C60 - lo + i) % plen) + 1] then st = st + 1 end
	end
	print(string.format("MB07-ANALYZE %s: plen=%d match=%d/%d firstbad=%d minperiod(full)=%d minperiod(8240+)=%d distinct=%d stackmatch=%d/%d",
		tag, plen, ok, n, firstbad, minper(lo, hi), minper(0x8240, hi), nd, st, stn))
end
local function report(tag)
	store_call()
	local arr = {}
	for k, t in pairs(sitew) do arr[#arr + 1] = { k = k, t = t } end
	table.sort(arr, function(a, b) return a.t.maxe > b.t.maxe end)
	local htop = {}
	for d, c in pairs(hist) do htop[#htop + 1] = { d = d, c = c } end
	table.sort(htop, function(a, b) return a.d > b.d end)
	local hs = ""
	for i = 1, math.min(12, #htop) do hs = hs .. string.format("%04Xx%d ", htop[i].d, htop[i].c) end
	local ctop = {}
	for _, c in ipairs(calls62) do ctop[#ctop + 1] = c end
	table.sort(ctop, function(a, b) return a.len > b.len end)
	local cs = ""
	for i = 1, math.min(10, #ctop) do
		cs = cs .. string.format("[dst=%04X src=%04X lr=%04X len=%d] ", ctop[i].dst, ctop[i].src, ctop[i].lr, ctop[i].len)
	end
	print(string.format("MB07-REPORT %s: wrap=%d h62=%d cat=%d mov=%d m12=%d pops=%d hops=%d | maxlen62=%d maxend62=%04X maxdst62=%04X stack62calls=%d",
		tag, c_str, h62, c_cat, c_mov, c_m12, pops, hops, maxlen62, maxend62, maxdst62, stack62))
	print("MB07-HIST62 top-dst: " .. hs)
	print("MB07-CALLS62 longest: " .. cs)
	for i = 1, math.min(15, #arr) do
		local t = arr[i].t
		print(string.format("  WRAP %s n=%d mindst=%04X maxend=%04X maxlen=%d", arr[i].k, t.n, t.mind, t.maxe, t.maxl))
	end
	analyze(tag)
	os.exit(0)
end

-- ===== alt scenario key queue =====
local akeys = {
	{ k = EXE,  l = "EXE-only" },
	{ k = AC,   l = "AC-after-plant" },
	{ k = K1,   l = "type-K1-after-AC" },
	{ k = K2,   l = "type-K2-after-AC" },
	{ k = K9,   l = "type-K9-after-AC" },
	{ k = KX10, l = "type-x10-after-AC" },
	{ k = EXE,  l = "EXE-after-AC" },
	{ k = LEFT, l = "LEFT" },
	{ k = EXE,  l = "EXE-after-LEFT" },
	{ k = RCL,  l = "RCL" },
	{ k = MODE, l = "MODE" },
	{ k = DOWN, l = "DOWN" },
	{ k = AC,   l = "AC2" },
	{ k = LEFT, l = "LEFT2" },
	{ k = EXE,  l = "EXE-final(control)" },
	{ k = ON,   l = "ON" },
}
local ai = 0
local last_copies, stable = -1, 0
local function totc() return c_str + h62 + c_cat + c_mov end

addposttick(function()
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				print("INPUT: typing done len=" .. blen() .. " buf=" .. bdump(0, 32))
				if SCN == "alt" then
					phase = "alt"; ai = 0; state = "idle"
					arm()
					plant(101)
				else
					phase = "final"; final_t = 0
					arm()
				end
				return
			end
			cur = keys[ki]
			Keyboard:PressKey(cur.code)
			state = "press"; hold_t = cur.hold
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:ReleaseAll(); state = "rel"; gap_t = cur.gap end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then
				state = "idle"
				if cur.label == "PROBE1" then
					print(string.format("PROBE1: len=%d %s", blen(), bdump(0, 8)))
				end
			end
		end

	elseif phase == "alt" then
		if state == "idle" then
			ai = ai + 1
			if ai > #akeys or stack62 > 0 then
				phase = "watch"; final_t = 0
				emu:SetClockSpeed(16)
				print("ALTK: queue done -> watch")
				return
			end
			cur = akeys[ai]
			Keyboard:PressKey(cur.k)
			state = "press"; hold_t = 16000
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:ReleaseAll(); state = "rel"; gap_t = 24000 end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then
				state = "idle"
				local t = totc()
				print(string.format("ALTK %s: copies=%d(+%d) maxlen62=%d maxend62=%04X stack62=%d blen=%d buf=%s pc=%04X sp=%04X",
					cur.l, t, t - (last_copies >= 0 and last_copies or t), maxlen62, maxend62, stack62,
					blen(), bdump(0, 12), cpu.pc, cpu.sp))
				last_copies = t
				if stack62 > 0 then
					print("ALTK-FLOOD: stack reached after " .. cur.l)
					phase = "watch"; final_t = 0
					emu:SetClockSpeed(16)
				end
			end
		end

	elseif phase == "final" then
		final_t = final_t + 1
		if SCN == "base" or SCN == "long" then
			if final_t == 1 then
				Keyboard:PressKey(RIGHT); Keyboard:PressKey(AC)
			elseif final_t == 16001 then
				Keyboard:ReleaseAll()
			elseif final_t == 20001 then
				Keyboard:PressKey(LEFT)
			elseif final_t == 36001 then
				Keyboard:ReleaseAll()
				if SCN == "base" then plant(100) else plant(204); data[PAY + 204] = 0 end
			elseif final_t == 40001 then
				Keyboard:PressKey(EXE)
			elseif final_t == 60001 then
				Keyboard:ReleaseAll()
				emu:SetClockSpeed(16)
				print("WATCH: 16x, EXE fired")
				phase = "watch"
			end
		elseif SCN == "typemore" then
			if final_t == 1 then
				Keyboard:PressKey(RIGHT); Keyboard:PressKey(AC)
			elseif final_t == 16001 then
				Keyboard:ReleaseAll()
			elseif final_t == 20001 then
				Keyboard:PressKey(LEFT)
			elseif final_t == 36001 then
				Keyboard:ReleaseAll()
				plant(100)
			elseif final_t == 40001 then
				Keyboard:PressKey(AC)
			elseif final_t == 60001 then
				Keyboard:ReleaseAll()
				print(string.format("TM: after AC-with-payload: strlen=%d h62=%d maxend62=%04X stack62=%d buf=%s",
					slen(PAY), h62, maxend62, stack62, bdump(0, 16)))
				ai = 0; phase = "tmore"; state = "idle"
			end
		end

	elseif phase == "tmore" then
		local tmq = { K1, K2, K9, KX10, K1, K2 }
		if state == "idle" then
			ai = ai + 1
			if ai > #tmq then
				phase = "tfinal"; final_t = 0
				return
			end
			cur = { k = tmq[ai] }
			Keyboard:PressKey(cur.k)
			state = "press"; hold_t = 16000
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:ReleaseAll(); state = "rel"; gap_t = 20000 end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then
				state = "idle"
				print(string.format("TM-KEY #%d code=%02X: strlen=%d buf=%s h62=%d maxend62=%04X stack62=%d pc=%04X",
					ai, cur.k, slen(PAY), bdump(0, 16), h62, maxend62, stack62, cpu.pc))
			end
		end

	elseif phase == "tfinal" then
		final_t = final_t + 1
		if final_t == 1 then
			Keyboard:PressKey(LEFT)
		elseif final_t == 20001 then
			Keyboard:ReleaseAll()
			print(string.format("TM: before EXE strlen=%d buf=%s", slen(PAY), bdump(0, 24)))
		elseif final_t == 24001 then
			Keyboard:PressKey(EXE)
		elseif final_t == 48001 then
			Keyboard:ReleaseAll()
			emu:SetClockSpeed(16)
			print("TM: watch 16x")
			phase = "watch"
		end

	elseif phase == "watch" then
		final_t = final_t + 1
		if final_t % 200000 == 0 then
			print(string.format("WATCH: t=%d pc=%04X sp=%04X copies=%d maxlen62=%d maxend62=%04X stack62=%d pops=%d hops=%d blen=%d",
				final_t, cpu.pc, cpu.sp, totc(), maxlen62, maxend62, stack62, pops, hops, blen()))
			local t = totc()
			if t == last_copies then stable = stable + 1 else stable = 0 end
			last_copies = t
			if (stable >= 3 and final_t > 400000) or final_t > 3000000 then
				report("END-" .. SCN)
			end
		end
	end
end)
