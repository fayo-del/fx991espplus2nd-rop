-- more05_chainwrite.lua -- CHAIN-WRITE PROOF v2 (harness kick, single run)
-- Q: can the ROP chain COMPUTE and STORE new bytes (write primitive beyond the payload)?
--
-- Gadgets used (ROM-verified; bank noted):
--   0x3066  (b0) 1E FE 8E F2        POP ER14; POP PC          (ptr from stack, 2B)
--   0x15482 (b1) 0E F0 8E F2        POP R0; POP PC            (value from stack, 2B->r0)
--   0x3B40  (b0) F0 10 8E F2        ADD R0,#0xF0; POP PC      (COMPUTE)
--   0x10470C(b1) E1 90 ... 1F FE    ST R0,[ER14]; ST R8..R4,[FP+1..5]; RT  (WRITE 1B at [ER14])
--   0x14690 (b1) 81 EE 1F FE        ADD ER14,#1; RT           (ptr++)
--   0x49C2  (b0) 1E F2 8E F2        POP ER2; POP PC
--   0x14CA2 (b1) 21 90 00 00 8E F2  ST R0,[ER2]; MOV R0,#0; POP PC  (WRITE 1B at [ER2])
--   0x3722  (b0) 1E F0 8E F2        POP ER0; POP PC
--   0x4292  (b0) 00 82 8E F2        MOV R2,R0; POP PC
--   0x2B20  (b0) 01 92 8E F2        ST R2,[ER0]; POP PC       (WRITE 1B at [ER0])
--   0x4EF2  (b0) park
--
-- Chain at CH=0x8C80, lr=0x2B1E, lcsr=0:
--   A) ER14=0x8500, r0=0x22; 8x [ADD R0,#0xF0; ST R0,[ER14]; ADD ER14,#1]
--      => mem[0x8500..0x8507] = 12 02 F2 E2 D2 C2 B2 A2  (computed ramp)
--   B) mem[0x8510]=0x77 via ER2 path;  C) mem[0x8511]=0x88 via ER0 path
--   D) 4 computed bytes into draw buffer 0x87D0..0x87D3
--   park; dump at park and at settle.
-- Run: cd research/CasioEmuX && SDL_VIDEODRIVER=dummy timeout 60 \
--        ./emulator/emulator model=models/fx991esplus2 script=more05_chainwrite.lua

dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local POPPC, PARKSPIN = 0x2B1E, 0x4B96
local CH = 0x8C80

local function ER(n) return ((cpu["r" .. (n + 1)] & 0xFF) << 8) | (cpu["r" .. n] & 0xFF) end
local function tile(a, b0, b1, b2, b3) data[a] = b0; data[a+1] = b1; data[a+2] = b2; data[a+3] = b3 end
local function cpu_s() return string.format("csr=%d pc=%04X sp=%04X lr=%04X lcsr=%d", cpu.csr, cpu.pc, cpu.sp, cpu.lr, cpu.lcsr) end
local function words(a, n)
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02X", (data[a + i] or 0) & 0xFF) end
	return s
end
local function T(a, pc, bank) if bank == 1 then tile(a, pc & 0xFF, (pc >> 8) & 0xFF, 0x01, 0x01) else tile(a, pc & 0xFF, (pc >> 8) & 0xFF, 0x0E, 0x4D) end end
local function V(a, v) data[a] = v & 0xFF; data[a+1] = (v >> 8) & 0xFF end

local T_, park_n, kicked = 0, 0, false
local function arm(addr, cap, fn)
	local fired = 0
	break_at(addr, function()
		fired = fired + 1
		if fired <= cap then fn(fired) end
		emu:set_paused(false)
	end)
end

local function dump(tag)
	print(string.format("DUMP[%s] t=%d %s", tag, T_, cpu_s()))
	print("RAM-8500-8507 (expect 12 02 F2 E2 D2 C2 B2 A2): " .. words(0x8500, 8))
	print("RAM-8510-8511 (expect 77 88): " .. words(0x8510, 2))
	print("DRAWBUF-87D0-87DF (expect 12 02 F2 E2 ..): " .. words(0x87D0, 16))
end

break_at(PARKSPIN, function()
	if kicked then
		park_n = park_n + 1
		if park_n == 1 then dump("AT-PARK") end
		if park_n <= 3 then print(string.format("PARKSPIN#%d %s", park_n, cpu_s())) end
	end
	emu:set_paused(false)
end)

arm(0x3B42, 16, function(n)
	print(string.format("ADD-R0 #%d: r0=%02X %s", n, cpu.r0 & 0xFF, cpu_s()))
end)
arm(0x1470E, 16, function(n)
	local e14 = ER(14)
	print(string.format("ST-R0-ER14 #%d: ER14=%04X r0=%02X -> mem[%04X]=%02X %s", n, e14, cpu.r0 & 0xFF, e14, (data[e14] or 0) & 0xFF, cpu_s()))
end)
arm(0x2B22, 8, function(n)
	local e0 = ER(0)
	print(string.format("ST-R2-ER0 #%d: ER0=%04X r2=%02X -> mem[%04X]=%02X %s", n, e0, cpu.r2 & 0xFF, e0, (data[e0] or 0) & 0xFF, cpu_s()))
end)
arm(0x14CA6, 4, function(n)
	local e2 = ER(2)
	print(string.format("ST-R0-ER2 #%d: ER2=%04X -> mem[%04X]=%02X %s", n, e2, e2, (data[e2] or 0) & 0xFF, cpu_s()))
end)

addposttick(function()
	T_ = T_ + 1
	if T_ == 100000 then
		kicked = true
		for a = CH, CH + 0xFF do data[a] = 0 end
		local o = CH
		-- A) computed ramp at 0x8500 via ER14 loop
		T(o, 0x3066, 0); o = o + 4; V(o, 0x8500); o = o + 2          -- POP ER14=0x8500
		T(o, 0x5482, 1); o = o + 4; V(o, 0x22); o = o + 2            -- POP R0=0x22
		for k = 0, 7 do
			T(o, 0x3B40, 0); o = o + 4                            -- ADD R0,#0xF0 ; POP PC
			T(o, 0x470C, 1); o = o + 4                            -- ST R0,[ER14] ; RT
			T(o, 0x4690, 1); o = o + 4                            -- ADD ER14,#1 ; RT
		end
		-- B) ER2 path: mem[0x8510]=0x77
		T(o, 0x49C2, 0); o = o + 4; V(o, 0x8510); o = o + 2
		T(o, 0x5482, 1); o = o + 4; V(o, 0x77); o = o + 2
		T(o, 0x4CA2, 1); o = o + 4
		-- C) ER0 write-what-where: mem[0x8511]=0x88
		T(o, 0x3722, 0); o = o + 4; V(o, 0x8511); o = o + 2
		T(o, 0x5482, 1); o = o + 4; V(o, 0x88); o = o + 2
		T(o, 0x4292, 0); o = o + 4
		T(o, 0x2B20, 0); o = o + 4
		-- D) draw buffer: 4 computed bytes at 0x87D0
		T(o, 0x3066, 0); o = o + 4; V(o, 0x87D0); o = o + 2
		T(o, 0x5482, 1); o = o + 4; V(o, 0x22); o = o + 2
		for k = 0, 3 do
			T(o, 0x3B40, 0); o = o + 4
			T(o, 0x470C, 1); o = o + 4
			T(o, 0x4690, 1); o = o + 4
		end
		T(o, 0x4EF2, 0); o = o + 4                                 -- park
		cpu.csr = 0; cpu.sp = CH; cpu.pc = POPPC; cpu.lr = POPPC; cpu.lcsr = 0
		print(string.format("KICK: %s chain[%04X..%04X]=%s", cpu_s(), CH, o - 1, words(CH, o - CH)))
	end
	if kicked and T_ == 103000 then
		dump("SETTLE")
		print("DONE")
		emu:set_paused(true)
	end
	if T_ >= 140000 then
		print(string.format("TIMEOUT-GUARD t=%d %s", T_, cpu_s()))
		dump("TIMEOUT")
		emu:set_paused(true)
	end
end)
