-- real01_game2d.lua — REAL 2-D playable game from the typed hackstring ROP chain.
-- Base: game_snake.lua (PROVEN 48-pass loop skeleton, typed trigger rop_e2e recipe).
--
-- GAME DESIGN (2-D cell mover; POS = LCD dst low byte, stored at LCD byte 0xF9FC —
-- row 31 byte 12, invisible, never touched by memcpy writes which stay <= 0xF90A):
--   per pass (steady loop, walk from pivot tile@0x8DAA):
--     b=58/62 keyscan 0x4D0E  -> r0=presence, r2=KID (7F=Right/Up, BF=Left/Down, FF=none)
--     b=66    0x4CDC           -> pass event (F80B.4 key pixel) + harness pass counter
--     b=70    head 0x3538      -> POP ER2 <- 0xF9FC (W74); POP ER8 <- junk (W76);
--                                  MOV ER0,ER2; RT   => ER2 = 0xF9FC (POS pointer)
--     b=78    keyscan 0x4D0E   -> r2 = KID (fresh; head clobbered r2)
--     b=82    0x14506 (b1)     -> L R0,[ER2]; POP PC        => r0 = POS = mem[0xF9FC]
--     b=86    0x4AA8 (b0)      -> SUB R0,R2; SUBC R1,R3; RT => r0 = POS - KID = POS'
--                                  deltas: 7F -> +0x81, BF -> +0x41, FF -> +0x01 (mod 256)
--     b=90    0x153B2 (b1)     -> ST R0,[ER2]; MOV R2,#0; RT => mem[0xF9FC] = POS' (state persists)
--     b=94    0x49C2 (b0)      -> POP ER2 <- 0xF80C (W98); POP PC => r3 = 0xF8
--     b=0     0x4292 (b0)      -> MOV R2,R0; POP PC          => r2 = POS' => ER2 = 0xF8|POS' = DST
--     b=4     0x39CA (b0)      -> MOV R0,#1; RT              => memcpy loop count = 1
--     b=8     0x35BE memcpy12  -> POP EA <- 0x8240 (W12); draws 12-byte cell at ER2 = 0xF8|POS'
--                                  src self-slides +12 B/pass (PUSH EA writeback)
--     post    W24/W28/W30/W34/W36 skeleton -> pivot 0x75DE -> SP=0x8DA8 -> next pass
--   CONTROLS: hold Right/Up (KID 7F) -> POS += 0x81 (~8 rows down + 1 col);
--             hold Left/Down (KID BF) -> POS += 0x41 (~4 rows down + 1 col);
--             no key (KID FF) -> POS += 0x01 (drift 8 px right).
--   The chain polls the keyboard itself every pass; the player only holds one arrow.
--   dst row = POS/16, col = POS%16 (12-byte bar wraps the row edge if col > 4).
--
-- Tile grid note: payload byte offset b <-> address with (a-0x8154)%100 = b.
-- Steady-loop tiles: grid-2 (b = 58,62,66,70,78,82,86,90,94,98,2,6,...) until the
-- POP ER2 at b=94 shifts +2 (its operand W98), landing on grid-0 tiles b=0,4,8
-- (memcpy at 0x8DDC). Post-memcpy exit pops end at SP=0x8DEC = W24 loader (skeleton).
--
-- Harness: typed trigger queue identical to game_snake.lua (PressKey from T=1),
-- payload equipped pre-trigger at 0x8154 (emulator stand-in for the hardware
-- autotyper+walk delivery), then AC,LEFT,EXE typed -> strcpy flood -> chain.
-- PLAYER = pass-driven arrow schedule (PressKey only). No data[] writes post-trigger.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, DOWN, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x36, 0x00, 0x10, 0x22, 0x62
local PAY_IN = 0x8154
local POS_ADDR = 0x8BBD   -- state byte in mid-RAM; (0x8BBD-0x8154)%100 = 65 = payload[65] = initial POS

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t, snap = "type", 0, {}
local scan_hits = 0
local lineio = false
PIVN, PIVP = 0, 0
cur_key = "Right@trigger"

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
	for r = 0, 31 do
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
local function lcdrows(r0n, r1n)
	local out = {}
	for rr = r0n, r1n do
		local s = ""
		for i = 0, 11 do s = s .. string.format("%02X", (data[0xF800 + rr * 16 + i] or 0) & 0xFF) end
		out[#out + 1] = s
	end
	return table.concat(out, "|")
end
local function save_frame(name)
	local f = io.open(name, "wb")
	for i = 0, 511 do f:write(string.char((data[0xF800 + i] or 0) & 0xFF)) end
	f:close()
	print("FRAME: saved " .. name)
end

-- warm-up (keys here may be eaten by boot; harmless)
push(SHIFT, "w1", nil, 12000, 12000); push(AC, "w2", nil, 12000, 24000)
-- SETUP open + digit-2 (page-1 select LineIO)
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
push(K1, "PROBE1", nil, 16000, 16000)

function finish(tag)
	print(string.format("PROTO: %s hits=%d pc=%04X sp=%04X ER14=%04X piv=%d cdcw=%d", tag, scan_hits, cpu.pc, cpu.sp,
		(cpu.r15 & 0xFF) * 0x100 + (cpu.r14 & 0xFF), PIVN, CDCW))
	print(string.format("PROTO: final-POS[F9FC]=%02X final-F80B=%02X rows0-17=%s", data[POS_ADDR] or 0, data[0xF80B] or 0, lcdrows(0, 17)))
	Keyboard:ReleaseAll()
	emu:set_paused(true)
	phase = "done"
end

local CSR_SET = {0x0,0x1,0x2,0x3,0x4,0x5,0x6,0x7,0x8,0x9,0xA,0xB,0xC,0xD,0xE,0xF}
local HITS, PRINTED = {}, {}
local function capped(k, cap)
	HITS[k] = (HITS[k] or 0) + 1
	if HITS[k] <= cap and not PRINTED[k] then PRINTED[k] = true; return true end
	return false
end

-- POP PC walk tracer (0x2B1E): first ~140 hops show the per-pass tile walk
local POPN = 0
break_at(0x2B1E, function()
	POPN = POPN + 1
	if POPN <= 140 then
		local w = (data[cpu.sp] or 0) | ((data[cpu.sp + 1] or 0) << 8)
		print(string.format("POPC#%d sp=%04X nextPC=%04X csrword=%04X lr=%04X", POPN, cpu.sp, w,
			(data[cpu.sp + 2] or 0) | ((data[cpu.sp + 3] or 0) << 8), cpu.lr))
	end
	emu:set_paused(false)
end)

-- KEYSCAN RT sampler (0x4D20): per-hop ER0 (presence) + r2 (KID)
break_at(0x4D20, function()
	scan_hits = scan_hits + 1
	if scan_hits <= 12 or scan_hits % 200 == 0 then
		print(string.format("SCAN#%d pc=%04X sp=%04X r0=%02X r2=%02X ER0=%04X", scan_hits, cpu.pc, cpu.sp,
			cpu.r0 & 0xFF, cpu.r2 & 0xFF, (cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF)))
	end
	emu:set_paused(false)
end)

-- memcpy entry (0x35BE): WALK-ONLY (lr==0x2B1E): dst=ER2, r2, r0, word[sp]=EA slot
local MBE, WMBE = 0, 0
local function mk35BE()
	return function()
		MBE = MBE + 1
		if cpu.lr == 0x2B1E then
			WMBE = WMBE + 1
			local er2 = (cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF)
			if WMBE <= 60 then
				print(string.format("WMBE#%d pass=%d sp=%04X ER2(dst)=%04X r2=%02X r0=%02X easlot=%04X POS=%02X key=%s", WMBE, CDCW, cpu.sp, er2,
					cpu.r2 & 0xFF, cpu.r0 & 0xFF,
					(data[cpu.sp] or 0) | ((data[cpu.sp + 1] or 0) << 8), data[POS_ADDR] or 0, cur_key))
			end
		end
		emu:set_paused(false)
	end
end
-- post-POP EA (0x35C0): walk-only popped src -> +12/pass slide + cell rows on the LCD
-- load/store probes (bank-1 gadgets): show ER2 pointer and r0 at each, walk-only, capped
local LDN, STN = 0, 0
break_at((1 << 16) | 0x6E0C, function()
	LDN = LDN + 1
	if LDN <= 24 and cpu.lr == 0x2B1E then
		print(string.format("LOAD#%d sp=%04X ER0=%04X (mem=%02X) r2=%02X", LDN, cpu.sp,
			(cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF),
			data[((cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF))] or 0, cpu.r2 & 0xFF))
	end
	emu:set_paused(false)
end)
break_at((1 << 16) | 0x470C, function()
	STN = STN + 1
	if STN <= 24 and cpu.lr == 0x2B1E then
		print(string.format("STORE#%d sp=%04X ER14=%04X r0=%02X", STN, cpu.sp,
			(cpu.r15 & 0xFF) * 0x100 + (cpu.r14 & 0xFF), cpu.r0 & 0xFF))
	end
	emu:set_paused(false)
end)

local function mk35C0()
	return function()
		if cpu.lr == 0x2B1E and WMBE <= 60 then
			print(string.format("WMBE#%d EA=%04X src12=%s lcd-rows=%s", WMBE, cpu.ea,
				string.format("%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
					data[cpu.ea] or 0, data[cpu.ea+1] or 0, data[cpu.ea+2] or 0, data[cpu.ea+3] or 0,
					data[cpu.ea+4] or 0, data[cpu.ea+5] or 0, data[cpu.ea+6] or 0, data[cpu.ea+7] or 0,
					data[cpu.ea+8] or 0, data[cpu.ea+9] or 0, data[cpu.ea+10] or 0, data[cpu.ea+11] or 0),
				lcdrows(0, 3)))
		end
		emu:set_paused(false)
	end
end
for _, csr in ipairs(CSR_SET) do
	break_at((csr << 16) | 0x35BE, mk35BE())
	break_at((csr << 16) | 0x35C0, mk35C0())
end

-- pivot/loader tracker
local function mkpiv(tag)
	return function()
		if tag == "PIVOT" then PIVN = PIVN + 1 else PIVP = PIVP + 1 end
		if PIVN + PIVP <= 6 then print(string.format("PIV %s pc=%04X sp=%04X", tag, cpu.pc, cpu.sp)) end
		emu:set_paused(false)
	end
end
for csr = 0, 15 do
	break_at((csr << 16) | 0x3066, mkpiv("LOAD"))
	break_at((csr << 16) | 0x75DE, mkpiv("PIVOT"))
end

-- per-pass key branch (0x4CDC family) = once-per-pass event -> PASS log + key schedule
CDCN, CDCW = 0, 0
local cdc_after = nil
-- player schedule: rotate Right(7F) / Left(BF) / none(FF) every SCHED_EVERY passes
local SCHED = {}
for i = 1, 20 do
	local pat = { { 0x37, "Right" }, { 0x26, "Left" }, { nil, "none" } }
	SCHED[#SCHED + 1] = pat[((i - 1) % 3) + 1]
end
local si = 0
local SCHED_EVERY = 3
local FRAME_AT = {}
for p = 3, 48, 3 do FRAME_AT[p] = true end
local function sched_next(tag)
	if si >= #SCHED then return end
	si = si + 1
	Keyboard:ReleaseAll()
	local e = SCHED[si]
	if e[1] then Keyboard:PressKey(e[1]) end
	cur_key = e[2]
	print(string.format("KEYSCHED pass=%d sched=%d key=%s (%s)", CDCW, si, e[2], tag))
end
local function mkcdc(addr, tag)
	return function()
		local walk = (cpu.lr == 0x2B1E)
		if not walk then emu:set_paused(false); return end
		local sp, r0 = cpu.sp, cpu.r0 & 0xFF
		CDCW = CDCW + 1
		if CDCW % SCHED_EVERY == 0 then sched_next(tag) end
		cdc_after = { tn = T + 1, ft = final_t, sp = sp, tag = tag, pre = (data[0xF80B] or 0) & 0xFF }
		if FRAME_AT[CDCW] then save_frame(string.format("real01_frame%d.raw", CDCW)) end
		if CDCW <= 48 then
			print(string.format("PASS#%d %s-WALK ft=%d sp=%04X r0=%02X r2=%02X ER0=%04X POS=%02X preF80B=%02X key=%s lcd0-3=%s",
				CDCW, tag, final_t, sp, r0, cpu.r2 & 0xFF, (cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF),
				data[POS_ADDR] or 0, data[0xF80B] or 0, cur_key, lcdrows(0, 3)))
		end
		emu:set_paused(false)
	end
end
for _, csr in ipairs(CSR_SET) do
	break_at((csr << 16) | 0x4CDC, mkcdc(0x4CDC, "CDC"))
	break_at((csr << 16) | 0x4CD6, mkcdc(0x4CD6, "RB"))
	break_at((csr << 16) | 0x4CE0, mkcdc(0x4CE0, "SB"))
end

local len_before_probe = nil

addposttick(function()
	T = T + 1
	if cdc_after then
		local f = (data[0xF80B] or 0) & 0xFF
		if CDCW <= 48 then
			print(string.format("CDC-AFTER pass#%d %s ft=%d postF80B=%02X bit4=%d pre=%02X", CDCW, cdc_after.tag, cdc_after.ft, f, (f >> 4) & 1, cdc_after.pre))
		end
		cdc_after = nil
	end

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
			Keyboard:PressKey(0x37)   -- Right held at trigger
			Keyboard:PressKey(AC)
		elseif final_t == 16001 then
			Keyboard:ReleaseAll()
		elseif final_t == 20001 then
			Keyboard:PressKey(LEFT)
		elseif final_t == 36001 then
			Keyboard:ReleaseAll()
			-- ===== payload: 0x4D0E flood + proven loop skeleton + 2-D game compute chain =====
			for e = 0, 49 do data[PAY_IN + e * 2] = 0x0E; data[PAY_IN + e * 2 + 1] = 0x4D end
			local function W(off, v) data[PAY_IN + off] = v & 0xFF; data[PAY_IN + off + 1] = (v >> 8) & 0xFF end
			-- proven loop skeleton (byte-identical to game_snake.lua)
			W(24, 0x3066)             -- POP ER14; POP PC re-loader (post-memcpy)
			W(28, 0x8DAC)             -- its ER14 value
			W(30, 0x3066)             -- 2nd loader
			W(32, 0x8DAC)             -- its ER14 value
			W(34, 0x8DA8)             -- ER14 = 0x8DA8 (pivot base)
			W(36, 0x75DE)             -- pivot MOV SP,ER14; POP ER14; RT
			W(38, 0x75DE)             -- backup pivot
			W(40, 0x4EF2)             -- park insurance
			W(42, 0x75DE)             -- backup pivot
			W(44, 0x3066)             -- entry first pc-slot (word[0x8D9C], phase 44)
			W(48, 0x8DAC)             -- its ER14 value
			W(56, 0x8DA8)             -- pivot self-refresh word[0x8DA8]=0x8DA8
			W(60, 0xF28E)             -- bytes "8E F2" = POP PC at 0x8DAC (replay base)
			W(66, 0x4CDC)             -- per-pass key branch (r0 from the W62 keyscan hop)
			-- ===== 2-D game compute chain (steady-loop walk from tile@0x8DAA/0x8DAE) =====
			W(64, 0x100E)             -- CSR word of tile (W62,W64) keeps bank0; payload[65] = initial POS = 0x10 (flood maps 0x8BBD->payload[65])
			W(70, 0x3722)             -- POP ER0 <- W74; POP PC  => ER0 = 0x8BBD (POS ptr; r2=KID survives)
			W(74, 0x8BBD)             --   op
			W(76, 0x6E0C); W(78, 0x0101)  -- bank1 0x16E0C: L R0,[ER0]; POP PC -> r0 = POS
			W(80, 0x4AA8)             -- bank0: SUB R0,R2; SUBC R1,R3; RT -> r0 = POS - KID = POS'
			W(84, 0x3066)             -- POP ER14 <- W88; POP PC  => ER14 = 0x8BBD (store ptr)
			W(88, 0x8BBD)             --   op
			W(90, 0x470C); W(92, 0x0101)  -- bank1 0x10470C: ST R0,[ER14]; ...; RT -> mem[0x8BBD] = POS'
			W(94, 0x49C2)             -- bank0: POP ER2 <- W98; POP PC
			W(98, 0xF80C)             --   ER2 = 0xF80C -> r3 = 0xF8 (dst high byte)
			W(0,  0x4292)             -- bank0: MOV R2,R0; POP PC -> r2 = POS' => ER2 = 0xF8|POS' (DST)
			W(4,  0x39CA)             -- bank0: MOV R0,#1; RT (memcpy loop count = 1)
			W(8,  0x35BE)             -- memcpy12 pc (tile at 0x8DDC)
			W(12, 0x8240)             -- its EA: src window, self-slides +12/pass
			-- payload hygiene: zero-free check + dump + bin artifact
			local zf, hex = true, ""
			for i = 0, 99 do
				local b = data[PAY_IN + i] or 0
				if b == 0 then zf = false end
				hex = hex .. string.format("%02X", b)
			end
			local bf = io.open("real01_payload.bin", "wb")
			for i = 0, 99 do bf:write(string.char(data[PAY_IN + i] & 0xFF)) end
			bf:close()
			print("PAYLOAD: len=" .. blen() .. " zerofree=" .. tostring(zf))
			print("PAYHEX: " .. hex)
			print("INPUT: payload planted len=" .. blen() .. " buf=" .. bdump(100))
			print(string.format("INPUT: initial POS[8BBD]=%02X", data[POS_ADDR] or 0))
		elseif final_t == 40001 then
			Keyboard:PressKey(0x37)   -- Right held at the EXE trigger
			Keyboard:PressKey(0x60)   -- EXE: tiler flood -> chain starts from the stack
		elseif final_t == 40003 then
			local s = ""
			for a = 0x8BB0, 0x8BC4 do s = s .. string.format("%02X", data[a] or 0) end
			print("POSTFLOOD 8BB0-8BC4: " .. s .. "  POS[8BBD]=" .. string.format("%02X", data[0x8BBD] or 0))
		elseif final_t == 60001 then
			emu:SetClockSpeed(16)
			Keyboard:ReleaseAll()
			sched_next("trigger")   -- hold SCHED[1] = Right from the walk start
			print("WATCH: 16x, pass-driven key schedule begins")
		elseif final_t > 60001 then
			if (final_t - 60001) % 200000 == 0 then
				local tiled = 0
				for a = 0x8240, 0x8DF8 do
					if (data[a] or 0) == 0x4D and (data[a - 1] or 0) == 0x0E then tiled = tiled + 1 end
				end
				print(string.format("WATCH: ft=%d pc=%04X sp=%04X ER14=%04X ER2=%04X POS=%02X tiles=%d hits=%d cdcw=%d piv=%d wmbe=%d key=%s rows0-3=%s",
					final_t, cpu.pc, cpu.sp, (cpu.r15 & 0xFF) * 0x100 + (cpu.r14 & 0xFF),
					(cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF), data[POS_ADDR] or 0, tiled, scan_hits, CDCW, PIVN, WMBE, cur_key, lcdrows(0, 3)))
			end
			if CDCW >= 48 then finish("GAME2D-LOOP") elseif final_t > 2600000 then finish("NO-TRIGGER") end
		end
	end
end)
