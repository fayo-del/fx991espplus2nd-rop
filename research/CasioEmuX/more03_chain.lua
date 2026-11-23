-- more03_chain.lua: does a NON-ZERO cache 0x81B8 (last EXE'd string) extend the
-- flood unit beyond 100? Type string A (digits), EXE (stash cache), AC (cache
-- survives), plant 100-byte payload B at 0x8154, fire Right/Left/EXE trigger,
-- dump RAM, compute minimal flood period + unit, check unit == B + A.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
emu:SetClockSpeed(8)

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT, K1, K2, K3, K4, K5, K6, K7, K8, K9 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37,
	0x00, 0x10, 0x20, 0x01, 0x11, 0x21, 0x02, 0x12, 0x22
local DIG = { K1, K2, K3, K4, K5, K6, K7, K8, K9 }  -- tokens 0x31..0x39
local PAY_IN = 0x8154
local OUT = "/home/yoxu/Projects/fx991espplus2nd/research/CasioEmuX/"

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t = "type", 0
local scan_hits = 0

local function blen()
	for i = 0, 99 do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 100
end
local function slen(a)
	for i = 0, 0x8DFF - a do if (data[a + i] or 0) == 0 then return i end end
	return 0x8DFF - a + 1
end
local function hex(a, n)
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02X", (data[a + i] or 0) & 0xFF) end
	return s
end
local function bdump(n)
	local s = ""
	for i = 0, (n or 32) - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end
	return s
end
local function push(code, label, hold, gap)
	keys[#keys + 1] = { code = code, label = label, hold = hold or 12000, gap = gap or 10000 }
end

-- warm-up
push(SHIFT, "w1", 12000, 12000); push(AC, "w2", 12000, 24000)
-- string A: 70 cycling digits -> tokens 0x31..0x39 (zero-free)
for i = 1, 70 do push(DIG[(i - 1) % 9 + 1], "A" .. i) end
push(EXE, "exeA", 20000, 30000)
push(AC, "acA", 16000, 24000)

local function report(tag)
	print(string.format("CH[%s]: in.len=%d buf=%s", tag, blen(), bdump(24)))
	print(string.format("CH[%s]: cache 81B8 len=%d: %s", tag, slen(0x81B8), hex(0x81B8, 72)))
	print(string.format("CH[%s]: 8184 len=%d 85AA len=%d 829E: %s", tag, slen(0x8184), slen(0x85AA), hex(0x829E, 32)))
	print(string.format("CH[%s]: 8230: %s | 8398: %s | 812C=%04X 8114=%02X 80F5=%02X pc=%04X",
		tag, hex(0x8230, 24), hex(0x8398, 24), data[0x812C] | (data[0x812D] or 0) << 8,
		data[0x8114] or 0, data[0x80F5] or 0, cpu.pc))
end

break_at(0x4D20, function()
	scan_hits = scan_hits + 1
	if scan_hits <= 3 or scan_hits % 10 == 0 then
		print(string.format("CHAIN: hop=%d pc=%04X sp=%04X", scan_hits, cpu.pc, cpu.sp))
	end
	emu:set_paused(false)
end)

local planted = false
addposttick(function()
	T = T + 1
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "final"
				print("INPUT: typing done len=" .. blen() .. " buf=" .. bdump(24))
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
				if cur.label == "exeA" or cur.label == "acA" then report(cur.label) end
				state = "idle"
			end
		end
	elseif phase == "final" then
		final_t = final_t + 1
		if final_t == 1 then
			report("final-start")
			Keyboard:PressKey(RIGHT)
		elseif final_t == 16001 then
			Keyboard:ReleaseAll()
		elseif final_t == 20001 then
			Keyboard:PressKey(LEFT)
		elseif final_t == 36001 then
			Keyboard:ReleaseAll()
			-- plant payload B: 100 zero-free bytes (0E4D flood + distinct marker words)
			for e = 0, 49 do data[PAY_IN + e * 2] = 0x0E; data[PAY_IN + e * 2 + 1] = 0x4D end
			local function W(off, v) data[PAY_IN + off] = v & 0xFF; data[PAY_IN + off + 1] = (v >> 8) & 0xFF end
			W(48, 0x3538) W(50, 0x3538) W(52, 0xF801) W(54, 0x35BE) W(56, 0x8154)
			planted = true
			print(string.format("PLANT: B in. strlen(0x8154)=%d (cache len=%d) buf=%s cache=%s",
				slen(0x8154), slen(0x81B8), bdump(24), hex(0x81B8, 24)))
		elseif final_t == 40001 then
			Keyboard:PressKey(EXE)
		elseif final_t == 60001 then
			Keyboard:ReleaseAll()
			emu:SetClockSpeed(16)
			print(string.format("WATCH: start t=%d pc=%04X sp=%04X strlen8154=%d hits=%d", final_t, cpu.pc, cpu.sp, slen(0x8154), scan_hits))
		elseif final_t > 60001 then
			if (final_t - 60001) % 200000 == 0 then
				local tiled = 0
				for a = 0x8240, 0x8DF8 do
					if (data[a] or 0) == 0x4D and (data[a - 1] or 0) == 0x0E then tiled = tiled + 1 end
				end
				print(string.format("WATCH: t=%d pc=%04X sp=%04X tiles=%d hits=%d strlen8154=%d",
					final_t, cpu.pc, cpu.sp, tiled, scan_hits, slen(0x8154)))
			end
			if scan_hits >= 10 or final_t > 2600000 then
				-- dump + period analysis
				local f = io.open(OUT .. "more03_chain_dump.bin", "wb")
				local d = {}
				for a = 0x8154, 0x8DFF do
					d[a] = (data[a] or 0) & 0xFF
					f:write(string.char(d[a]))
				end
				f:close()
				print(string.format("DUMP: hits=%d pc=%04X sp=%04X strlen8154=%d -> more03_chain_dump.bin", scan_hits, cpu.pc, cpu.sp, slen(0x8154)))
				-- minimal period over 0x8154..0x8DFF
				local N = 0x8DFF - 0x8154 + 1
				local function period(p)
					for i = 0, N - 1 - p do
						if d[0x8154 + i] ~= d[0x8154 + i + p] then return false end
					end
					return true
				end
				local per = -1
				for p = 1, 600 do if period(p) then per = p; break end end
				print(string.format("DUMP: minimal period=%d", per))
				if per > 0 then
					print(string.format("DUMP: unit[0..%d]=%s", math.min(per - 1, 219), hex(0x8154, math.min(per, 220))))
					local set = {}
					for i = 0, per - 1 do set[d[0x8154 + i]] = true end
					local nv = 0
					for _ in pairs(set) do nv = nv + 1 end
					print(string.format("DUMP: unit len=%d distinct byte values=%d", per, nv))
					-- compare unit tail vs cache content (A)
					print(string.format("DUMP: cache now: %s", hex(0x81B8, 72)))
				end
				emu:set_paused(true)
				phase = "done"
			end
		end
	end
end)
