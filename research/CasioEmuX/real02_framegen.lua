-- real02_framegen.lua — FRAMEGEN: prove FULL content freedom: the typed-hackstring
-- ROP chain COMPUTES a multi-byte frame into mid-RAM (0x8510..) and shows it on the
-- LCD via memcpy12, pass after pass, with a changing pattern.
-- Base: game_snake.lua (VERIFIED 48-pass loop, pivot 0x75DE re-syncs SP each pass).
--
-- PAYLOAD DIFF vs game_snake.lua (everything else byte-identical):
--   W(58)=W(64)=W(70)=W(76)=0x3854  -- 4 tiles of 0x3854:
--        0x3854: ADD R2,#208; ST R2,[EA+]; ADD R0,#208; ST R0,[EA+]; ST R3,[EA+];
--                POP R4; RT        (3 COMPUTED bytes at successive [EA+], 6 stack B/tile)
--     steady-state walk from sp=0x8DAA: tile@8DAA(W58,W60) -> POP R4@8DAE(W62) ->
--     tile@8DB0(W64,W66) -> POP R4@8DB4(W68) -> tile@8DB6(W70,W72) -> POP R4@8DBA(W74)
--     -> tile@8DBC(W76,W78) -> POP R4@8DC0(W80) -> sp=8DC2 = head tile (W82,W84).
--     => 12 computed bytes written at [EA..EA+11] per pass, EA += 12 per pass.
--   W(6)=0x8510  -- memcpy12 src EA = the computed mid-RAM buffer (was 0x8240 flood).
--     memcpy12's PUSH EA writes the advanced EA back into the popped slot (8DDA), so
--     the src slides +12/work-pass IN LOCKSTEP with the 0x3854 write pointer.
--   W(66)=flood  -- the 0x4CDC key branch is replaced by a 0x3854 csr word (pass
--     counting moves to the memcpy walk hits). dst stays ER2=0xF8<KID> via head+keyscan.
-- Per pass: 12 computed bytes land at 0x8510+12*(pass-1).. and memcpy12 copies exactly
-- those 12 B to LCD dst=0xF8<KID> (row chosen by the held arrow). Pattern changes every
-- pass because r0/r2 accumulate ADD #208 per tile and r2=KID follows the key schedule.
--
-- Harness: typed trigger (rop_e2e recipe) + payload equipped pre-trigger (documented
-- stand-in for the hardware autotyper delivery), then AC,LEFT,EXE typed via PressKey.
-- PLAYER = work-pass-driven arrow schedule (PressKey only). NO data[] writes post-trigger.
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
	print(string.format("PROTO: %s hits=%d pc=%04X sp=%04X ER14=%04X piv=%d wmbe=%d workpass=%d w3854=%d", tag, scan_hits, cpu.pc, cpu.sp,
		(cpu.r15 & 0xFF) * 0x100 + (cpu.r14 & 0xFF), PIVN, WMBE, WORKPASS, W3854N))
	-- full LCD dump (32 rows x 16 B) + computed buffer dump
	local rows = {}
	for rr = 0, 31 do
		local s = ""
		for i = 0, 15 do s = s .. string.format("%02X", (data[0xF800 + rr * 16 + i] or 0) & 0xFF) end
		rows[#rows + 1] = s
	end
	print("PROTO: LCD-rows0-31=" .. table.concat(rows, "|"))
	local buf = ""
	for a = 0x8500, 0x8580 do buf = buf .. string.format("%02X", (data[a] or 0) & 0xFF) end
	print("PROTO: RAM-8500-8580=" .. buf)
	local eas = ""
	for a = 0x8DDA, 0x8DDB do eas = eas .. string.format("%02X", (data[a] or 0) & 0xFF) end
	print("PROTO: EA-slot-8DDA=" .. eas .. " EAreg=" .. string.format("%04X", cpu.ea))
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

-- POP PC tracer (0x2B1E): post-trigger walk tiles, capped
local poppc_n = 0
break_at(0x2B1E, function()
	if final_t > 40001 then
		poppc_n = poppc_n + 1
		if poppc_n <= 140 then
			print(string.format("POPPC#%d sp=%04X tile=%02X%02X%02X%02X lr=%04X csr=%X", poppc_n, cpu.sp,
				data[cpu.sp] or 0, data[cpu.sp+1] or 0, data[cpu.sp+2] or 0, data[cpu.sp+3] or 0, cpu.lr, cpu.csr))
		end
	end
	emu:set_paused(false)
end)

-- 0x3854 computed-store gadget: log at its RT (0x3860), after the 3 stores
W3854N = 0
break_at(0x3860, function()
	if final_t > 40001 then
		W3854N = W3854N + 1
		if W3854N <= 60 then
			local ea = cpu.ea
			print(string.format("W3854#%d sp=%04X EA=%04X (wrote %02X %02X %02X at %04X..%04X) r0=%02X r2=%02X r3=%02X lr=%04X",
				W3854N, cpu.sp, ea,
				data[ea-3] or 0, data[ea-2] or 0, data[ea-1] or 0, ea-3, ea-1,
				cpu.r0 & 0xFF, cpu.r2 & 0xFF, cpu.r3 & 0xFF, cpu.lr))
		end
	end
	emu:set_paused(false)
end)

-- memcpy entry (0x35BE): WALK-ONLY (lr==0x2B1E): dst=ER2, word[sp]=EA slot
MBE, WMBE, WORKPASS = 0, 0, 0
local last_easlot = -1
local function mk35BE()
	return function()
		MBE = MBE + 1
		if cpu.lr == 0x2B1E then
			WMBE = WMBE + 1
			local er2 = (cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF)
			local easlot = (data[cpu.sp] or 0) | ((data[cpu.sp + 1] or 0) << 8)
			if easlot ~= last_easlot then
				last_easlot = easlot
				WORKPASS = WORKPASS + 1
				if WORKPASS <= 12 then
					print(string.format("WORKPASS#%d WMBE=%d sp=%04X ER2(dst)=%04X r2=%02X r0=%02X easlot=%04X EAreg=%04X key=%s", WORKPASS, WMBE, cpu.sp, er2,
						cpu.r2 & 0xFF, cpu.r0 & 0xFF, easlot, cpu.ea, cur_key))
					if WORKPASS >= 1 and WORKPASS <= 10 then
						save_frame(string.format("real02_frame%d.raw", WORKPASS))
					end
					if WORKPASS % 2 == 0 then sched_next("workpass") end
				end
			elseif WMBE <= 40 then
				print(string.format("WMBE#%d (same easlot=%04X) sp=%04X ER2=%04X r0=%02X", WMBE, easlot, cpu.sp, er2, cpu.r0 & 0xFF))
			end
		end
		emu:set_paused(false)
	end
end
-- post-POP EA (0x35C0): walk-only popped src -> +12/pass slide + computed 12 B + LCD rows
local function mk35C0()
	return function()
		if cpu.lr == 0x2B1E and WMBE <= 60 then
			print(string.format("WMBE#%d EA=%04X src12=%s lcd=%s key=%s", WMBE, cpu.ea,
				string.format("%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
					data[cpu.ea] or 0, data[cpu.ea+1] or 0, data[cpu.ea+2] or 0, data[cpu.ea+3] or 0,
					data[cpu.ea+4] or 0, data[cpu.ea+5] or 0, data[cpu.ea+6] or 0, data[cpu.ea+7] or 0,
					data[cpu.ea+8] or 0, data[cpu.ea+9] or 0, data[cpu.ea+10] or 0, data[cpu.ea+11] or 0),
				lcdrows(0, 3), cur_key))
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

-- work-pass-driven key schedule (harness side, PressKey only)
local SCHED = {
	{ 0x37, "Right" }, { 0x26, "Left" }, { 0x27, "Up" }, { 0x36, "Down" }, { nil, "none" },
	{ 0x37, "Right" }, { 0x26, "Left" }, { 0x27, "Up" }, { 0x36, "Down" }, { nil, "none" },
	{ 0x37, "Right" }, { 0x26, "Left" },
}
local si = 0
function sched_next(tag)
	if si >= #SCHED then return end
	si = si + 1
	Keyboard:ReleaseAll()
	local e = SCHED[si]
	if e[1] then Keyboard:PressKey(e[1]) end
	cur_key = e[2]
	print(string.format("KEYSCHED workpass=%d sched=%d key=%s (%s)", WORKPASS, si, e[2], tag))
end

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
			Keyboard:PressKey(0x37)   -- Right held at trigger
			Keyboard:PressKey(AC)
		elseif final_t == 16001 then
			Keyboard:ReleaseAll()
		elseif final_t == 20001 then
			Keyboard:PressKey(LEFT)
		elseif final_t == 36001 then
			Keyboard:ReleaseAll()
			-- ===== payload: 0E4D flood + proven v11b loop skeleton + 4x 0x3854 computed-write section =====
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
			W(58, 0x3854)             -- COMPUTED STORE #1: 3 bytes at [EA+] (tile@8DAA)
			W(64, 0x3854)             -- COMPUTED STORE #2 (tile@8DB0; W66=flood csr)
			W(70, 0x3854)             -- COMPUTED STORE #3 (tile@8DB6; W72=flood csr)
			W(76, 0x3854)             -- COMPUTED STORE #4 (tile@8DBC; W78=flood csr)
			                              -- => 12 computed bytes at [EA..EA+11] per pass
			W(82, 0x3538)             -- HEAD: POP ER2 <- W(86); POP ER8 <- W(88); RT
			W(86, 0xF80C)             -- head ER2 operand: r3 := 0xF8 (dst high byte)
			W(90, 0x4D0E)             -- KEYSCAN hop AFTER head (runs after the 0x3854 writes):
			                          -- r2 <- KID -> memcpy dst = 0xF8<KID> (key-chosen row) AND the
			                          -- next pass's computed stores use r2=KID as seed => pattern
			                          -- changes with the key schedule. EA gets re-pinned to 0xF040
			                          -- here, but the following memcpy POP EA reloads it from the
			                          -- sliding slot, so the write<->src lockstep is preserved.
			W(20, 0x2B1E)             -- PASSTHROUGH at the post-memcpy tail hop (sp=8DE8): keeps
			                          -- the only keyscan out of the tail so EA survives to the next
			                          -- pass's write section (lockstep with the memcpy slot)
			W(94, 0x3136)             -- R0-loader (POP ER0; POP ER4; POP PC): r0=1, r2 untouched
			W(98, 0x4D01)             -- its ER0 value: r0=1, r1=0x4D junk (zero-free)
			W(2,  0x35BE)             -- memcpy12 pc (reached via the R0-loader's POP PC)
			W(6,  0x8510)             -- its EA: src = COMPUTED mid-RAM buffer 0x8510 (slides
			                          -- +12/work-pass via PUSH EA writeback, lockstep with 0x3854)
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
			local bf = io.open("real02_framegen_payload.bin", "wb")
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
			print("WATCH: 16x, work-pass-driven key schedule begins")
		elseif final_t > 60001 then
			if (final_t - 60001) % 200000 == 0 then
				local tiled = 0
				for a = 0x8240, 0x8DF8 do
					if (data[a] or 0) == 0x4D and (data[a - 1] or 0) == 0x0E then tiled = tiled + 1 end
				end
				print(string.format("WATCH: ft=%d pc=%04X sp=%04X ER14=%04X ER2=%04X tiles=%d hits=%d piv=%d wmbe=%d workpass=%d w3854=%d key=%s rows0-3=%s",
					final_t, cpu.pc, cpu.sp, (cpu.r15 & 0xFF) * 0x100 + (cpu.r14 & 0xFF),
					(cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF), tiled, scan_hits, PIVN, WMBE, WORKPASS, W3854N, cur_key, lcdrows(0, 3)))
			end
			if WORKPASS >= 8 then finish("FRAMEGEN-LOOP") elseif final_t > 2600000 then finish("NO-TRIGGER") end
		end
	end
end)
