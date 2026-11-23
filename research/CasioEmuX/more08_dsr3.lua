-- more08_dsr3.lua — debug the bank-1 DSR teleport: trace pc/csr after arming.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
local T = 0
local SCR = 0x8C80
local stage = 0
local romf = io.open("models/fx991esplus2/rom.bin", "rb")
local ROM = romf:read(0x20000)
romf:close()
local function romb(off) return string.format("%02X", ROM:byte(off + 1)) end
addposttick(function()
	T = T + 1
	if stage == 0 and T == 200000 then
		data[0x8154] = 0x5A
		data[0x9800] = 0x00
		for i = 0, 15 do data[SCR + i] = 0x0E end
		cpu.r2 = 0x54; cpu.r3 = 0x81
		cpu.r1 = 1
		cpu.ea = 0x9800
		cpu.sp = SCR
		cpu.lr = 0x4EF2
		cpu.lcsr = 0
		cpu.csr = 1
		cpu.pc = 0x1326
		stage = 1
		print(string.format("ARMED t=%d csr=%d pc=%04X ER2=%04X ea=%04X r1=%d rom[11326]=%s",
			T, cpu.csr, cpu.pc, (cpu.r3<<8)|cpu.r2, cpu.ea, cpu.r1,
			string.format("%02X%02X%02X%02X", ROM:byte(0x11327), ROM:byte(0x11328), ROM:byte(0x11329), ROM:byte(0x1132A))))
	elseif stage == 1 then
		if T % 2000 == 0 and T < 200000 + 40000 then
			print(string.format("t=%d csr=%d pc=%04X r0=%02X data[9800]=%02X data[8154]=%02X",
				T, cpu.csr, cpu.pc, cpu.r[0] & 0xFF, (data[0x9800] or 0) & 0xFF, (data[0x8154] or 0) & 0xFF))
		end
		if (data[0x9800] or 0) ~= 0 then
			print(string.format("CAPTURED t=%d data[9800]=%02X rom[18154]=%s RAM[8154]=%02X", T, data[0x9800], romb(0x18154), data[0x8154]))
			stage = 2
		end
	elseif stage == 2 and T > 200000 + 200000 then
		print("done stage=2")
		emu:set_paused(true)
	end
	if T > 3000000 then print("TIMEOUT stage=" .. stage) emu:set_paused(true) end
end)
