-- BANK-1 FETCH PROOF + GAME-GADGET VERIFICATION (harness-kicked, one emulator run, two kicks)
--   cd research/CasioEmuX && SDL_VIDEODRIVER=dummy timeout 60 \
--     ./emulator/emulator model=models/fx991esplus2 script=rop_bank1.lua
--
-- Semantics under test (source-verified):
--   * POP PC @0x2B1E pops PC=Pop16() then CSR=Pop16()&0xF   (CPUPushPop.cpp:122-127, MM_LARGE)
--   * Fetch: csr &= csr_mask(0x0001); ReadCode((csr<<16)|pc) (CPU.cpp:370-380, model.lua)
--   => 4-byte stack tile [pc_lo pc_hi csr_lo csr_hi]: odd csr_lo => bank-1 fetch at 0x1xxxx.
--
-- Phase 1 (bank-0 control): plain flood tiles 0E 4D 0E 4D (CSR word 0x0E4D -> &0xF=0xD -> &1=0)
--   must stay bank 0 across hops.
-- Phase 2 (bank-1 + gadgets): tiles with CSR word 0x0101 (bytes 01 01, odd low byte) fetch
--   bank 1. Gadgets: 0x13584 (MOV ER2,ER0; ADD ER0,ER4; RT), 0x13A80 (MOV ER2,ER12; POP PC),
--   0x0992C (ADD ER2,#1; POP XR8; POP PC), 0x04292 (MOV R2,R0; POP PC),
--   0x03A50 (CMP R0,#1; BC EQ,0x3A56 / fall -> 0x3A22 MOV R0,#1; POP PC).
-- Breaks are armed at multi-cycle points (RT/POP PC/POP XR8) + park spin 0x4B96, because
-- chipset.Tick batches single-cycle instructions (posttick may not sample their pc).

dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local POPPC, KEYSCAN_RT, PARKSPIN = 0x2B1E, 0x4D20, 0x4B96
local CH = 0x8C80

local rf = assert(io.open("models/fx991esplus2/rom.bin", "rb"))
local ROM = rf:read("*a"); rf:close()
local function romhex(a, n)
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02X", string.byte(ROM, a + 1 + i)) end
	return s
end
local function ER(n) return ((cpu["r" .. (n + 1)] & 0xFF) << 8) | (cpu["r" .. n] & 0xFF) end  -- ERn = r(n+1):r(n), n even
local function tile(a, b0, b1, b2, b3) data[a] = b0; data[a+1] = b1; data[a+2] = b2; data[a+3] = b3 end
local function cpu_s() return string.format("csr=%d pc=%04X sp=%04X lr=%04X", cpu.csr, cpu.pc, cpu.sp, cpu.lr) end
local function words(a, n)
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02X", (data[a + i] or 0) & 0xFF) end
	return s
end

local T, phase, sub = 0, 0, 0
local fw_pc, fw_sp = nil, nil
local park_n = 0

local function arm(addr, cap, fn)
	local fired = 0
	break_at(addr, function()
		fired = fired + 1
		if fired <= cap then fn(fired) end
		emu:set_paused(false)
	end)
end
-- park spin always counts (even beyond the print cap) so phase transitions work
break_at(PARKSPIN, function()
	park_n = park_n + 1
	if park_n <= 3 then print(string.format("PARKSPIN#%d %s", park_n, cpu_s())) end
	emu:set_paused(false)
end)

addposttick(function()
	T = T + 1

	if T == 90000 then
		fw_pc, fw_sp = cpu.pc, cpu.sp
		print(string.format("FW: idle pc=%04X sp=%04X csr=%d", fw_pc, fw_sp, cpu.csr))
	end

	if T == 100000 then
		-- ================= PHASE 1: bank-0 control (plain 0E4D0E4D tiles) ==========
		phase = 1; sub = 0; park_n = 0
		cpu.lcsr = 0
		tile(CH + 0x00, 0x0E, 0x4D, 0x0E, 0x4D)  -- T0: PC=0x4D0E, CSR word 0x0E4D -> bank 0
		tile(CH + 0x04, 0x0E, 0x4D, 0x0E, 0x4D)  -- T1: same
		tile(CH + 0x08, 0xF2, 0x4E, 0x0E, 0x4D)  -- T2: PC=0x4EF2 park, CSR -> bank 0
		Keyboard:PressKey(0x37)                  -- Right held: KEYSCAN ER0=1
		cpu.csr = 0; cpu.sp = CH; cpu.pc = POPPC; cpu.lr = POPPC
		print("KICK1: " .. cpu_s() .. " tiles=" .. words(CH, 12))
	end

	-- phase 1 settle: after park spin seen, watch a bit, restore fw, kick phase 2
	if phase == 1 and (park_n >= 1 or T >= 130000) then
		sub = sub + 1
		if sub == 2000 then
			print(string.format("P1-SETTLE t=%d %s ER0=%04X (expect park spin pc=4B96, csr stayed 0)", T, cpu_s(), ER(0)))
			Keyboard:ReleaseAll()
			cpu.pc, cpu.sp, cpu.csr = fw_pc, fw_sp, 0
			print("FW restored: " .. cpu_s())
			-- ================= PHASE 2: bank-1 tiles + gadget chain ==========
			phase = 2; sub = 0; park_n = 0; cpu.lcsr = 1  -- RT exits keep csr=lcsr=1 (bank 1)
			for a = CH, CH + 0x1F do data[a] = 0 end
			tile(CH + 0x00, 0x84, 0x35, 0x01, 0x01)  -- T0: PC=0x3584, CSR word 0x0101 -> bank 1
			tile(CH + 0x04, 0x80, 0x3A, 0x01, 0x01)  -- T1: PC=0x3A80, CSR 0x0101 -> bank 1
			tile(CH + 0x08, 0x2C, 0x99, 0x00, 0x00)  -- T2: PC=0x992C, CSR 0 -> bank 0
			tile(CH + 0x0C, 0x0E, 0x4D, 0x0E, 0x4D)  -- T3: junk (POP XR8 filler)
			tile(CH + 0x10, 0x0E, 0x4D, 0x0E, 0x4D)  -- T4: junk
			tile(CH + 0x14, 0x92, 0x42, 0x00, 0x00)  -- T5: PC=0x4292, CSR 0
			tile(CH + 0x18, 0x50, 0x3A, 0x00, 0x00)  -- T6: PC=0x3A50, CSR 0
			tile(CH + 0x1C, 0xF2, 0x4E, 0x00, 0x00)  -- T7: PC=0x4EF2 park
			cpu.r0 = 0x11; cpu.r1 = 0x22            -- ER0 = 0x2211
			cpu.r4 = 0x33; cpu.r5 = 0x44            -- ER4 = 0x4433
			cpu.r12 = 0x55; cpu.r13 = 0x66          -- ER12 = 0x6655
			cpu.r2 = 0x00; cpu.r3 = 0xF8            -- ER2 page = 0xF8
			cpu.csr = 0; cpu.sp = CH; cpu.pc = POPPC; cpu.lr = 0x3A82  -- RT in bank 1 lands on 0x13A82 (POP PC)
			print("KICK2: " .. cpu_s() .. string.format(" ER0=%04X ER4=%04X ER12=%04X", ER(0), ER(4), ER(12)) ..
				" tiles=" .. words(CH, 32))
		end
	end

	if phase == 2 and (park_n >= 1 or T >= 160000) then
		sub = sub + 1
		if sub == 1500 then
			print(string.format("P2-SETTLE t=%d %s (expect park spin pc=4B96)", T, cpu_s()))
			print("DONE")
			emu:set_paused(true)
		end
	end
end)

-- ---- trace: POP PC at 0x2B1E (bank 0) ----
arm(POPPC, 8, function(n)
	print(string.format("POPPC#%d %s tile[sp]=%s", n, cpu_s(), words(cpu.sp, 8)))
end)

-- ---- phase 1: KEYSCAN RT in bank 0 (plain 0E4D tile must keep csr=0) ----
arm(KEYSCAN_RT, 4, function(n)
	print(string.format("KEYSCAN-RT#%d %s ER0=%04X rom@4D0E=%s", n, cpu_s(), ER(0), romhex(0x4D0E, 8)))
end)

-- ---- bank-1 gadget 0x13584: MOV ER2,ER0; ADD ER0,ER4; RT @0x13588 ----
arm(0x13584, 2, function(n)
	print(string.format("B1-ENTRY 0x13584 %s ER0=%04X ER2=%04X rom@0x13584=%s (bank-0 rom@0x3584=%s)",
		cpu_s(), ER(0), ER(2), romhex(0x13584, 6), romhex(0x3584, 6)))
end)
arm(0x13588, 2, function(n)
	print(string.format("B1-GADGET-RT 0x13588 %s ER2=%04X (expect 2211) ER0=%04X (expect 2211+4433=6644) rom@0x13584=%s",
		cpu_s(), ER(2), ER(0), romhex(0x13584, 6)))
end)

-- ---- bank-1 POP PC point 0x13A82 (RT target AND tail of 0x13A80) ----
arm(0x13A82, 4, function(n)
	print(string.format("B1-POPPC@0x13A82 #%d %s ER2=%04X tile[sp]=%s", n, cpu_s(), ER(2), words(cpu.sp, 8)))
end)
arm(0x13A80, 2, function(n)
	print(string.format("B1-13A80-ENTRY %s ER12=%04X ER2-before=%04X", cpu_s(), ER(12), ER(2)))
end)

-- ---- bank-0 gadget 0x992C: ADD ER2,#1; POP XR8 @0x992E; POP PC @0x9930 ----
arm(0x992C, 2, function(n)
	print(string.format("ADD-ENTRY 0x992C %s ER2-before=%04X", cpu_s(), ER(2)))
end)
arm(0x992E, 2, function(n)
	print(string.format("ADD-DONE 0x992E %s ER2-after=%04X (expect +1)", cpu_s(), ER(2)))
end)
arm(0x9930, 2, function(n)
	print(string.format("ADD-POPPC 0x9930 %s sp=%04X tile[sp]=%s", cpu_s(), cpu.sp, words(cpu.sp, 8)))
end)

-- ---- bank-0 gadget 0x4292: MOV R2,R0; POP PC @0x4294 ----
arm(0x4292, 2, function(n)
	print(string.format("MOVR2-ENTRY 0x4292 %s r0=%02X ER2-before=%04X", cpu_s(), cpu.r0 & 0xFF, ER(2)))
end)
arm(0x4294, 2, function(n)
	print(string.format("MOVR2-DONE 0x4294 %s r2=%02X ER2-after=%04X (expect F8<<8|r0)", cpu_s(), cpu.r2 & 0xFF, ER(2)))
end)

-- ---- bank-0 gadget 0x3A50: CMP R0,#1; BC EQ,0x3A56; fall BC AL,0x3A22 ----
arm(0x3A50, 2, function(n)
	print(string.format("CMPBC-ENTRY 0x3A50 %s r0=%02X (CMP R0,#1)", cpu_s(), cpu.r0 & 0xFF))
end)
arm(0x3A22, 2, function(n)
	print(string.format("CMPBC-FALL 0x3A22 %s (r0!=1 path: MOV R0,#1; POP PC next)", cpu_s()))
end)
arm(0x3A56, 2, function(n)
	print(string.format("CMPBC-EQ 0x3A56 %s (r0==1 path: MOV R0,#0; POP PC next)", cpu_s()))
end)
arm(0x3A24, 2, function(n)
	print(string.format("CMPBC-FALL-POPPC 0x3A24 %s r0=%02X (expect 01 on fall path)", cpu_s(), cpu.r0 & 0xFF))
end)
arm(0x3A58, 2, function(n)
	print(string.format("CMPBC-EQ-POPPC 0x3A58 %s r0=%02X (expect 00 on EQ path)", cpu_s(), cpu.r0 & 0xFF))
end)
