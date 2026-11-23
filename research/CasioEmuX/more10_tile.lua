-- MB10 run2: (b) chain-TILE variant — payload word W(84)=0x73A2 so the walk's hop #10
-- POP-PC's directly into the token-insert handler 0x73A2 (tile bytes A2 73 0E 4D:
-- PC=0x73A2, CSR word 0x4D0E -> bank 0). A key is held from hop #2. NUL planted at
-- 0x8186 at hop #2 (harness write; bounds strlen(0x8154)=50 so the 0x7402 250-cap
-- passes) so the insert is not bailed. Then (c): at hop #13 teleport to strcpy wrapper
-- 0x2B10 with ER0=0x81B8 ER2=0x8154 -> second flood; count distinct before/after.
dofile("emulator/lua-common.lua")
local T = 0

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, DOWN, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x36, 0x00, 0x10, 0x22, 0x62
local PAY_IN = 0x8154

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

local base = {}
local payload = {}
local h73, h7402, h7448, h74fa, h2b10 = 0, 0, 0, 0, 0
local flood2_done = false

local function region_diff(lo, hi, ref, tag)
	local out = {}
	for a = lo, hi do
		local b = (data[a] or 0) & 0xFF
		if b ~= ref[a] then out[#out + 1] = string.format("%04X:%02X>%02X", a, ref[a] & 0xFF, b) end
	end
	if #out == 0 then
		print(tag .. ": NO-CHANGE")
	else
		print(tag .. ": " .. #out .. " changed: " .. table.concat(out, " ", 1, math.min(#out, 30)))
	end
end

local function dump_span(tag)
	local f = io.open("/tmp/more10_run2_" .. tag .. ".bin", "wb")
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
	local wins = {}
	for off = 0, 99, 2 do
		local s = ""
		for i = 0, 99 do s = s .. string.char((data[PAY_IN + off + i] or 0) & 0xFF) end
		wins[s] = true
	end
	local nw = 0; for _ in pairs(wins) do nw = nw + 1 end
	print(string.format("STATS[%s]: distinct-values=%d mismatches-vs-P1=%d distinct-even-100win=%d", tag, nv, mism, nw))
	if mism > 0 then print("STATS[" .. tag .. "] mism: " .. table.concat(mism_list, " ")) end
end

break_at(0x73A2, function()
	h73 = h73 + 1
	print(string.format("PATH-73A2 #%d sp=%04X lr=%04X csr=%X dsr=%02X", h73, cpu.sp, cpu.lr, cpu.csr, cpu.dsr))
	emu:set_paused(false)
end)
break_at(0x7402, function()
	h7402 = h7402 + 1
	if h7402 <= 2 then print(string.format("PATH-7402 #%d sp=%04X r0=%02X", h7402, cpu.sp, cpu.r0 & 0xFF)) end
	emu:set_paused(false)
end)
break_at(0x7448, function()
	h7448 = h7448 + 1
	if h7448 <= 2 then print(string.format("PATH-7448 #%d sp=%04X", h7448, cpu.sp)) end
	emu:set_paused(false)
end)
break_at(0x74FA, function()
	h74fa = h74fa + 1
	if h74fa <= 2 then print(string.format("PATH-74FA(BAIL) #%d r0=%02X", h74fa, cpu.r0 & 0xFF)) end
	emu:set_paused(false)
end)
break_at(0x2B10, function()
	h2b10 = h2b10 + 1
	local er0 = (cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF)
	local er2 = (cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF)
	print(string.format("PATH-2B10 #%d sp=%04X ER0=%04X ER2=%04X", h2b10, cpu.sp, er0, er2))
	emu:set_paused(false)
end)

local done = false
local function finish(tag)
	if done then return end
	done = true
	print(string.format("PROTO: %s hits=%d pc=%04X sp=%04X h73=%d h7402=%d h7448=%d h74fa=%d h2b10=%d",
		tag, scan_hits, cpu.pc, cpu.sp, h73, h7402, h7448, h74fa, h2b10))
	print("PROTO: final-buf " .. bdump(64) .. " len=" .. blen())
	dump_span("final")
	stats("final")
	Keyboard:ReleaseAll()
	emu:set_paused(true)
	phase = "done"
end

break_at(0x4D20, function()
	scan_hits = scan_hits + 1
	local sp = cpu.sp
	if scan_hits == 1 then
		for a = 0x8154, 0x81B7 do base[a] = (data[a] or 0) & 0xFF end
		for i = 1, 100 do payload[i] = base[0x8154 + i - 1] end
		print(string.format("TRIGGER: hop#1 pc=%04X sp=%04X lr=%04X csr=%X dsr=%02X ER14=%02X%02X", cpu.pc, sp, cpu.lr, cpu.csr, cpu.dsr, cpu.r15 & 0xFF, cpu.r14 & 0xFF))
		print("BASE: buf100=" .. bdump(100))
		dump_span("hop1")
	end
	if scan_hits == 2 then
		Keyboard:PressKey(0x00)      -- digit 1 held through the 0x73A2 tile at hop #10
		data[0x8186] = 0x00          -- bound strlen(0x8154)=50 (harness NUL plant)
		base[0x8186] = 0x00          -- ignore the planted NUL in diffs
		print(string.format("HOP#2: key 0x00 held, NUL at 0x8186, strlen=%d, tile@hop10 offset=%d",
			blen(), (48 + 4 * 9) % 100))
	end
	if scan_hits >= 3 and scan_hits <= 12 then
		Keyboard:PressKey(0x00)      -- keep digit 1 held (idempotent re-press)
	end
	if scan_hits >= 11 and scan_hits <= 16 then
		print(string.format("HOP#%d post-tile-73A2:", scan_hits))
		region_diff(0x8154, 0x81B7, base, "  (b-tile) buf-diff")
	end
	if scan_hits == 13 and not flood2_done then
		flood2_done = true
		Keyboard:ReleaseAll()
		dump_span("pre_flood2")
		stats("pre_flood2")
		cpu.r0 = 0xB8; cpu.r1 = 0x81
		cpu.r2 = 0x54; cpu.r3 = 0x81
		cpu.pc = 0x2B10
		cpu.lr = 0x2B1E
		cpu.csr = 0
		cpu.dsr = 0
		print(string.format("FLOOD2: hop#13 -> pc=0x2B10 ER0=81B8 ER2=8154 sp=%04X", sp))
	end
	if scan_hits == 20 then
		dump_span("post_flood2")
		stats("post_flood2")
		print("HOP#20 post-flood2 buf: " .. bdump(64))
	end
	if scan_hits == 22 then finish("RUN2-DONE") end
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
				if lb == "PROBE1" then
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
			local function W(off, v) data[PAY_IN + off] = v & 0xFF; data[PAY_IN + off + 1] = (v >> 8) & 0xFF end
			W(84, 0x73A2)   -- tile for hop #10: bytes A2 73 0E 4D -> PC=0x73A2, CSR word 0x4D0E (bank0)
			-- W(86) stays 0x4D0E flood (CSR word of the tile + next tile)
			print("INPUT: payload flood + W(84)=0x73A2, len=" .. blen())
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
			if scan_hits >= 26 then finish("HITS26") elseif final_t > 6000000 then finish("TIMEOUT") end
		end
	end
end)
