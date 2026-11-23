-- MB10 run3 (c): from the chain, plant a NEW 96-byte block at 0x8154 via memcpy12
-- (0x35BE, dst=ER2=0x8154, src=EA word popped from the walk slot, r0=8 -> 8x12B,
-- dst stride 16), src = ROM 0x23C6 (keycodes table, attacker-chosen EA), then fire
-- the AC-stamp strcpy wrapper 0x2B10 (ER0=0x81B8 dst, ER2=0x8154 src) = second flood.
-- Count distinct bytes vs the P1 period before/after. Typed recipe verbatim; payload pure flood.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
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
local h2b10, h35be = 0, 0
local planted, flooded = false, false

local function region_diff(lo, hi, ref, tag)
	local out = {}
	for a = lo, hi do
		local b = (data[a] or 0) & 0xFF
		if b ~= ref[a] then out[#out + 1] = string.format("%04X:%02X>%02X", a, ref[a] & 0xFF, b) end
	end
	if #out == 0 then
		print(tag .. ": NO-CHANGE")
	else
		print(tag .. ": " .. #out .. " changed: " .. table.concat(out, " ", 1, math.min(#out, 40)))
	end
end

local function dump_span(tag)
	local f = io.open("/tmp/more10_run3_" .. tag .. ".bin", "wb")
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
			if #mism_list < 40 then mism_list[#mism_list + 1] = string.format("%04X:%02X>%02X", a, e, b) end
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
	print(string.format("STATS[%s]: distinct-values=%d mismatches-vs-P1=%d distinct-even-100win=%d buf=%s",
		tag, nv, mism, nw, bdump(48)))
	if mism > 0 then print("STATS[" .. tag .. "] mism: " .. table.concat(mism_list, " ")) end
end

break_at(0x2B10, function()
	h2b10 = h2b10 + 1
	if h2b10 > 20 and h2b10 <= 26 then
		local er0 = (cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF)
		local er2 = (cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF)
		print(string.format("PATH-2B10 #%d sp=%04X ER0=%04X ER2=%04X", h2b10, cpu.sp, er0, er2))
	end
	emu:set_paused(false)
end)
break_at(0x35BE, function()
	h35be = h35be + 1
	if h35be > 20 and h35be <= 24 then
		local er2 = (cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF)
		print(string.format("PATH-35BE #%d sp=%04X ER2=%04X r0=%02X EA=%04X word[sp]=%04X", h35be, cpu.sp, er2, cpu.r0 & 0xFF, cpu.ea, (data[cpu.sp] or 0) | ((data[cpu.sp + 1] or 0) << 8)))
	end
	emu:set_paused(false)
end)

local done = false
local function finish(tag)
	if done then return end
	done = true
	print(string.format("PROTO: %s hits=%d pc=%04X sp=%04X h2b10=%d h35be=%d", tag, scan_hits, cpu.pc, cpu.sp, h2b10, h35be))
	print("PROTO: final-buf " .. bdump(100) .. " len=" .. blen())
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
		print(string.format("TRIGGER: hop#1 pc=%04X sp=%04X lr=%04X csr=%X dsr=%02X", cpu.pc, sp, cpu.lr, cpu.csr, cpu.dsr))
		print("BASE: buf100=" .. bdump(100))
		dump_span("hop1")
	end
	if scan_hits == 2 and not planted then
		planted = true
		-- memcpy12 plant: POP EA takes the word at sp; write EA=0x23C6 (ROM keycodes table) there
		data[sp] = 0xC6
		data[sp + 1] = 0x23
		cpu.r0 = 8          -- 8 iterations x 12 bytes = 96 bytes
		cpu.r2 = 0x54       -- ER2 = 0x8154 (dst)
		cpu.r3 = 0x81
		cpu.lr = 0x2B1E     -- RT -> POP PC -> walk continues at sp+12
		cpu.csr = 0
		cpu.dsr = 0
		cpu.pc = 0x35BE     -- memcpy12
		print(string.format("PLANT: hop#2 -> pc=0x35BE sp=%04X EA=23C6 r0=8 ER2=8154", sp))
	end
	if scan_hits == 3 then
		print("HOP#3 post-plant:")
		region_diff(0x8154, 0x81B7, base, "  (c) buf-diff")
		stats("post_plant")
	end
	if scan_hits == 4 and not flooded then
		flooded = true
		dump_span("pre_flood2")
		stats("pre_flood2")
		cpu.r0 = 0xB8; cpu.r1 = 0x81   -- ER0 = 0x81B8 (dst)
		cpu.r2 = 0x54; cpu.r3 = 0x81   -- ER2 = 0x8154 (src)
		cpu.lr = 0x2B1E
		cpu.csr = 0
		cpu.dsr = 0
		cpu.pc = 0x2B10                 -- strcpy wrapper: second flood
		print(string.format("FLOOD2: hop#4 -> pc=0x2B10 ER0=81B8 ER2=8154 sp=%04X", sp))
	end
	if scan_hits == 5 then
		print("HOP#5 post-flood2:")
		region_diff(0x8154, 0x81B7, base, "  (c) buf-diff")
		stats("post_flood2")
		dump_span("post_flood2")
	end
	if scan_hits == 6 then finish("RUN3-DONE") end
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
			print("INPUT: payload pure-0E4D flood in, len=" .. blen())
		elseif final_t == 40001 then
			Keyboard:PressKey(0x60)
		elseif final_t == 60001 then
			Keyboard:ReleaseAll()
			emu:SetClockSpeed(16)
			print("WATCH: 16x")
		elseif final_t > 60001 then
			if (final_t - 60001) % 200000 == 0 then
				print(string.format("WATCH: t=%d pc=%04X sp=%04X hits=%d h2b10=%d h35be=%d buf=%s",
					final_t, cpu.pc, cpu.sp, scan_hits, h2b10, h35be, bdump(24)))
			end
			if scan_hits >= 8 then finish("HITS8") elseif final_t > 6000000 then finish("TIMEOUT") end
		end
	end
end)
