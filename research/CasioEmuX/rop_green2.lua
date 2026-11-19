-- GREEN-RUN (ready; not yet executed — 1 emulator run needed):
--   cd research/CasioEmuX && SDL_VIDEODRIVER=dummy timeout 10 \
--     ./emulator/emulator model=models/fx991esplus2 script=rop_green2.lua
--
-- Final bank0 chain, all semantics oki-verified:
--   * POP PC (0x2B1E) pops FOUR bytes: [pc_lo, pc_hi, x, y] (x,y ignored)
--   * 0x35BE gadget: POP EA (src, 2 bytes from stack) -> L XR4,[EA+] /
--     L QR8,[EA+] (12 bytes) -> PUSH EA -> LEA [ER2] -> ST XR4,[EA+] /
--     ST QR8,[EA+] (12 bytes to [ER2]); loop count in R0 (ADD R0,#-1 / BC NE);
--     tail POP ER0/QR8/XR4 then RT -> PC = LR.
--   * LR is the chain's "next pointer" for RT-ending gadgets: kick lr=0x2B1E.
--   * KEYSCAN 0x4D0E: KOD(0xF046)=127; LEA 0xF040 (KID); L R2,[EA]; CMP #255;
--     ADDC R0,#0; RT @0x4D20. ER0 = 1 iff KID != 0xFF (key seen).
--   * dst = 0x87D0 (firmware draw buffer): pattern survives park because the
--     app main loop is dead; the LCD refresh copies it to 0xF800.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local POPPC, CPY, KEYSCAN, PARK = 0x2B1E, 0x35BE, 0x4D0E, 0x4EF2
local CH, PAT, DBUF = 0x8C80, 0x8C74, 0x87D0

local T, phase, sub = 0, 0, 0
local fw_pc, fw_sp = nil, nil
local snap = {}

local function cpu_s()
	return string.format("pc=%04X sp=%04X csr=%d ea=%04X lr=%04X", cpu.pc, cpu.sp, cpu.csr, cpu.ea, cpu.lr)
end
local function wr16(a, v)
	data[a] = v & 0xFF; data[a + 1] = (v >> 8) & 0xFF
end
local function wr32(a, v)
	wr16(a, v); wr16(a + 2, 0)
end
local function dump(tag, base, n)
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02X", data[base + i]) end
	print("FRAME: " .. tag .. " " .. s)
end

addposttick(function()
	T = T + 1

	if T == 90000 then
		fw_pc, fw_sp = cpu.pc, cpu.sp
		print(string.format("ROP: firmware idle pc=%04X sp=%04X", fw_pc, fw_sp))
	end

	if T == 100000 then
		phase = 1; sub = 0
		for i = 0, 11 do data[PAT + i] = 0xFF end        -- 12-byte pattern
		for a = CH, CH + 0x1B do data[a] = 0x00 end      -- clear chain area
		wr32(CH + 0x00, CPY)                             -- 0x8C80: memcpy gadget
		wr32(CH + 0x04, PAT)                             -- 0x8C84: src (POP EA)
		wr32(CH + 0x08, 0x0000); wr32(CH + 0x0C, 0x0000) -- QR8/XR4 junk (0x8C88..0x8C91)
		wr32(CH + 0x12, KEYSCAN)                         -- 0x8C92: key read
		wr32(CH + 0x16, PARK)                            -- 0x8C96: park
		cpu.csr = 0
		cpu.sp = CH
		cpu.pc = POPPC
		cpu.lr = POPPC                                   -- RT-ending gadgets return here
		cpu.r0 = 1                                       -- memcpy: one 12-byte block
		cpu.r2 = 0x00; cpu.r3 = 0xF8                     -- ER2 = 0xF800 (LCD row0)
		Keyboard:PressKey(0x37)                          -- Right held
		print("ROP: P1 kicked " .. cpu_s())
		break_at(0x4D20, function()
			print(string.format("ROP: @4D20 KEYSCAN RT ER0=%04X (r0=%02X r1=%02X) Right held -> expect != 0x0000 when key seen; 0x0001 = no key",
				(cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF), cpu.r0 & 0xFF, cpu.r1 & 0xFF))
			emu:set_paused(false)
		end)
	end
	if phase == 1 then
		sub = sub + 1
		if sub == 2 then dump("P1+2 row0:", 0xF800, 12) end
		if sub == 100 then dump("P1+100 row0:", 0xF800, 12) end
		if sub == 2000 then
			dump("P1+2000 row0:", 0xF800, 12)
			dump("P1+2000 row1:", 0xF810, 12)
			print("ROP: P1 done " .. cpu_s())
			unbreak_at(0x4D20)
			Keyboard:ReleaseAll()
			cpu.pc = fw_pc; cpu.sp = fw_sp; cpu.csr = 0
			phase = 2; sub = 0
			print("ROP: P2 firmware restored " .. cpu_s())
		end
	elseif phase == 2 then
		sub = sub + 1
		if sub == 1000 or sub == 4000 then
			dump("P2 t" .. sub .. " row0:", 0xF800, 12)
			dump("P2 t" .. sub .. " 0x87D0:", DBUF, 12)
		end
		if sub == 4000 then
			phase = 3; sub = 0
			for a = 0x8100, 0x8DFF do snap[a] = (data[a] or 0) & 0xFF end
			for i = 0, 99 do data[0x8154 + i] = (i ~ 0xA5) & 0xFF end
			Keyboard:PressKey(0x30)
			print("ROP: P3 markers written, '=' down (long hold)")
		end
	elseif phase == 3 then
		sub = sub + 1
		local function diffn(lo, hi)
			local n = 0
			for a = lo, hi do if ((data[a] or 0) & 0xFF) ~= snap[a] then n = n + 1 end end
			return n
		end
		if sub == 1000 or sub == 10000 or sub == 50000 then
			print(string.format("ROP: P3 t%d %s diff=%d", sub, cpu_s(), diffn(0x8100, 0x8DFF)))
		end
		if sub == 100000 then
			print(string.format("ROP: P3 end diff=%d %s", diffn(0x8100, 0x8DFF), cpu_s()))
			local st, en
			for a = 0x8100, 0x8DFF do
				local ch = ((data[a] or 0) & 0xFF) ~= snap[a]
				if ch and st == nil then st, en = a, a
				elseif ch then en = a
				elseif st then
					local s = ""
					for b = st, math.min(en, st + 11) do s = s .. string.format("%02X", (data[b] or 0) & 0xFF) end
					print(string.format("FRAME: P3 chg %04X-%04X: %s", st, en, s))
					st = nil
				end
			end
			if st then
				local s = ""
				for b = st, math.min(en, st + 11) do s = s .. string.format("%02X", (data[b] or 0) & 0xFF) end
				print(string.format("FRAME: P3 chg %04X-%04X: %s", st, en, s))
			end
			dump("P3 row0:", 0xF800, 12)
			Keyboard:ReleaseAll()
			emu:set_paused(true)
			phase = 4
		end
	end
end)
