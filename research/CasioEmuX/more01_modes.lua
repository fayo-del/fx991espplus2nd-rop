-- MORE01 MODES: for each MODE-menu digit 1-9, enter the mode, type 100 filler
-- keys, and measure max strlen at 0x8154 + where input bytes land (region nz
-- counts). Also one SETUP (SHIFT+MODE,2) LineIO attempt with a Sigma probe.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
emu:SetClockSpeed(8)

local T = 0
local SHIFT, ALPHA, MODE, EXE, AC, DEL, LEFT, DOWN = 0x07,0x17,0x47,0x60,0x42,0x32,0x26,0x36

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil

local function slen()
	for i = 0, 0x1AC do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 0x1AD
end
local function bdump(n, base)
	local s = ""
	for i = 0, (n or 16) - 1 do s = s .. string.format("%02X", (data[(base or 0x8154) + i] or 0) & 0xFF) end
	return s
end
local function push(code, label, hold, gap)
	keys[#keys + 1] = { code = code, label = label, hold = hold or 26000, gap = gap or 10000 }
end
local function nz(a, b)
	local n = 0
	for i = a, b do if (data[i] or 0) ~= 0 then n = n + 1 end end
	return n
end
local function st()
	return string.format("F5=%02X FC=%02X FD=%02X FE=%02X 1F=%02X", data[0x80F5] or 0, data[0x80FC] or 0, data[0x80FD] or 0, data[0x80FE] or 0, data[0x811F] or 0)
end
local maxs = -1
local function sample(tag)
	local s = slen()
	if s > maxs then maxs = s end
	print(string.format("SW %-10s slen=%3d len=%3d head=%s st %s", tag, s, (data[0x8114] or 0) & 0xFF, bdump(10), st()))
end
local function regions(tag)
	print(string.format("RG %-10s nz: 8100-53=%d 8154-B7=%d 81B8-29D=%d 829E-2CE=%d 82CF-3FF=%d 8400-5FF=%d 8600-8DFF=%d",
		tag, nz(0x8100,0x8153), nz(0x8154,0x81B7), nz(0x81B8,0x829D), nz(0x829E,0x82CE), nz(0x82CF,0x83FF), nz(0x8400,0x85FF), nz(0x8600,0x8DFF)))
end

local FILL = { 0x00, 0x10, 0x20, 0x01, 0x11, 0x21, 0x02, 0x12, 0x22, 0x64, 0x63, 0x30, 0x40, 0x31, 0x41, 0x62 }

-- warm-up
push(AC, "warmAC"); push(0x00, "warmK1"); push(AC, "warmAC2")
-- SETUP attempt (LineIO): SHIFT MODE 2, then Sigma probe
push(SHIFT, "SU-sh"); push(MODE, "SU-mode"); push(0x10, "SU-2")
push(SHIFT, "SU-sh2"); push(0x56, "SU-sigma"); push(AC, "SU-ac")
-- RCL phase: store 1+2 via EXE, then paste tests
push(0x00, "R-1"); push(0x30, "R-plus"); push(0x10, "R-2"); push(EXE, "R-EXE"); push(AC, "R-ac")
push(SHIFT, "R-sh"); push(0x40, "R-rcl40")          -- SHIFT+(-) = RCL?
push(AC, "R-ac2")
push(SHIFT, "R-sh2"); push(0x60, "R-rcl60")          -- SHIFT+EXE = ANS?
push(AC, "R-ac3")
for i = 1, 90 do push(FILL[(i - 1) % #FILL + 1], string.format("R%03d", i)) end
push(LEFT, "R-l1"); push(LEFT, "R-l2"); push(LEFT, "R-l3"); push(LEFT, "R-l4"); push(LEFT, "R-l5")
push(SHIFT, "R-sh3"); push(0x40, "R-midrcl")
for i = 1, 12 do push(FILL[(i - 1) % #FILL + 1], string.format("Rp%02d", i)) end
-- modes 1..9 via bare MODE + digit
local DIG = { 0x00, 0x10, 0x20, 0x01, 0x11, 0x21, 0x02, 0x12, 0x22 }
for mi, d in ipairs(DIG) do
	push(MODE, "M-mode" .. mi)
	push(d, "M-d" .. string.format("%02X", d))
	push(AC, "M-acb" .. mi)
	for i = 1, 105 do push(FILL[(i - 1) % #FILL + 1], string.format("M%d-%03d", mi, i)) end
	push(AC, "M-end" .. mi)
end

addposttick(function()
	T = T + 1
	if state == "idle" then
		ki = ki + 1
		if ki > #keys then
			print(string.format("DONE modes: global maxslen=%d", maxs))
			print("DONE modes")
			regions("final")
			local f = io.open("/tmp/mb01_modes_dump.bin", "wb")
			local parts = {}
			for a = 0x8100, 0x8DFF do parts[#parts + 1] = string.char((data[a] or 0) & 0xFF) end
			f:write(table.concat(parts)); f:close()
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
			if lb:sub(1, 2) == "SU" or lb:sub(1, 2) == "R-" or lb:sub(1, 1) == "R" or lb:sub(1, 4) == "M-ac" or lb:sub(1, 5) == "M-mod" or lb:sub(1, 4) == "M-acb" or lb:sub(1, 2) == "M-" and lb:sub(4, 4) == "d" or lb:sub(1, 5) == "M-end" or lb:sub(1, 4) == "warm" then
				sample(lb)
			end
			local m = lb:match("^M(%d+)-(%d+)$")
			if m then
				local n = tonumber(m[2])
				if n % 25 == 0 then sample(lb) end
				if n == 105 then regions("M" .. m[1]) end
			end
			state = "idle"
		end
	end
end)
