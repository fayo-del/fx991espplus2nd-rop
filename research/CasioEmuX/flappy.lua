-- Flappy Bird for the Casio fx-991ES PLUS 2nd edition emulator (CY-845A).
--
-- Interactive: ./emulator/emulator model=models/fx991esplus2 script=flappy.lua
-- Demo:         FLAPPY_DEMO=1 SDL_VIDEODRIVER=dummy ./emulator/emulator model=models/fx991esplus2 script=flappy.lua
-- Debug:        FLAPPY_DEBUG=1 adds per-step traces.
--
-- After boot the CPU is parked in a harmless DI + self-loop at free RAM
-- 0x8FF0, so the firmware never touches the LCD again and this script owns
-- 0xF800..0xF9FF. Playfield: 32x10 cells of 3x3 px on LCD rows 1..30; the
-- score is drawn as two 3x5 digits in the top-left corner. The bird sits at
-- column 3, gravity pulls it down one cell per step, flap (EXE / Right / Up)
-- raises one cell. Pipes 2 cells wide scroll in from the right with a
-- 3-cell gap; passing one scores, hitting pipe/floor/ceiling ends the game.

dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local DEMO       = os.getenv("FLAPPY_DEMO") == "1" -- demo: auto-flap + frame capture
local DEBUG      = os.getenv("FLAPPY_DEBUG") ~= nil
local STEP_TICKS = 8192                            -- ~15.6 steps/s at the 128 kiHz default clock

-- Key codes (ko<<4)|ki, from models/fx991esplus2/model.lua.
local K_EXE, K_UP, K_RIGHT = 0x60, 0x27, 0x37
local FLAP_KEYS = { [K_EXE] = true, [K_UP] = true, [K_RIGHT] = true }

--------------------------------------------------------------- game state
local birdy, score, pipes, over_ticks, step
local lastcode -- last keycode seen by the GetPressed edge detector
local save_frame -- forward declaration (defined with the screen helpers)

local GW, GH, ROW0 = 32, 10, 1
local GAP, PIPESW, SPACING, BIRDX = 3, 2, 10, 3 -- gap height, pipe width, spawn spacing, bird column

-- Screen helpers. 16 bytes/row, rows 1..31 visible, 12 visible bytes (96 px);
-- bit 7 of byte 0 is the leftmost pixel.
local BASE = 0xF800
local function setpx(col, row, on)
	if col < 0 or col > 95 or row < 0 or row > 31 then return end -- guard: offscreen writes corrupt CPU state
	local b = BASE + row*16 + (col >> 3)
	local bit = 1 << (7 - (col & 7))
	if on then data[b] = data[b] | bit else data[b] = data[b] & ~bit end
end
local function cell(cx, cy)
	for dy = 0, 2 do for dx = 0, 2 do setpx(cx*3 + dx, ROW0 + cy*3 + dy, true) end end
end
local function cls()
	for row = 1, 31 do for b = 0, 11 do data[BASE + row*16 + b] = 0 end end
end

-- 3x5 digit font (rows top-to-bottom, bit 2 = leftmost column).
local FONT = {
	['0']={7,5,5,5,7}, ['1']={2,6,2,2,7}, ['2']={7,1,7,4,7}, ['3']={7,1,3,1,7},
	['4']={5,5,7,1,1}, ['5']={7,4,7,1,7}, ['6']={7,4,7,5,7}, ['7']={7,1,2,2,2},
	['8']={7,5,7,5,7}, ['9']={7,5,7,1,7},
}
local function digit(d, col)
	local rows = FONT[tostring(d)]
	for r, bits in ipairs(rows) do
		for b = 0, 2 do if bits & (1 << (2 - b)) ~= 0 then setpx(col + b, r, true) end end
	end
end
function save_frame(name)
	local f = io.open(name, "wb")
	for i = 0, 511 do f:write(string.char(data[BASE + i])) end
	f:close()
	print("Flappy: saved " .. name)
end
local function draw_score()
	if score >= 10 then digit(math.floor(score / 10) % 10, 0) end
	digit(score % 10, 4)
end

------------------------------------------------------------------------ boot
local ticks, booted = 0, false
addposttick(function()
	ticks = ticks + 1
	if booted then return end
	if ticks == 10 then Keyboard:PressKey(0xFF); print("Flappy: power on") end
	if ticks == 200000 then Keyboard:ReleaseAll() end
	if ticks == 1000000 then
		-- DI; BR -2  at 0x8FF0 (free RAM above the stack top 0x8E00).
		data[0x8FF0] = 0xEB; data[0x8FF1] = 0xF7
		data[0x8FF2] = 0xCE; data[0x8FF3] = 0xFF
		cpu.csr = 0; cpu.pc = 0x8FF0; cpu.lr = 0xDEAD
		Keyboard:ReleaseAll()
		print("Flappy: CPU parked in self-loop at 0x8FF0, game owns the LCD")
		booted = true
		save_frame("flappy_frame0.raw") -- LCD state right after the hijack
	end
end)

-------------------------------------------------------------- game helpers
local function restart()
	math.randomseed(ticks)
	birdy = 5
	score, over_ticks, step = 0, 0, 0
	pipes = {}
	for i = 0, 2 do
		pipes[#pipes + 1] = { x = GW + 2 + i * SPACING, gy = math.random(0, GH - GAP), passed = false }
	end
	lastcode = -1
end

local function flap_wanted() -- demo auto-flap: flap when the bird sits below the gap center
	local nearest = nil
	for _, p in ipairs(pipes) do
		if p.x + PIPESW > BIRDX and (nearest == nil or p.x < nearest.x) then nearest = p end
	end
	if nearest == nil then return false end
	return birdy > nearest.gy + math.floor(GAP / 2)
end

------------------------------------------------------------- game stepping
local postticks, frames_captured, demo_done, restarts = 0, 0, false, 0

addposttick(function()
	local ok, err = xpcall(function()
	if not booted then return end
	postticks = postticks + 1
	if postticks % STEP_TICKS ~= 0 then return end
	step = step + 1

	local do_flap = false

	if over_ticks > 0 then -- game over: flash a border, then restart
		over_ticks = over_ticks + 1
		cls()
		for col = 0, 95 do setpx(col, ROW0, true); setpx(col, ROW0 + GH*3 - 1, true) end
		for row = ROW0, ROW0 + GH*3 - 1 do setpx(0, row, true); setpx(95, row, true) end
		if over_ticks >= 16 then
			print(string.format("Flappy: game over (score %d), restarting", score))
			restarts = restarts + 1
			restart()
			if DEMO and demo_done and restarts >= 1 then
				print("Flappy: demo complete (score 3, game over + restart verified), shutting down")
				emu:shutdown()
				return
			end
		end
		return
	end

	-- input edge detection: GetPressed reports held keycode, -1 otherwise
	local c = Keyboard:GetPressed()
	if c and c >= 0 and c ~= lastcode and FLAP_KEYS[c] then do_flap = true end
	lastcode = c

	if DEMO and not demo_done and flap_wanted() then
		do_flap = true -- pure-logic flap (physical keypress caused MMU abort)
	end

	-- physics: flap overrides gravity for this step
	if do_flap then birdy = birdy - 1 else birdy = birdy + 1 end

	-- pipes scroll left, despawn, spawn, score on pass
	for _, p in ipairs(pipes) do p.x = p.x - 1 end
	if pipes[1].x < -PIPESW then table.remove(pipes, 1) end
	if pipes[#pipes].x <= GW - SPACING then
		pipes[#pipes + 1] = { x = GW + 1, gy = math.random(0, GH - GAP), passed = false }
	end

	-- collisions: floor, ceiling, pipes
	local dying = false
	if birdy < 0 or birdy >= GH then dying = true end
	for _, p in ipairs(pipes) do
		if BIRDX >= p.x and BIRDX < p.x + PIPESW and (birdy < p.gy or birdy >= p.gy + GAP) then
			dying = true
		end
	end

	-- scoring: pipe fully behind the bird column
	for _, p in ipairs(pipes) do
		if not p.passed and p.x + PIPESW <= BIRDX then
			p.passed = true
			score = score + 1
			print(string.format("Flappy: passed pipe, score %d (step %d)", score, step))
		end
	end

	if dying then
		print(string.format("Flappy: collision (birdy %d), score %d, game over", birdy, score))
		over_ticks = 1
		return
	end

	-- draw
	cls()
	for _, p in ipairs(pipes) do
		for row = 0, GH - 1 do
			if row < p.gy or row >= p.gy + GAP then
				for w = 0, PIPESW - 1 do cell(p.x + w, row) end
			end
		end
	end
	cell(BIRDX, birdy)
	draw_score()

	if DEBUG then
		local s = ""
		for _, p in ipairs(pipes) do s = s .. string.format("(x=%d,gy=%d)", p.x, p.gy) end
		print(string.format("Flappy: step %d, birdy %d, flap %s, score %d, pipes %s",
			step, birdy, tostring(do_flap), score, s))
	end

	-- demo frame captures: 1 in flight before any pipe, 2/3 after passes
	if DEMO then
		if frames_captured == 0 and step == 15 then
			frames_captured = 1
			save_frame("flappy_frame1.raw") -- bird mid-flight, pipe on screen
		elseif frames_captured == 1 and score >= 1 then
			frames_captured = 2
			save_frame("flappy_frame2.raw") -- after the first pipe
		elseif frames_captured == 2 and score >= 2 then
			frames_captured = 3
			save_frame("flappy_frame3.raw") -- after the second pipe
		end
		if frames_captured >= 3 and score >= 3 and not demo_done then
			demo_done = true -- stop flapping: the bird falls, collides, game over
		end
	end
	end, function(e) return "hook error: " .. debug.traceback(e) end)
	if not ok then print("Flappy: hook error: " .. tostring(err)) end
end)

restart()
print("Flappy: initialized (demo=" .. tostring(DEMO) .. ")")
