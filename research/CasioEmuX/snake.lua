-- Snake for the Casio fx-991ES PLUS 2nd edition emulator (CY-845A).
--
-- Interactive:  ./emulator/emulator model=models/fx991esplus2 script=snake.lua
-- Demo:         SNAKE_DEMO=1 SDL_VIDEODRIVER=dummy ./emulator/emulator model=models/fx991esplus2 script=snake.lua
-- Debug:        SNAKE_DEBUG=1 adds per-move traces.
--
-- After boot the CPU is parked in a harmless DI + self-loop at free RAM
-- 0x8FF0, so the firmware never touches the LCD again and this script owns
-- 0xF800..0xF9FF. Playfield: 32x10 cells of 3x3 px on LCD rows 1..30; the
-- score is drawn as two 3x5 digits in the top-left corner.

dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local DEMO       = os.getenv("SNAKE_DEMO") == "1" -- demo: auto-pilot + frame capture
local DEBUG      = os.getenv("SNAKE_DEBUG") ~= nil
local MOVE_TICKS = 16384                          -- 8 moves/s at the 128 kiHz default clock

-- Key codes (ko<<4)|ki, from models/fx991esplus2/model.lua.
local K_UP, K_DOWN, K_LEFT, K_RIGHT = 0x27, 0x36, 0x26, 0x37
local DIRS = { [K_UP]={0,-1}, [K_DOWN]={0,1}, [K_LEFT]={-1,0}, [K_RIGHT]={1,0} }

--------------------------------------------------------------- game state
local snake, fd, dx, dy, score, over_ticks -- over_ticks > 0: game-over countdown
local lastcode -- last keycode seen by the GetPressed edge detector
local save_frame -- forward declaration (boot hook captures it)

-- Screen helpers. 16 bytes/row, rows 1..31 visible, 12 visible bytes (96 px);
-- bit 7 of byte 0 is the leftmost pixel.
local GW, GH, ROW0 = 32, 10, 1
local BASE = 0xF800
local function setpx(col, row, on)
	local b = BASE + row*16 + (col >> 3)
	local bit = 1 << (7 - (col & 7))
	if on then data[b] = data[b] | bit else data[b] = data[b] & ~bit end
end
local function cell(cx, cy)
	for dy2 = 0, 2 do for dx2 = 0, 2 do setpx(cx*3 + dx2, ROW0 + cy*3 + dy2, true) end end
end
local function food_ring(fx, fy)
	for dy2 = 0, 2 do for dx2 = 0, 2 do
		setpx(fx*3 + dx2, ROW0 + fy*3 + dy2, dx2 == 0 or dx2 == 2 or dy2 == 0 or dy2 == 2)
	end end
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
	print("Snake: saved " .. name)
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
	if ticks == 10 then Keyboard:PressKey(0xFF); print("Snake: power on") end
	if ticks == 200000 then Keyboard:ReleaseAll() end
	if ticks == 1000000 then
		-- DI; BR -2  at 0x8FF0 (free RAM above the stack top 0x8E00).
		data[0x8FF0] = 0xEB; data[0x8FF1] = 0xF7
		data[0x8FF2] = 0xCE; data[0x8FF3] = 0xFF
		cpu.csr = 0; cpu.pc = 0x8FF0; cpu.lr = 0xDEAD
		Keyboard:ReleaseAll()
		print("Snake: CPU parked in self-loop at 0x8FF0, game owns the LCD")
		booted = true
		save_frame("snake_frame0.raw") -- LCD state right after the hijack
	end
end)

-------------------------------------------------------------- game helpers
local function restart()
	snake = {}
	for i = 0, 2 do snake[#snake + 1] = { 16 - i, 5 } end
	dx, dy = 1, 0
	score, over_ticks = 0, 0
	lastcode = -1
	math.randomseed(ticks)
	while true do
		fd = { x = math.random(0, GW - 1), y = math.random(0, GH - 1) }
		local free = true
		for _, c in ipairs(snake) do
			if c[1] == fd.x and c[2] == fd.y then free = false; break end
		end
		if free then break end
	end
end

local function key_towards() -- demo auto-pilot: steer towards the food
	local head = snake[#snake]
	local cands = {}
	for code, nd in pairs(DIRS) do
		if nd[1] ~= -dx or nd[2] ~= -dy then -- no 180
			local nx, ny = head[1] + nd[1], head[2] + nd[2]
			local blocked = nx < 0 or nx >= GW or ny < 0 or ny >= GH
			if not blocked then
				for i = #snake, 2, -1 do -- tail cell is about to move away
					if snake[i][1] == nx and snake[i][2] == ny then blocked = true; break end
				end
			end
			if not blocked then
				cands[#cands + 1] = { math.abs(fd.x - nx) + math.abs(fd.y - ny), code }
			end
		end
	end
	if #cands == 0 then return nil end
	table.sort(cands, function(a, b) return a[1] < b[1] end)
	return cands[1][2]
end

------------------------------------------------------------------ game loop
local postticks, frames_captured, forced_dir = 0, 0, nil
restart()

addposttick(function()
	local ok, err = xpcall(function()
	if not booted then return end
	postticks = postticks + 1
	if postticks % MOVE_TICKS ~= 0 then return end

	if over_ticks > 0 then -- game over: flash a border, then restart
		over_ticks = over_ticks + 1
		cls()
		for col = 0, 95 do setpx(col, ROW0, true); setpx(col, ROW0 + GH*3 - 1, true) end
		for row = ROW0, ROW0 + GH*3 - 1 do setpx(0, row, true); setpx(95, row, true) end
		if over_ticks == 8 then
			print(string.format("Snake: game over (score %d), restarting", score))
			restart()
		end
		return
	end

	forced_dir = DEMO and key_towards() or nil
	if forced_dir then
		Keyboard:ReleaseAll()
		Keyboard:PressKey(forced_dir)
	end

	-- Input edge detection: GetPressed reports the held keycode while held,
	-- -1 otherwise; act only on a new press and refuse 180 degree turns.
	local c = Keyboard:GetPressed()
	if c and c >= 0 and c ~= lastcode then
		local nd = DIRS[c]
		if nd and (nd[1] ~= -dx or nd[2] ~= -dy) then dx, dy = nd[1], nd[2] end
	end
	lastcode = c

	local head = snake[#snake]
	local nx, ny = head[1] + dx, head[2] + dy
	if nx < 0 or nx >= GW or ny < 0 or ny >= GH then
		over_ticks = 1
		print(string.format("Snake: wall collision, score %d", score))
		return
	end
	for i = #snake, 2, -1 do
		if snake[i][1] == nx and snake[i][2] == ny then
			over_ticks = 1
			print(string.format("Snake: self collision, score %d", score))
			return
		end
	end
	snake[#snake + 1] = { nx, ny }
	if nx == fd.x and ny == fd.y then
		score = score + 1
		print(string.format("Snake: ate food, score %d, length %d", score, #snake))
		if DEMO then
			save_frame(string.format("snake_frame%d.raw", score + 1)) -- frame2 after eat #1, frame3 after eat #2
			if score >= 2 then
				print("Snake: demo complete, shutting down")
				emu:shutdown()
				return
			end
		end
	else
		table.remove(snake, 1)
	end

	-- draw
	cls()
	for _, cc in ipairs(snake) do cell(cc[1], cc[2]) end
	food_ring(fd.x, fd.y)
	draw_score()
	if DEMO and frames_captured == 0 and postticks > MOVE_TICKS * 8 then
		frames_captured = 1
		save_frame("snake_frame1.raw") -- snake mid-game, moving
	end
end, function(e) return "hook error: " .. debug.traceback(e) end)
	if not ok then print("Snake: hook error: " .. tostring(err)) end
end)
