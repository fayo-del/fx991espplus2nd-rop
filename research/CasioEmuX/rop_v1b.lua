-- V1b: close the 1-byte gap (typed cap len=99, need 100).
-- Stage A: SETUP menu probes with screens (does digit-2 take? LineIO byte tell).
-- Stage B: e2e-head typed fill (30 rounds digits+Sigma chords).
-- Stage C: margin mode at cap - every typoable token class + walks, sampled.
-- Stage D: [AC][<-][EXE][EXE] trigger w/ uncapped strcpy logger (dst/src/true len
--          + 12 bytes at dst), hit counters, tile scan, cursor-var dump.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37
local K1, K2, K9, KX10 = 0x00, 0x10, 0x22, 0x62
local K8, K5 = 0x12, 0x11

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase = "type"
local no_grow, last_len, max_len, margin_mode = 0, -1, 0, false
local landed_log = {}
local renders = 0

local function blen() for i = 0, 299 do if (data[0x8154 + i] or 0) == 0 then return i end end return 300 end
local function bdump(lo, n) local s = "" for i = lo, lo + n - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end return s end
local function push(code, label, hold, gap) keys[#keys + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 16000 } end
local function chord(mod, code, label) push(mod, label .. "/mod"); push(code, label) end
local function render(tag)
	keys[#keys + 1] = { render = tag }
end

-- ===== Stage A: SETUP probes =====
push(SHIFT, "w1", 12000, 12000); push(AC, "w2", 12000, 24000)
push(SHIFT, "a1-mod", 30000, 30000); push(MODE, "a1-MODE", 30000, 40000)
render("A-setup1")
push(K2, "a1-2", 30000, 40000)
render("A-setup1-2")
chord(SHIFT, 0x56, "a1-sigv")     -- 8 bytes boxed => MathIO; 2 bytes => LineIO
push(AC, "A-AC", 16000, 24000)
push(SHIFT, "a2-mod", 30000, 30000); push(MODE, "a2-MODE", 30000, 40000)
render("A-setup2")
push(K2, "a2-2a", 30000, 30000); push(K2, "a2-2b", 30000, 40000)
render("A-setup2-2")
chord(SHIFT, 0x56, "a2-sigv")
push(AC, "B-AC", 16000, 24000)

-- ===== Stage B: e2e head + fill =====
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
for round = 1, 30 do
	for i = 1, 12 do push(round % 2 == 1 and K8 or K5, "d" .. round .. "-" .. i) end
	for i = 1, 4 do chord(SHIFT, 0x56, "s" .. round .. "-" .. i) end
end
-- ===== Stage C margin keys (appended; sampled per key) =====
local margin = {}
local function mp(code, label, mod) margin[#margin + 1] = { code = code, label = label, mod = mod } end
mp(K1, "m-1"); mp(K8, "m-8"); mp(K5, "m-5")
mp(0x46, "m-xbox")
mp(SHIFT, "m-sig/mod", true); mp(0x56, "m-sig")
mp(SHIFT, "m-ddx/mod", true); mp(0x16, "m-ddx")
mp(SHIFT, "m-pol/mod", true); mp(0x30, "m-pol")
mp(SHIFT, "m-rec/mod", true); mp(0x40, "m-rec")
mp(0x56, "m-log2")
mp(SHIFT, "m-ran/mod", true); mp(0x63, "m-ran")
mp(0x61, "m-ans")
mp(ALPHA, "m-X/mod", true); mp(0x33, "m-X")
mp(ALPHA, "m-e/mod", true); mp(0x62, "m-e")
mp(0x62, "m-x10")
mp(SHIFT, "m-com/mod", true); mp(0x33, "m-com")
mp(RIGHT, "m-R"); mp(LEFT, "m-L")
mp(DEL, "m-DEL"); mp(K8, "m-8del")
-- margin blocks: 6 blocks of the above after every 5 fill rounds
for round = 1, 6 do
end

local hit = {}
local function note(a) hit[a] = (hit[a] or 0) + 1 end
local strcpy_logs
local function er(hi, lo) return ((hi & 0xFF) << 8) | (lo & 0xFF) end
local function slen(base, max)
	local n = 0
	while n < (max or 300) and (data[base + n] or 0) ~= 0 do n = n + 1 end
	return n
end
local function arm_strcpy_logger()
	break_at(0x6B62, function()
		if (strcpy_logs or 0) < 120 then
			local d, s = er(cpu.r1, cpu.r0), er(cpu.r3, cpu.r2)
			local dd = {}
			for i = 0, 11 do dd[#dd + 1] = string.format("%02X", data[d + i] or 0) end
			print(string.format("STRCPY: dst=%04X src=%04X lr=%04X sp=%04X srclen=%d dsthead=%s",
				d, s, cpu.lr, cpu.sp, slen(s), table.concat(dd)))
			strcpy_logs = (strcpy_logs or 0) + 1
		end
		note("strcpy")
		if (strcpy_logs or 0) >= 120 then unbreak_at(0x6B62) end
		emu:set_paused(false)
	end)
end
break_at(0x4D20, function() note("k4d20"); emu:set_paused(false) end)
break_at(0x3538, function() note("k3538"); emu:set_paused(false) end)
break_at(0x35BE, function() note("k35be"); emu:set_paused(false) end)
break_at(0x2B1E, function() note("k2b1e"); emu:set_paused(false) end)

local final_t, fill_done = 0, false
local function render_screen(tag)
	print("SCREEN: ---- " .. tag .. " ----")
	for r = 0, 24 do
		local line = ""
		for b = 0, 11 do
			local v = data[0xF800 + r * 16 + b] or 0
			for bit = 7, 0, -1 do line = line .. (((v >> bit) & 1) == 1 and "#" or ".") end
		end
		print("SCREEN: " .. line)
	end
end
local cursorvars = function()
	return string.format("%02X%02X %02X%02X", data[0x8113] or 0, data[0x8114] or 0, data[0x8115] or 0, data[0x8116] or 0)
end
addposttick(function()
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "watch"; final_t = 0
				emu:SetClockSpeed(8)
				print("WATCH: typing exhausted, no trigger")
				return
			end
			cur = keys[ki]
			if cur.render then
				renders = renders + 1
				if renders <= 2 then render_screen(cur.render) end
			else
				if cur.mod then Keyboard:PressKey(cur.mod); state = "mod"; hold_t = 6000
				else Keyboard:PressKey(cur.code); state = "press"; hold_t = cur.hold end
			end
		elseif state == "mod" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:PressKey(cur.code); state = "press"; hold_t = cur.hold end
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:ReleaseAll(); state = "rel"; gap_t = cur.gap end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then
				-- growth check per key
				local n = blen()
				if n > max_len then max_len = n end
				if last_len >= 0 then
					if n ~= last_len then
						if #landed_log < 200 then
							landed_log[#landed_log + 1] = (cur and cur.label or "?") .. ":" .. last_len .. "->" .. n
						end
						no_grow = 0
					else
						no_grow = no_grow + 1
					end
				end
				last_len = n
				if cur.label == "PROBE1" then print(string.format("PROBE1: len=%d curv=%s", n, cursorvars())) end
				if cur.label == "a1-sigv" or cur.label == "a2-sigv" then
					print(string.format("SIGV: %s bytes=%s curv=%s", cur.label, bdump(0, 12), cursorvars()))
				end
				-- append margin keys progressively: when cap detected
				if not fill_done and n >= 100 then
					fill_done = true
					print(string.format("FILL-CAP: len=100+ maxlen=%d keys=%d curv=%s", max_len, ki, cursorvars()))
					push(AC, "TRIG-AC", 16000, 24000); push(LEFT, "TRIG-LEFT", 16000, 20000)
					push(EXE, "TRIG-EXE", 24000, 30000); push(EXE, "TRIG-EXE2", 24000, 30000)
				elseif not fill_done and no_grow == 20 then
					print(string.format("MARGIN: engage at len=%d curv=%s", n, cursorvars()))
					for j = 1, 3 do
						for _, m in ipairs(margin) do
							if m.mod then push(m.mod, m.label .. "/mod"); push(m.code, m.label)
							else push(m.code, m.label) end
						end
					end
					push(AC, "TRIG-AC", 16000, 24000); push(LEFT, "TRIG-LEFT", 16000, 20000)
					push(EXE, "TRIG-EXE", 24000, 30000); push(EXE, "TRIG-EXE2", 24000, 30000)
				end
				if cur.label and cur.label:sub(1, 4) == "TRIG" then
					if cur.label == "TRIG-LEFT" then arm_strcpy_logger() end
					print(string.format("TRIGKEY: %s len=%d curv=%s bufhead=%s", cur.label, blen(), cursorvars(), bdump(0, 8)))
					if cur.label == "TRIG-EXE2" then
						phase = "watch"; final_t = 0
						emu:SetClockSpeed(8)
						print("WATCH: 8x trigger done len=" .. blen())
						return
					end
				end
				state = "idle"
			end
		end
	elseif phase == "watch" then
		final_t = final_t + 1
		if final_t % 200000 == 0 then
			local tiled = 0
			for a = 0x8240, 0x8DFB do if (data[a] or 0) > 0x30 then tiled = tiled + 1 end end
			print(string.format("WATCH: t=%d pc=%04X sp=%04X lr=%04X len=%d tiles=%d h={2b1e:%d 3538:%d 35be:%d 4d20:%d str:%d}",
				final_t, cpu.pc, cpu.sp, cpu.lr, blen(), tiled,
				hit.k2b1e or 0, hit.k3538 or 0, hit.k35be or 0, hit.k4d20 or 0, hit.strcpy or 0))
		end
		if final_t >= 2600000 then
			print(string.format("END: pc=%04X sp=%04X lr=%04X h={2b1e:%d 3538:%d 35be:%d 4d20:%d str:%d} maxlen=%d",
				cpu.pc, cpu.sp, cpu.lr, hit.k2b1e or 0, hit.k3538 or 0, hit.k35be or 0, hit.k4d20 or 0, hit.strcpy or 0, max_len))
			local rows = {}
			for rr = 0, 7 do
				local s2 = ""
				for i = 0, 11 do s2 = s2 .. string.format("%02X", data[0xF800 + rr * 16 + i]) end
				rows[#rows + 1] = s2
			end
			print("LCD: " .. table.concat(rows, " | "))
			emu:set_paused(true)
			phase = "done"
		end
	end
end)
