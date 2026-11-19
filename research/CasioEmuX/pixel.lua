-- Pixel for the Casio fx-991ES PLUS 2nd edition emulator (CY-845A).
--
-- Interactive:  ./emulator/emulator model=models/fx991esplus2 script=pixel.lua
-- Demo:         PIXEL_DEMO=1 SDL_VIDEODRIVER=dummy ./emulator/emulator model=models/fx991esplus2 script=pixel.lua
--
-- After boot the CPU is parked in a harmless DI + self-loop at free RAM
-- 0x8FF0, so the firmware never touches the LCD again and this script owns
-- 0xF800..0xF9FF. Playfield: 32x10 cells of 3x3 px on LCD rows 1..30.

dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local DEMO       = os.getenv("PIXEL_DEMO") == "1"
local DEBUG      = os.getenv("PIXEL_DEBUG") ~= nil
local MOVE_TICKS = 16384

-- Key codes (ko<<4)|ki, from models/fx991esplus2/model.lua.
local K_UP, K_DOWN, K_LEFT, K_RIGHT = 0x27, 0x36, 0x26, 0x37
local DIRS = { [K_UP]={0,-1}, [K_DOWN]={0,1}, [K_LEFT]={-1,0}, [K_RIGHT]={1,0} }

-- Game state
local cell_x, cell_y, dx, dy = 16, 5, 1, 0
local frames_captured = 0

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
local function cls()
    for row = 1, 31 do for b = 0, 11 do data[BASE + row*16 + b] = 0 end end
end

-- Boot hook
local ticks, booted = 0, false
addposttick(function()
    ticks = ticks + 1
    if booted then return end
    if ticks == 10 then Keyboard:PressKey(0xFF); print("Pixel: power on") end
    if ticks == 200000 then Keyboard:ReleaseAll() end
    if ticks == 1000000 then
        -- DI; BR -2  at 0x8FF0 (free RAM above the stack top 0x8E00).
        data[0x8FF0] = 0xEB; data[0x8FF1] = 0xF7
        data[0x8FF2] = 0xCE; data[0x8FF3] = 0xFF
        cpu.csr = 0; cpu.pc = 0x8FF0; cpu.lr = 0xDEAD
        Keyboard:ReleaseAll()
        print("Pixel: CPU parked in self-loop at 0x8FF0, game owns the LCD")
        booted = true
        save_frame("pixel_frame0.raw") -- LCD state right after the hijack
    end
end)

-- Posttick hook
local postticks = 0
addposttick(function()
    local ok, err = xpcall(function()
        if not booted then return end
        postticks = postticks + 1
        if postticks % MOVE_TICKS ~= 0 then return end

        -- Auto-move in demo mode
        if DEMO then
            Keyboard:ReleaseAll()
            Keyboard:PressKey(K_RIGHT)
        else
            -- Input edge detection: GetPressed reports the held keycode while held,
            -- -1 otherwise; act only on a new press and refuse 180 degree turns.
            local c = Keyboard:GetPressed()
            if c and c >= 0 then
                local nd = DIRS[c]
                if nd and (nd[1] ~= -dx or nd[2] ~= -dy) then dx, dy = nd[1], nd[2] end
            end
        end

        -- Update cell position
        cell_x, cell_y = cell_x + dx, cell_y + dy
        if cell_x < 0 or cell_x >= GW or cell_y < 0 or cell_y >= GH then
            print("Pixel: wall collision")
            return
        end

        -- Draw
        cls()
        cell(cell_x, cell_y)
        print(string.format("Pixel: position (%d, %d)", cell_x, cell_y))

        -- Frame capture
        if DEMO and frames_captured == 0 and postticks > MOVE_TICKS * 8 then
            frames_captured = 1
            save_frame("pixel_frame1.raw")
        end
        if DEMO and frames_captured == 1 and postticks > MOVE_TICKS * 16 then
            frames_captured = 2
            save_frame("pixel_frame2.raw")
        end
        if DEMO and frames_captured == 2 and postticks > MOVE_TICKS * 24 then
            frames_captured = 3
            print("Pixel: demo complete, shutting down")
            emu:shutdown()
        end
    end, function(e) return "Pixel: hook error: " .. debug.traceback(e) end)
    if not ok then print("Pixel: hook error: " .. tostring(err)) end
end)

-- Frame capture function
function save_frame(name)
    local f = io.open(name, "wb")
    for i = 0, 511 do f:write(string.char(data[BASE + i])) end
    f:close()
    print("Pixel: saved " .. name)
end