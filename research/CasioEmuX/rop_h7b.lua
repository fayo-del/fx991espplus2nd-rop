-- Hack #7 (unstable byte) — WIKI-EXACT basic-overflow sequence on CY-845.
-- Wikipedia method for Sigma calculators, plus the 1M-5M-tick flash waits.
-- Sequential op-machine: key / wait / clock / sample ops; keys ALWAYS run at
-- 1x clock (the frame-visibility rule), flash waits at 16x.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37, 0x00, 0x10, 0x22, 0x62

local ops = {}
local function key(code, label, hold, gap)
	ops[#ops + 1] = { op = "key", code = code, label = label, hold = hold or 16000, gap = gap or 20000 }
end
local function wait(ticks, label)
	ops[#ops + 1] = { op = "wait", ticks = ticks, label = label }
end
local function clock(speed)
	ops[#ops + 1] = { op = "clock", speed = speed }
end
local function sample(tag)
	ops[#ops + 1] = { op = "sample", tag = tag }
end

local function blen()
	for i = 0, 120 do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 121
end
local function hex(a0, n)
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02X", data[a0 + i] or 0) end
	return s
end

-- ============ Phase A: warm-up + SETUP (LineIO attempt) ============
key(SHIFT); key(AC); key(AC)
key(SHIFT); key(MODE, "MODE1", 16000, 40000); key(K2, "setup2-2", 16000, 40000)
key(SHIFT); key(0x56, "SIGV1")
sample("after-setup")
-- ============ Phase B: WIKI method (no DEL dance) ============
-- formula: X=Σ(X,1,1×10⁹
key(ALPHA); key(0x33, "X1")
key(ALPHA); key(CALC, "eq")
key(SHIFT); key(0x56, "Sigma")
key(ALPHA); key(0x33, "X2")
key(SHIFT); key(0x33, "comma1")
key(K1, "one")
key(SHIFT); key(0x33, "comma2")
key(K1, "one2")
key(KX10, "x10")
key(K9, "nine")
sample("formula")
-- CALC = AC LEFT  (the wiki's CALC/=-error step + the AC/LEFT variant)
key(CALC, "CALC", 16000, 24000)
key(EXE, "EXE", 20000, 30000)
key(AC, "AC", 16000, 24000)
key(LEFT, "LEFT", 16000, 16000)
sample("after-AC-LEFT")
-- ============ Phase C: advance-probe — 12x '1' typed, each sampled ============
for i = 1, 12 do
	key(K1, "ADV" .. i)
	sample("adv" .. i)
end
-- ============ Phase D: FLASH-WAIT 1M ticks (16x) before the symbol insert ============
clock(16); wait(1000000, "flash1M"); clock(1)
-- ============ Phase E: Σ( insert, retries, each sampled ============
for i = 1, 3 do
	key(SHIFT); key(0x56, "SYMΣ." .. i)
	sample("sym" .. i)
end
-- ============ Phase F: cursor-move walks BETWEEN flash waits ============
for i = 1, 3 do
	key(RIGHT, "MOV-R" .. i)
	clock(16); wait(2000000, "flash2M-r" .. i); clock(1)
	sample("movr" .. i)
end
key(LEFT, "MOV-L1")
clock(16); wait(2000000, "flash2M-l1"); clock(1)
sample("movl1")
-- ============ Phase G: another Σ( insert post-flashes ============
for i = 1, 3 do
	key(SHIFT); key(0x56, "SYMΣ2." .. i)
	sample("sym2." .. i)
end
-- ============ final: full-window dumps ============
ops[#ops + 1] = { op = "final" }

local oi, state, hold_t, gap_t, wait_t, cur = 0, "run", 0, 0, 0, nil
local T = 0

addposttick(function()
	T = T + 1
	if state == "run" then
		oi = oi + 1
		if oi > #ops then state = "stop"; return end
		cur = ops[oi]
		if cur.op == "key" then
			Keyboard:PressKey(cur.code)
			state = "press"; hold_t = cur.hold
		elseif cur.op == "wait" then
			state = "waiting"; wait_t = cur.ticks
		elseif cur.op == "clock" then
			emu:SetClockSpeed(cur.speed)
			state = "run"
		elseif cur.op == "sample" then
			print(string.format("H7[%s]: t=%d len=%d buf=%s ext=%s far=%s", cur.tag, T, blen(),
				hex(0x8154, 24), hex(0x81B8, 32), hex(0x8214, 24)))
			state = "run"
		elseif cur.op == "final" then
			print("H7[final]: len=" .. blen())
			print("H7[final]: input=" .. hex(0x8154, 100))
			print("H7[final]: cache=" .. hex(0x81B8, 100))
			print("H7[final]: far=" .. hex(0x821C, 100))
			print(string.format("H7[final]: pc=%04X sp=%04X", cpu.pc, cpu.sp))
			state = "stop"
		end
	elseif state == "press" then
		hold_t = hold_t - 1
		if hold_t <= 0 then
			Keyboard:ReleaseAll()
			state = "rel"; gap_t = cur.gap
		end
	elseif state == "rel" then
		gap_t = gap_t - 1
		if gap_t <= 0 then state = "run" end
	elseif state == "waiting" then
		wait_t = wait_t - 1
		if wait_t <= 0 then state = "run"; emu:SetClockSpeed(1) print("H7: flash-wait done t=" .. T) end
	end
end)
