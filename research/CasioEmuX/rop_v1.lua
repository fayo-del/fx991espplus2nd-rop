-- V1: typed fill to strlen(0x8154) >= 100, then [AC][<-][EXE] trigger.
-- Head = E3/E4-verbatim. Typing = rounds of 12 digits + 4 Sigma( chords,
-- with margin-mode attempts when growth stalls (every typable token class).
-- Instrumentation: per-key landing log, 0x6B58 (strcpy inner) arg logger,
-- 0x4D20/0x3538/0x35BE/0x2B1E hit counters, RAM tile scan, LCD dump.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37
local K1, K2, K9, KX10 = 0x00, 0x10, 0x22, 0x62
local K8, K5 = 0x12, 0x11
local M56 = 0x56   -- Sigma( key
local M46 = 0x46   -- x^box template (21 5E B8 60 31 B9)
local M16 = 0x16   -- SHIFT: d/dx( (6B B8 ...)
local M30 = 0x30   -- SHIFT: Pol(
local M62 = 0x62   -- alpha: e (81)

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase = "type"
local typeticks = 0
local no_grow = 0
local landed_log = {}
local last_len = -1
local max_len = 0

local function blen() for i = 0, 299 do if (data[0x8154 + i] or 0) == 0 then return i end end return 300 end
local function bdump(lo, n) local s = "" for i = lo, lo + n - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end return s end
local function push(code, label, hold, gap) keys[#keys + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 16000 } end
local function chord(mod, code, label) push(mod, label .. "/mod"); push(code, label) end

-- ===== head: e2e/E3-verbatim =====
push(SHIFT, "w1", 12000, 12000); push(AC, "w2", 12000, 24000)
chord(SHIFT, MODE, "setup1"); push(K2, "setup1-2", 30000, 40000)
chord(SHIFT, 0x56, "sigv1")
chord(SHIFT, MODE, "setup2"); push(K2, "setup2-2", 30000, 40000)
chord(SHIFT, 0x56, "sigv2"); push(AC, "AC-clear", 16000, 24000)
chord(ALPHA, 0x33, "X1"); chord(ALPHA, CALC, "eq"); chord(SHIFT, 0x56, "Sigma")
chord(ALPHA, 0x33, "X2"); chord(SHIFT, 0x33, "comma1"); push(K1, "one")
chord(SHIFT, 0x33, "comma2"); push(K1, "one2"); push(KX10, "x10"); push(K9, "nine")
push(CALC, "CALC", 16000, 24000); push(EXE, "EXE", 24000, 30000)
push(AC, "AC", 16000, 24000); push(LEFT, "LEFT", 16000, 16000)
push(DEL, "DEL1"); push(DEL, "DEL2"); push(DEL, "DEL3")
push(K2, "two"); push(CALC, "CALC2", 16000, 24000); push(EXE, "EXE2", 24000, 30000)
push(LEFT, "LEFT2", 16000, 20000)
push(K1, "PROBE1", 16000, 16000)
push(AC, "AC-f", 16000, 24000); push(LEFT, "LEFT-f", 16000, 20000)

-- ===== typed fill: 30 rounds x (12 digits + 4 Sigma chords) =====
for round = 1, 30 do
	for i = 1, 12 do push(round % 2 == 1 and K8 or K5, "d" .. round .. "-" .. i) end
	for i = 1, 4 do chord(SHIFT, 0x56, "s" .. round .. "-" .. i) end
end
-- ===== margin mode: alternate token classes to land the last bytes =====
for cycle = 1, 12 do
	if cycle % 3 == 1 then push(K1, "m-d1-" .. cycle)
	elseif cycle % 3 == 2 then push(M46, "m-xbox-" .. cycle)
	else chord(SHIFT, 0x56, "m-sigma-" .. cycle) end
	if cycle % 4 == 0 then push(K8, "m-d8-" .. cycle); push(K5, "m-d5-" .. cycle) end
	if cycle % 4 == 2 then chord(SHIFT, M16, "m-ddx-" .. cycle) end
end

local hit = {}
local function note(a) hit[a] = (hit[a] or 0) + 1 end
local strcpy_logs = 0
local function er(hi, lo) return ((hi & 0xFF) << 8) | (lo & 0xFF) end
local function slen(base, max)
	local n = 0
	while n < (max or 64) and (data[base + n] or 0) ~= 0 do n = n + 1 end
	return n
end
local function arm_strcpy_logger()
	break_at(0x6B62, function()
		if strcpy_logs < 160 then
			local d, s = er(cpu.r1, cpu.r0), er(cpu.r3, cpu.r2)
			print(string.format("STRCPY: dst=%04X src=%04X lr=%04X sp=%04X srclen=%d", d, s, cpu.lr, cpu.sp, slen(s)))
			strcpy_logs = strcpy_logs + 1
		end
		note("strcpy")
		if strcpy_logs >= 160 then unbreak_at(0x6B62) end
		emu:set_paused(false)
	end)
end
break_at(0x4D20, function() note("k4d20"); emu:set_paused(false) end)
break_at(0x3538, function() note("k3538"); emu:set_paused(false) end)
break_at(0x35BE, function() note("k35be"); emu:set_paused(false) end)
break_at(0x2B1E, function() note("k2b1e"); emu:set_paused(false) end)

local final_t = 0
local fill_done = false
addposttick(function()
	if phase == "type" then
		typeticks = typeticks + 1
		if state == "idle" and not fill_done then
			local n = blen()
			if n > max_len then max_len = n end
			if last_len >= 0 then
				if n ~= last_len then
					landed_log[#landed_log + 1] = (cur and cur.label or "?") .. ":" .. last_len .. "->" .. n
					no_grow = 0
				else
					no_grow = no_grow + 1
				end
			end
			last_len = n
			if n >= 100 or no_grow >= 60 then
				fill_done = true
				print(string.format("FILL: done len=%d maxlen=%d keys=%d", blen(), max_len, ki))
				print("FILL: landed(" .. #landed_log .. ") " .. table.concat(landed_log, " ", 1, math.min(#landed_log, 120)))
				print("FILL: buf " .. bdump(0, 112))
				local cache = ""
				for i = 0, 99 do cache = cache .. string.format("%02X", data[0x81B8 + i] or 0) end
				print("FILL: cache " .. cache:sub(1, 96))
				-- trigger: AC, LEFT, EXE x2 (wiki sequence)
				push(AC, "TRIG-AC", 16000, 24000)
				push(LEFT, "TRIG-LEFT", 16000, 20000)
				push(EXE, "TRIG-EXE", 24000, 30000)
				push(EXE, "TRIG-EXE2", 24000, 30000)
			end
		end
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "watch"; final_t = 0
				emu:SetClockSpeed(8)
				print("WATCH: 8x typing exhausted without trigger")
				return
			end
			cur = keys[ki]
			if cur.mod then Keyboard:PressKey(cur.mod); state = "mod"; hold_t = 6000
			else Keyboard:PressKey(cur.code); state = "press"; hold_t = cur.hold end
		elseif state == "mod" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:PressKey(cur.code); state = "press"; hold_t = cur.hold end
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:ReleaseAll(); state = "rel"; gap_t = cur.gap end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then
				state = "idle"
				if cur.label == "PROBE1" then print(string.format("PROBE1: len=%d", blen())) end
				if cur.label and cur.label:sub(1, 4) == "TRIG" then
					if cur.label == "TRIG-LEFT" then arm_strcpy_logger() end
					print(string.format("TRIGKEY: %s len=%d bufhead=%s", cur.label, blen(), bdump(0, 8)))
					if cur.label == "TRIG-EXE2" then
						phase = "watch"
						final_t = 0
						emu:SetClockSpeed(8)
						print("WATCH: 8x trigger done len=" .. blen())
						return
					end
				end
			end
		end

	elseif phase == "watch" then
		final_t = final_t + 1
		if final_t % 100000 == 0 then
			local tiled = 0
			for a = 0x8240, 0x8DFB do
				local v = (data[a] or 0)
				if v > 0x30 then tiled = tiled + 1 end
			end
			print(string.format("WATCH: t=%d pc=%04X sp=%04X lr=%04X len=%d tiles=%d h={2b1e:%d 3538:%d 35be:%d 4d20:%d str:%d}",
				final_t, cpu.pc, cpu.sp, cpu.lr, blen(), tiled,
				hit.k2b1e or 0, hit.k3538 or 0, hit.k35be or 0, hit.k4d20 or 0, hit.strcpy or 0))
		end
		if final_t >= 3000000 then
			print(string.format("END: pc=%04X sp=%04X lr=%04X h={2b1e:%d 3538:%d 35be:%d 4d20:%d str:%d}",
				cpu.pc, cpu.sp, cpu.lr, hit.k2b1e or 0, hit.k3538 or 0, hit.k35be or 0, hit.k4d20 or 0, hit.strcpy or 0))
			local rows = {}
			for rr = 0, 11 do
				local s2 = ""
				for i = 0, 11 do s2 = s2 .. string.format("%02X", data[0xF800 + rr * 16 + i]) end
				rows[#rows + 1] = s2
			end
			print("LCD: " .. table.concat(rows, " | "))
			local tail = ""
			for a = 0x8C40, 0x8EBF do tail = tail .. string.format("%02X", data[a] or 0) end
			print("STACK: " .. tail)
			emu:set_paused(true)
			phase = "done"
		end
	end
end)
