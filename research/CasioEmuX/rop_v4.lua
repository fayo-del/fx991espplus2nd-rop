-- V4: is there an editor state whose typed cap > 99 bytes?
-- A: MODE-5 row editor (V3: rows mirror 0x81B8) - type 140 digits, sample cap.
-- B: TABLE mode (MODE 7?) f(x) editor - same test.
-- C: after long row, exit to COMP, dump 0x8154/cache state (strlen preserved?).
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local MODE, EXE, AC, SHIFT, LEFT, RIGHT, DEL, ALPHA, CALC, K1, K5, K7, KX10, K9 =
	0x47, 0x60, 0x42, 0x07, 0x26, 0x37, 0x32, 0x17, 0x06, 0x00, 0x11, 0x02, 0x62, 0x22

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase = "type"
local last_len = -1
local maxlen = 0
local sample_count = 0

local function blen() for i = 0, 299 do if (data[0x8154 + i] or 0) == 0 then return i end end return 300 end
local function bdump(lo, n) local s = "" for i = lo, lo + n - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end return s end
local function push(code, label, hold, gap) keys[#keys + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 16000 } end

local function sample(tag)
	print(string.format("SAMPLE[%s]: len=%d buf=%s cache0=%02X cache00=%02X%02X %02X%02X",
		tag, blen(), bdump(0, 16), data[0x81B7] or 0, data[0x81B8] or 0, data[0x81B9] or 0, data[0x81C0] or 0, data[0x81C1] or 0))
end
local function mark(tag) keys[#keys + 1] = { dump = tag } end

-- A: MODE 5 row editor (works per V3: rows store to 0x8154 + mirror 0x81B8)
push(AC, "wAC", 12000, 24000)
push(MODE, "MODE", 30000, 40000); push(K5, "mode5", 30000, 40000); push(EXE, "mode5exe", 24000, 30000)
mark("A-mode-written")
for i = 1, 140 do
	push(K1, "A1-" .. i)
end
mark("A-typed-140")
-- try EXE to commit, then continue typing
push(EXE, "A-EXE", 24000, 30000)
for i = 1, 60 do push(K5, "A5-" .. i) end
mark("A-typed-more")
-- B: exit to COMP (MODE 1), then check state
push(MODE, "MODE-c", 30000, 40000); push(K1, "comp", 30000, 40000); push(EXE, "compexe", 24000, 30000)
mark("B-back-to-comp")
push(AC, "AC-comp", 16000, 24000)
mark("B-after-AC")
-- C: TABLE mode attempt (MODE 7): type into f(x)= editor, fill digits (the typed stdin)
push(MODE, "MODE-t", 30000, 40000); push(K7, "table7", 30000, 40000); push(EXE, "table-exe", 24000, 30000)
mark("C-table")
for i = 1, 140 do push(K1, "C1-" .. i) end
mark("C-typed-140")

addposttick(function()
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				print("V4-DONE maxlen=" .. maxlen)
				emu:set_paused(true)
				phase = "done"
				return
			end
			cur = keys[ki]
			if cur.dump then
				sample(cur.dump)
				-- stays idle; next tick advances to the following key
			else
				Keyboard:PressKey(cur.code); state = "press"; hold_t = cur.hold
			end
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then Keyboard:ReleaseAll(); state = "rel"; gap_t = cur.gap end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then
				state = "idle"
				local n = blen()
				if n > maxlen then maxlen = n end
				sample_count = sample_count + 1
				if sample_count % 10 == 0 then
					print(string.format("LAND %s len=%d", cur.label, n))
				end
			end
		end
	end
end)
