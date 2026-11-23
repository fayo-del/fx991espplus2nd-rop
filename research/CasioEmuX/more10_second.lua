-- MB10 run1: (a) do keys pressed DURING the chain modify 0x8154..0x81B7?
--            (b) teleport the chain into the token-insert handler 0x73A2 (0x7402 family)
--                with a key held -> does 0x8154 change? (raw, and after planting a NUL
--                at 0x8186 to bound strlen so the 250-cap at 0x7402 passes)
--            (c) fire the strcpy wrapper 0x2B10 (dst=0x81B8 src=0x8154) from the chain
--                -> second flood -> distinct-byte count before/after.
-- Typed recipe verbatim from rop_e2e.lua / content_map.lua; payload = pure 0x4D0E flood.
dofile("emulator/lua-common.lua")
local T = 0

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, DOWN, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x36, 0x00, 0x10, 0x22, 0x62
local PAY_IN = 0x8154
local OUT = "/tmp/"

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t = "type", 0
local scan_hits = 0

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
	keys[#keys + 1] = { code = code, label = label, expect = expect, hold = hold or 16000, gap = gap or 20000 }
end
local function render(tag) keys[#keys + 1] = { render = tag } end
local function render_screen(tag) print("SCREEN: ---- " .. tag .. " ----") end
local function chord(mod, code, label, expect)
	push(mod, label .. "/mod", nil, 16000, 16000)
	push(code, label, expect, 16000, 16000)
end

-- warm-up
push(SHIFT, "w1", nil, 12000, 12000); push(AC, "w2", nil, 12000, 24000)
chord(SHIFT, MODE, "setup1")
render("setup1")
push(K2, "setup1-digit2", nil, 30000, 40000)
render("setup1 after 2")
chord(SHIFT, 0x56, "sigma-verify")
chord(SHIFT, MODE, "setup2")
push(K2, "setup2-digit2", nil, 30000, 40000)
render("setup2 after 2")
chord(SHIFT, 0x56, "sigma-verify2")
push(AC, "AC-clear", nil, 16000, 24000)
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
render("formula typed")
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

-- ===== experiment state =====
local base = {}      -- 0x8154..0x81B7 at hop1 (= payload)
local lowbase = {}   -- 0x8100..0x8153 at hop1
local payload = {}   -- payload[1..100]
local KEYSEQ = { 0x00, 0x10, 0x22, 0x26, 0x37, 0x42, 0x60 }  -- (a) keys, pressed at hops 2..8
local h73, h7402, h7448, h5108, h74fa, h2b10 = 0, 0, 0, 0, 0, 0
local tele1_done, nul_done, tele2_done, flood2_done = false, false, false, false
local last_hit_t = 0

local function region_diff(lo, hi, ref, tag)
	local out = {}
	for a = lo, hi do
		local b = (data[a] or 0) & 0xFF
		local r = ref[a]
		if b ~= r then out[#out + 1] = string.format("%04X:%02X>%02X", a, r & 0xFF, b) end
	end
	if #out == 0 then
		print(tag .. ": NO-CHANGE " .. string.format("%04X-%04X", lo, hi))
	else
		print(tag .. ": " .. #out .. " changed: " .. table.concat(out, " ", 1, math.min(#out, 24)))
	end
end

local function dump_span(tag)
	local f = io.open(OUT .. "more10_run1_" .. tag .. ".bin", "wb")
	for a = 0x8100, 0x8DFF do f:write(string.char((data[a] or 0) & 0xFF)) end
	f:close()
end

local function stats(tag)
	local vals = {}
	local mism = 0
	local mism_list = {}
	for a = 0x8154, 0x8DFF do
		local b = (data[a] or 0) & 0xFF
		vals[b] = true
		local e = payload[((a - PAY_IN) % 100) + 1]
		if b ~= e then
			mism = mism + 1
			if #mism_list < 30 then mism_list[#mism_list + 1] = string.format("%04X:%02X>%02X", a, e, b) end
		end
	end
	local nv = 0; for _ in pairs(vals) do nv = nv + 1 end
	-- distinct even-aligned 100-byte windows over the span
	local wins = {}
	for off = 0, 99, 2 do
		local s = ""
		for i = 0, 99 do s = s .. string.char((data[PAY_IN + off + i] or 0) & 0xFF) end
		wins[s] = true
	end
	local nw = 0; for _ in pairs(wins) do nw = nw + 1 end
	print(string.format("STATS[%s]: distinct byte-values in 0x8154-0x8DFF=%d, mismatches vs P1-period=%d, distinct even 100-windows=%d",
		tag, nv, mism, nw))
	if mism > 0 then print("STATS[" .. tag .. "] first mismatches: " .. table.concat(mism_list, " ")) end
end

break_at(0x73A2, function()
	h73 = h73 + 1
	if h73 <= 3 then print(string.format("PATH-73A2 #%d pc=%04X sp=%04X lr=%04X csr=%X dsr=%02X r0=%02X", h73, cpu.pc, cpu.sp, cpu.lr, cpu.csr, cpu.dsr, cpu.r0 & 0xFF)) end
	emu:set_paused(false)
end)
break_at(0x7402, function()
	h7402 = h7402 + 1
	if h7402 <= 3 then print(string.format("PATH-7402 #%d sp=%04X r0=%02X", h7402, cpu.sp, cpu.r0 & 0xFF)) end
	emu:set_paused(false)
end)
break_at(0x7448, function()
	h7448 = h7448 + 1
	if h7448 <= 3 then print(string.format("PATH-7448(memmove-insert) #%d sp=%04X", h7448, cpu.sp)) end
	emu:set_paused(false)
end)
break_at(0x5108, function()
	h5108 = h5108 + 1
	emu:set_paused(false)
end)
break_at(0x74FA, function()
	h74fa = h74fa + 1
	if h74fa <= 3 then print(string.format("PATH-74FA(BAIL) #%d sp=%04X r0=%02X", h74fa, cpu.sp, cpu.r0 & 0xFF)) end
	emu:set_paused(false)
end)
break_at(0x2B10, function()
	h2b10 = h2b10 + 1
	if h2b10 <= 4 then
		local er0 = (cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF)
		local er2 = (cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF)
		print(string.format("PATH-2B10(strcpy-wrap) #%d sp=%04X ER0=%04X ER2=%04X", h2b10, cpu.sp, er0, er2))
	end
	emu:set_paused(false)
end)

local done = false
local function finish(tag)
	if done then return end
	done = true
	print(string.format("PROTO: %s hits=%d pc=%04X sp=%04X h73=%d h7402=%d h7448=%d h5108=%d h74fa=%d h2b10=%d",
		tag, scan_hits, cpu.pc, cpu.sp, h73, h7402, h7448, h5108, h74fa, h2b10))
	print("PROTO: final-buf " .. bdump(64) .. " len=" .. blen())
	print(string.format("PROTO: low 0x8100-0x8153: 812C=%02X%02X 8113=%02X 8114=%02X 80F5=%02X",
		data[0x812D] or 0, data[0x812C] or 0, data[0x8113] or 0, data[0x8114] or 0, data[0x80F5] or 0))
	dump_span("final")
	stats("final")
	Keyboard:ReleaseAll()
	emu:set_paused(true)
	phase = "done"
end

break_at(0x4D20, function()
	scan_hits = scan_hits + 1
	last_hit_t = final_t
	local sp = cpu.sp
	if scan_hits == 1 then
		for a = 0x8154, 0x81B7 do base[a] = (data[a] or 0) & 0xFF end
		for a = 0x8100, 0x8153 do lowbase[a] = (data[a] or 0) & 0xFF end
		for i = 1, 100 do payload[i] = base[0x8154 + i - 1] end
		print(string.format("TRIGGER: hop#1 pc=%04X sp=%04X lr=%04X csr=%X dsr=%02X", cpu.pc, sp, cpu.lr, cpu.csr, cpu.dsr))
		print("BASE: buf100=" .. bdump(100))
		print(string.format("BASE: 812C=%02X%02X 8113=%02X 8114=%02X 80F5=%02X 8100-0x8153=%s",
			data[0x812D] or 0, data[0x812C] or 0, data[0x8113] or 0, data[0x8114] or 0, data[0x80F5] or 0,
			(function() local s = "" for a = 0x8100, 0x8153 do s = s .. string.format("%02X", data[a] or 0) end return s end)()))
		dump_span("hop1")
	elseif scan_hits >= 3 and scan_hits <= 9 then
		-- (a): report effect of the key pressed at the previous hop
		local k = KEYSEQ[scan_hits - 2]
		print(string.format("HOP#%d (key %02X held since prev hop):", scan_hits, k))
		region_diff(0x8154, 0x81B7, base, "  (a) buf-diff")
		region_diff(0x8100, 0x8153, lowbase, "  (a) low-diff")
	end
	-- (a) key schedule: press KEYSEQ[k-1] at hop k (k = 2..8)
	if scan_hits >= 2 and scan_hits <= 8 then
		Keyboard:ReleaseAll()
		Keyboard:PressKey(KEYSEQ[scan_hits - 1])
	end
	-- (b) variant 1: raw teleport into insert handler at hop 9, digit-1 held
	if scan_hits == 9 and not tele1_done then
		tele1_done = true
		Keyboard:ReleaseAll()
		Keyboard:PressKey(0x00)  -- digit 1 -> token 0x31
		cpu.pc = 0x73A2
		cpu.lr = 0x2B1E
		cpu.csr = 0
		cpu.dsr = 0
		print(string.format("TELE1: hop#9 -> pc=0x73A2 sp=%04X key=0x00 held, 80F5=%02X", sp, data[0x80F5] or 0))
	end
	-- hops 10..12: watch the result of tele1
	if scan_hits >= 10 and scan_hits <= 12 then
		print(string.format("HOP#%d post-tele1:", scan_hits))
		region_diff(0x8154, 0x81B7, base, "  (b1) buf-diff")
	end
	-- (b) variant 2: plant NUL at 0x8186 (bounds strlen(0x8154)=50 so the 0x7402 cap passes),
	-- then teleport into the insert handler again with digit-2 held
	if scan_hits == 13 and not nul_done then
		nul_done = true
		Keyboard:ReleaseAll()
		Keyboard:PressKey(0x10)  -- digit 2 -> token 0x32
		data[0x8186] = 0x00
		print(string.format("NUL: planted 0 at 0x8186; strlen(0x8154) now=%d", blen()))
		cpu.pc = 0x73A2
		cpu.lr = 0x2B1E
		cpu.csr = 0
		cpu.dsr = 0
		tele2_done = true
		print(string.format("TELE2: hop#13 -> pc=0x73A2 sp=%04X key=0x10 held", sp))
	end
	if scan_hits >= 14 and scan_hits <= 17 then
		print(string.format("HOP#%d post-tele2:", scan_hits))
		region_diff(0x8154, 0x81B7, base, "  (b2) buf-diff")
		region_diff(0x8100, 0x8153, lowbase, "  (b2) low-diff")
	end
	-- (c): fire the second flood: strcpy wrapper 0x2B10 with ER0=0x81B8 (dst), ER2=0x8154 (src)
	if scan_hits == 18 and not flood2_done then
		flood2_done = true
		Keyboard:ReleaseAll()
		dump_span("pre_flood2")
		stats("pre_flood2")
		cpu.r0 = 0xB8; cpu.r1 = 0x81   -- ER0 = 0x81B8
		cpu.r2 = 0x54; cpu.r3 = 0x81   -- ER2 = 0x8154
		cpu.pc = 0x2B10
		cpu.lr = 0x2B1E
		cpu.csr = 0
		cpu.dsr = 0
		print(string.format("FLOOD2: hop#18 -> pc=0x2B10 ER0=81B8 ER2=8154 sp=%04X buf=%s", sp, bdump(48)))
	end
	if scan_hits >= 19 and scan_hits <= 26 then
		if scan_hits == 19 then
			print("HOP#19 post-flood2:")
			region_diff(0x8154, 0x81B7, base, "  (c) buf-diff")
			stats("post_flood2")
		end
	end
	if scan_hits == 27 then
		dump_span("post_flood2")
		stats("post_flood2_final")
		finish("RUN1-DONE")
	end
	emu:set_paused(false)
end)

local len_before_probe = nil

addposttick(function()
	T = T + 1
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "final"
				print("INPUT: typing done len=" .. blen() .. " buf=" .. bdump(48))
				return
			end
			cur = keys[ki]
			if cur.code then
				Keyboard:PressKey(cur.code)
				state = "press"; hold_t = cur.hold
			else
				render_screen(cur.render)
			end
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
				if lb == "sigma-verify" or lb == "sigma-verify2" then
					local n = blen()
					local bare = n >= 2 and (data[0x8154 + n - 2] == 0x69) and (data[0x8154 + n - 1] == 0xB8)
					local boxed = false
					for i = 0, 97 do
						if (data[0x8154 + i] or 0) == 0x21 and (data[0x8154 + i + 1] or 0) == 0xBA then boxed = true; break end
					end
					print(string.format("SIGMA: %s len=%d bare=%s boxed=%s", lb, n, tostring(bare), tostring(boxed)))
				elseif lb == "PROBE1" then
					len_before_probe = len_before_probe or blen()
					print(string.format("PROBE1: before=%d after=%d %s", len_before_probe, blen(),
						blen() > len_before_probe and "GREW(bad)" or "NOT-INSERTED(good)"))
				end
				state = "idle"
			end
		end
	elseif phase == "final" then
		final_t = final_t + 1
		if final_t == 1 then
			Keyboard:PressKey(0x37)
			Keyboard:PressKey(AC)
		elseif final_t == 16001 then
			Keyboard:ReleaseAll()
		elseif final_t == 20001 then
			Keyboard:PressKey(LEFT)
		elseif final_t == 36001 then
			Keyboard:ReleaseAll()
			for e = 0, 49 do data[PAY_IN + e * 2] = 0x0E; data[PAY_IN + e * 2 + 1] = 0x4D end
			print("INPUT: payload pure-0E4D flood in, len=" .. blen())
		elseif final_t == 40001 then
			Keyboard:PressKey(0x60)
		elseif final_t == 60001 then
			Keyboard:ReleaseAll()
			emu:SetClockSpeed(16)
			print("WATCH: 16x")
		elseif final_t > 60001 then
			if (final_t - 60001) % 200000 == 0 then
				print(string.format("WATCH: t=%d pc=%04X sp=%04X hits=%d h73=%d h7402=%d h74fa=%d h2b10=%d buf=%s",
					final_t, cpu.pc, cpu.sp, scan_hits, h73, h7402, h74fa, h2b10, bdump(16)))
			end
			if scan_hits >= 30 then finish("HITS30") elseif final_t > 6000000 then finish("TIMEOUT") end
		end
	end
end)
