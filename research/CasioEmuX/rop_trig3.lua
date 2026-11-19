-- Shorter-overflow trigger search: 3 candidate triggers, each combined with the
-- TYPABLE digit payload ('8','5' = 38 35 = the 0x3538 gadget word). 1x clock.
-- Per test: RAM diff-scan (0x8100..0x8E7F baseline vs post-trigger), 38-35 tile
-- count past 0x8240, @0x3538/@0x4D20 hit classes, blen + post state.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT, UP, DOWN =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37, 0x27, 0x36
local K1, K8, K5 = 0x00, 0x12, 0x11

local g3538, g4d20 = 0, 0
break_at(0x3538, function()
	g3538 = g3538 + 1
	if g3538 <= 6 then
		print(string.format("HIT-3538: #%d sp=%04X ER2=%04X r0=%02X lr=%04X", g3538, cpu.sp,
			(cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF), cpu.r0 & 0xFF, cpu.lr))
	end
	emu:set_paused(false)
end)
break_at(0x4D20, function()
	g4d20 = g4d20 + 1
	emu:set_paused(false)
end)

local ops = {}
local function key(code, label, hold, gap)
	ops[#ops + 1] = { op = "key", code = code, label = label, hold = hold or 16000, gap = gap or 20000 }
end
local function chord(mod, code, label, tries)
	for i = 1, tries or 1 do
		key(mod, label .. "/m" .. i); key(code, label .. "." .. i)
	end
end
local function fill85(n)
	for i = 1, n do
		key(i % 2 == 1 and K8 or K5, "f85." .. i, 12000, 14000)
	end
end

-- unified state snapshot
local snap
local function snap_save()
	snap = {}
	for a = 0x8100, 0x8E7F do snap[a] = data[a] or 0 end
end
local function snap_diff(tag)
	local n, tiles = 0, 0
	local regions, st, en = {}, nil, nil
	for a = 0x8100, 0x8E7F do
		if ((data[a] or 0) & 0xFF) ~= snap[a] then
			n = n + 1
			if st and a == en + 1 then
				en = a
			else
				if st then regions[#regions + 1] = { st, en } end
				st, en = a, a
			end
		end
	end
	if st then regions[#regions + 1] = { st, en } end
	for a = 0x8240, 0x8DF8 do
		if (data[a] or 0) == 0x35 and (data[a - 1] or 0) == 0x38 then tiles = tiles + 1 end
	end
	local bl = 0
	while bl <= 120 and (data[0x8154 + bl] or 0) ~= 0 do bl = bl + 1 end
	print(string.format("TRIG[%s]: diff=%d tiles(38 35)=%d blen=%d pc=%04X sp=%04X h3538=%d h4d20=%d",
		tag, n, tiles, bl, cpu.pc, cpu.sp, g3538, g4d20))
	for _, r in ipairs(regions) do
		if r[2] - r[1] >= 12 then
			local s = ""
			for b = r[1], math.min(r[2], r[1] + 15) do s = s .. string.format("%02X", data[b] or 0) end
			print(string.format("TRIG[%s]: %04X-%04X: %s", tag, r[1], r[2], s))
		end
	end
end

local function blen()
	local n = 0
	while n <= 120 and (data[0x8154 + n] or 0) ~= 0 do n = n + 1 end
	return n
end
local function hex(a0, n)
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02X", data[a0 + i] or 0) end
	return s
end

-- ============ common head ============
key(SHIFT); key(AC)
key(SHIFT); key(MODE, "MODE", 16000, 40000); key(K1 * 0 + 0x10, "setup2", 16000, 40000)
key(SHIFT); key(0x56, "sigv")
key(AC)

-- ============ TEST 1: A^0 (tieba A^0-fa) ============
key(ALPHA); key(0x04, "A.1")          -- A var = ALPHA + 0x04 (ROM alpha table row4 col0)
key(ALPHA); key(0x04, "A.2")
key(ALPHA); key(0x04, "A.3")
-- the '^' = the x^box template key (0x46): inserts [box]^([box] template... retry x3
chord(SHIFT and 0x46, 0x46, "caret", 1)
key(0x46, "caret2"); key(0x46, "caret3")
key(0x00, "zero")
key(EXE, "A0-EXE", 20000, 30000)
key(AC, "A0-AC"); key(LEFT, "A0-LEFT")
-- typed payload fill + trigger
fill85(28)
key(AC, "T1-AC"); key(LEFT, "T1-LEFT"); key(EXE, "T1-EXE", 20000, 30000)

-- ============ TEST 2: 1÷3(4) auto-paren ============
key(AC)
key(0x00, "one.T2"); key(0x41, "div.T2"); key(0x20, "three.T2")
key(0x23, "paren.T2"); key(0x00, "four.T2"); key(0x33, "rparen.T2")
key(EXE, "T2-EXE", 20000, 30000)
key(LEFT, "T2-LEFT")
sample = key -- placeholder no-op guard
fill85(28)
key(AC, "T2-AC2"); key(LEFT, "T2-LEFT2"); key(EXE, "T2-EXE2", 20000, 30000)

-- ============ TEST 3: Integral(/Pol( template ============
key(AC)
key(0x16, "int.T2")                   -- Integral-( template (base 0x16... unused here)
key(0x6C and 0x30, "plus.T3")         -- Pol( = SHIFT + '+' = 6C
chord(SHIFT, 0x30, "pol")
fill85(24)
key(AC, "T3-AC"); key(LEFT, "T3-LEFT"); key(EXE, "T3-EXE", 20000, 30000)

-- ============ the machine ============
local oi, state, hold_t, gap_t, cur, phase = 0, "run", 0, 0, nil, 0
local T = 0
snap_save()

addposttick(function()
	T = T + 1
	if phase == 0 then
		if state == "run" then
			oi = oi + 1
			if oi > #ops then
				phase = 1
				print("TRIG[final]: len=" .. blen() .. " buf=" .. hex(0x8154, 32))
				print("TRIG[final]: h3538=" .. g3538 .. " h4d20=" .. g4d20)
				emu:set_paused(true)
				return
			end
			cur = ops[oi]
			if cur.op == "key" then
				-- per-key snapshot at test boundaries: key AC/EXE = the ends
				if cur.label and cur.label:match("%-EXE") then snap_save() end
				if cur.label and cur.label:match("^T%d") and not cur.label:match("%-EXE") and not snap_test_done then end
				Keyboard:PressKey(cur.code)
				state = "press"; hold_t = cur.hold
			end
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then
				Keyboard:ReleaseAll()
				state = "rel"; gap_t = cur.gap
			end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then
				-- fill85 landing probe: log the first and every 8th fill
				if cur.label and cur.label:match("^f85") then
					local i = tonumber(cur.label:match("(%d+)$"))
					if i == 1 or i % 8 == 0 then
						print(string.format("TRIG[f85@%s]: idx=%s len=%d", cur.label, i, blen()) .. " tail=" .. hex(0x8154 + math.max(0, blen() - 8), 8))
					end
				end
				if cur.label and (cur.label:match("^A%.") or cur.label:match("^caret")) then
					print(string.format("TRIG[%s]: len=%d buf=%s", cur.label, blen(), hex(0x8154, 16)))
				end
				if cur.label == "A0-EXE" then
					snap_diff("A0-EXE")
					print("TRIG[A0-EXE]: buf=" .. hex(0x8154, 40))
				end
				if cur.label == "T2-EXE" then
					snap_diff("T2-EXE")
					print("TRIG[T2-EXE]: buf=" .. hex(0x8154, 24))
				end
				if cur.label == "T1-EXE" or cur.label == "T2-EXE2" or cur.label == "T3-EXE" then
					snap_diff(cur.label)
				end
				state = "run"
			end
		end
	end
end)
