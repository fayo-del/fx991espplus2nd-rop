-- more08_dsr2.lua — MB08SFRStore run 3: CPU-level DSR=1 read, result captured in RAM.
-- bank1 0x11326 loop: `01 E3` DSR<-001h ; `20 90` L R0,[ER2] ; `8F FE` NOP ; `51 90` ST R0,[EA+]
--                     `81 E2` ADD ER2,#1 ; `FF 11` ADD R1,#-1 ; `F9 C8` BC NE,01326 ; `1F FE` RT
-- With R1=1: copies ONE byte from (DSR<<16)|ER2 into segment-0 [EA], then RT.
-- Probe A: pc=0x1326 (with DSR<-1 prefix)  -> data[EA] should be rom file 0x18154 byte.
-- Probe B: pc=0x1328 (prefix skipped)      -> data[EA] should be RAM data[0x8154] byte.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local SCR = 0x8C80
local stage = 0          -- 0=pre 1=probe A armed 2=A done, arm B 3=B done
local rearm = 0

local romf = io.open("models/fx991esplus2/rom.bin", "rb")
local ROM = romf:read(0x20000)
romf:close()
local function romb(off) return string.format("%02X", ROM:byte(off + 1)) end
local function hex(a, n)
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02X", (data[a + i] or 0) & 0xFF) end
	return s
end

local function arm(with_prefix)
	for i = 0, 15 do data[SCR + i] = 0x0E end
	data[0x9800] = 0x00
	cpu.r2 = 0x54; cpu.r3 = 0x81   -- ER2 = 0x8154
	cpu.r1 = 1                     -- one iteration
	cpu.ea = 0x9800                -- dst in emulator extra page (scratch)
	cpu.sp = SCR
	cpu.lr = 0x4EF2
	cpu.lcsr = 0
	cpu.csr = 1
	cpu.pc = with_prefix and 0x1326 or 0x1328
	rearm = T
end

addposttick(function()
	T = T + 1
	if stage == 0 and T == 200000 then
		data[0x8154] = 0x5A   -- host marker in RAM
		print(string.format("MMU: data[8154]=%s data[18154]=%s rom[18154]=%s data[88154]=%s rom[8154]=%s DSR-SFR=%02X",
			hex(0x8154, 2), hex(0x18154, 2), romb(0x18154), hex(0x88154, 2), romb(0x8154), data[0xF000] or 0))
		print("PROBE-A arm: bank1 0x11326 DSR<-001h; L R0,[ER2=8154]; ST R0,[EA=9800]; RT")
		stage = 1
		arm(true)
	elseif stage == 1 then
		local v = (data[0x9800] or 0) & 0xFF
		if v ~= 0 or T - rearm > 300000 then
			print(string.format("PROBE-A RESULT: data[9800]=%02X | RAM data[8154]=%02X | rom file 18154=%s  => DSR=1 read %s",
				v, data[0x8154] or 0, romb(0x18154),
				tostring(v == tonumber(romb(0x18154), 16) and "SEGMENT-1 ROM (not RAM)" or (v == 0x5A and "SEGMENT-0 RAM" or "???"))))
			stage = 2
			arm(false)
			if T - rearm > 300000 then stage = 3 end
		elseif T - rearm > 100000 then
			arm(true)   -- re-arm in case an IRQ hijacked the teleport
		end
	elseif stage == 2 then
		local v = (data[0x9800] or 0) & 0xFF
		if v ~= 0 or T - rearm > 300000 then
			print(string.format("PROBE-B RESULT (no prefix, control): data[9800]=%02X | RAM data[8154]=%02X => read %s",
				v, data[0x8154] or 0, tostring(v == 0x5A and "SEGMENT-0 RAM" or "???")))
			stage = 3
		end
	elseif stage == 3 then
		print("MORE08-DSR2: done")
		emu:set_paused(true)
	end
	if T > 4000000 then
		print("TIMEOUT stage=" .. stage)
		emu:set_paused(true)
	end
end)
