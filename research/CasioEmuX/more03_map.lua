-- more03_map.lua: pre-trigger RAM map of coexisting typed strings.
-- Types 3 distinct strings with EXE between (history), AC+RCL, UP browse,
-- then dumps RAM 0x8000-0x8DFF and prints region hex + marker-run scan.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
emu:SetClockSpeed(8)

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, UP, RCL, K1, K2, K9 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x27, 0x17, 0x00, 0x10, 0x22
local OUT = "/home/yoxu/Projects/fx991espplus2nd/research/CasioEmuX/"

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t = "type", 0

local function blen()
	for i = 0, 99 do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 100
end
local function bdump(n)
	local s = ""
	for i = 0, (n or 32) - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end
	return s
end
local function slen(a) -- strlen from a up to 0x8DFF
	for i = 0, 0x8DFF - a do if (data[a + i] or 0) == 0 then return i end end
	return 0x8DFF - a + 1
end
local function hex(a, n)
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02X", (data[a + i] or 0) & 0xFF) end
	return s
end
local function push(code, label, hold, gap)
	keys[#keys + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 16000 }
end

-- warm-up
push(SHIFT, "w1", 12000, 12000); push(AC, "w2", 12000, 24000)
-- string A: 20 x '1' (token 0x31), EXE
for i = 1, 20 do push(K1, "A" .. i) end
push(EXE, "exeA", 20000, 30000)
-- AC, string B: 20 x '2' (0x32), EXE
push(AC, "acB"); for i = 1, 20 do push(K2, "B" .. i) end
push(EXE, "exeB", 20000, 30000)
-- AC, string C: 20 x '9' (0x39), EXE
push(AC, "acC"); for i = 1, 20 do push(K9, "C" .. i) end
push(EXE, "exeC", 20000, 30000)
-- AC, RCL, UP x2
push(AC, "acR"); push(RCL, "rcl", 16000, 30000)
push(UP, "up1", 16000, 30000); push(UP, "up2", 16000, 30000)

local function report(tag)
	print(string.format("MAP[%s]: in.len=%d buf=%s", tag, blen(), bdump(48)))
	print(string.format("MAP[%s]: 8184(%d)=%s", tag, slen(0x8184), hex(0x8184, 40)))
	print(string.format("MAP[%s]: 81B8(%d)=%s", tag, slen(0x81B8), hex(0x81B8, 40)))
	print(string.format("MAP[%s]: 85AA(%d)=%s", tag, slen(0x85AA), hex(0x85AA, 40)))
	print(string.format("MAP[%s]: 829E(%d)=%s", tag, slen(0x829E), hex(0x829E, 40)))
	print(string.format("MAP[%s]: 8230(%d)=%s", tag, slen(0x8230), hex(0x8230, 40)))
	print(string.format("MAP[%s]: 812C=%04X 812E=%04X 8113=%02X 8114=%02X 80F5=%02X",
		tag, data[0x812C] | (data[0x812D] or 0) << 8, data[0x812E] | (data[0x812F] or 0) << 8,
		data[0x8113] or 0, data[0x8114] or 0, data[0x80F5] or 0))
end

addposttick(function()
	T = T + 1
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "final"
				print("INPUT: typing done len=" .. blen() .. " buf=" .. bdump(48))
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
				local lb = cur.label
				if lb == "exeA" or lb == "exeB" or lb == "exeC" or lb == "acB" or lb == "acC"
					or lb == "acR" or lb == "rcl" or lb == "up1" or lb == "up2" then
					report(lb)
				end
				state = "idle"
			end
		end
	elseif phase == "final" then
		final_t = final_t + 1
		if final_t == 1 then
			report("FINAL")
			-- full RAM dump
			local f = io.open(OUT .. "more03_map_dump.bin", "wb")
			for a = 0x8000, 0x8DFF do f:write(string.char((data[a] or 0) & 0xFF)) end
			f:close()
			print("MAP: dumped 0x8000-0x8DFF to more03_map_dump.bin")
			-- marker-run scan: runs of 0x31/0x32/0x39 length>=6
			for _, m in ipairs({ 0x31, 0x32, 0x39 }) do
				local a = 0x8000
				while a <= 0x8DFF do
					if (data[a] or 0) == m then
						local b = a
						while b <= 0x8DFF and (data[b] or 0) == m do b = b + 1 end
						if b - a >= 6 then
							print(string.format("MAP: run %02X at %04X-%04X len=%d", m, a, b - 1, b - a))
						end
						a = b
					else a = a + 1 end
				end
			end
			-- region hex dump
			for _, r in ipairs({ 0x8100, 0x8200, 0x8300, 0x8400, 0x8500, 0x8600, 0x87D0, 0x8C00 }) do
				print(string.format("MAP: %04X: %s", r, hex(r, 96)))
			end
			print(string.format("MAP: pc=%04X sp=%04X", cpu.pc, cpu.sp))
			emu:set_paused(true)
			phase = "done"
		end
	end
end)
