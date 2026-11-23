-- MORE01 CAP: max typed length at 0x8154 by PURE KEYBOARD in MathIO (COMP).
-- Phase A: type a 16-key cycle of single-byte-token keys until insert stops.
-- Phase B: at cap, probe LEFT+key (middle insert), DEL+key, SHIFT+DEL(INS)+key.
-- Phase C: history/RCL: store "1+2" via EXE, refill, try SHIFT+candidate pastes.
-- Phase D: dumps 0x8100-0x8400 + region checksums (2nd-line buffer 0x829E...).
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
emu:SetClockSpeed(8)

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT = 0x07,0x17,0x47,0x06,0x60,0x42,0x32,0x26,0x37
local OUT = "/tmp/mb01_"

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase = "type"
local maxlen, maxslen = -1, -1

local function slen()
	for i = 0, 0x1AC do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 0x1AD
end
local function lenvar() return (data[0x8114] or 0) & 0xFF end
local function bdump(n, base)
	local s = ""
	for i = 0, (n or 16) - 1 do s = s .. string.format("%02X", (data[(base or 0x8154) + i] or 0) & 0xFF) end
	return s
end
local function push(code, label, hold, gap)
	keys[#keys + 1] = { code = code, label = label, hold = hold or 12000, gap = gap or 12000 }
end
local function sample(tag)
	local l, s = lenvar(), slen()
	if s > maxslen then maxslen = s end
	if l > maxlen then maxlen = l end
	print(string.format("S %-14s len=%3d slen=%3d head=%s pc=%04X", tag, l, s, bdump(12), cpu.pc & 0xFFFF))
end
local function nz(a, b)
	local n = 0
	for i = a, b do if (data[i] or 0) ~= 0 then n = n + 1 end end
	return n
end

local FILL = { 0x00, 0x10, 0x20, 0x01, 0x11, 0x21, 0x02, 0x12, 0x22, 0x64, 0x63, 0x30, 0x40, 0x31, 0x41, 0x62 }

-- warm-up: verify input path lands
push(AC, "warmAC"); push(0x00, "warmK1"); push(AC, "warmAC2")
-- Phase A: 150 fillers
for i = 1, 150 do push(FILL[(i - 1) % #FILL + 1], string.format("F%03d", i)) end
-- Phase B: at-cap probes
push(LEFT, "B-left1"); push(LEFT, "B-left2"); push(LEFT, "B-left3"); push(0x00, "B-midK1")
push(DEL, "B-del"); push(0x00, "B-afterdel")
push(SHIFT, "B-shift"); push(DEL, "B-ins?"); push(0x00, "B-afterins")
push(AC, "B-ac")
-- Phase C: history/RCL
push(0x00, "C-1"); push(0x30, "C-plus"); push(0x10, "C-2"); push(EXE, "C-EXE"); push(AC, "C-ac")
for i = 1, 45 do push(FILL[(i - 1) % #FILL + 1], string.format("C%03d", i)) end
local RCLC = { 0x40, 0x30, 0x62, 0x63, 0x61, 0x41, 0x31, 0x60, 0x64 }
for _, c in ipairs(RCLC) do
	push(AC, "C-ac" .. string.format("%02X", c))
	for i = 1, 40 do push(FILL[(i - 1) % #FILL + 1], string.format("Cf%02X-%02d", c, i)) end
	push(SHIFT, "C-sh" .. string.format("%02X", c)); push(c, "C-rcl?" .. string.format("%02X", c))
	push(LEFT, "C-l"); push(LEFT, "C-l2"); push(SHIFT, "C-sh2" .. string.format("%02X", c)); push(c, "C-rclmid" .. string.format("%02X", c))
	for i = 1, 12 do push(FILL[(i - 1) % #FILL + 1], string.format("Cp%02X-%02d", c, i)) end
end
-- Phase D marker
push(AC, "D-ac")

addposttick(function()
	T = T + 1
	if state == "idle" then
		ki = ki + 1
		if ki > #keys then
			print(string.format("DONE: maxlen=%d maxslen=%d final len=%d slen=%d", maxlen, maxslen, lenvar(), slen()))
			print("DUMP 8100-81FF: " .. bdump(0x100, 0x8100))
			print("DUMP 8200-82FF: " .. bdump(0x100, 0x8200))
			print("DUMP 8300-83FF: " .. bdump(0x100, 0x8300))
			print(string.format("NZ 829E-82CE=%d 81B8-829D=%d 8100-8153=%d", nz(0x829E, 0x82CE), nz(0x81B8, 0x829D), nz(0x8100, 0x8153)))
			local f = io.open(OUT .. "cap_dump.bin", "wb")
			local parts = {}
			for a = 0x8100, 0x8DFF do parts[#parts + 1] = string.char((data[a] or 0) & 0xFF) end
			f:write(table.concat(parts)); f:close()
			print("DUMP file /tmp/mb01_cap_dump.bin (0x8100-0x8DFF)")
			emu:set_paused(true)
			state = "done"
			return
		end
		cur = keys[ki]
		Keyboard:PressKey(cur.code)
		state = "press"; hold_t = cur.hold
	elseif state == "press" then
		hold_t = hold_t - 1
		if hold_t <= 0 then
			Keyboard:ReleaseAll()
			state = "rel"; gap_t = cur.gap
		end
	elseif state == "rel" then
		gap_t = gap_t - 1
		if gap_t <= 0 then
			local lb = cur.label or "?"
			if lb:sub(1, 1) == "F" or lb:sub(1, 1) == "B" or lb:sub(1, 2) == "C-" or lb:sub(1, 2) == "Cf" or lb:sub(1, 2) == "Cp" or lb:sub(1, 6) == "C-rcl?" or lb:sub(1, 7) == "C-rclmi" or lb:sub(1, 4) == "warm" then
				sample(lb)
			end
			state = "idle"
		end
	end
end)
