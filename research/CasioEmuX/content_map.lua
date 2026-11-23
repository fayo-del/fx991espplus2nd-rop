-- CONTENT MAP: run the rop_e2e typed recipe once; at the first chain hop dump
-- RAM 0x8100-0x8DFF to files, then force memcpy12 (0x35BE) src EA to each region
-- base via register teleport + stack word, and print the 12-byte readback.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, DOWN, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x36, 0x00, 0x10, 0x22, 0x62
local PAY_IN = 0x8154
local OUT = "/home/yoxu/Projects/fx991espplus2nd/research/CasioEmuX/"

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t = "type", 0
local scan_hits, be35_hits = 0, 0
local lineio = false

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
local function render_screen(tag)
	print("SCREEN: ---- " .. tag .. " ----")
end
local function chord(mod, code, label, expect)
	push(mod, label .. "/mod", nil, 16000, 16000)
	push(code, label, expect, 16000, 16000)
end

-- warm-up
push(SHIFT, "w1", nil, 12000, 12000); push(AC, "w2", nil, 12000, 24000)
-- SETUP open + digit-2 (LineIO)
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
-- formula: X = Σ(X,1,1×10^9
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
-- calc = ac <-
push(CALC, "CALC", nil, 16000, 24000)
push(EXE, "EXE", nil, 24000, 30000)
push(AC, "AC", nil, 16000, 24000)
push(LEFT, "LEFT", nil, 16000, 16000)
-- del del del 2
push(DEL, "DEL1", nil, 16000, 12000)
push(DEL, "DEL2", nil, 16000, 12000)
push(DEL, "DEL3", nil, 16000, 12000)
push(K2, "two", { { 0x32 } })
-- calc = <-
push(CALC, "CALC2", nil, 16000, 24000)
push(EXE, "EXE2", nil, 24000, 30000)
push(LEFT, "LEFT2", nil, 16000, 20000)
push(K1, "PROBE1", nil, 16000, 16000)

-- region bases to force as memcpy12 src EA (one per chain hop)
local TESTS = {
	0x8100, 0x8154, 0x8155, 0x8184, 0x81B8, 0x85AA, 0x829E, 0x82CE,
	0x8230, 0x8240, 0x8241, 0x8242, 0x8270, 0x87D0, 0x8C60, 0x8C74,
	0x8D74, 0x8DF0,
}
local SCR = 0x8C80   -- scratch "stack" for the forced memcpy12 POP EA
local DST = 0x8C00   -- RAM dst for the forced memcpy12 readback

local function dump_ram(n)
	local parts = {}
	for a = 0x8100, 0x8DFF do parts[#parts + 1] = string.char((data[a] or 0) & 0xFF) end
	local f = io.open(OUT .. "content_map_dump" .. n .. ".bin", "wb")
	f:write(table.concat(parts))
	f:close()
end
local function dump_payload()
	local f = io.open(OUT .. "content_map_payload.bin", "wb")
	for i = 0, 99 do f:write(string.char((data[PAY_IN + i] or 0) & 0xFF)) end
	f:close()
end
local function hex12(a)
	local s = ""
	for i = 0, 11 do s = s .. string.format("%02X", (data[a + i] or 0) & 0xFF) end
	return s
end
local function tiles()
	local t = 0
	for a = 0x8240, 0x8DF8 do
		if (data[a] or 0) == 0x4D and (data[a - 1] or 0) == 0x0E then t = t + 1 end
	end
	return t
end

-- harness marker inside the pre-existing stack area (provenance tag)
local uniq = { 0xDE, 0xAD, 0xBE, 0xEF, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0 }
for i = 1, #uniq do data[0x8C70 + i] = uniq[i] end

local parked = false
break_at(0x4D20, function()
	scan_hits = scan_hits + 1
	local sp = cpu.sp
	if scan_hits == 1 then
		print(string.format("TRIGGER: first KEYSCAN hop #%d pc=%04X sp=%04X dsr=%02X tiles=%d",
			scan_hits, cpu.pc, sp, cpu.dsr, tiles()))
		dump_ram(1)
		dump_payload()
		print("DUMP: dump1 written (0x8100-0x8DFF), payload=" .. bdump(100))
	end
	if scan_hits == 8 then
		dump_ram(2)
		print(string.format("DUMP: dump2 written, tiles=%d sp=%04X", tiles(), sp))
	end
	if scan_hits >= 2 and scan_hits <= #TESTS + 1 then
		-- read back the previous forced memcpy12 result (DST..DST+11)
		if scan_hits >= 3 then
			local b = TESTS[scan_hits - 2]
			print(string.format("SRC12 base=%04X memread=%s memcpy12=%s match=%s",
				b, hex12(b), hex12(DST), tostring(hex12(b) == hex12(DST))))
		end
		-- teleport: run memcpy12 with forced EA = next test base
		local t = TESTS[scan_hits - 1]
		data[SCR] = t & 0xFF
		data[SCR + 1] = (t >> 8) & 0xFF
		for i = 2, 25 do data[SCR + i] = (i % 2 == 0) and 0x0E or 0x4D end
		cpu.sp = SCR
		cpu.r0 = 1                    -- one 12-byte iteration
		cpu.r2 = DST & 0xFF
		cpu.r3 = (DST >> 8) & 0xFF    -- ER2 = dst
		cpu.lr = 0x4D0E               -- RT -> KEYSCAN -> 0x4D20 -> next hop
		cpu.csr = 0
		cpu.dsr = 0
		cpu.pc = 0x35BE               -- memcpy12
	elseif scan_hits == #TESTS + 2 then
		local b = TESTS[#TESTS]
		print(string.format("SRC12 base=%04X memread=%s memcpy12=%s match=%s",
			b, hex12(b), hex12(DST), tostring(hex12(b) == hex12(DST))))
		print(string.format("DONE: tests=%d hits=%d tiles=%d", #TESTS, scan_hits, tiles()))
		dump_ram(3)
		print("DUMP: dump3 written after tests")
		parked = true
		cpu.csr = 0
		cpu.pc = 0x4EF2               -- terminal park
		cpu.lr = 0x4EF2
	elseif scan_hits > #TESTS + 2 then
		parked = true
		cpu.csr = 0
		cpu.pc = 0x4EF2
		cpu.lr = 0x4EF2
	end
	emu:set_paused(false)
end)
break_at(0x35BE, function()
	be35_hits = be35_hits + 1
	if be35_hits <= 6 then
		print(string.format("MBE-HIT #%d: sp=%04X ER2=%04X r0=%02X lr=%04X word[sp]=%04X",
			be35_hits, cpu.sp,
			(cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF), cpu.r0 & 0xFF, cpu.lr,
			(data[cpu.sp] or 0) | ((data[cpu.sp + 1] or 0) << 8)))
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
					if bare and not boxed then lineio = true end
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
			dump_ram(0)   -- pre-trigger reference snapshot
			print("DUMP: dump0 (pre-trigger) written")
			Keyboard:PressKey(0x37)   -- Right held: KEYSCAN sets r0=1
			Keyboard:PressKey(AC)
		elseif final_t == 16001 then
			Keyboard:ReleaseAll()
		elseif final_t == 20001 then
			Keyboard:PressKey(LEFT)
		elseif final_t == 36001 then
			Keyboard:ReleaseAll()
			for i = 0, 11 do data[0x87D0 + i] = 0xA0 + ((i % 5) + 1) * 16 + (i % 5) + 1 end
			for e = 0, 49 do data[PAY_IN + e * 2] = 0x0E; data[PAY_IN + e * 2 + 1] = 0x4D end
			local function W(off, v) data[PAY_IN + off] = v & 0xFF; data[PAY_IN + off + 1] = (v >> 8) & 0xFF end
			W(48, 0x3538) W(50, 0x3538) W(52, 0xF801) W(54, 0x35BE) W(56, 0x8154)
			print("INPUT: payload 0E4D-flood in, len=" .. blen())
		elseif final_t == 40001 then
			Keyboard:PressKey(0x60)
		elseif final_t == 60001 then
			Keyboard:ReleaseAll()
			emu:SetClockSpeed(16)
			print("WATCH: 16x")
		elseif final_t > 60001 then
			if (final_t - 60001) % 200000 == 0 then
				print(string.format("WATCH: t=%d pc=%04X sp=%04X tiles=%d hits=%d be35=%d",
					final_t, cpu.pc, cpu.sp, tiles(), scan_hits, be35_hits))
			end
			if parked and final_t > 60001 + 200000 then
				print("CONTENT-MAP: parked, done")
				emu:set_paused(true)
				phase = "done"
			elseif final_t > 6000000 then
				print(string.format("NO-TRIGGER hits=%d pc=%04X sp=%04X", scan_hits, cpu.pc, cpu.sp))
				emu:set_paused(true)
				phase = "done"
			end
		end
	end
end)
