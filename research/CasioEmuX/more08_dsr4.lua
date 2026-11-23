-- more08_dsr4.lua — MB08SFRStore run 4: CPU-level DSR=1 read, result stored to RAM via
-- bank1 real 0x12F8: `01 E3` DSR<-001h ; `20 90` L R0,[ER2] ; `8F FE` NOP ; `51 90` ST R0,[EA+]
--                  `81 E2` ADD ER2,#1 ; `FF 11` ADD R1,#-1 ; `F9 C8` BC NE,12F8 ; `1F FE` RT
-- R1=1 => one byte copied from (1<<16)|ER2 to segment-0 [EA], then RT to lr.
-- Probe A: pc=0x12F8 (prefix present)  -> expect data[EA] = rom file 0x18154 byte (0x0A)
-- Probe B: pc=0x12FA (prefix skipped)  -> expect data[EA] = RAM data[0x8154] (0x5A marker)
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
local T = 0
local SCR = 0x8C80
local stage = 0
local rearm = 0
local romf = io.open("models/fx991esplus2/rom.bin", "rb")
local ROM = romf:read(0x20000)
romf:close()
local function romb(off) return string.format("%02X", ROM:byte(off + 1)) end
local function arm(prefix)
	data[0x9800] = 0x00
	for i = 0, 15 do data[SCR + i] = 0x0E end
	cpu.r2 = 0x54; cpu.r3 = 0x81   -- ER2 = 0x8154
	cpu.r1 = 1
	cpu.ea = 0x9800
	cpu.sp = SCR
	cpu.lr = 0x4EF2
	cpu.lcsr = 0
	cpu.csr = 1
	cpu.pc = prefix and 0x12F8 or 0x12FA
	rearm = T
end
addposttick(function()
	T = T + 1
	if stage == 0 and T == 200000 then
		data[0x8154] = 0x5A
		print(string.format("MMU: data[8154]=%02X data[18154]=%s rom[18154]=%s data[88154]=%s rom[8154]=%s DSR-SFR[F000]=%02X",
			data[0x8154] or 0, string.format("%02X", (data[0x18154] or 0) & 0xFF), romb(0x18154),
			string.format("%02X", (data[0x88154] or 0) & 0xFF), romb(0x8154), data[0xF000] or 0))
		stage = 1
		arm(true)
		print("ARM A: csr=1 pc=12F8 (DSR<-1 prefix)")
	elseif stage == 1 then
		local v = (data[0x9800] or 0) & 0xFF
		if v ~= 0 then
			print(string.format("PROBE-A (DSR<-1 prefix): data[9800]=%02X | rom file 18154=%s | RAM data[8154]=%02X => CPU read %s",
				v, romb(0x18154), data[0x8154] or 0,
				tostring(v == tonumber(romb(0x18154), 16)) and "SEGMENT-1 (ROM bank1), NOT RAM" or (v == 0x5A and "segment-0 RAM" or "?")))
			stage = 2
			arm(false)
			print("ARM B: csr=1 pc=12FA (no prefix, control)")
		elseif T - rearm > 200000 then
			arm(true)  -- re-arm if an IRQ hijacked
		end
	elseif stage == 2 then
		local v = (data[0x9800] or 0) & 0xFF
		if v ~= 0 then
			print(string.format("PROBE-B (no prefix control): data[9800]=%02X | RAM data[8154]=%02X => CPU read %s",
				v, data[0x8154] or 0, tostring(v == 0x5A) and "SEGMENT-0 RAM (as expected)" or "?"))
			stage = 3
		elseif T - rearm > 400000 then
			print("PROBE-B no capture")
			stage = 3
		end
	elseif stage == 3 then
		print("MORE08-DSR4: done")
		emu:set_paused(true)
	end
	if T > 5000000 then print("TIMEOUT stage=" .. stage) emu:set_paused(true) end
end)
