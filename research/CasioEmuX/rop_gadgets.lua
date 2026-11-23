-- GAME-GADGET VERIFICATION, single kick (rop_gadgets.lua)
--   cd research/CasioEmuX && SDL_VIDEODRIVER=dummy timeout 60 \
--     ./emulator/emulator model=models/fx991esplus2 script=rop_gadgets.lua
--
-- Bank semantics (source + run-verified):
--   * POP PC tile [pc_lo pc_hi csr_lo csr_hi]: fetch bank = (csr_word & 0xF) & csr_mask(1)
--     => odd csr_lo byte fetches bank 1 (0x1xxxx).  (CPUPushPop.cpp:122-127, CPU.cpp:370-380)
--   * RT exits set csr = LCSR (CPUControl.cpp:226), so lr=0x2B1E (bank-0 POP PC) is the
--     safe RT target; each following tile re-selects the bank via its own CSR word.
--
-- Chain (CH=0x8C80), lr=0x2B1E:
--   T0 84 35 01 01 -> 0x13584 (bank1) MOV ER2,ER0; ADD ER0,ER4; RT@0x13588
--   T1 80 3A 01 01 -> 0x13A80 (bank1) MOV ER2,ER12; POP PC@0x13A82
--   T2 2C 99 00 00 -> 0x0992C (bank0) ADD ER2,#1; POP XR8@0x992E; POP PC@0x9930
--   T3/T4 junk     -> consumed by POP XR8
--   T5 92 42 00 00 -> 0x04292 (bank0) MOV R2,R0; POP PC@0x4294
--   T6 50 3A 00 00 -> 0x03A50 (bank0) CMP R0,#1; BC EQ,0x3A56 / fall -> 0x3A22 MOV R0,#1; POP PC@0x3A24
--   T7 F2 4E 00 00 -> 0x4EF2 park -> spin 0x4B96

dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local POPPC, PARKSPIN = 0x2B1E, 0x4B96
local CH = 0x8C80

local rf = assert(io.open("models/fx991esplus2/rom.bin", "rb"))
local ROM = rf:read("*a"); rf:close()
local function romhex(a, n)
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02X", string.byte(ROM, a + 1 + i)) end
	return s
end
local function ER(n) return ((cpu["r" .. (n + 1)] & 0xFF) << 8) | (cpu["r" .. n] & 0xFF) end
local function tile(a, b0, b1, b2, b3) data[a] = b0; data[a+1] = b1; data[a+2] = b2; data[a+3] = b3 end
local function cpu_s() return string.format("csr=%d pc=%04X sp=%04X lr=%04X lcsr=%d", cpu.csr, cpu.pc, cpu.sp, cpu.lr, cpu.lcsr) end
local function words(a, n)
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02X", (data[a + i] or 0) & 0xFF) end
	return s
end

local T, sub, park_n, kicked = 0, 0, 0, false

local function arm(addr, cap, fn)
	local fired = 0
	break_at(addr, function()
		fired = fired + 1
		if fired <= cap then fn(fired) end
		emu:set_paused(false)
	end)
end

-- park spin counts only after the kick
break_at(PARKSPIN, function()
	if kicked then
		park_n = park_n + 1
		if park_n <= 3 then print(string.format("PARKSPIN#%d %s", park_n, cpu_s())) end
	end
	emu:set_paused(false)
end)

addposttick(function()
	T = T + 1
	if T == 100000 then
		kicked = true
		for a = CH, CH + 0x1F do data[a] = 0 end
		tile(CH + 0x00, 0x84, 0x35, 0x01, 0x01)  -- T0 -> 0x13584 bank 1
		tile(CH + 0x04, 0x80, 0x3A, 0x01, 0x01)  -- T1 -> 0x13A80 bank 1
		tile(CH + 0x08, 0x2C, 0x99, 0x00, 0x00)  -- T2 -> 0x0992C bank 0
		tile(CH + 0x0C, 0x0E, 0x4D, 0x0E, 0x4D)  -- T3 junk
		tile(CH + 0x10, 0x0E, 0x4D, 0x0E, 0x4D)  -- T4 junk
		tile(CH + 0x14, 0x92, 0x42, 0x00, 0x00)  -- T5 -> 0x04292 bank 0
		tile(CH + 0x18, 0x50, 0x3A, 0x00, 0x00)  -- T6 -> 0x03A50 bank 0
		tile(CH + 0x1C, 0xF2, 0x4E, 0x00, 0x00)  -- T7 -> 0x4EF2 park
		cpu.r0 = 0x11; cpu.r1 = 0x22            -- ER0 = 0x2211
		cpu.r4 = 0x33; cpu.r5 = 0x44            -- ER4 = 0x4433
		cpu.r12 = 0x55; cpu.r13 = 0x66          -- ER12 = 0x6655
		cpu.r2 = 0x00; cpu.r3 = 0xF8            -- ER2 page 0xF8
		cpu.csr = 0; cpu.sp = CH; cpu.pc = POPPC; cpu.lr = POPPC
		print("KICK: " .. cpu_s() .. string.format(" ER0=%04X ER4=%04X ER12=%04X", ER(0), ER(4), ER(12)) .. " tiles=" .. words(CH, 32))
	end
	if kicked and park_n >= 1 then
		sub = sub + 1
		if sub == 1500 then
			print(string.format("SETTLE t=%d %s ER2=%04X (expect park spin pc=4B96)", T, cpu_s(), ER(2)))
			print("DONE")
			emu:set_paused(true)
		end
	end
	if T >= 130000 then
		print(string.format("TIMEOUT-GUARD t=%d %s ER2=%04X", T, cpu_s(), ER(2)))
		emu:set_paused(true)
	end
end)

-- bank-1 fetch proof + gadget 0x13584
arm(0x13584, 2, function(n)
	print(string.format("B1-ENTRY 0x13584 %s ER0=%04X ER2=%04X rom@0x13584=%s (bank0 rom@0x3584=%s)",
		cpu_s(), ER(0), ER(2), romhex(0x13584, 6), romhex(0x3584, 6)))
end)
arm(0x13588, 2, function(n)
	print(string.format("B1-G1-RT 0x13588 %s ER2=%04X (expect 2211) ER0=%04X (expect 6644)", cpu_s(), ER(2), ER(0)))
end)
-- bank-1 gadget 0x13A80: MOV ER2,ER12; POP PC
arm(0x13A80, 2, function(n)
	print(string.format("B1-G2-ENTRY 0x13A80 %s ER12=%04X ER2-before=%04X", cpu_s(), ER(12), ER(2)))
end)
arm(0x13A82, 3, function(n)
	print(string.format("B1-G2-POPPC 0x13A82 #%d %s ER2=%04X (expect 6655) tile[sp]=%s", n, cpu_s(), ER(2), words(cpu.sp, 8)))
end)
-- bank-0 gadget 0x992C: ADD ER2,#1; POP XR8; POP PC
arm(0x992C, 2, function(n)
	print(string.format("G3-ADD-ENTRY 0x992C %s ER2-before=%04X", cpu_s(), ER(2)))
end)
arm(0x992E, 2, function(n)
	print(string.format("G3-ADD-DONE 0x992E %s ER2-after=%04X (expect +1)", cpu_s(), ER(2)))
end)
arm(0x9930, 2, function(n)
	print(string.format("G3-POPPC 0x9930 %s sp=%04X tile[sp]=%s", cpu_s(), cpu.sp, words(cpu.sp, 8)))
end)
-- bank-0 gadget 0x4292: MOV R2,R0; POP PC
arm(0x4292, 2, function(n)
	print(string.format("G4-ENTRY 0x4292 %s r0=%02X ER2-before=%04X", cpu_s(), cpu.r0 & 0xFF, ER(2)))
end)
arm(0x4294, 2, function(n)
	print(string.format("G4-DONE 0x4294 %s r2=%02X ER2-after=%04X (expect F8%02X)", cpu_s(), cpu.r2 & 0xFF, ER(2), cpu.r0 & 0xFF))
end)
-- bank-0 gadget 0x3A50: CMP R0,#1; BC EQ,0x3A56 / fall 0x3A22
arm(0x3A50, 2, function(n)
	print(string.format("G5-ENTRY 0x3A50 %s r0=%02X (CMP R0,#1)", cpu_s(), cpu.r0 & 0xFF))
end)
arm(0x3A22, 2, function(n)
	print(string.format("G5-FALL 0x3A22 %s (r0!=1 path)", cpu_s()))
end)
arm(0x3A56, 2, function(n)
	print(string.format("G5-EQ 0x3A56 %s (r0==1 path)", cpu_s()))
end)
arm(0x3A24, 2, function(n)
	print(string.format("G5-FALL-POPPC 0x3A24 %s r0=%02X (expect 01)", cpu_s(), cpu.r0 & 0xFF))
end)
arm(0x3A58, 2, function(n)
	print(string.format("G5-EQ-POPPC 0x3A58 %s r0=%02X (expect 00)", cpu_s(), cpu.r0 & 0xFF))
end)
