# Snake Input Research for FX-991ES Plus 2nd Edition

## Arrow Key Matrix
The `model.lua` uses GUI pixel coordinates and grid indices for key definitions. Arrow keys are defined as:

| Keycode (KOD) | GUI Coordinates (px, py) | Derived Matrix (ko, ki) | Button Index
|---------------|--------------------------|------------------------|--------------
| 0x26         | (155, 319)              | `ko=0x0`, `ki=6`         | `button_ix = ko*8 + ki = 0*8 + 6 = 6`
| 0x37         | (155, 321)              | `ko=0x0`, `ki=7`         | `button_ix = 0*8 + 7 = 7`
| 0x27         | (188, 289)              | `ko=2`, `ki=1`          | `button_ix = 2*8 + 1 = 17`
| 0x36         | (188, 291)              | `ko=2`, `ki=2`          | `button_ix = 2*8 + 2 = 18`

**Derivation**:
- `ko = (code >> 4) & 0xF`
- `ki = code & 0xF`

## Key Registers
From `research/gyx-decomp/assets/ML610904.H`:
- **`KID`**: Key Input Detect register (`0xF040`)
- **`KOD`**: Key Output Drive register (`0xF046`)
- **`KOMASK`**: Key Output Mask register (`0xF044`/`0xF045`)

## LCD Pixel Mapping
The LCD is located at `0xF800`–`0xF9FF`, with:
- **Visible Rows**: 1–31 (0–30 in 0-based indexing).
- **Bytes per Row**: 12 bytes (16 bytes total, but only 12 are used).
- **Byte Address**: `0xF800 + (y + 1) * 16 + x / 8`
- **Bit Address**: `0x80 >> (x & 7)` (MSB first)

**Example**:
- Pixel `(0, 0)` → Byte `0xF800 + 1 * 16 + 0 / 8 = 0xF810`, Bit `0x80 >> 0 = 0x80`
- Pixel `(11, 1)` → Byte `0xF800 + 2 * 16 + 11 / 8 = 0xF81F`, Bit `0x80 >> 3 = 0x08`

## Required Firmware Registers
To control the LCD, ensure the following registers are correctly set:
- **LCD Control Register**: `0x811F` (Display Enable/Mode)
- **Unknown Timing Registers**: `0xF00C`/`0xF00D` (Timing) are unverified; use `unknown` for now.

## Inference
- The `KID` register (`0xF040`) detects key presses by reading the `KI*` bits.
- The `KOD` register (`0xF046`) outputs the keycode when a key is pressed.
- The `KOMASK` register (`0xF044`/`0xF045`) can be used to filter key outputs for specific keys.

This report is based on verified facts from `model.lua`, `ML610904.H`, and LCD documentation.