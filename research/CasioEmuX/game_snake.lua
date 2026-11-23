-- game_snake.lua — SNAKE-LITE game loop, driven by the typed hackstring trigger.
-- Base: game_loop.lua (VERIFIED 48-pass interactive loop, rop_work1 v11b skeleton).
--
-- GAME DESIGN (1-D arrow mover; 2-D +/-1 math is NOT expressible: the payload's
-- only key register is r2=KID, and the only walk-safe key->reg carriers are the
-- 0x4D0E keyscan (r2=KID) — see game-snake.md for the budget justification):
--   per pass: KEYSCAN 0x4D0E (flood hops) -> r0=presence, r2=KID (7F=Right/Up,
--             BF=Left/Down, FF=none)
--             -> 0x4CDC branch (W66): F80B.4 := key-held   (on-LCD "button" bit)
--             -> head 0x3538 (W82): ER2 <- 0xF80C          (r3 := 0xF8)
--             -> KEYSCAN 0x4D0E (W90): r2 <- KID           (r3 survives: 0xF8)
--             -> R0-loader 0x3136 (W94/W98): r0 := 1 (exactly one 12-B copy)
--             -> memcpy12 0x35BE (W2, EA=W6): draws the 12-byte cell at
--                dst = ER2 = 0xF8<KID>  ->  0xF87F (Right/Up) / 0xF8BF (Left/Down)
--                                        / 0xF8FF (none)
--                src self-slides +12 B/pass (PUSH EA writeback) -> sprite animates
--             -> re-loader chain + pivot 0x75DE -> next pass
--   The cell therefore MOVES between LCD rows by arrow key (0xF87F=row7/8 area,
--   0xF8BF=row11/12, 0xF8FF=row15/16); old cells persist (zero-byte ban forbids
--   0x00 erase bytes) -> the snake leaves a growing trail. F80B.4 is the
--   key-pressed indicator pixel.
--
-- CHANGE vs game_loop.lua (phase-preserving: head moved W(86)->W(82), so its
-- operands shift W(90)/W(92)->W(86)/W(88), and W(90) becomes a keyscan hop;
-- W(94)/W(98)/W(2)/W(6) and the whole tail stay byte-identical):
--   W(82) = 0x3538   (head, was flood 0x4D0E)
--   W(86) = 0xF80C   (head ER2 operand: r3=0xF8, was flood)
--   W(90) = 0x4D0E   (keyscan AFTER head: r2=KID at memcpy, was 0xF80C)
--   W(88) = flood    (head POP ER8 junk, unchanged)
-- Harness: typed trigger queue (rop_e2e.lua recipe, PressKey from T=1), payload
-- equipped pre-trigger (emulator stand-in for the hardware autotyper+walk
-- delivery — the flash-walk is not emulator-reachable, see kyb_h7findings.md),
-- then AC,LEFT,EXE typed via PressKey. The PLAYER = pass-driven arrow schedule
-- (PressKey only): Right/Left/none/Down/Up rotating every SCHED_EVERY passes.
-- No data[] writes at/after the trigger: the chain state evolves from the typed
-- trigger + held arrows only.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, DOWN, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x36, 0x00, 0x10, 0x22, 0x62
local PAY_IN = 0x8154

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
	print(string.format("PROTO: final-F80B=%02X rows0-17=%s", data[0xF80B] or 0, lcdrows(0, 17)))
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

-- KEYSCAN RT sampler (0x4D20): per-hop ER0 (presence) + r2 (KID)
break_at(0x4D20, function()
	scan_hits = scan_hits + 1
	if scan_hits <= 12 or scan_hits % 200 == 0 then
		print(string.format("SCAN#%d pc=%04X sp=%04X r0=%02X r2=%02X ER0=%04X", scan_hits, cpu.pc, cpu.sp,
			cpu.r0 & 0xFF, cpu.r2 & 0xFF, (cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF)))
	end
	emu:set_paused(false)
end)

-- memcpy entry (0x35BE): WALK-ONLY (lr==0x2B1E): dst=ER2, r2=KID at this moment, word[sp]=EA slot
local MBE, WMBE = 0, 0
local function mk35BE()
	return function()
		MBE = MBE + 1
		if cpu.lr == 0x2B1E then
			WMBE = WMBE + 1
			local er2 = (cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF)
			if WMBE <= 60 then
				print(string.format("WMBE#%d pass=%d sp=%04X ER2(dst)=%04X r2=%02X r0=%02X easlot=%04X key=%s", WMBE, CDCW, cpu.sp, er2,
					cpu.r2 & 0xFF, cpu.r0 & 0xFF,
					(data[cpu.sp] or 0) | ((data[cpu.sp + 1] or 0) << 8), cur_key))
			end
		end
		emu:set_paused(false)
	end
end
-- post-POP EA (0x35C0): walk-only popped src -> +12/pass slide + cell rows on the LCD
local function mk35C0()
	return function()
		if cpu.lr == 0x2B1E and WMBE <= 60 then
			print(string.format("WMBE#%d EA=%04X src12=%s lcd7-8|11-12|15-16=%s|%s|%s", WMBE, cpu.ea,
				string.format("%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
					data[cpu.ea] or 0, data[cpu.ea+1] or 0, data[cpu.ea+2] or 0, data[cpu.ea+3] or 0,
					data[cpu.ea+4] or 0, data[cpu.ea+5] or 0, data[cpu.ea+6] or 0, data[cpu.ea+7] or 0,
					data[cpu.ea+8] or 0, data[cpu.ea+9] or 0, data[cpu.ea+10] or 0, data[cpu.ea+11] or 0),
				lcdrows(7, 8), lcdrows(11, 12), lcdrows(15, 16)))
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
local SCHED = {
	{ 0x37, "Right" }, { 0x26, "Left" }, { nil, "none" }, { 0x36, "Down" }, { 0x27, "Up" },
	{ 0x37, "Right" }, { 0x26, "Left" }, { nil, "none" }, { 0x36, "Down" }, { 0x27, "Up" },
	{ 0x37, "Right" }, { 0x26, "Left" }, { nil, "none" }, { 0x36, "Down" }, { 0x27, "Up" },
	{ 0x37, "Right" }, { 0x26, "Left" }, { nil, "none" },
}
local si = 0
local SCHED_EVERY = 3
local FRAME_AT = { [2]=true, [5]=true, [8]=true, [11]=true, [14]=true, [17]=true, [20]=true, [23]=true, [26]=true, [29]=true, [32]=true, [35]=true, [38]=true, [41]=true, [44]=true, [47]=true }
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
		if FRAME_AT[CDCW] then save_frame(string.format("game_snake_frame%d.raw", CDCW)) end
		if CDCW <= 40 then
			print(string.format("PASS#%d %s-WALK ft=%d sp=%04X r0=%02X r2=%02X ER0=%04X preF80B=%02X key=%s lcd0-3=%s",
				CDCW, tag, final_t, sp, r0, cpu.r2 & 0xFF, (cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF),
				data[0xF80B] or 0, cur_key, lcdrows(0, 3)))
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
		if CDCW <= 40 then
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
			-- ===== payload: 0E4D flood + proven v11b loop skeleton + snake head move =====
			for e = 0, 49 do data[PAY_IN + e * 2] = 0x0E; data[PAY_IN + e * 2 + 1] = 0x4D end
			local function W(off, v) data[PAY_IN + off] = v & 0xFF; data[PAY_IN + off + 1] = (v >> 8) & 0xFF end
			W(30, 0x3066)             -- POP ER14; POP PC: pre-catch ER14 re-load (every pass)
			W(34, 0x8DA8)             -- its ER14 value
			W(36, 0x75DE)             -- MOV SP,ER14; POP ER14; RT: pivot
			W(38, 0x75DE)             -- backup pivot catch at word[0x8DFA]
			W(42, 0x75DE)             -- backup pivot catch at word[0x8DFE]
			W(44, 0x3066)             -- pass-1 first pc-slot load (word[0x8D9C])
			W(48, 0x8DAC)             -- its ER14 value (replay base 0x8DAC)
			W(56, 0x8DA8)             -- pivot self-refresh: word[0x8DA8]=0x8DA8
			W(40, 0x4EF2)             -- park insurance for a +2-shifted phase
			W(66, 0x4CDC)             -- branch gadget: r0 fresh from the W(62) keyscan hop
			W(82, 0x3538)             -- HEAD (moved from W86): POP ER2 <- W(86); POP ER8 <- W(88); RT
			W(86, 0xF80C)             -- head ER2 operand: r3 := 0xF8 (dst high byte)
			W(90, 0x4D0E)             -- KEYSCAN hop AFTER head: r2 <- KID -> dst = 0xF8<KID>
			W(94, 0x3136)             -- R0-loader (POP ER0; POP ER4; POP PC): r0=1, r2 untouched
			W(98, 0x4D01)             -- its ER0 value: r0=1, r1=0x4D junk (zero-free)
			W(2,  0x35BE)             -- memcpy12 pc (reached via the R0-loader's POP PC)
			W(6,  0x8240)             -- its EA: src = tiled-flood base; PUSH EA writeback
			                          -- advances it +12 per pass (self-sliding src window)
			W(24, 0x3066)             -- odd-phase re-loader: restores ER14 after memcpy's QR8 clobber
			W(28, 0x8DAC)             -- its ER14 value = replay base
			W(32, 0x8DAC)             -- old-loader's ER14 value (odd-phase 2nd load)
			W(60, 0xF28E)             -- bytes "8E F2" = POP PC at 0x8DAC -> chains to pivot W(36)
			-- payload hygiene: zero-free check + dump + bin artifact
			local zf, hex = true, ""
			for i = 0, 99 do
				local b = data[PAY_IN + i] or 0
				if b == 0 then zf = false end
				hex = hex .. string.format("%02X", b)
			end
			local bf = io.open("game_snake_payload.bin", "wb")
			for i = 0, 99 do bf:write(string.char(data[PAY_IN + i] & 0xFF)) end
			bf:close()
			print("PAYLOAD: len=" .. blen() .. " zerofree=" .. tostring(zf))
			print("PAYHEX: " .. hex)
			print("INPUT: payload planted len=" .. blen() .. " buf=" .. bdump(100))
		elseif final_t == 40001 then
			Keyboard:PressKey(0x37)   -- Right held at the EXE trigger
			Keyboard:PressKey(0x60)   -- EXE: tiler flood -> chain starts from the stack
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
				print(string.format("WATCH: ft=%d pc=%04X sp=%04X ER14=%04X ER2=%04X tiles=%d hits=%d cdcw=%d piv=%d wmbe=%d key=%s rows0-3=%s",
					final_t, cpu.pc, cpu.sp, (cpu.r15 & 0xFF) * 0x100 + (cpu.r14 & 0xFF),
					(cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF), tiled, scan_hits, CDCW, PIVN, WMBE, cur_key, lcdrows(0, 3)))
			end
			if CDCW >= 48 then finish("SNAKE-LOOP") elseif final_t > 2600000 then finish("NO-TRIGGER") end
		end
	end
end)
