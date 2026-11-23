-- sec_strcat_census.lua (worker SecCopies, 2026-11-22)
-- Census of the two copy families NOT covered by prior rop_v*-sessions:
--   strcat  0xCB5E (append, dst-scanned to NUL then src appended; dst=ER0 src=ER2)
--   memmove 0x5108 (dst=ER0 src=ER2 len word at [SP] on entry)
-- logged with call-site (LR) attribution, dstlen/srclen from data[], and a
-- stack-write marker when dst+len reaches >=0x8C00 (stack/control region).
-- Session: start typing at T=1 (proven window), short formula, AC/EXE/LEFT,
-- then 2M-tick watch. Pure census: no injected bytes.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local function er(hi, lo) return ((hi & 0xFF) << 8) | (lo & 0xFF) end
local function slen(base, max)
	local n = 0
	while n < (max or 300) and (data[base + n] or 0) ~= 0 do n = n + 1 end
	return n
end

local agg = {}      -- key -> count
local logs = 0
local stacklog = 0
local final_t = 0
local function note(key) agg[key] = (agg[key] or 0) + 1 end

-- strcat: dst=ER0, src=ER2 at entry (loop 0xCB72 does the append)
break_at(0xCB5E, function()
	local dst = er(cpu.r1, cpu.r0)
	local src = er(cpu.r3, cpu.r2)
	local dl = (dst >= 0x8000 and dst < 0x8E00) and slen(dst, 400) or -1
	local sl = (src >= 0x8000 and src < 0x8E00) and slen(src, 400) or -1
	if dl >= 0 then
		local endaddr = (dl >= 0 and sl >= 0) and (dst + dl + sl) or -1
		note(string.format("STRCAT dst=%04X dlen=%d src=%04X slen=%d", dst, dl, src, sl))
		if (endaddr >= 0x8900 and endaddr < 0x8E00) or (dst >= 0x8900) then
			logs = logs + 1
			if stacklog < 40 then
				print(string.format("STRCAT-NEARSTACK: t=%d lr=%04X dst=%04X dlen=%d src=%04X slen=%d end=%04X",
					final_t, cpu.lr, dst, dl, src, sl, endaddr))
				stacklog = stacklog + 1
			end
		end
	end
	emu:set_paused(false)
end)

-- memmove: dst=ER0, src=ER2, len = word at [SP] (caller PUSHed len before BL)
break_at(0x5108, function()
	local dst = er(cpu.r1, cpu.r0)
	local src = er(cpu.r3, cpu.r2)
	local len = (data[cpu.sp] or 0) | ((data[cpu.sp + 1] or 0) << 8)
	local key = string.format("MEMMOVE lr=%04X dst=%04X src=%04X len=%d end=%04X", cpu.lr, dst, src, len, dst + len)
	note(key)
	if (dst >= 0x8900 and dst < 0x8E00) or (dst + len > 0x8900 and dst < 0x8E00) then
		logs = logs + 1
		if stacklog < 40 then
			print(string.format("MEMMOVE-NEARSTACK: t=%d lr=%04X dst=%04X src=%04X len=%d end=%04X",
				final_t, cpu.lr, dst, src, len, dst + len))
			stacklog = stacklog + 1
		end
	end
	emu:set_paused(false)
end)

-- template insert: strcpy(0x8154 <- [ER14-18]) — stack->input copy, check src len
break_at(0x8C06, function()
	local fp = er(cpu.r15, cpu.r14)
	local srcb = ""
	local sl0 = slen(fp - 18, 64)
	if stacklog < 60 then
		for i = 0, sl0 do srcb = srcb .. string.format("%02X", data[fp - 18 + i] or 0) end
		print(string.format("TPL-INSERT: t=%d fp=%04X src=%04X srclen=%d bytes=%s dst=0x8154",
			final_t, fp, fp - 18, sl0, srcb))
		stacklog = stacklog + 1
	end
	note("TPL-INSERT")
	emu:set_paused(false)
end)

local keys, ki, state, hold_t, gap_t, cur = {}, 0, "idle", 0, 0, nil
local phase = "boot"
local SHIFT, ALPHA, CALC, EXE, AC, DEL, LEFT = 0x07, 0x17, 0x06, 0x60, 0x42, 0x32, 0x26
local KX10, K9 = 0x62, 0x22
local function push(code, label, hold, gap)
	keys[#keys + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 16000 }
end
local function chord(mod, code, label)
	keys[#keys + 1] = { mod = mod, code = code, label = label, hold = 16000, gap = 16000 }
end

-- typing starts at T=1 (session-10 rule) — short representative session
phase = "type"
push(SHIFT, "SH1"); push(AC, "AC1", 16000, 24000)
chord(ALPHA, 0x33, "X")
push(0x10, "two"); push(0x20, "three"); push(0x00, "one")
push(CALC, "CALC", 16000, 24000); push(EXE, "EXE1", 24000, 30000)
push(AC, "AC2", 16000, 24000); push(LEFT, "LEFT", 16000, 20000)
push(EXE, "EXE2", 24000, 30000)
push(AC, "AC3", 16000, 24000); push(LEFT, "LEFT2", 16000, 20000); push(EXE, "EXE3", 24000, 30000)
chord(SHIFT, 0x56, "Sigma")
chord(ALPHA, 0x33, "X2")
push(KX10, "x10"); push(K9, "nine")
push(CALC, "CALC2", 16000, 24000); push(EXE, "EXE4", 24000, 30000)
push(AC, "AC4", 16000, 24000); push(LEFT, "LEFT3", 16000, 20000); push(EXE, "EXE5", 24000, 30000)

addposttick(function()
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "watch"; final_t = 0
				emu:SetClockSpeed(8)
				print(string.format("TYPE-DONE keys=%d t=%d len8154=%d", ki - 1, final_t, slen(0x8154)))
				return
			end
			cur = keys[ki]
			if cur.mod then Keyboard:PressKey(cur.mod); state = "mod"; hold_t = 16000
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
				if cur.label and cur.label:sub(1, 4) == "EXE5" then
					phase = "watch"; final_t = 0
					emu:SetClockSpeed(8)
					print(string.format("TYPE-DONE full t=%d len8154=%d", final_t, slen(0x8154)))
				end
			end
		end
	elseif phase == "watch" then
		final_t = final_t + 1
		if final_t % 500000 == 0 then
			local tiled = 0
			for a = 0x8240, 0x8DFB do if (data[a] or 0) > 0x30 then tiled = tiled + 1 end end
			print(string.format("WATCH: t=%d pc=%04X sp=%04X str8154=%d tiles=%d logs=%d near=%d",
				final_t, cpu.pc, cpu.sp, slen(0x8154), tiled, logs, stacklog))
		end
		if final_t >= 2000000 then
			print("=== AGG ===")
			for k, v in pairs(agg) do print(k .. " x" .. v) end
			print(string.format("=== END logsnear=%d", stacklog))
			phase = "done"; emu:set_paused(true)
		end
	end
end)

-- aggregate printed by WATCH/done via AT-END dump below
