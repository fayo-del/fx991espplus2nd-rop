-- more08_sfr.lua — MB08SFRStore: SFR storage (0xF000-0xFFFF) pre/post trigger,
-- chain read-back of SFRs, and DSR data-space aliasing. CY-845 / fx-991ES PLUS 2nd.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, DOWN, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x36, 0x00, 0x10, 0x22, 0x62
local PAY_IN = 0x8154
local OUT = "/home/yoxu/Projects/fx991espplus2nd/research/CasioEmuX/"
local SCR = 0x8C80   -- scratch stack for teleports
local DST = 0x8C00   -- RAM dst for memcpy12 readback

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t = "type", 0
local scan_hits = 0
local parked = false
local dsr_probe = 0          -- 0=off 1=ER14 0x8154 2=ER14 0x8D00
local sfr_pre = {}
local dspr_pre = {}

local function blen()
	for i = 0, 99 do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 100
end
local function bdump(n)
	local s = ""
	for i = 0, (n or 32) - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end
	return s
end
local function hex(a, n)
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02X", (data[a + i] or 0) & 0xFF) end
	return s
end
local function push(code, label, expect, hold, gap)
	keys[#keys + 1] = { code = code, label = label, expect = expect, hold = hold or 16000, gap = gap or 20000 }
end
local function render(tag) keys[#keys + 1] = { render = tag } end
local function render_screen(tag)
	print("SCREEN: ---- " .. tag .. " ----")
	for r = 0, 24 do
		local line = ""
		for b = 0, 11 do
			local v = data[0xF800 + r * 16 + b] or 0
			for bit = 7, 0, -1 do line = line .. (((v >> bit) & 1) == 1 and "#" or ".") end
		end
		print("SCREEN: " .. line)
	end
end
local function chord(mod, code, label, expect)
	push(mod, label .. "/mod", nil, 16000, 16000)
	push(code, label, expect, 16000, 16000)
end
local function dump_bin(name, base, len)
	local f = io.open(OUT .. name, "wb")
	for a = base, base + len - 1 do f:write(string.char((data[a] or 0) & 0xFF)) end
	f:close()
end
local function sfr_list(a0, a1)
	local parts = {}
	for a = a0, a1 - 1 do
		local v = (data[a] or 0) & 0xFF
		if v ~= 0 then parts[#parts + 1] = string.format("%04X=%02X", a, v) end
	end
	return table.concat(parts, " ")
end
local function dspr_stats(tag)
	local seen, nz = {}, 0
	for a = 0xF800, 0xF9FB do
		local v = (data[a] or 0) & 0xFF
		if v ~= 0 then nz = nz + 1; seen[v] = (seen[v] or 0) + 1 end
	end
	local nd = 0
	for _ in pairs(seen) do nd = nd + 1 end
	print(string.format("DSPR-%s: nonzero=%d distinct=%d", tag, nz, nd))
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
local romf = io.open("models/fx991esplus2/rom.bin", "rb")
local ROM = romf:read(0x20000)
romf:close()
local function romhex(off, n)
	local s = ""
	for i = 1, n do s = s .. string.format("%02X", ROM:byte(off + i)) end
	return s
end

-- SFR sources forced as memcpy12 src EA (one per chain hop), read back at DST
local TESTS = {
	0xF800, 0xF840, 0xF8C0, 0xF040, 0xF000, 0xF030, 0xF032, 0xF220, 0xF480, 0xF4A0, 0x9800, 0x8154,
}

-- warm-up
push(SHIFT, "w1", nil, 12000, 12000); push(AC, "w2", nil, 12000, 24000)
-- SETUP open + digit-2 (LineIO)
chord(SHIFT, MODE, "setup1")
push(K2, "setup1-digit2", nil, 30000, 40000)
chord(SHIFT, 0x56, "sigma-verify")
chord(SHIFT, MODE, "setup2")
push(K2, "setup2-digit2", nil, 30000, 40000)
chord(SHIFT, 0x56, "sigma-verify2")
push(AC, "AC-clear", nil, 16000, 24000)
-- BCD step: type 129129129 then EXE so BCD param SFRs (0xF480+) hold attacker digits
push(K1, "b1", { { 0x31 } }); push(K2, "b2", { { 0x32 } }); push(K9, "b9", { { 0x39 } })
push(K1, "b1b", { { 0x31 } }); push(K2, "b2b", { { 0x32 } }); push(K9, "b9b", { { 0x39 } })
push(K1, "b1c", { { 0x31 } }); push(K2, "b2c", { { 0x32 } }); push(K9, "b9c", { { 0x39 } })
push(EXE, "bcd-exe", nil, 24000, 30000)
push(AC, "AC-after-bcd", nil, 16000, 24000)
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

-- harness marker inside the pre-existing stack area
local uniq = { 0xDE, 0xAD, 0xBE, 0xEF, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0 }
for i = 1, #uniq do data[0x8C70 + i] = uniq[i] end

break_at(0x4D20, function()
	scan_hits = scan_hits + 1
	local sp = cpu.sp
	if scan_hits == 1 then
		print(string.format("TRIGGER: first KEYSCAN hop pc=%04X sp=%04X dsr=%02X tiles=%d",
			cpu.pc, sp, cpu.dsr, tiles()))
		-- SFR post-trigger dump + diff vs pre
		local changed = {}
		for a = 0xF000, 0xFFFF do
			local v = (data[a] or 0) & 0xFF
			if v ~= sfr_pre[a] then changed[#changed + 1] = string.format("%04X:%02X->%02X", a, sfr_pre[a], v) end
		end
		dump_bin("more08_sfr_post.bin", 0xF000, 0x1000)
		dump_bin("more08_dspr_post.bin", 0xF800, 0x200)
		print("SFR-DIFF post-vs-pre (0xF000-0xFFFF): [" .. table.concat(changed, " ") .. "]")
		local dch = 0
		for a = 0xF800, 0xF9FB do
			if ((data[a] or 0) & 0xFF) ~= dspr_pre[a] then dch = dch + 1 end
		end
		print(string.format("DSPR-DIFF post-vs-pre: %d of 384 bytes changed; DSPR-post[0..15]=%s", dch, hex(0xF800, 16)))
		print("SFR-POST nonzero 0xF000-0xF2FF: " .. sfr_list(0xF000, 0xF300))
		print("SFR-POST nonzero 0xF400-0xF4FF: " .. sfr_list(0xF400, 0xF500))
		dspr_stats("post")
		print("KID at hop1 = " .. string.format("%02X", data[0xF040] or 0))
		-- MMU-level DSR alias probes (same ReadData((dsr<<16)|EA) the CPU uses)
		print(string.format("ALIAS: data[8154]=%s data[18154]=%s (rom file 18154=%s) data[88154]=%s (rom file 8154=%s) data[9800]=%s data[8D00]=%s",
			hex(0x8154, 4), hex(0x18154, 4), romhex(0x18154, 4), hex(0x88154, 4), romhex(0x8154, 4), hex(0x9800, 4), hex(0x8D00, 4)))
		-- write-side MMU proof: write via segment-1 offset must not touch RAM
		local ram_before = hex(0x8154, 4)
		data[0x18154] = 0xAA
		print(string.format("DSRWRITE: data[18154]=0xAA -> data[8154] %s (was %s, unchanged=%s), data[18154] readback=%s",
			hex(0x8154, 4), ram_before, tostring(hex(0x8154, 4) == ram_before), hex(0x18154, 4)))
	elseif scan_hits >= 2 and scan_hits <= #TESTS + 1 then
		if scan_hits >= 3 then
			local b = TESTS[scan_hits - 2]
			print(string.format("SRC12 base=%04X memread=%s memcpy12=%s match=%s",
				b, hex12(b), hex12(DST), tostring(hex12(b) == hex12(DST))))
		end
		local t = TESTS[scan_hits - 1]
		data[SCR] = t & 0xFF
		data[SCR + 1] = (t >> 8) & 0xFF
		for i = 2, 25 do data[SCR + i] = (i % 2 == 0) and 0x0E or 0x4D end
		cpu.sp = SCR
		cpu.r0 = 1
		cpu.r2 = DST & 0xFF
		cpu.r3 = (DST >> 8) & 0xFF
		cpu.lr = 0x4D0E
		cpu.csr = 0
		cpu.dsr = 0
		cpu.pc = 0x35BE
	elseif scan_hits == #TESTS + 2 then
		local b = TESTS[#TESTS]
		print(string.format("SRC12 base=%04X memread=%s memcpy12=%s match=%s",
			b, hex12(b), hex12(DST), tostring(hex12(b) == hex12(DST))))
		-- DSR=1 CPU-level read probe #1: bank1 0x10312: DSR<-001h; L R0,[ER14]; POP XR12; RT
		dsr_probe = 1
		cpu.r14 = 0x54; cpu.r15 = 0x81          -- ER14 = 0x8154
		cpu.sp = SCR
		for i = 0, 15 do data[SCR + i] = 0x0E end
		cpu.lr = 0x4D0E
		cpu.lcsr = 0
		cpu.csr = 1
		cpu.pc = 0x0312
	elseif scan_hits == #TESTS + 3 then
		print(string.format("DSR1-READ #1: ER14=8154 -> r0=%02X ; RAM data[8154]=%02X ; rom file 18154=%s",
			cpu.r0 & 0xFF, data[0x8154] or 0, romhex(0x18154, 1)))
		dsr_probe = 2
		cpu.r14 = 0x00; cpu.r15 = 0x8D          -- ER14 = 0x8D00 (stack area, flooded)
		cpu.sp = SCR
		cpu.lr = 0x4D0E
		cpu.lcsr = 0
		cpu.csr = 1
		cpu.pc = 0x0312
	elseif scan_hits == #TESTS + 4 then
		print(string.format("DSR1-READ #2: ER14=8D00 -> r0=%02X ; RAM data[8D00]=%02X ; rom file 18D00=%s",
			cpu.r0 & 0xFF, data[0x8D00] or 0, romhex(0x18D00, 1)))
		print(string.format("DONE: tests=%d hits=%d tiles=%d", #TESTS, scan_hits, tiles()))
		parked = true
		cpu.csr = 0
		cpu.pc = 0x4EF2
		cpu.lr = 0x4EF2
	elseif scan_hits > #TESTS + 4 then
		parked = true
		cpu.csr = 0
		cpu.pc = 0x4EF2
		cpu.lr = 0x4EF2
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
					print(string.format("SIGMA: %s len=%d bare=%s", lb, n, tostring(bare)))
				elseif lb == "bcd-exe" then
					print("BCD-SFR after typing 129129129 + EXE:")
					print("  F400-F40F: " .. hex(0xF400, 16))
					print("  F480(param1): " .. hex(0xF480, 12) .. "  F4A0(param2): " .. hex(0xF4A0, 12))
					print("  F4C0(temp1):  " .. hex(0xF4C0, 12) .. "  F4E0(temp2):  " .. hex(0xF4E0, 12))
					print("  buf=" .. bdump(24))
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
			-- ===== pre-trigger SFR snapshot =====
			for a = 0xF000, 0xFFFF do sfr_pre[a] = (data[a] or 0) & 0xFF end
			for a = 0xF800, 0xF9FB do dspr_pre[a] = (data[a] or 0) & 0xFF end
			dump_bin("more08_sfr_pre.bin", 0xF000, 0x1000)
			dump_bin("more08_dspr_pre.bin", 0xF800, 0x200)
			print("SFR-PRE nonzero 0xF000-0xF2FF: " .. sfr_list(0xF000, 0xF300))
			print("SFR-PRE nonzero 0xF300-0xF4FF: " .. sfr_list(0xF300, 0xF500))
			print("DSPR-PRE 0xF800-0xF8FF: " .. hex(0xF800, 0x100))
			print("DSPR-PRE 0xF900-0xF9FB: " .. hex(0xF900, 0xFC))
			dspr_stats("pre")
			print("KID idle = " .. string.format("%02X", data[0xF040] or 0))
			print(string.format("ALIAS pre: data[8154]=%s data[18154]=%s rom[18154]=%s data[88154]=%s rom[8154]=%s data[9800]=%s data[8D00]=%s",
				hex(0x8154, 4), hex(0x18154, 4), romhex(0x18154, 4), hex(0x88154, 4), romhex(0x8154, 4), hex(0x9800, 4), hex(0x8D00, 4)))
			Keyboard:PressKey(0x37)   -- Right held: KEYSCAN sets r0=1
			Keyboard:PressKey(AC)
		elseif final_t == 100 then
			print("KID right-held = " .. string.format("%02X", data[0xF040] or 0))
		elseif final_t == 16001 then
			Keyboard:ReleaseAll()
		elseif final_t == 20001 then
			Keyboard:PressKey(LEFT)
		elseif final_t == 36001 then
			Keyboard:ReleaseAll()
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
			if (final_t - 60001) % 400000 == 0 then
				print(string.format("WATCH: t=%d pc=%04X sp=%04X tiles=%d hits=%d DSPR[0..15]=%s",
					final_t, cpu.pc, cpu.sp, tiles(), scan_hits, hex(0xF800, 16)))
			end
			if parked and final_t > 60001 + 400000 then
				print("MORE08: parked, done")
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
