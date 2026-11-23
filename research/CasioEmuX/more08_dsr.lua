-- more08_dsr.lua — MB08SFRStore run 2: CPU-level DSR data-space aliasing proof.
-- Bank-1 gadget 0x10312: `01 E3` DSR<-001h ; `E0 90` L R0,[ER14] ; `2E FC` POP XR12 ; `1F FE` RT
-- Teleport there with ER14=0x8154 and capture r0 at real pc 0x10318 (before RT).
-- Control: same but pc=0x10314 (skip the DSR prefix) -> should read RAM (segment 0).
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local SCR = 0x8C80
local probe = 0
local done = false

local romf = io.open("models/fx991esplus2/rom.bin", "rb")
local ROM = romf:read(0x20000)
romf:close()
local function romhex(off, n)
	local s = ""
	for i = 1, n do s = s .. string.format("%02X", ROM:byte(off + i)) end
	return s
end
local function hex(a, n)
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02X", (data[a + i] or 0) & 0xFF) end
	return s
end

break_at(0x10318, function()
	-- hit before RT executes; r0 = result of `L R0,[ER14]` (prefix pair already ran)
	if probe == 1 then
		print(string.format("CPU-DSR1-READ: ER14=8154 -> r0=%02X | RAM data[8154]=%02X | rom file 18154=%s | data[18154]=%s",
			cpu.r0 & 0xFF, data[0x8154] or 0, romhex(0x18154, 1), hex(0x18154, 1)))
	elseif probe == 2 then
		print(string.format("CPU-CTRL-READ (no prefix): ER14=8154 -> r0=%02X | RAM data[8154]=%02X",
			cpu.r0 & 0xFF, data[0x8154] or 0))
	elseif probe == 3 then
		print(string.format("CPU-DSR1-READ2: ER14=8D00 -> r0=%02X | RAM data[8D00]=%02X | rom file 18D00=%s",
			cpu.r0 & 0xFF, data[0x8D00] or 0, romhex(0x18D00, 1)))
	end
	probe = probe + 1
	if probe == 2 then
		-- control: skip prefix, pc=0x10314 (L R0,[ER14] with reg_dsr=0)
		cpu.r14 = 0x54; cpu.r15 = 0x81
		cpu.sp = SCR
		cpu.csr = 1
		cpu.pc = 0x0314
	elseif probe == 3 then
		cpu.r14 = 0x00; cpu.r15 = 0x8D
		cpu.sp = SCR
		cpu.csr = 1
		cpu.pc = 0x0312
	else
		done = true
		cpu.csr = 0
		cpu.pc = 0x4EF2
		cpu.lr = 0x4EF2
	end
	emu:set_paused(false)
end)

addposttick(function()
	T = T + 1
	if done then
		print("MORE08-DSR: done")
		emu:set_paused(true)
		return
	end
	if T == 200000 then
		print(string.format("PRE: data[8154]=%s data[18154]=%s rom[18154]=%s data[88154]=%s rom[8154]=%s data[8154+0x100]=%s dsr_sfr=%02X",
			hex(0x8154, 4), hex(0x18154, 4), romhex(0x18154, 4), hex(0x88154, 4), romhex(0x8154, 4), hex(0x8254, 4), data[0xF000] or 0))
		for i = 0, 15 do data[SCR + i] = 0x0E end
		probe = 1
		cpu.r14 = 0x54; cpu.r15 = 0x81   -- ER14 = 0x8154
		cpu.sp = SCR
		cpu.lr = 0x4EF2
		cpu.lcsr = 0
		cpu.csr = 1
		cpu.pc = 0x0312                  -- bank1 0x10312: DSR<-001h; L R0,[ER14]; POP XR12; RT
		print(string.format("TELEPORT: csr=1 pc=0312 ER14=%04X", (cpu.r15 << 8) | cpu.r14))
	elseif T > 3000000 then
		print("TIMEOUT probe=" .. probe)
		emu:set_paused(true)
	end
end)
