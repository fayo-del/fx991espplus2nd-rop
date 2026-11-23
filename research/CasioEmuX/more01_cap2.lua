-- MORE01 CAP2: reach the true typed cap at 0x8154 (MathIO) with reliable key
-- delivery (hold 30000), then probe every bypass candidate at the cap:
-- middle-insert (LEFT+key), DEL+key, INS (SHIFT+DEL)+key, AC, and RCL/ANS
-- pastes (SHIFT+candidates) at cap and mid-line. Dumps regions + file.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
emu:SetClockSpeed(8)

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT, UP, DOWN = 0x07,0x17,0x47,0x06,0x60,0x42,0x32,0x26,0x37,0x27,0x36
local OUT = "/tmp/mb01_"

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local maxlen, maxslen = -1, -1
local stall = 0

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
	keys[#keys + 1] = { code = code, label = label, hold = hold or 30000, gap = gap or 12000 }
end
local function sample(tag)
	local l, s = lenvar(), slen()
	if s > maxslen then maxslen = s end
	if l > maxlen then maxlen = l end
	print(string.format("S %-12s len=%3d slen=%3d head=%s tail=%s pc=%04X", tag, l, s, bdump(10), bdump(10, 0x8154 + math.max(0, s - 10)), cpu.pc & 0xFFFF))
end
local function nz(a, b)
	local n = 0
	for i = a, b do if (data[i] or 0) ~= 0 then n = n + 1 end end
	return n
end

local FILL = { 0x00, 0x10, 0x20, 0x01, 0x11, 0x21, 0x02, 0x12, 0x22, 0x64, 0x63, 0x30, 0x40, 0x31, 0x41, 0x62 }

-- warm-up
push(AC, "warmAC"); push(0x00, "warmK1"); push(AC, "warmAC2"); push(0x00, "warmK1b")
-- Phase A: fillers until stall (160 max)
for i = 1, 160 do push(FILL[(i - 1) % #FILL + 1], string.format("F%03d", i), 30000, 12000) end
-- Phase B: at-cap probes
push(LEFT, "B-l1"); push(LEFT, "B-l2"); push(LEFT, "B-l3"); push(0x00, "B-midK1")
push(DEL, "B-del"); push(0x00, "B-afterdel")
push(SHIFT, "B-sh"); push(DEL, "B-ins"); push(0x00, "B-afterins")
push(AC, "B-ac"); push(0x00, "B-afterac")
-- Phase C: history + RCL candidates at/near cap
push(0x00, "C-1"); push(0x30, "C-plus"); push(0x10, "C-2"); push(EXE, "C-EXE"); push(AC, "C-ac0")
for i = 1, 90 do push(FILL[(i - 1) % #FILL + 1], string.format("C%03d", i), 30000, 12000) end
local RCLC = { 0x40, 0x30, 0x62, 0x63, 0x61, 0x41, 0x31, 0x60, 0x64 }
for _, c in ipairs(RCLC) do
	push(SHIFT, "C-sh" .. string.format("%02X", c)); push(c, "C-rcl" .. string.format("%02X", c))
end
-- now refill to cap and paste mid-line
for i = 1, 90 do push(FILL[(i - 1) % #FILL + 1], string.format("D%03d", i), 30000, 12000) end
push(LEFT, "D-l1"); push(LEFT, "D-l2"); push(LEFT, "D-l3"); push(LEFT, "D-l4"); push(LEFT, "D-l5")
for _, c in ipairs(RCLC) do
	push(SHIFT, "D-sh" .. string.format("%02X", c)); push(c, "D-midrcl" .. string.format("%02X", c))
	for i = 1, 6 do push(FILL[(i - 1) % #FILL + 1], string.format("Dp%02X-%02d", c, i), 30000, 12000) end
end
push(AC, "Z-ac")

addposttick(function()
	T = T + 1
	if state == "idle" then
		ki = ki + 1
		if ki > #keys then
			print(string.format("DONE: maxlen=%d maxslen=%d final len=%d slen=%d", maxlen, maxslen, lenvar(), slen()))
			print("DUMP 8100-81FF: " .. bdump(0x100, 0x8100))
			print("DUMP 8280-837F: " .. bdump(0x100, 0x8280))
			print(string.format("NZ 829E-82CE=%d 81B8-829D=%d", nz(0x829E, 0x82CE), nz(0x81B8, 0x829D)))
			print("2NDLINE 829E-82CE: " .. bdump(0x31, 0x829E))
			local f = io.open(OUT .. "cap2_dump.bin", "wb")
			local parts = {}
			for a = 0x8100, 0x8DFF do parts[#parts + 1] = string.char((data[a] or 0) & 0xFF) end
			f:write(table.concat(parts)); f:close()
			print("DUMP file /tmp/mb01_cap2_dump.bin")
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
			local c1 = lb:sub(1, 1)
			if c1 == "F" or c1 == "B" or c1 == "C" or c1 == "D" or c1 == "w" or c1 == "Z" then
				sample(lb)
			end
			state = "idle"
		end
	end
end)
