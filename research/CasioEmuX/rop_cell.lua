-- Visible-cell payload test on the patched build (matrix-drive verified).
-- Payload: memcpy12 0x35BE -> dst 0xF810 (LCD row 1), src = the tile 0x8154,
-- len 12, pattern = a visible 12-byte row, TYPED — no data[] payload writes.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
emu:SetClockSpeed(8)

local T, ops, oi = 0, {}, 0
local state, hold_t, gap_t, wait_t, cur = "idle", 0, 0, 0, nil
local g3538, g4d20 = 0, 0

break_at(0x3538, function()
	g3538 = g3538 + 1
	print(string.format("CHAIN-3538: #%d sp=%04X ER2=%04X r0=%02X lr=%04X", g3538, cpu.sp,
		(cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF), cpu.r0 & 0xFF, cpu.lr))
	emu:set_paused(false)
end)
break_at(0x4D20, function()
	g4d20 = g4d20 + 1
	print(string.format("CHAIN-4D20: #%d sp=%04X ER0=%04X", g4d20, cpu.sp,
		(cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF)))
	emu:set_paused(false)
end)

local function key(c, l, hold, gap) ops[#ops + 1] = { code = c, label = l, hold = hold or 16000, gap = gap or 20000 } end
local function chord(m, c, l) key(m, l .. "/m"); key(c, l) end
local function waitk(n, tag) ops[#ops + 1] = { op = "wait", n = n, tag = tag } end
local function samp(tag) ops[#ops + 1] = { op = "samp", tag = tag } end
local function blen() local n = 0 while n <= 130 and (data[0x8154 + n] or 0) ~= 0 do n = n + 1 end return n end

-- head + LineIO attempt (SHIFT MODE 2) + Sigma probes
key(0x07); key(0x42)
chord(0x07, 0x30, "el")          -- A^0 probe (the static-polish class = wait)
key(0x17); key(0x33, "X1")
samp("head")

-- typed payload head: the caret-template = A^0 = A caret 0 = the A-var
chord(0x17, 0x04, "A.1")
chord(0x17, 0x04, "A.2")
key(0x46, "caret", 12000, 14000)
key(0x00, "zero2", 12000, 14000)
key(0x04, "A-key")               -- the A^0 = the alpha-var A = the = (the = =)
key(0x60, "A0-EXE", 20000, 30000)
samp("A0")

-- the typed 8/5 payload x14 (the 0x3538 words x14 = 28 bytes)
for i = 1, 14 do
	key(0x12, "f85." .. i, 12000, 14000)
	key(0x11, "f85b." .. i, 12000, 14000)
end
samp("payload")

-- the trigger
key(0x42, "AC"); key(0x26, "LEFT"); key(0x60, "EXE", 20000, 30000)
waitk(4000000, "flood-watch")
samp("post-flood")
ops[#ops + 1] = { op = "final" }

addposttick(function()
	T = T + 1
	if done then return end
	if state == "idle" then
		oi = oi + 1
		if oi > #ops then done = true emu:set_paused(true) return end
		cur = ops[oi]
		if cur.op == "key" then
			Keyboard:PressKey(cur.code)
			state = "press"; hold_t = cur.hold
		elseif cur.op == "wait" then
			state = "wait"; wait_t = cur.n
		elseif cur.op == "samp" then
			print(string.format("FID[%s] t=%d len=%d row1=%s tiles35=%d h3538=%d h4d20=%d",
				cur.tag, T, blen(), hex(0xF810, 12), "?", g3538, g4d20))
			state = "idle"
		elseif cur.op == "final" then
			print(string.format("FID[final] t=%d len=%d row1=%s h3538=%d h4d20=%d", T, blen(),
				hex(0xF810, 12), g3538, g4d20))
			done = true
			emu:set_paused(true)
			return
		end
	elseif state == "press" then
		hold_t = hold_t - 1
		if hold_t <= 0 then Keyboard:ReleaseAll(); state = "rel"; gap_t = cur.gap end
	elseif state == "rel" then
		gap_t = gap_t - 1
		if gap_t <= 0 then state = "idle" end
	elseif state == "wait" then
		wait_t = wait_t - 1
		if wait_t <= 0 then state = "idle" end
	end
end)
