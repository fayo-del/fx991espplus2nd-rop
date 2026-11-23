-- FINAL RUN: warm-up keys, SETUP open (verified by render), digit-2 select,
-- Sigma bare check, then full formula + overflow + payload + chain pipeline.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, DOWN, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x36, 0x00, 0x10, 0x22, 0x62
local PAY_IN = 0x8154

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t, snap = "type", 0, {}
local scan_hits, store_caps, dump1 = 0, 0, 0
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

-- warm-up (keys here may be eaten by boot; harmless)
push(SHIFT, "w1", nil, 12000, 12000); push(AC, "w2", nil, 12000, 24000)
-- SETUP open + digit-2 (page-1 select LineIO)
chord(SHIFT, MODE, "setup1")
render("setup1")
push(K2, "setup1-digit2", nil, 30000, 40000)
render("setup1 after 2")
-- verify: Sigma must be bare (exactly 2 bytes 69 B8)
chord(SHIFT, 0x56, "sigma-verify")
-- if boxed: one more open+2 pass
chord(SHIFT, MODE, "setup2")
push(K2, "setup2-digit2", nil, 30000, 40000)
render("setup2 after 2")
chord(SHIFT, 0x56, "sigma-verify2")
push(AC, "AC-clear", nil, 16000, 24000)
-- ====== formula: X = Σ(X,1,1×10^9 ======
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
-- ====== calc = ac <- ======
push(CALC, "CALC", nil, 16000, 24000)
push(EXE, "EXE", nil, 24000, 30000)
push(AC, "AC", nil, 16000, 24000)
push(LEFT, "LEFT", nil, 16000, 16000)
-- ====== del del del 2 ======
push(DEL, "DEL1", nil, 16000, 12000)
push(DEL, "DEL2", nil, 16000, 12000)
push(DEL, "DEL3", nil, 16000, 12000)
push(K2, "two", { { 0x32 } })
-- ====== calc = <- ======
push(CALC, "CALC2", nil, 16000, 24000)
push(EXE, "EXE2", nil, 24000, 30000)
push(LEFT, "LEFT2", nil, 16000, 20000)
-- ====== probe: 1 must not insert ======
push(K1, "PROBE1", nil, 16000, 16000)

function finish(tag)
	print(string.format("PROTO: %s hits=%d pc=%04X sp=%04X", tag, scan_hits, cpu.pc, cpu.sp))
	print("PROTO: final-buf " .. bdump(48) .. " len=" .. blen())
	local function wd(a, n) local s = "" for i = 0, n - 1 do s = s .. string.format("%02X", (data[a + i] or 0) & 0xFF) end return s end
	print("PROTO: RAM-8110-8130: " .. wd(0x8110, 0x20))
	print("PROTO: RAM-84F0-8520: " .. wd(0x84F0, 0x30))
	print("PROTO: RAM-8500-8520: " .. wd(0x8500, 0x20))
	Keyboard:ReleaseAll()
	emu:set_paused(true)
	phase = "done"
end

-- unique pattern (harness-planted) at 0x8C74
local uniq={0xDE,0xAD,0xBE,0xEF,0x12,0x34,0x56,0x78,0x9A,0xBC,0xDE,0xF0}
for i=1,#uniq do data[0x8C70+i]=uniq[i] end
be35_hits, be35_mine = 0, 0
break_at(0x4D20, function()
	scan_hits = scan_hits + 1
	local w = {}
	for i = -8, 7, 2 do w[#w+1] = string.format("%04X", data[cpu.sp + i] | (data[cpu.sp + i + 1] << 8)) end
	print(string.format("CHAIN: KEYSCAN #%d ER0=%04X pc=%04X sp=%04X lr=%04X words[sp-8..sp+7]=%s", scan_hits,
		(cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF), cpu.pc, cpu.sp, cpu.lr, table.concat(w, " ")))
	emu:set_paused(false)
end)
-- MB05: log first POP-PC sp values post-trigger to learn entry phase
local poppc_n, parked_n = 0, 0
break_at(0x2B1E, function()
	if final_t > 40001 then
		poppc_n = poppc_n + 1
		if poppc_n <= 8 then
			print(string.format("POPPC#%d sp=%04X (mod100=%d) tile=%02X%02X%02X%02X pc=%04X", poppc_n, cpu.sp, (cpu.sp - 0x8154) % 100,
				data[cpu.sp] or 0, data[cpu.sp+1] or 0, data[cpu.sp+2] or 0, data[cpu.sp+3] or 0, cpu.pc))
		end
	end
	emu:set_paused(false)
end)
break_at(0x4B96, function()
	if final_t > 40001 then
		parked_n = parked_n + 1
		if parked_n <= 2 then print(string.format("PARK-REACHED #%d sp=%04X pc=%04X", parked_n, cpu.sp, cpu.pc)) end
	end
	emu:set_paused(false)
end)
local st_n = 0
break_at(0x1470E, function()  -- after ST R0,[ER14] at 0x10470C
	st_n = st_n + 1
	if st_n <= 12 then
		local e14 = (cpu.r15 & 0xFF) * 0x100 + (cpu.r14 & 0xFF)
		print(string.format("MB05-ST #%d: ER14=%04X r0=%02X -> mem[%04X]=%02X sp=%04X", st_n, e14, cpu.r0 & 0xFF, e14, (data[e14] or 0) & 0xFF, cpu.sp))
	end
	emu:set_paused(false)
end)
local add_n = 0
break_at(0x3B42, function()  -- after ADD R0,#0xF0
	add_n = add_n + 1
	if add_n <= 12 then print(string.format("MB05-ADD #%d: r0=%02X sp=%04X", add_n, cpu.r0 & 0xFF, cpu.sp)) end
	emu:set_paused(false)
end)

local h38 = 0
break_at(0x3538, function()
	h38 = h38 + 1
	if h38 <= 4 or (cpu.sp >= 0x8D50 and cpu.sp <= 0x8DC0) then
		print(string.format("HIT-3538 #%d: sp=%04X ER2=%04X lr=%04X", h38, cpu.sp,
			(cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF), cpu.lr))
	end
	emu:set_paused(false)
end)
be35_hits, be35_mine = be35_hits or 0, be35_mine or 0
break_at(0x35BE, function()
	be35_hits = be35_hits + 1
	if phase == "final" and final_t > 60000 and be35_hits > 0 and dump1 == 0 then
		dump1 = 1
		local a = ""
		for i = 0, 0x1F do a = a .. string.format("%02X", (data[0x87D0 + i] or 0) & 0xFF) end
		local b = ""
		for i = 0, 0x1B do b = b .. string.format("%02X", (data[0xF800 + i] or 0) & 0xFF) end
		print("IMMDUMP-87D0 " .. a)
		print("IMMDUMP-F800 " .. b)
	end
	local er2 = (cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF)
	if (er2 & 0xFFF8) == 0xF800 then
		be35_mine = be35_mine + 1
		local d={}
		for i=0,11 do d[#d+1]=string.format("%02X", data[0xF810+i]) end
		print(string.format("HIT-35BE(mine) #%d: sp=%04X ER2=%04X EA=%04X r0=%02X lr=%04X pattern-src=%02X%02X%02X%02X", be35_mine, cpu.sp, er2, cpu.ea, cpu.r0 & 0xFF, cpu.lr, data[0x8154] or 0, data[0x8155] or 0, data[0x8156] or 0, data[0x8157] or 0))
	end
	emu:set_paused(false)
end)
-- filtered store-capture: fire at 0x35CC (post-ST) only when ER2 in [0xF800..0xF8FF]
break_at(0x35CC, function()
	local er2 = (cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF)
	if er2 >= 0xF800 and er2 <= 0xF8FF then
		local d = {}
		for i = 0, 15 do d[#d+1] = string.format("%02X", data[0xF800 + i]) end
		local d1 = {}
		for i = 0, 11 do d1[#d1+1] = string.format("%02X", data[0xF810 + i]) end
		if store_caps < 4 then
			print(string.format("STORE-CAPTURE: sp=%04X ER2=%04X r0=%02X EA=%04X row0=%s row1=%s", cpu.sp, er2, cpu.r0 & 0xFF, cpu.ea, table.concat(d), table.concat(d1)))
			store_caps = store_caps + 1
		end
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
				elseif lb == "setup1" or lb == "setup1 after 2" or lb == "setup2 after 2" or lb == "formula typed" then
					render_screen(lb)
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
			for a = 0x8100, 0x8E7F do snap[a] = (data[a] or 0) & 0xFF end
			Keyboard:PressKey(0x37)   -- Right held: KEYSCAN sets r0=1 (single memcpy iteration)
			Keyboard:PressKey(AC)
		elseif final_t == 16001 then
			Keyboard:ReleaseAll()
		elseif final_t == 20001 then
			Keyboard:PressKey(LEFT)
		elseif final_t == 36001 then
			Keyboard:ReleaseAll()
			for i = 0, 11 do data[0x87D0 + i] = 0xA0 + ((i % 5) + 1) * 16 + (i % 5) + 1 end
			pat0 = 1
			-- MB05 typed chain-write payload (100 zero-free bytes, parse-aligned at off 44;
			-- measured entry sp0=0x8D9C => phase (0x8D9C-0x8154)%100 = 44)
			local P = {}
			local function put(off, ...) local bs = {...} for i = 1, #bs do P[(off + i - 1) % 100] = bs[i] end end
			-- setup at 44: POP ER14=0x8511 ; POP R0=0x55 ; ADD R0,#0xF0
			put(44, 0x66,0x30,0x0E,0x4D, 0x11,0x85, 0x82,0x54,0x01,0x01, 0x55,0x4D, 0x40,0x3B,0x0E,0x4D)
			-- 6x loop body (ADD / ST R0,[ER14] / ADD ER14,#1) from 60
			for k = 0, 5 do
				put(60 + 12*k, 0x40,0x3B,0x0E,0x4D, 0x0C,0x47,0x01,0x01, 0x90,0x46,0x01,0x01)
			end
			-- park tiles fill the rest (32..43)
			put(32, 0xF2,0x4E,0x0E,0x4D, 0xF2,0x4E,0x0E,0x4D, 0xF2,0x4E,0x0E,0x4D)
			for off = 0, 99 do data[PAY_IN + off] = P[off] or 0x4D end
			print("INPUT: MB05 payload planted (phase44)")




			-- 70..83 = memcpy tail sacrifice; 84..99 = pad
			print("INPUT: payload 0E4D-flood in, len=" .. blen())
		elseif final_t == 40001 then
			Keyboard:PressKey(0x60)
		elseif final_t == 60001 then
			Keyboard:ReleaseAll()
			emu:SetClockSpeed(16)
			print("WATCH: 16x")
		elseif final_t > 60001 then
			if (final_t - 60001) % 100000 == 0 then
				local tiled = 0
				for a = 0x8240, 0x8DF8 do
					if (data[a] or 0) == 0x4D and (data[a - 1] or 0) == 0x0E then tiled = tiled + 1 end
				end
				local rs = {}
				for rr = 0, 5 do
					local s2 = ""
					for i = 0, 11 do s2 = s2 .. string.format("%02X", data[0xF800 + rr * 16 + i]) end
					rs[rr + 1] = s2
				end
				print(string.format("WATCH: t=%d pc=%04X sp=%04X tiles=%d hits=%d rows=%s|%s|%s|%s|%s|%s", final_t, cpu.pc, cpu.sp, tiled, scan_hits, rs[1], rs[2], rs[3], rs[4], rs[5], rs[6]))
			end
			if parked_n >= 1 and st_n >= 6 then finish("PARKED-AFTER-WRITES") elseif scan_hits >= 50 then finish("TRIGGERED-CHAIN-RUNS") elseif parked_n >= 1 and (final_t - 60001) > 200000 then finish("PARKED") elseif final_t > 6000000 then finish("NO-TRIGGER") end
		end
	end
end)
