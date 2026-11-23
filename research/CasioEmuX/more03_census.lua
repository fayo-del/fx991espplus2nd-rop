-- more03_census.lua: log EVERY strcpy(0x2B10)/strcat(0x2B24|0xCB5E)/memmove(0x5108)/
-- memcpy12(0x35BE) call during a history-rich key session, with dst/src/len and the
-- key being pressed. Goal: per-site measured table; any dst>=0x8C00 or SFR?
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
emu:SetClockSpeed(8)

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT, UP, DOWN, RCL =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37, 0x27, 0x36, 0x17
local DIG = { 0x00, 0x10, 0x20, 0x01, 0x11, 0x21, 0x02, 0x12, 0x22 } -- 1..9

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t = "type", 0
local cur_label = "boot"

local function slen(a)
	if a < 0x8000 or a > 0x8DFF then return -1 end
	for i = 0, 0x8DFF - a do if (data[a + i] or 0) == 0 then return i end end
	return 0x8E00 - a
end
local function er0() return (cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF) end
local function er2() return (cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF) end

-- census state: site -> {count, maxlen, dsts=set, srcs=set, examples={}}
local sites = {}
local interesting = {}
local function log(site, prim, dst, src, len)
	local s = sites[site]
	if not s then s = { prim = prim, count = 0, maxlen = 0, dsts = {}, srcs = {}, ex = {} }; sites[site] = s end
	s.count = s.count + 1
	if len > s.maxlen then s.maxlen = len end
	s.dsts[dst] = true; s.srcs[src] = true
	if #s.ex < 6 then s.ex[#s.ex + 1] = string.format("%s dst=%04X src=%04X len=%d key=%s", prim, dst, src, len, cur_label) end
	local hot = (dst >= 0x8C00 and dst <= 0x8DFF) or dst >= 0xF000 or (src >= 0x8100 and src <= 0x8DFF and len > 100)
	if hot and #interesting < 60 then
		interesting[#interesting + 1] = string.format("HOT site=%04X %s dst=%04X src=%04X len=%d key=%s", site, prim, dst, src, len, cur_label)
	end
end

local seen = {}
local function mk(addr, prim)
	break_at(addr, function()
		local dst, src, len = er0(), er2(), -1
		if prim == "strcpy" or prim == "strcat" then len = slen(src) end
		local key = string.format("%04X|%s|%04X|%04X", addr, prim, dst, src)
		if not seen[key] then
			seen[key] = true
			log(cpu.lr & 0xFFFF, prim, dst, src, prim == "strcat" and (slen(dst) + len) or len)
		end
		emu:set_paused(false)
	end)
end
mk(0x2B10, "strcpy")
mk(0x2B24, "strcat")
mk(0xCB5E, "strcat-direct")
mk(0x5108, "memmove")
mk(0x35BE, "memcpy12")

local function push(code, label, hold, gap)
	keys[#keys + 1] = { code = code, label = label, hold = hold or 12000, gap = gap or 10000 }
end

push(SHIFT, "w1", 12000, 12000); push(AC, "w2", 12000, 24000)
for i = 1, 12 do push(DIG[1], "A" .. i) end          -- 12 x '1'
push(EXE, "exeA", 20000, 30000)
push(AC, "ac1")
for i = 1, 12 do push(DIG[2], "B" .. i) end          -- 12 x '2'
push(EXE, "exeB", 20000, 30000)
push(AC, "ac2")
for i = 1, 12 do push(DIG[3], "C" .. i) end          -- 12 x '3'
push(EXE, "exeC", 20000, 30000)
push(AC, "ac3")
push(UP, "up1", 16000, 24000)                        -- recall history
push(UP, "up2", 16000, 24000)
push(RCL, "rcl", 16000, 24000)
push(DOWN, "down", 16000, 24000)
push(LEFT, "left", 16000, 24000)
push(SHIFT, "sig-mod"); push(0x56, "sigma", 16000, 24000)  -- template insert (0x8C06/0x8BF6 path)
push(AC, "ac4")
for i = 1, 12 do push(DIG[9], "D" .. i) end          -- 12 x '9'
push(EXE, "exeD", 20000, 30000)

addposttick(function()
	T = T + 1
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "final"
				print("CENSUS: typing done")
				return
			end
			cur = keys[ki]
			cur_label = cur.label
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
			if gap_t <= 0 then state = "idle" end
		end
	elseif phase == "final" then
		final_t = final_t + 1
		if final_t == 300000 then
			emu:SetClockSpeed(16)
		elseif final_t > 500000 then
			print("CENSUS: === per-site summary (site=return addr, count, maxlen, dst set, src set) ===")
			local order = {}
			for site, s in pairs(sites) do order[#order + 1] = site end
			table.sort(order)
			for _, site in ipairs(order) do
				local s = sites[site]
				local dl, sl = {}, {}
				for d in pairs(s.dsts) do dl[#dl + 1] = string.format("%04X", d) end
				for d in pairs(s.srcs) do sl[#sl + 1] = string.format("%04X", d) end
				print(string.format("SITE %04X %-13s n=%-4d maxlen=%-4d dst={%s} src={%s}",
					site, s.prim, s.count, s.maxlen, table.concat(dl, ","), table.concat(sl, ",")))
				for _, e in ipairs(s.ex) do print(string.format("    ex: %s", e)) end
			end
			print("CENSUS: === HOT (dst>=0x8C00 or SFR, or RAM src len>100) ===")
			for _, l in ipairs(interesting) do print("  " .. l) end
			if #interesting == 0 then print("  (none)") end
			emu:set_paused(true)
			phase = "done"
		end
	end
end)
