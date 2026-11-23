-- more03_floodstamps.lua: fire the standard trigger (plant 100B payload at 0x8154,
-- Right/Left/EXE) and log EVERY strcpy/strcat/memmove/memcpy12 call during the
-- flood: site(LR), dst=ER0, src=ER2, slen(src). Question: do any flood stamps have
-- dst>=0x8C60 (stack) or SFR, and does any stamp read src beyond 0x8154+100?
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
emu:SetClockSpeed(8)

local T = 0
local SHIFT, AC, EXE, LEFT, RIGHT = 0x07, 0x42, 0x60, 0x26, 0x37
local PAY_IN = 0x8154

local phase, final_t = "final", 0
local scan_hits = 0
local logs = {}
local nlogs = 0

local function slen(a)
	if a < 0x8000 or a > 0x8DFF then return -1 end
	for i = 0, 0x8DFF - a do if (data[a + i] or 0) == 0 then return i end end
	return 0x8E00 - a
end
local function er0() return (cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF) end
local function er2() return (cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF) end

local seen = {}
local function mk(addr, prim)
	break_at(addr, function()
		local dst, src = er0(), er2()
		local len = slen(src)
		local key = string.format("%04X|%s|%04X|%04X|%d", addr, prim, dst, src, len)
		if not seen[key] then
			seen[key] = true
			nlogs = nlogs + 1
			if nlogs <= 90 then
				logs[#logs + 1] = string.format("STAMP %s site=%04X dst=%04X src=%04X slen(src)=%d", prim, cpu.lr & 0xFFFF, dst, src, len)
			end
		end
		emu:set_paused(false)
	end)
end
mk(0x2B10, "strcpy")
mk(0x2B24, "strcat")
mk(0xCB5E, "strcat-dir")
mk(0x5108, "memmove")
mk(0x35BE, "memcpy12")

break_at(0x4D20, function()
	scan_hits = scan_hits + 1
	emu:set_paused(false)
end)

addposttick(function()
	T = T + 1
	if phase == "final" then
		final_t = final_t + 1
		if final_t == 1 then
			Keyboard:PressKey(RIGHT)
		elseif final_t == 16001 then
			Keyboard:ReleaseAll()
		elseif final_t == 20001 then
			Keyboard:PressKey(LEFT)
		elseif final_t == 36001 then
			Keyboard:ReleaseAll()
			for e = 0, 49 do data[PAY_IN + e * 2] = 0x0E; data[PAY_IN + e * 2 + 1] = 0x4D end
			local function W(off, v) data[PAY_IN + off] = v & 0xFF; data[PAY_IN + off + 1] = (v >> 8) & 0xFF end
			W(48, 0x3538) W(50, 0x3538) W(52, 0xF801) W(54, 0x35BE) W(56, 0x8154)
			print(string.format("PLANT: strlen(0x8154)=%d", slen(0x8154)))
		elseif final_t == 40001 then
			Keyboard:PressKey(EXE)
		elseif final_t == 60001 then
			Keyboard:ReleaseAll()
			emu:SetClockSpeed(16)
		elseif final_t > 60001 then
			if scan_hits >= 8 or final_t > 1300000 then
				print(string.format("FLOOD: hits=%d pc=%04X sp=%04X strlen8154=%d nstamps=%d", scan_hits, cpu.pc, cpu.sp, slen(0x8154), nlogs))
				for _, l in ipairs(logs) do print(l) end
				-- summary: distinct dsts >= 0x8200, max slen(src), any dst>=0x8C00 or >=0xF000
				local maxslen, hotdst = -1, 0
				for k in pairs(seen) do
					local dst = tonumber(k:match("|%04X|"), 16)
					local sl = tonumber(k:match("|(%d+)$"))
					if sl and sl > maxslen then maxslen = sl end
					if dst >= 0x8C00 or dst >= 0xF000 then hotdst = hotdst + 1 end
				end
				print(string.format("FLOOD-SUMMARY: distinct stamps=%d max slen(src)=%d stamps with dst>=0x8C00 or SFR=%d", nlogs, maxslen, hotdst))
				emu:set_paused(true)
				phase = "done"
			end
		end
	end
end)
