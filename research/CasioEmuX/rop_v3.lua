-- V3: STAT-mode memory cartography. Where do typed STAT rows land?
-- If the STAT list overlaps 0x81B7/0x81B8+ (tutorial: cache "also used in STAT"),
-- STAT digits become a keyboard-only filler for the >99-byte strlen state.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local MODE, EXE, AC, SHIFT, LEFT, DEL, K1, K5 = 0x47, 0x60, 0x42, 0x07, 0x26, 0x32, 0x00, 0x11

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase = "type"
local snap = {}
local snapcount = 0

local function push(code, label, hold, gap) keys[#keys + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 16000 } end

local function snapregion(tag)
	local changed, nz = {}, 0
	for a = 0x8100, 0x82FF do
		local v = (data[a] or 0)
		if v ~= (snap[a] or 0) then changed[#changed + 1] = string.format("%04X=%02X", a, v) end
		if v ~= 0 then nz = nz + 1 end
	end
	print(string.format("SNAP[%s] t=%d changed=%d %s", tag, snapcount, #changed, table.concat(changed, " ", 1, math.min(#changed, 90))))
end
local function mark(tag)
	keys[#keys + 1] = { dump = tag }
end

-- baseline
keys[#keys + 1] = { base = 1 }
-- warm AC, then STAT 1-VAR: MODE 3 (single digit since menu = shift-mode-3)
push(AC, "wAC", 12000, 24000)
push(MODE, "MODE", 30000, 40000)
push(K5, "stat3", 30000, 40000)   -- MODE menu: 3=STAT? try 5 first (may be menu idx)
push(EXE, "stat3-EXE", 24000, 30000)
mark("after-mode")
for i = 1, 3 do push(K5, "row5-" .. i); push(EXE, "row5exe-" .. i, 24000, 30000) end
mark("after-3-rows")
for i = 1, 4 do push(K1, "row1-" .. i); push(EXE, "row1exe-" .. i, 24000, 30000) end
mark("after-4-more")
-- long digit rows (contents larger, e.g. 12345): shift into x var entry
for i = 1, 6 do
	push(K1, "big1-" .. i); push(K5, "big2-" .. i); push(K1, "big3-" .. i); push(EXE, "bigexe-" .. i, 24000, 30000)
end
mark("after-big-rows")
-- return to COMP: MODE 1
push(MODE, "MODE2", 30000, 40000); push(K1, "comp1", 30000, 40000)
push(EXE, "comp-EXE", 24000, 30000)
mark("back-to-comp")
push(AC, "AC-comp", 16000, 24000)
mark("after-AC-comp")

addposttick(function()
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				emu:set_paused(true)
				phase = "done"
				print("V3-DONE")
				return
			end
			cur = keys[ki]
			if cur.base then
				for a = 0x8100, 0x82FF do snap[a] = (data[a] or 0) & 0xFF end
				print("BASELINE: t=" .. snapcount)
			elseif cur.dump then
				snapregion(cur.dump)
				-- refresh snapshot so next dump shows only new changes
				for a = 0x8100, 0x82FF do snap[a] = (data[a] or 0) & 0xFF end
			else
				Keyboard:PressKey(cur.code); state = "press"; hold_t = cur.hold
			end
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:ReleaseAll(); state = "rel"; gap_t = cur.gap end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then state = "idle" end
		end
	end
	snapcount = snapcount + 1
end)
