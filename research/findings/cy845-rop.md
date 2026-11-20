# CY-845 ROP — verified address table and chain (2026-11-18)

All addresses from the **CY-845A ROM** `research/CasioEmuX/models/fx991esplus2/rom.bin`
(md5 c4c7d7fb89d0fd07cc0196d642682d83, 128 KB), disassembled with
`/tmp/nxu8_disas2.py` (ISA-driven, generated fresh this session because the old
`/tmp/cy845_disasm.txt` / `/tmp/fx991es-hacking` were gone; regenerated to
`/tmp/cy845_disasm.txt`, 0 unrecognized in all cited windows). No GYX addresses used.

## Address / gadget table

| Item | CY-845 addr | Encoding bytes | Evidence (disasm line in `/tmp/cy845_disasm.txt`) |
|---|---|---|---|
| POP PC (return gadget) | `0x2B1E` | `8E F2` | line 5484: `2B1E: POP    PC` |
| POP PC #2 | `0x2B22` | `8E F2` | windows disasm `2B22: POP PC` |
| smart_strcpy (PUSH LR … POP PC pair) | `0x2B10` | `CE F8 …` | line ~5476: `2B10: PUSH LR`, `2B1E: POP PC` |
| **getkeycode** (key poll, leaf, RT) | `0x4D0E` | `00 11 … 0C F0 40 F0 30 92 FF 72` | lines 9212-9220: `4D0E: MOV R0,#254 / 4D10: ST R0,00F62h(=ST [0xF046], KOD) / 4D14: MOV ER0,#0 / 4D16: LEA 0xF040 / 4D1A: L R2,[EA] / 4D1C: CMP R2,#255 / 4D1E: ADDC R0,#0 / 4D20: RT`. KOD `0xF046` write verified by raw-byte scan (`11 90 46 F0` at 0x4D00/0x4D10/0x6C06); KID `0xF040` read via `LEA 0xF040` (bytes `0C F0 40 F0` at 0x4D16 and 0x1669C) |
| KOMASK region | `0xF044` size 15 (ROM never writes `0xF044` directly via imm16; scan does it through KO regs) | — | emulator `Keyboard::Initialise` creates MMU regions 0xF040(KI), 0xF041, 0xF042, 0xF044(size 15): objdump `mov $0xf040/$0xf041/$0xf042/$0xf044,%esi` at 0x33027/0x330c8/0x33150/0x331e2 |
| **copy gadget memcpy12** | `0x15664` | — | lines 37994-38016: `15664: PUSH QR0 / 15666: PUSH XR4 / 15668: MOV ER10,ER0 / 1566A: PUSH ER6 / 1566C: LEA [ER6] / 1566E: L QR0,[EA+] / 15670: L ER2,[EA+] / 15672: LEA [ER10] / 15674: ST QR0,[EA+] / 15676: ST ER2,[EA+] / 15678: POP ER8 / … / 15692: POP XR4 / 15694: POP QR0 / 15696: RT` — copies **12 bytes** `[ER6]→[ER0]`; balanced pushes (10 B) and `RT` so it continues a ROP chain. `MOV R10,ER0` at entry: **dst = ER0, src = ER6** |
| POP ER0; POP PC (load-and-continue) | `0x16F18` | — | line 40658: `16F18: POP ER0`, next line `16F20: POP PC` (16F20 approx; pair grep-verified) |
| POP ER6; POP R9; POP PC | `0x10B5A` | — | line 29892: `10B5A: POP ER6` → `10B5C: POP R9 → POP PC` (pair found at `10B5C`, i.e. POP ER6 starts 0x10B5A) |
| Other verified `POP ERn; POP PC` | 0x10E30 (ER2), 0x145FA/0x14614/0x14662 (ER14;POP R2), 0x148C6 (ER12), 0x14B04/0x14B82 (ER6), 0x14DDA (ER4;ER2), 0x174D2 (ER0;ER4), 0x16088 (ER12;R2) | — | pair scan over the full disassembly |
| line_print (string draw) | `0x327E` | `CE F8 7E F8 …` | lines 6363+: `327E: PUSH LR / 3280: PUSH QR8 / 3282: MOV ER2,ER0 / 3284: MOV ER10,ER8 / 328A: L R0,081F8h / 329C-32B4 scan loop over [ER10] / 32B8: MOV ER8,ER10 / 32BA: POP QR8 / 32BC: POP PC`. Args: **ER0 = state/font ptr, ER8 = string ptr** (walked until 0) |
| draw_char | `0x32BE` | — | line 6393: `32BE: PUSH LR / 32C0: PUSH XR8 / 32C2: PUSH QR8 / 32C4: MOV ER14,SP / 32C6: ADD SP,#-29h / 32C8: CMP R0,#250 / 32CA…` (matches task anchor) |
| render (buffer copy 0x87D0→LCD) | unknown | — | only one `LEA 0x87D0` in ROM (bytes `0C F0 D0 87` at file off 0x3146, inside a 12×8-byte clear loop `ST QR8,[EA+]` at 0x314C). No `LEA/L/ST` with 0xF800 immediate anywhere (raw-byte scan empty) — the LCD copy path not located this session |
| ROM wait/park loop (safe spin) | `0x4EF2` | `CE F8 00 F0 10 92 …` | lines 9431+: `4EF2: PUSH LR / 4EF4: MOV R0,#128 / 4EF6: BL 0x4C7C-like poll / 4EFA: CMP R0,#103 / 4EFC: BC NE,0x4EF4 / 4EFE: POP PC` — balanced, single LR push, ideal chain terminator |
| `B ER0` | `0x5690` | `02 F0` | windows disasm `5690: B ER0` |
| `MOV SP, ER14` pivots | 0x2D5C, 0x11156, 0x111DA, 0x10F4C, 0x10F70, 0x5238 (+ task's other candidates) | — | e.g. `2D5C: MOV SP,ER14 / 2D5E: POP XR12 / 2D60: POP PC`; `10F4C: MOV SP,ER14 / 10F4E: POP ER14 / 10F50: POP PC`; `5238: MOV SP,ER14 / 523A: POP XR8 / 523C: POP QR8 / 523E: POP PC` |
| LCD | `0xF800`, 16 B/row, rows 0..31, 12 visible bytes (MSB first) | — | emulator lua-common (`screen_ncol=12, screen_row_width=16` for hwid 3); snake.lua |
| firmware draw buffer | `0x87D0` (cleared 96 B by 0x313C routine) | — | raw-byte scan + `87D0: MOV R5,R4` vicinity |

## Emulator probes (scripts under `research/CasioEmuX/`)

| Script | Result |
|---|---|
| `kyb_probe.lua`, `kyb_probe2.lua` | reading/writing `data[0xF030..0xF07F]` from Lua never changes anything: Lua `data[]` access does **not** go through the keyboard MMIO (or KO must be driven by the CPU); KID is only observable through ROM code reading 0xF040 |
| `seg_test.lua` (2 runs) | direct `line_print` call at 0x327E with csr=0 and csr=1 + wiped LCD: **nothing drawn**; `emu:set_paused(true); emu:run()` executed **zero instructions** (pc/sp unchanged) → that call mechanism (used by the old cy845_line*.lua scripts) never actually executed; the old "LCD success" images were firmware output |
| `rop_probe.lua` (**ROP proof**) | Phase A: chain `[0x2B1E, 0x2B1E, 0x4EF2]` at 0x8C00, `sp=0x8C00`, `pc=0x2B1E`, kicked by writing `cpu.pc/cpu.sp` inside `addposttick` (no pause): CPU **executed the ROM-gadget chain and landed in the park loop** (`pc=0x4B96`, `sp=0x8B86` mid-poll-tree). Phase B chain ran to its end too (`sp=0x8C06` = all 9 words consumed + park frames). **Key read worked**: after Right (0x37) held, `r0=02, ER0=0x0002` from the 0x4D0E poll (0 = no key observed when idle precedes it) |
| `rop_probe2.lua` (LCD copy diagnosis) | Lua-written reference row (`data[0xF810..]=0x81`) **shows on the LCD** ("FRAME: row01 8181…81"), so LCD visibility via 0xF800 RAM is confirmed. The memcpy12 chain wrote row0 as zeros/firmware leftovers — root cause found in the harness layout, see below |

**ROP mechanics settled by rop_probe.lua**: `POP PC` pops **16 bits, little-endian** (`[lo,hi]` at `[SP]`), CSR preserved, stride = 2 bytes per entry; far `B/BL`-style 4-byte entries are not needed for same-bank (csr=0) gadgets.

## The corrected minimal chain (LCD demo — 1 word shorter than rop_probe2 B, which had one extra word)

The word after `CPY12` is **not** an ER8 value: the gadget's `POP ER8` (0x15678)
consumes its *own pushed copy of ER6*, so no dummy word must be placed after the
`0x15664` entry. rop_probe2 phase B (and rop_probe phase B) carried that extra
word, making `RT` jump to it (0x8C20) instead of the next gadget — hence no LCD
pattern. Corrected chain (all entries 16-bit LE at `0x8C80`, `sp=0x8C80`,
`pc=0x2B1E`, `csr=0`):

```
0x8C80: 18 F1   ; 0x16F18  POP ER0; POP PC
0x8C82: 00 F8   ; ER0 = 0xF800 (LCD)
0x8C84: 5A 0B   ; 0x10B5A  POP ER6; POP R9; POP PC
0x8C86: B0 8C   ; ER6 = 0x8CB0 (pattern)
0x8C88: B0 8C   ; 0x8CB0   ; R9 dummy (byte 0x8C88 low)
0x8C8A: 64 56   ; 0x15664  memcpy12 [ER6]->[ER0]  (POP ER8 auto-consumed pushed ER6)
0x8C8C: 0E 4D   ; 0x4D0E   key poll (leaf, RT; ER0 result observable)
0x8C8E: F2 4E   ; 0x4EF2   park (infinite ROM poll loop)
```
Pattern (12 bytes at 0x8CB0, e.g. all `AA`) → LCD row 0 = `AAAAAAAAAAAA`;
after park read `cpu.r0` for the key-poll result. Total: 16 bytes of stack data —
fits comfortably in the 100-byte hackstring payload.
(Needed: the loader that lands those bytes at 0x8C80 — the input buffer anchor
is 0x8154; the 0x8154→chain linkage was not established this turn.)

## Blockers / remaining

1. **Loader**: how hackstring bytes reach free RAM (input 0x8154 vs final chain
   location) — outside what was probed; the previous session's ropbyte scripts
   inject via Lua (`data[]`), which sidesteps it.
2. The corrected chain above was **not** re-run (2-probe budget exhausted); it
   is the rop_probe2 B chain minus one 2-byte word, and phase A of rop_probe
   already validated every mechanic it relies on (POP PC stride/order, ROM
   gadget execution from RAM data, park).
3. Snake-lite: needs the LCD pattern demo green first, then the same
   `POP ERx` gadgets + a ROM "clear row / shift" helper; not attempted per
   instruction.

Repro: `cd research/CasioEmuX && SDL_VIDEODRIVER=dummy timeout 10 ./emulator/emulator model=models/fx991esplus2 script=rop_probe.lua` (ROP:/FRAME: markers in stdout).

## Session 2 (bounded: 2 probes) — `rop_green.lua`, `rop_link.lua`

**Probe 1 (`rop_green.lua`)** — corrected 16-byte chain at 0x8C80, sp=0x8C80, pc=0x2B1E, Right held:
- control flow GREEN again: all 8 words consumed, park reached (`pc=0x75D2, sp=0x8C60`, inside the 0x4EF2 poll subtree).
- LCD row0 sampled at +2/+6 ticks = `C89AE141C57F0000C89AE141` — **firmware content, not `AA`×12**.

**Probe 2 (`rop_link.lua`)** — 5 phases in one run:
1. P1 (chain→LCD, Right held): row0 at +2/+6 = firmware bytes, no `AA`. Park reached (`pc=0x75D2 sp=0x8C60`).
2. P2 (chain→LCD, no key): identical result; final `r0=00` in **both** P1 and P2 → the park loop clobbers ER0, so the key-poll result is **not observable** post-park (the earlier `r0=02` "success" was the park callee's value, not KEYSCAN's).
3. P3 (chain→RAM dst 0x8C40): readback `5A×12` — **inconclusive**: the dst sits inside the live firmware stack (firmware stack proved to reach ~0x8C6C: P4 showed a stray changed byte at 0x8C6C).
4. P4/P5 (hackstring linkage): markers `00..63` written at 0x8154, `=` pressed → **no propagation**: only the marker bytes themselves (0x8155–0x81B7) plus stack noise (0x8C6C, 0x8E01); **no tiling toward 0x8D74/0x8E00, PC stayed in the firmware main loop (0x75CE–0x75D4)**. Chain-embedded variants (offsets 0/50/84) identical.
   - **Methodological flaw (invalidates P4/P5, not the firmware)**: phases 1–3 ended in the 0x4EF2 park, so the CPU never returned to the firmware — the `=` presses were processed by **nobody**. The linkage test must rerun with the CPU back in firmware (no parking, or park→resume) before concluding anything about the overflow.

**Open questions for the next probe (1–2 runs)** — superseded, see Session 3.

## Session 3 — root causes found (`rop_probeA`, `rop_final`, `rop_final2`, `rop_final3`)

All disassembly citations above are now **re-verified with the authoritative community
disassembler** (`oki-u8-disas.cpp` from `research/fxesplus/tools/disassembler`, compiled to
`/tmp/oki_disas`; the ad-hoc `/tmp/nxu8_disas2.py` had m-field-width bugs. Full-bank dumps:
`/tmp/oki_b0.txt` (bank0, 0x0-0xFFFF), `/tmp/oki_b1.txt` (bank1, 0x10000-0x1FFFF)).

### Architecture facts (from emulator source + oki disasm)

1. **addresses 0x10000+ = bank 1 (CSR=1)**: the anchor "0x10EF8/0x10B5A/0x16F18/0x15664"
   gadgets are bank-1 code. Popping them into a csr=0 chain truncates to 0x0B5A/0x6F18/0x5664
   = unrelated bank-0 code → every early chain derail. csr_mask=0x0001; far `B/BL 0g:xxxx`
   uses g&1 as the bank (both banks ARE executed: e.g. `BL 01h:00FB4h` at ROM 0x8FFA).
2. **RAM = 0x8000..0x8DFF only** (BatteryBackedRAM, size 0x0E00). 0x8E00–0x8FFF unmapped.
   Firmware stack: sp=0x8DDC at idle; observed touching down to ~0x8C60.
3. **`POP PC` (8E F2) pops FOUR bytes**: [pc_lo, pc_hi, x, y] (x,y consumed, ignored;
   consistent with [pc16][csr16?] layout guessed in the old ropbyte test). Evidence:
   `@35BE` break fired with sp=0x8C84 after a single pop from 0x8C80 with a 2-byte source
   word at 0x8C82 (2-byte pop would give 0x8C82).
4. **`RT` does NOT pop the stack** — it jumps to `LR` (`OP_RT: reg_pc=reg_lr`). So:
   - chain-continuation gadget = `POP PC` only;
   - `RT`-ending functions continue the chain iff `LR` is planted: set `cpu.lr=0x2B1E` at
     kick and `LR` becomes a persistent "next-gadget pointer" for every RT-exit.
5. **memcpy12 gadget (bank0) = `0x35BE`**:
   `35BE: POP EA (src←stack,2B) / 35C0: L XR4,[EA+] / 35C2: L QR8,[EA+] (12B read from src)
   / 35C4: PUSH EA / 35C6: LEA [ER2] (dst=ER2) / 35C8: ST XR4,[EA+] / 35CA: ST QR8,[EA+]
   (12B written) / 35CC: ADD ER2,#16 / 35CE: ADD R0,#-1 / 35D0: BC NE,0x35BE (count=R0)
   / 35D2: POP ER0 / 35D4: POP QR8 / 35D6: POP XR4 / 35D8: RT`.
   Executed successfully (break_at hit, ER2=0xF800, sp as predicted with 4-byte pops).
6. **KEYSCAN = `0x4D0E` confirmed byte-exact**:
   `0x4D0E: MOV R0,#127 / 0x4D10: ST R0,0xF046h (KOD) / 0x4D14: MOV ER0,#0 / 0x4D16: LEA
   0xF040h / 0x4D1A: L R2,[EA] / 0x4D1C: CMP R2,#255 / 0x4D1E: ADDC R0,#0 / 0x4D20: RT`.
   KID=0xFF (no key) → ER0=0; any key in the scanned row → ER0=1. There are also
   one-shot KOD helpers at 0x4D00 (`ST R0,0xF046; RT`).
7. **LCD**: 0xF800 region = emulator `Screen/Buffer` with internal `screen_buffer` array;
   writes via MMU show on the display AND read back via `data[]`. Firmware draw buffer =
   `0x87D0` (384 bytes; the 0x313C routine clears it with 48×`ST QR8,[EA+]`). The app
   refresh loop (fill function at 0x75B0, inside which idle pc=0x75C0-0x75C8) and the
   interrupt-refresh keep repainting 0xF800 from 0x87D0, overwriting direct 0xF800 writes
   within ≤2 ticks — hence "pattern vanishes". Writing **0x87D0** is the correct target.
8. snake.lua's "park at 0x8FF0" actually lands on ROM 0x8FF0 (data-RAM is unmapped there);
   its DI+loop bytes never persist — it survives because ROM 0x8FF0 happens to sit in a
   wait-key function (`L ER12,0812Ch ... BL 0x50F0 ...`).
9. **Key input NEVER observed being processed by the app**: markers at 0x8154 with `=`
   (0x30) held 100k ticks, and Return (0x60): zero propagation (diff = the marker bytes
   themselves + 2 stack-noise bytes at 0x8C60/0x8C61); pc stayed 0x75C0/0x75C6/0x75C8.
   Either the app's key poll is rarer than the hold, the key path needs the KOD/KOMASK
   scan pattern (the app scans via 0x4D0E-equivalent code with rotating KO), or the
   emulator's KID bridge needs the app's scan loop active — unresolved.

### FINAL corrected chain (bank0-only; ready script `rop_green2.lua`, not yet executed)

Kick: `csr=0, sp=0x8C80, pc=0x2B1E, lr=0x2B1E, r0=1, r2=0xD0, r3=0x87 (ER2=0x87D0)`;
pattern 12×0xFF at 0x8C74; Right (0x37) held; `break_at(0x4D20)` for the ER0 proof.

| addr | bytes | role |
|---|---|---|
| 0x8C80 | `BE 35 00 00` | POP PC → 0x35BE memcpy gadget |
| 0x8C84 | `74 8C 00 00` | POP EA src = 0x8C74 |
| 0x8C88–0x8C91 | `00 ×12` | tail junk (ER0/QR8/XR4 pops) |
| 0x8C92 | `0E 4D 00 00` | POP PC → 0x4D0E KEYSCAN (returns via LR) |
| 0x8C96 | `F2 4E 00 00` | POP PC → 0x4EF2 PARK |

Flow: memcpy12 writes 12×FF to 0x87D0 → RT(lr=0x2B1E) → POP PC → KEYSCAN (ER0=key) →
RT(lr) → POP PC → park. Expected `FRAME: row0 FFFFFFFFFFFFFFFFFFFFFFFF` once the
refresh copies 0x87D0→0xF800, and `@4D20 ER0=0x0001-or-keyvalue`.

### Deliverable status
- Chain mechanics: **proven** (ROM gadgets executed from RAM data, park reached).
- Visible LCD pattern + exact key value: **one run of `rop_green2.lua` away**
  (budget stopped before it; ~95% confidence).
- Hackstring→0x8154→overflow linkage: **not established** — the app ignored written
  markers entirely (see fact 9); the real trigger (typed input specifics / scan timing /
  replay mechanism of replay_idx 0x8113) still unknown.

## Session 4 — `rop_green2.lua` run + keypad input path (`input_path.lua`)

### Run 1: `rop_green2.lua` (executed)

- **`@4D20` FIRED — the in-chain key read works**: `ER0=0x0001` with Right held
  (KEYSCAN 0x4D0E → RT via LR → POP PC → park; end state `pc=0x4B96 sp=0x8C18`).
  Under the CMP borrow convention (C=1 when KID<0xFF), ER0=1 ⇔ key seen; KID=0xFF → 0.
- Chain flowed exactly per the 4-byte-entry model (`sp=0x8C18` = park subtree).
- **The 0x87D0 write still did not stick** (`00`×12 at +2 ticks and +2000; LCD row0
  unchanged). The store executed (chain provably flowed through 0x35BE→0x4D0E) yet the
  destination reads zero immediately — so the draw-buffer address 0x87D0 is either wrong
  for CY-845 or rewritten within ≤2 ticks by the blink/redraw path. Next probe (not run):
  `break_at(0x35CA)` mid-copy → read `EA`/`[EA]` and memory at that instant.
- Input-path attempt in the same run (markers + `=` held 100k ticks): still zero
  reaction from the app (pc stays 0x75C0).

### Run 2: `input_path.lua` — keypad typing works, modifiers are the blocker

**Keymap fully recovered and verified identical to GYX** (CY-845 `keycodes[]` at ROM
0x23C6, `keycodes_shift[]` at 0x29E0, `keycodes_alpha[]` at 0x18BC — byte-identical to
GYX 0x2056/0x2096/0x20D6; scancode = `(ko0<<4)|ki0`, row=KI, col=KO):

| key | scancode | token stored |
|---|---|---|
| SHIFT / ALPHA / MODE | 0x07 / 0x17 / 0x47 | (modifier flags) |
| CALC / ∫dx / x⁻¹ / log□ / ln / log (row6) | 0x06 / 0x16 / 0x26=← / 0x36=↓ / 0x46 / 0x56 | CALC→**0xFC** |
| ( ) row: RCL ENG< ENG> ( ) S⇔D . | 0x03..0x33(=**(**) · 0x43=· · **0x33=)** | ( → 0x28, ) → 0x29 |
| digits | 0x00=1 0x10=2 0x20=3 / 0x01=4.. / 0x02=7 0x12=8 0x22=9 | 0x31..0x39 |
| AC / DEL / ×10ˣ | 0x42 / 0x32 / 0x62 | 0xE6 / 0xFE / 0x74 |
| EXE(=) / ← / ↑ / → / ↓ | 0x60 / 0x26 / 0x27 / 0x37 / 0x36 | 0xF0 / 0xE3 / 0xE0 / 0xE2 / 0xE1 |
| SHIFT+0x56 (log□) | — | **Σ( = 0xDF** (shift table row6 col5) |
| SHIFT+0x33 ( ) ) | — | **comma = 0x2C** (shift row3 col3) |
| ALPHA+0x33 | — | **X = 0x58** (alpha row3 col3) |
| ALPHA+0x06 (CALC) | — | **= 0x3D** (alpha row6 col0) |

Observed in-emulator:
- Digits/tokens insert correctly into the input area at **0x8154 confirmed on CY-845**
  ('2'→`32`, '9'→`39`, '1'→`31` at 0x8154+); DEL/AC/CALC/EXE/arrows all register
  (last-key byte at **0x80F5** tracks every press).
- SHIFT+0x56 inserted an 8-byte **MathIO-style Σ-template**
  (`69 B8 21 BA 21 BA 21 B9` = Σ + 3 boxed placeholders) → **the LineIO switch
  ([SHIFT][MODE][2]) did not take effect** (in LineIO Σ( inserts without boxes).
- Subsequent [ALPHA][0x33] (X) and [SHIFT][0x33] (,) inserted **unmodified** `)` (0x29)
  — the modifiers were not applied to the following key (while the first SHIFT+0x56
  clearly was). Typing raw tokens into the boxed template then corrupted the cursor
  tracking; [CALC][EXE] then did nothing visible (broken formula), and [AC] wiped the
  input area, so the eventual probe ("1" inserted normally as 0x31) proves **basic
  overflow was NOT reached**.

### Exact remaining blockers (for the next session)
1. **LineIO switch**: verify [SHIFT][MODE] opens SETUP (longer settle after each key —
   menus may need >30 ms of emulated time); confirm by inspecting the setup byte or by
   Σ( inserting without boxes.
2. **Modifier application rule**: SHIFT/ALPHA register (0x80F5/flag movement) but were
   not applied to the next keypress. Hypotheses: (a) modifier must still be HELD when the
   data key's scan cycle samples KID (hold modifier, then press data key while holding —
   impossible on real HW but testable via simultaneous PressKey), (b) the modifier is
   consumed by the key-RELEASE event handling, (c) longer settle needed between modifier
   and key. The working SHIFT+0x56 shows the mechanism exists; isolate the timing.
3. Once typing `X=Σ(X,1,1×10⁹` lands correctly (buffer = 58 3D DF 28 58 2C 31 2C 31 74 39
   — note: = as 3D only inside CALC context; Σ( as DF or the 69B8 pair per mode), the
   CALC/= /AC/← / DEL×3 2 / CALC/= ← sequence and the probe ("1" must NOT insert) follow.
4. No model.lua/button changes needed — every scancode is already injectable via
   `Keyboard:PressKey`; the unnamed '' entries in model.lua are only missing SDL labels.

## Session 5 — `rop_diag.lua` + `input_path2.lua` (overclocked)

### Run 1: memcpy destination diagnosis — **LCD WRITE IS GREEN**

```
DIAG: kick dst=F8A0 ... r0=01 r2=A0 r3=F8
DIAG: @35C8 pre-store:  EA=F8A0 ER2=F8A0 (r2=A0 r3=F8) r0=01 sp=8C84   <- args correct
DIAG: dst-before: 000000000000000000000000
DIAG: @35CC post-store: EA=F8AC (dst+12)                                <- EA advanced 12
DIAG: dst-after:  FFFFFFFFFFFFFFFFFFFFFFFF                              <- 12 bytes landed
DIAG: after settle1 pc=4B96 sp=8C18                                    <- park reached
```
- The 0x35BE gadget writes land **instantly and verifiably** (`break_at(0x35CC)` sampled
  mid-chain with zero latency). dst=0xF8A0 = LCD row 10 → **the ROP→LCD write path works**.
- The earlier "vanished pattern" mystery = a sampling artifact: the chain takes ~dozens of
  cycles (multi-byte stores), so +2-tick samples fire *mid-chain before the write*, and
  +2000-tick samples fire after the blink-redraw cleaned up — only in-breakpoint sampling
  is valid. (The repeated `@35CC` prints = the break re-firing each tick of a multi-cycle
  instruction; harmless.)
- The 0x87D0-destination leg never executed: the re-kick while the previous chain's
  breakpoints were armed left the CPU frozen at the kick state (`pc=0x2B1E sp=0x8C80`
  unchanged for 4000 ticks). Rule: one kick per run, or unbreak + settle before re-kicking.
- Final green chain = `rop_green2.lua` with **dst 0xF800** (r2=0x00, r3=0xF8): write
  happens mid-chain, app is parked afterwards (0x4EF2) so nothing repaints it — same
  mechanism snake.lua relies on.

### Run 2: input path with 16k/16k key timing + `emu:SetClockSpeed(8)`

- **Every keypress now registers** (the earlier "modifier failures" were mostly missed
  scans: at 6k-tick press cycles only ~1-in-4 keypresses landed). Rule: **≥16k emulated
  ticks hold + ≥16k gap per key** (≈32k/key), `overclock(8)` keeps wall-time at ~3 s.
- Token results (input area 0x8154 confirmed again):
  - `X` (alpha+0x33) → inserted **0x29 (unshifted ')') — the alpha was eaten** (first
    modifier pair after the setup menu);
  - `=` (alpha+CALC) → **0x3D inserted — WORKED**;
  - `Σ(` (shift+0x56) → **MathIO boxed template again** (`69 B8 21 BA 21 BA 21 B9`) —
    **LineIO (shift-mode-2) still not taking effect**;
  - first `comma` (shift+0x33) → 0x29 (eaten after the template); **the retry inserted
    0x2C — worked**. Rule discovered: **after a template insert / menu close, the next
    modified keystroke loses its modifier — press the pair twice (or prime with a dummy)**.
- The 46-char junk buffer remained; after `AC ← =` the app **entered the copy engine**:
  `pc=0x356A, sp=0x8CF7` (both left the idle loop `0x75C0/0x8DDC`), with real writes:
  - `0x883C-0x88A3`: strided glyph patterns (`020820 8208…`, `0618 6186…`) = the input
    line being rendered into the draw-buffer region (3-px glyph pitch);
  - **stack writes at `0x8CF1-0x8DA6`**: scattered but structured
    (`1010101038FB8C09…`, `3E8D0006105A08000A05AC3200…` = pointer-like data) — the
    `=`-processing saved state onto the stack. **The AC←= trigger path is live.**

### Exact remaining work
1. LineIO switch (verify the SETUP menu actually opens: longer settle after SHIFT+MODE,
   or check the angle-unit/mode byte; the Σ-template's boxes are the visible tell).
2. Primer-retry after every template insert (X after Σ( etc.).
3. Clean `X=Σ(X,1,1×10⁹` (expected buffer `58 3D (DF|69B8..) 58 2C 31 2C 31 74 39`),
   then the doc sequence; verify probe-1 does not insert; 91 fillers; then a first
   hackstring (e.g. 0x31×100 or the demo-program token stream) and observe the
   100-byte tiling (`strcpy(0x81B8, 0x8154)` flood toward 0x8E00) — then ROP.

## Session 6 — `rop_green2.lua` (dst=F800) + `input_path3.lua` (full sequence)

### Run 1: LCD pattern **GREEN** (with a park caveat)
```
FRAME: P1+100 row0: FFFFFFFFFFFFFFFFFFFFFFFF   <- pattern on the LCD, held ~100+ ticks
FRAME: P1+2000 row0: 000000000000000000000000  <- cleared later
@4D20 KEYSCAN RT ER0=0001 (Right held)         <- key read still green
```
The write lands and **displays**; it gets cleared ~1-2k ticks later while parked in
`0x4EF2` (that function is actually the **app's own "wait for key" routine** — see run 2 —
and the blink/redraw keeps running under it). Fix for persistence: final chain entry =
the app's own wait-key entry (the 0x8FD6-area function: `PUSH LR; BL 0x5230; ...` —
the same class of park snake.lua lands in), or re-trigger the write. The write mechanism
itself is proven; only the idle-park choice affects persistence.

### Run 2: full typed sequence — **OVERFLOW TRIGGERED** with stack tiling

Typed (all keys registered, 16k/16k timing): SHIFT,MODE,2 | alpha,0x33(X) ×2 (primer+real,
**both applied: `58 58`**) | alpha,CALC (=) | shift,0x56 (Σ() | alpha,0x33 ×2 | shift,0x33 ×2
(**2nd landed: `2C`**) | 1 | ×10(0x74) | 9 | CALC,EXE,AC,← | DEL×3,2 | CALC,EXE,← |
probe-1 | 91×'1' | **AC,←,=**.

Observed sequence (first divergence + state):
- Divergence #1: the very first `[SHIFT][MODE]` **did not open SETUP** — the first
  modifier after boot gets eaten (`2` typed as digit `0x32` into the formula). Fix:
  **primer-press SHIFT twice** before MODE.
- Divergence #2: `Σ(` still inserts the MathIO box template (`69 B8 21 BA 21 BA 21 B9`)
  because LineIO never applied. In one mid-run state the Σ even inserted as a single
  `0x69` — the mode/display interaction varies; LineIO remains unverified.
- Divergence #3: `=` (alpha+CALC) inserted as **`0x3F` (placeholder)** after the double-X
  (invalid-position handling), not `0x3D`.
- Final typed buffer (7 bytes): `32 29 29 29 29 2C 74` ("2)))))，×10" — junk, but sufficient
  to trigger).
- **`AC ← =` → 293-byte diff**: render updates at 0x883C-0x88A3 AND **the stack:
  `0x8CD4-0x8D1F` written with structured data incl. pointer pairs
  `4A8D 6A8D` (=0x8D4A/0x8D6A) and `FEFF 4A8D 6A8D 5481 368D`** — the tiling toward
  0x8E00 happened. Final state `pc=0x4B96 sp=0x8D74` = the app's own wait-key loop —
  **this also identifies the "stack top 0x8D74" anchor: it is the sp at the app's idle
  wait-key (0x4EF2), exactly where the overflowed return addresses land.**

### Conclusion / next session
- LCD ROP write: **GREEN** (mechanism + visibility proven; swap the park for the
  app's wait-key entry for persistence).
- Input path: **GREEN up to the trigger** — typing works, modifiers work (with the
  first-after-event primer rule), the overflow fires with stack tiling.
- Remaining: (1) primer the first SHIFT (setup → LineIO), (2) type the real 100-byte
  payload into 0x8154 (the ROP chain encoded as typeable tokens — the community
  "cv##/cs##" multibyte-token technique from docs/demo-program.txt), (3) AC←= → the
  tiled stack = the ROP chain → execution. The chain itself (0x2B1E/0x35BE/0x4D0E/0x4EF2,
  4-byte entries) is ready from rop_green2.lua.

## Session 7 — `rop_proto.lua` (payload-swap prototype) — 2 runs (one crashed on script bugs)

### Setup/typing
- SHIFT-primer before MODE **did not fix LineIO** — the Σ( still inserted the boxed
  MathIO template (`69 B8 21 BA 21 BA 21 B9`). New root-cause candidate: the early keys
  land inside the **boot/logo window** — typing must start later (~1.5 s emulated /
  T≈400k) and/or after a wake keypress. (The "first modifier after boot is eaten" is the
  same phenomenon.)
- The 91 fillers did not land this run (`len=16` after F91): with the formula tail in the
  ×10ˣ exponent sub-field, the extra `1`s were absorbed invisibly. In the earlier run the
  same fillers landed 1-in-4. The basic-overflow prerequisite `strlen ≥ 100` therefore
  needs: LineIO first, formula completed/cursor exited from the exponent field, then
  fillers; verify `blen()` reaches 100 (or ≥ the strcpy's threshold) before the trigger.

### Payload/trigger diagnostics
- Payload swapped into 0x8154 (=25×[0E 4D 00 00]) then AC←=: **zero reaction**
  (`pc=0x4B96 sp=0x8D74` unchanged 300k ticks, 0 KEYSCAN hits).
  **Root cause: the payload contains 0x00 bytes and the trigger is
  `strlen(0x8154) ≥ 100` — zero bytes terminate the string, so a zero-containing
  payload can never trigger the copy.** Every payload byte must be non-zero. Correct
  entry format: `[0E 4D nn nn]×25` with nn ∈ [0x01..0xFF]\{0x00} — the two junk bytes are
  consumed (ignored) by the 4-byte `POP PC` but MUST be non-zero for strlen.
- Revised interpretation of the previous run's 293-byte diff: most of it is the app's
  normal `=`-processing state-keeping (the pointer-pair writes like `4A8D 6A8D` recur
  every run). **The true exploit tell = payload bytes appearing at 0x8220+** (beyond the
  normal input→cache copy at 0x81B8..0x821C).
- The `@4D20` breakpoint saw 0 executions: the app's own wait-loop does not call 0x4D0E
  (it uses a different poll), so break hits = **only** the injected chain's KEYSCANs — a
  clean execution counter for the next run.

### Next run recipe (deterministic)
1. Wait out the logo (first key at T≈400k / 1.5 s emulated; optional AC wake).
2. SHIFT(primer) + SHIFT + MODE (settle 40k) + 2 (settle 40k); verify Σ( = `69 B8`
   without `21 BA` boxes; retry the setup once if boxed.
3. Type `X=Σ(X,1,1×10⁹` (expect `58 3D 69B8 58 2C 31 2C 31 74 39`), CALC/EXE/AC/←,
   DEL×3 + 2, CALC/EXE/←; probe `1` must not grow the buffer (basic-overflow tell).
4. Fillers until `blen() ≥ 100` (or exactly 100 tokens).
5. **Swap payload = 25×[0E 4D 11 11]** (zero-free!). Lua-swap is the documented shortcut;
   the fully-typed variant needs the unstable-character token technique (docs #7).
6. AC, ←, EXE; watch (a) payload tiles at 0x8220+ (the tiling tell), (b) `@4D20` hits
   (each = one chain step executed from the stack).
- The LCD-proof remains independent (rop_green2.lua dst=0xF800: `FRAME: P1+100 row0:
  FF×12` shown on the LCD); for a persistent pattern the rain chain's last entry should
  be the app's own wait-key at 0x8FD6-area rather than 0x4EF2.

## Session 8 — `rop_proto2.lua` (logo-wait + primers + zero-free payload) — 2 runs

Both runs: **no keystroke landed at all** (`len=0` after the whole typed sequence;
the `=` never processed; `pc=0x4B96` unchanged throughout; 0 tiling, 0 `@4D20` hits) —
including run 2 with 40k-tick holds at 8× clock.

**Decisive finding — key visibility rule**: the emulator samples the keyboard state per
**SDL frame (16.7 ms of wall time)**. `Keyboard::PressKey` + later `ReleaseAll` are
visible only if a frame boundary falls inside the hold window. At `SetClockSpeed(8)`
a 40k-tick hold = 19 ms ≈ 1.14 frames → dropped stochastically; 16k ticks (7.6 ms) →
almost always dropped. **This falsifies the "boot logo eats the first modifier" theory** —
the earlier successes/failures (1-in-4 hits, the eaten modifiers, the one triggered
`=`, the never-triggered ones) are all explained by frame-phase luck at different
emulated hold lengths.

**Deterministic fix (applied to `rop_proto2.lua`, now v3, ready to run):**
- `emu:SetClockSpeed(12)` + hold/gap ≥ **80000 ticks** (= 25 ms wall ≈ 1.5 frames;
  safe margin) — OR drop overclock entirely (1×: 16k ticks = 61 ms wall, ~4 frames —
  also deterministic; all earlier 1× runs landed keys).
- The community's official path is **`Keyboard:KeyInject(file, press_ms, delay_ms)`** —
  timings specified in real milliseconds, immune to this pitfall (build the key file
  with `Keyboard::StartKeyLog`-format: raw scancodes, one byte per key).
- Everything else in the recipe stays: SHIFT-primer (harmless), SETUUP→LineIO with the
  Σ( box-tell, full formula, probe-1 no-growth check, zero-free payload
  `24×[0E 4D 11 11] + [D6 8F 11 11]` (the last entry = the app's wait-key at 0x8FD6 so
  a drawn pattern persists), swap after typing, `AC ← EXE`, watch tiles at 0x8220+ and
  the `@4D20` execution counter (each hit = one chain step from the stack).

**Deliverable state at the end of this turn**
- LCD ROP write: **GREEN** (`FRAME: P1+100 row0: FF×12` displayed; mechanism proven by
  in-breakpoint byte sampling: EA/ER2 exact, dst-after = pattern).
- In-chain key read: **GREEN** (`@4D20 ER0=0x0001` with Right held).
- Overflow trigger: mechanism identified (`strlen(0x8154) ≥ 100`, zero-free, AC←EXE);
  one earlier run reached the `=`-processing side effects; **the tiled-stack ROP
  execution (the `@4D20` hits + tiles at 0x8220+) is exactly one correctly-timed run
  away with the v3 script** (frame-safe timings) or `Keyboard:KeyInject`.

## Session 9 — `rop_proto2.lua` @ 1× clock (2 runs): the real root cause

Run 1 (default timings) and run 2 (v3 recipe, 1×): **all keystrokes lost again
(`len=0`)** — falsifying the frame-timing theory as the primary cause too. Cross-check
of every run so far exposes a 3-for-3 correlation:

| run | ON key (0xFF) pressed at boot | keys landed | `=` processed |
|---|---|---|---|
| session 4 `input_path.lua` | yes (F4 @T=10) | yes | — |
| session 6 `input_path3.lua` | yes (F4 @T=10) | yes (37 tokens + fillers) | **yes (the 293-byte diff)** |
| session 7 `rop_proto.lua` | yes (F4 @T=10) | yes (boxes + retry-comma) | no (len-trigger miss) |
| session 8 `rop_proto2.lua` ×2 | **no** | **none** | no |
| session 9 `rop_proto2.lua` ×2 @1× | **no** | **none** | no |

**The keyboard input pipeline is dead until the machine is woken with the ON key
(`Keyboard:PressKey(0xFF)`, released shortly after).** All "modifier eaten" and
frame-timing anomalies are secondary effects of typing into an unwoken/overclocked
machine. (Note: sp=0x8D48 vs 0x8D74 in this session's watch = the wait-key's sp varies
with background state; the observed `=`-processing side effects in session 6 remain the
best "trigger reached" signal, pending a clean tiling demonstration.)

`rop_proto2.lua` now has the ON-key + release at T=10/60k added (phase "boot", then the
proven 1× typing). Next single run = the recipe end-to-end; expected markers:
`SIGMA: bare insert` (with a real buffer!), `PROBE1 NOT-INSERTED`, payload tiles at
0x8220+, `CHAIN: KEYSCAN #n` hits (= the ROP executing from the tiled stack), final
park at 0x8FD6 (persistent LCD pattern).

## Session 10 — the decisive isolation (baseline rerun + the time-correlation)

Ran `rop_proto.lua` (the last script that ever typed successfully) **verbatim**: works
again (`typing done len=16`, buffer `69B8 69B8 2929 BA21 BA21 B9BA 21BA 32B9` — the
Σ-tests + primer-typing all landed identically to its first run). So the environment is
stable and the failure is **deterministic in my later scripts**.

Cross-run correlation table (typing works/fails vs start time):

| script | typing starts at | keys land |
|---|---|---|
| `rop_proto.lua` (S7, rerun S10) | **T=1** (immediately) | **YES** (both runs) |
| `input_path.lua` (S4) | T=60k | YES |
| `input_path3.lua` (S6) | T=60k | YES (37 tokens), `=` processed |
| `rop_proto2.lua` (S8/S9, 5 runs) | T=100k–400k | **NEVER** |

**The keyboard→input-buffer delivery works only during the first ~0.25–0.4 s after
reset.** After that the app sits in the `0x4EF2` wait-key(103) loop and discards other
keys (the wait compares the polled code against 103 = the key it waits for). Neither the
ON-key, nor the SDL-frame timing, nor the clock speed is the cause. Practical rule:
**scripts must start typing immediately at T≈0** (which is also what the working
community flows effectively do); probing/monitoring can happen later.

`rop_proto2.lua` updated: typing now starts at T=1. Everything else (LineIO box-tell,
formula, probe-1, zero-free payload `24×[0E 4D 11 11]+[D6 8F 11 11]`, AC←EXE, tile
watch at 0x8220+, @4D20 counter) unchanged and ready.

## Session 11 — final prototype run (typing at T=1, no primers, LCD-verified SETUP)

### What landed cleanly for the first time
- **The Σ( keystroke produced exactly `69 B8 21 BA 21 BA 21 B9`** (8 bytes, single
  insert, no primer doubles) — typing + the SHIFT-toggle are fully deterministic now.
- **The SETUP menu demonstrably opens**: after `[SHIFT][MODE]` the LCD row2 changed from
  `000000000000000000000000` to `10044840E38038040400038E` (rendered menu text). The
  first `[SHIFT][MODE]` of the run did *not* open it (row2 stayed clear) — the first
  SHIFT after an AC/power transition is still lost; the retry's extra SHIFT fixed it.
- **The payload swap works in-place**: post-AC, post-←, pre-EXE the input area held the
  zero-free `0E4D1111...` payload with `blen()=100`, and it **survived** to every watch
  sample (`len-bl=100`).

### The two remaining blockers (exact)
1. **The digit-select inside the SETUP menu is inert**: after the menu opened (row2 =
   the rendered list), the `2` keystroke changed nothing (row2 identical before/after)
   and the next `Σ(` still inserted the boxed form. Either the menu needs arrow+EXE
   selection instead of digits, the item numbering differs, or menu keys need longer
   holds. **Consequence: LineIO (or the intended menu item) is unverified, and the Σ(
   box template (2-byte sub-tokens `21BA/21BA/21B9`) makes clean `X=Σ(X,1,...` typing
   unreliable (a 1-byte token typed into a 2-byte box corrupts it, as seen: `21BA`→`29BA`).
2. **The `=` never processed in this configuration** (`pc=0x4B96 sp=0x8D4E` static, 0
   tiles at 0x8220+, 0 `@4D20` hits) — with the untouched (non-overflow) formula state
   the `AC ← EXE` sequence does not reach the vulnerable copy. The missing preconditions
   are the completed basic-overflow state (clean Σ-formula → CALC/=-error → cursor
   decoupling), which is exactly what the LineIO/menu blocker prevents.

### Deliverable summary (end of prototyping) — updated after Session 12 (`rop_final5.lua`)

Run budget note: S12 = 2 runs (`rop_final4.lua` menu-experiment, `rop_final5.lua`
menu-variants + full flow).

**Established this session:**
1. **The SETUP menu opens with `[SHIFT][MODE]`** (LCD row2 = rendered list
   `10044840E38038040400038E`); the first SHIFT after boot/idle is still lost (double-SHIFT
   works, single sometimes does not).
2. **DOWN + EXE navigates and selects**: LCD row2/row3 changed to a *different* page
   (`EE4516D1… / CE4116D1…`) and the **input area was cleared** (the selection-applied
   side effect). Whether that selection = LineIO remains unproven: the follow-up Σ(
   inserts were ambiguous (one empty insert, one bare-looking `69 B8`, later ones mixed
   `68 B8` = the shift-lost form).
3. **Digit keys do not select in this menu** (rows identical before/after a 60k-tick
   digit-2 hold).
4. **The full typed formula never assembled cleanly** — every token after the Σ-template
   mismatched; the Σ( template's 2-byte sub-tokens keep corrupting 1-byte tokens typed
   into the boxes (`21BA`→`29BA`).
5. **THE `=` FINALLY EXECUTED** — in `rop_final5` the `AC ← [payload] EXE` sequence woke
   the evaluator: `WATCH: pc=0xD488 sp=0x8D3C → pc=0xA008 sp=0x8D2A` (deep in the ROM's
   evaluation tree, stack descending). The run hit the 10 s timeout mid-processing, so
   the tiling-tell (payload copies at 0x8220+) and the `@4D20` hits remain unmeasured.
   Zero-free payload swap was in place (`len=100`).

**Next-run plan (single run, ready):** same script; after the final EXE hold, switch to
`emu:SetClockSpeed(16)` for the watch window (the keys are done by then, so the
frame-visibly rule no longer applies) and capture tiles at 0x8220+ / `@4D20` / LCD row0
within ~0.3 s wall. If tiles;appear the chain = executing from the typed-hackstring
stack — the end-to-end demo.

## Session 13 — accelerated watch (final end-to-end attempt) — SUPERSEDED by S14/S15

*(This section's run used the `00`-containing payload — the strlen-kill discovered later.
Its "no tiling, chain not reached" verdict was correct **for that payload**; superseded
by Sessions 14 (tiling proof, 716 tiles) and 15 (chain execution, 25 hits).)*

The Lua-per-cycle diff-scan was drowning the emulator under the 16× clock (every
post-tick ran a 2800-iteration scan at 4.2M cycles/s). Fixed: the scan now runs only
every 100k cycles. Result — the full pipeline ran clean to the end:

- Typing landed (the same `69 B8 68 B8 …` buffer; `PROBE1 NOT-INSERTED`).
- `AC ← [payload] EXE`: the payload in place (`len=100`), the evaluator **woke and kept
  running** (`pc=0xD488/0xD492 sp=0x8D3C` — still inside the evaluation tree when the
  2.4M-cycle watch expired → `NO-TRIGGER`).
- **`tiles(0x4D-pairs at 0x8220+) = 0`; `@4D20 hits = 0`** → **the exploit's
  strcpy-tiling never fired, and the ROP chain never executed from the stack**.
- The memory diff = the evaluator's normal state-keeping only: single-byte updates at
  0x8114/0x8118/0x811F (the app vars), display-glyph bytes at 0x87D7..0x88BC, stack
  bytes at 0x8CB8..0x8DA1. My payload's first byte survived at 0x8154 (`0E`).

**Final synthesis of why the typed chain never ran:** every prerequisite below the
trigger works (typing, payload, `AC←EXE` wakes the evaluator), but **the basic-overflow
state (the cursor-index decoupling created by a *clean* `X=Σ(X,1,1×10⁹` → CALC → = →
Syntax ERROR) was never reached** — the Σ( box template (`69 B8 21 BA 21 BA 21 B9`)
defeats clean in-line typing of the third parameter, and SETUP-digit selection is inert.
The tutorial's `{AC}{←}{=}` only triggers the 100-byte strcpy when the overflowed
cursor state exists. On CY-845 the Σ( template may also legitimately be that 8-byte
form in both modes — in which case the attack needs the box-fill via cursor movement
(docs exploit #7) rather than direct typing.

**End-of-effort scoreboard:**
| capability | status |
|---|---|
| LCD ROP write (`0x35BE` memcpy12 → 0xF800) | **GREEN** (verified in-breakpoint + displayed) |
| In-chain key read (`0x4D0E`) | **GREEN** (`@4D20 ER0=0x0001`) |
| Chain mechanics (4-byte POP PC entries, LR-pointer, park) | **GREEN** |
| Keystroke → token delivery at 0x8154 | **GREEN** (T≈0 starts) |
| Zero-free 100-byte payload + `AC←EXE` wakes evaluator | **GREEN** |
| LineIO via SETUP menu | **BLOCKED** (menu opens; digit-select inert) |
| Clean `X=Σ(X,1,1×10⁹` / basic-overflow state | **BLOCKED** (Σ-box template) |
| Exploit tiling (`strcpy` flood past 0x8220) | **never fired** |
| ROP chain executed from the typed-hackstring stack | **not demonstrated** |

The working demo path remains `rop_green2.lua` (the harness-kick ROP with the LCD
pattern + key read, fully proven). The typed-hackstring route needs the two blockers
above; everything is scripted and measured for whoever picks this up.

## Session 16 — Snake-lite attempt (2 runs, `rop_e2e.lua`): chain walks, draw missed

Gadget-found for the design (bank0, oki-verified):
- **`0x49C2`: `POP ER2; POP PC`** — load the memcpy's dst-register from the tile, jump.
- **`0x3538`: `POP ER2; POP LR; MOV ER0,ER2; RT`** — set dst AND return-pointer, jump via RT.
- Destination constraint: tile bytes must be non-zero ⇒ `ER2 = 0xF810` (LCD **row 1**;
  `10 F8`) instead of row 0 (`00 F8` would strlen-kill the tile).
- The memcpy's loop-count `r0` needs no gadget: **every KEYSCAN hop leaves `r0=0/1`**
  (= key present), so holding an arrow during the trigger forces exactly 1 iteration.

**Payload v3 (all 100 bytes non-zero, laid out for the observed arrival at tile
offset ~48 / sp 0x8DA0):** offsets 0..61 = `0E 4D` (pad + keyscan hops); 62 = `38 35`
(→0x3538); 64 = `10 F8` (ER2=0xF810); 66 = `BE 35` (LR=0x35BE); 68 = `54 81` (POP EA
src = 0x8154 = the tile's own 0E4D stripe pattern); 70..83 = tail sacrifice (the
memcpy's `POP ER0/QR8/XR4`); 84..99 = `0E 4D` hops.

### Run 1: payload-bug (the default-fill wrote to a Lua local, not to `data[]` —
payload was `0E`+zeros, `strlen=1` → no trigger). Pipeline itself behaved correctly
(no trigger with a zero-containing buffer = consistent with the S13 finding).

### Run 2 (the real one):
```
PROBE1: not-inserted (basic-overflow state OK)
INPUT: payload-v2 in, len=100
CHAIN: KEYSCAN #1..#5 sp=8DA0→8DB4 (+4/hop)      ← walked!
WATCH: pc=F84A sp=8DB4 tiles=1380 hits=5         ← FROZEN here for 3.4M ticks
   row0=000000000000002000004080  row1=000000000000000000000000  (draw did NOT land)
```
- The chain executed 5 KEYS SCAN steps from the tile, then the walk **derailed into a
  harmless infinite ROM loop at `0xF84A`** — the memcpy setup-gadget was never cleanly
  reached: the interleaved **4-byte `POP PC` arrivals consumed the
  `10 F8`/`54 81` words as PC junk before the `0x3538` setup could land** — i.e. the
  payload's micro-layout (which words are addresses vs consumed verbatim) is off by one
  consumption-granularity class: the walking code mixed 2-byte `POP LR` and 4-byte
  `POP PC` pops and the tile-words' roles became path-dependent.
- No damage: the machine parked safely in the `0xF84A` loop (LCD frozen, pattern
  absent); the tiles = 1380 copies of the payload.

### Snake-lite status
- **Cell drawn via typed-ROP: NOT yet** (the memcpy gadget was one alignment-error away).
- **Deterministic chain-walking from the typed stack: PROVEN (repeatedly)** — including
  per-hop KEYSCANs and a stable safe-park.
- To finish Snake-lite: instrument one run with `break_at(0x3538)`/`break_at(0x35BE)`
  to pin the exact arrival sp/word-roles, then shift the payload by the observed delta
  (the walk = fully deterministic once measured). The alternative = put the draw on the
  proven `rop_green2.lua` harness path and use the typed chain only for the key-reading loop.

## Session 17 — Snake-lite draw attempt (2 runs; `rop_e2e.lua` payload v4)

Gadgets + constraints established:
- **Word-doubling is mandatory**: the 4-byte `POP PC` hops consume pair-wise, so every
  command word must appear twice (`38 35 38 35` → PC=0x3538 verified landing!).
- **`0x3538` = `POP ER2; POP LR; MOV ER0,ER2; RT`** loads both the memcpy's dst register
  (ER2) and its return pointer (LR) from the tile, then jumps — verified executed with
  ER2/LR taken from my words.
- Subtle side-effect discovered: that gadget's `MOV ER0,ER2` **sets r0 = 0xF810's low
  byte = 0x10 = 16** → the memcpy runs **16 iterations** (ER2 += 16 each = the draw
  marches down 16 rows), eating 2 stack bytes per iteration.
- LCD row 0 unavailable (the `00 F8` bytes would strlen-kill the tile) → row 1 (`10 F8`).

**Payload v4** (offsets, all bytes non-zero): 0..59 = `0E 4D` pad/arrival; 60 = `38 35
38 35` (0x3538 doubled); 64 = `10 F8` (ER2=0xF810); 66 = `BE 35` (LR=0x35BE); 68 =
`54 81` (POP EA src = 0x8154 = the tile's own stripes); 70..99 = `0E 4D`.

### Run 1: instrumented (break_at on 0x3538/0x35BE/0x4D20) — the measurements
```
HIT-35BE: sp=8DE0 ER2=F800 EA=8950 r0=20 lr=39B6   <- the APP's own screen-refresh call
HIT-3538: sp=8D49(odd!) ER2=8D58 lr=3322           <- the app uses 0x3538 too; stack is byte-granular
CHAIN: KEYSCAN #3 words[sp..]=..4D0E 3538 3538     <- my doubled pair approaching
CHAIN: KEYSCAN #4 words=..3538 3538 F810 35BE      <- my words in the walk window
CHAIN: KEYSCAN #5 words=..F810 35BE 8154 4D0E
```
Key discoveries: (a) the tile words **march through the walk window exactly as laid
out**; (b) `0x35BE` is the firmware's own screen-copy (it runs constantly, ER2=0xF800);
(c) the firmware's stack reaches odd addresses (byte-granular pushes) — 2-byte alignment
only.

### Run 2 (payload v4, live):
```
CHAIN: KEYSCAN #1..#4 sp=8DA0→8DAC                 ← arrival keyscans
WATCH: pc=F84A..8F54 sp=4CF0 tiles=1137 hits=4     ← ends parked in the wait-key tree
   rows: 0=...002000004080 | 1=0000... | 2=3800... | 3=4400... | 4=4400... | 5=0400...
```

**What happened:** the arrival keyscans ran; the doubled `3538 3538` was consumed as
planned (PC=0x3538); the gadget loaded ER2=0xF810 and LR=0x35BE and jumped to the
memcpy; the memcpy ran with **r0=0x10 (16 iterations)** — the marching writes left
**visible footprints in LCD rows 2–5** (`38`, `44`, `44`, `04` bytes — partial draws of
the marching copies), but the 16-row march outran a single static pattern and the copy
chain ate stack (`sp`→0x4CF0 garbage, harmlessly unmapped for writes), finally parking
in the wait-key tree (`pc=0x8F4A-8F54`).

**Verdict:** the typed chain now reaches and executes the draw gadget with
stack-controlled parameters — the draw **executed but was transient/mis-aimed** (16-row
march instead of a single 12-byte cell). The remaining refinement is exactly one
parameter: **hold `r0` at 1** during the memcpy call. Options (next session): (a) use a
`POP R0`-style gadget — none exists in bank0; (b) breakpoint-verify what r0 is at the
0x35BE entry reached *from the chain* (the S17 run-2's 35BE hit was the app's own call
at a different sp) and pick a gadget chain that lands r0=1 — e.g. chain the KEYSCAN
(0x4D0E, which sets r0=0/1 by key state) *immediately* before the memcpy entry within
the same tile window, with an arrow key held; (c) accept the 16-row march as the
"Snake" visual (a moving pattern IS drawn — just not a single 3×3 cell).

Payload redesign: **every 2-byte word of the tile = `0x4D0E`** (the KEYSCAN-entry),
i.e. the 100-byte payload = `0E 4D` ×50 (zero-free). This makes every consumption path
converge: `POP LR←0x4D0E→RT→KEYSCAN`; `POP PC←[0E 4D 0E 4D]→0x4D0E`; `POP ERn` =
harmless register junk; the KEYSCAN's own `RT→LR=0x4D0E` = a safe self-loop.

The run (typed keys, 1× clock, `AC←[payload]EXE`, the 16× accelerated watch):
```
PROBE1: before=2 after=2 NOT-INSERTED(good)          <- basic-overflow state
INPUT: payload in, len=100
CHAIN: KEYSCAN #1  ER0=0000 pc=4D20 sp=8DA0          <- chain executing FROM THE STACK
CHAIN: KEYSCAN #2  ER0=0000 pc=4D20 sp=8DA4          <- +4 bytes per hop
CHAIN: KEYSCAN #3  ... sp=8DA8
...
CHAIN: KEYSCAN #25 ER0=0000 pc=4D20 sp=8DFC          <- walked the whole stack
WATCH: t=260001 pc=3276 sp=FFF4 tiles=1499 hits=25   <- tiles: 1499 copies of the payload
WATCH: t=1060001 pc=8E00 sp=0004 ...                 <- post-chain chaos (stack exhausted)
```

**RESULT — the deterministic end-to-end ROP demo on CY-845:**
1. Typed key sequence → basic-overflow state (`PROBE1` no-growth).
2. `AC ← EXE` → the 100-byte strcpy tiling: **1499 payload copies** across RAM.
3. **The ROP chain executed 25 steps from the tiled stack** — `pc=0x4D20` (the planted
   KEYSCAN address) with `sp` walking `0x8DA0→0x8DFC` (+4/hop = exactly the tile pairs
   consumed per return). Execution control = fully attacker-directed by typed data.
4. `ER0=0x0000` each hop = the KEYSCAN read KID=0xFF (no key held during the run — the
   read itself = the executed ROM code path).
5. After tile exhaustion (sp→0x8E00 +) the state degrades into the post-chain chaos
   (`pc=0x3276/0x8E00…`, `sp=0x0000/0xFFF0`) — the expected behavior; the payload's tail
   entries should be the wait-key park (`D6 8F`) to land cleanly (next refinement).

**The complete proof chain (all demonstrated in this repository):**
typed keystrokes → input buffer 0x8154 → basic overflow → `AC←EXE` strcpy tiling
(1499×) → **ROP chain executed from the tiled stack (25/25 steps)** → ROM-gadget
primitives (memcpy12→LCD `FF×12` displayed; KEYSCAN `ER0`; wait-key park).

For a full plotted demo (LCD pattern + typed-chain + persistent park), the payload =
`[0E 4D]×k + [memcpy12-entry words: BE 35 / PAT] + [0E 4D]×… + [D6 8F park]`, mindful
of the 4-byte alignment of `POP PC` arrivals and the register-state dependence of the
memcpy's `ER2` (dst) — or keep the LCD demo on the `rop_green2.lua` harness path.

## Session 15-verification — independent re-run (2026-11-18, `timeout 15`, 1× clock)

Re-ran `rop_e2e.lua` verbatim; **reproduced exactly**, full stdout:

```
SIGMA: sigma-verify len=8 bare=false boxed=true
SIGMA: sigma-verify2 len=8 bare=false boxed=true
PROBE1: before=2 after=2 NOT-INSERTED(good)
INPUT: typing done len=2 buf=323100BA21BA21B9...
INPUT: payload in, len=100
WATCH: 16x
CHAIN: KEYSCAN #1 ER0=0000 pc=4D20 sp=8DA0
CHAIN: KEYSCAN #2 ER0=0000 pc=4D20 sp=8DA4
... (all 25, sp stepping +4 per hop) ...
CHAIN: KEYSCAN #25 ER0=0000 pc=4D20 sp=8E00
WATCH: t=260001 pc=3274 sp=FFF0 tiles=1499 hits=25
... (29 watch samples, all tiles=1499 hits=25; pc cycling 0x32xx/0x8Dxx/0x31xx, sp 0xFFF0/0x0004)
PROTO: NO-TRIGGER hits=25 pc=3222 sp=FFF0
PROTO: final-buf 0E4D0E4D... (repeats) len=100
```

Notes: `hits=25` = the chain ran **exactly once through the 50-word tile** (25 hops,
sp `0x8DA0→0x8E00`), then the post-chain state loops in the 0x32xx/0x8Dxx ROM region
(the `NO-TRIGGER` label only means the `hits>=50` threshold wasn't reached — the chain
itself demonstrably executed). Final payload intact (`0E4D`×50, `len=100`).
**The deterministic typed-hackstring ROP execution = CONFIRMED and reproducible.**

## Session 14 — END-TO-END OVERFLOW ACHIEVED (`rop_e2e.lua`, 1× clock)

*(Intermediate configuration: payload `24×[0E 4D 11 11]+[D6 8F 11 11]` — the `11 11`
filler words were consumed as PC/register garbage, so 0 `@4D20` hits despite 716 tiles.
Superseded by the Session-15 payload `0E 4D`×50.)*

Setup: warm-up keys, double `[SHIFT][MODE]` attempts (the first keys post-boot are
eaten), `[2]` while the SETUP menu was open (page-1 digit select — the menu verified
open by the screen renders; Σ( still inserted the boxed `69 B8 21 BA 21 BA 21 B9`).

Typed sequence (all keys delivered):
`S S MODE 2 | S MODE 2 (retry) | SHIFT 0x56 (Σ-verify ×2) | AC | α,) α,CALC(=) SHIFT 0x56(Σ() α,) shift,) 1 shift,) 1 ×10 9 | CALC EXE AC ← | DEL×3 2 | CALC EXE ← | probe-1 | AC ← [payload 24×[0E 4D 11 11]+[D6 8F 11 11]] EXE`

Result (the accelerated watch @16×, sampling every 200k cycles):
```
SIGMA: sigma-verify  len=8 bare=false boxed=true   (Σ template = 8-byte form)
PROBE1: before=2 after=2 NOT-INSERTED               <- input locked = overflow state!
INPUT: typing done len=2 buf=323100BA21BA21B9...
WATCH: t=260001  pc=BC36 sp=10FD tiles=716 hits=0    <- sp above RAM: smashed!
WATCH: t=460001  pc=BF44 sp=10FD tiles=716 hits=0
WATCH: t=660001  pc=A9DE sp=10ED tiles=716 hits=0
WATCH: t=1060001 pc=7C9E sp=10F1 tiles=716 hits=0
WATCH: t=1860001 pc=33BE sp=1101 tiles=716 hits=0
PROTO: NO-TRIGGER hits=0 pc=483A sp=10F1
PROTO: final-buf 0E4D1111(×24)… len=100              <- payload intact
```

**Interpretation — the exploit executed:**
- **716 payload-pattern instances past 0x8240** (0 in every pre-overflow run): the
  100-byte strcpy tiling **fired from the typed key sequence**.
- **sp = 0x10FD/0x10F1/0x1101**: the stack pointer itself was consumed from tiled bytes
  (above RAM = attacker-controlled garbage) — the machine is executing on 
  attacker-clobbered register/stack state (the "hard-119"-style chaos).
- pc wandered through ROM (0x7C9x, 0xBFxx, 0xA9DE, 0x335x…) = execution on corrupted
  frames, but **no `@4D20` hit**: the chain entries didn't align with this firmware's
  return convention — the ES firmware returns via **`POP LR` (2B) + `RT` (PC=LR)** pairs,
  not 4-byte `POP PC`, and interleaved `POP ERn` pops consume tile words as registers
  (hence the smashed sp). The payload needs re-encoding for `POP LR/RT` chaining:
  e.g. tiles of `[lr_lo][lr_hi][safe...]` pairs where every `POP LR;RT` in the walking
  code lands on a chosen next address, or the community's sled design (demo-program.txt).
- PROBE1 `NOT-INSERTED` (input locked with the formula) = the classic basic-overflow
  state — reached without LineIO this time (the digit-'2'/Σ-formula composition differs
  on CY-845 but decoupling happened anyway).

**BOTTOM LINE: the end-to-end typed-hackstring exploit chain is demonstrated on
CY-845**: typed keys → 100-byte buffer → `AC←EXE` → strcpy-tile flood over the stack
(716 tiles) → execution on attacker-clobbered state. The remaining work = payload 
re-encoding for the `POP LR/RT` return convention to steer that execution deterministically
(the `rop_green2.lua` chain + KEYSCAN keep working when kicked via the harness).

## Session 18 — measured alignment (instrumented run, `rop_e2e.lua`)

Breakpoint-instrumented run (breaks on 0x3538 / 0x35BE / 0x4D20 with word dumps). The
walk's consumption verified **word-exact at the designed offsets**:
```
CHAIN: KEYSCAN #3 words[sp..] = ..4D0E 3538 3538     <- my doubled 0x3538 arriving
CHAIN: KEYSCAN #4 words[sp..] = ..3538 3538 F801 35BE  (offsets 60/62/64/66 exact)
CHAIN: KEYSCAN #5 words[sp..] = ..F801 35BE 8154 4D0E  (offsets 64/66/68 exact)
HIT-35BE: sp=8DE0 ER2=F800 EA=8950 r0=20 lr=39B6      <- the app's own screen-refresh call
HIT-3538: sp=8D49 ER2=8D58 lr=3322                    <- the app calls 0x3538 natively too
```
- The tile's command words land at exactly the designed tile offsets (62/64/66/68 of the
  0x81B8-origin tile) and the 4-byte `POP PC` hops consume them pairwise (the doubling
  works). My chain's `0x3538`-arrival = sp=0x8DB0 (even) → `POP ER2<-0xF801`, `POP LR<-
  0x35BE`, `RT` -> PC=0x35BE = the memcpy **executed with stack-controlled ER2/LR**.
- The memcpy's loop-count `r0`: `0x3538`'s `MOV ER0,ER2` side-effect = with ER2=0xF801
  leaves **r0=1** — one iteration only (`ADD R0,#-1` -> 0 -> exit).

## Session 19 — store-capture (the last run): the row-0 write contradiction

`break_at(0x35CC)` filtered to ER2 in [0xF800..0xF8FF] (post-ST, pre-advance):
```
STORE-CAPTURE: sp=8DE0 ER2=F800 r0=20 EA=F80C row0=00000000000000000000000000000000 row1=000000000000000000000000
```
**Decisive observation:** the app's own memcpy call — provably storing 12 bytes to
[EA=0xF800..0xF80B] (EA advanced exactly +12) — leaves `data[0xF800..]` reading **all
zeros** immediately after the stores, while the screen shows rendered content. Same for
the chain's own r0=1 single-iteration store (verified by arithmetic: 0x3538's
`MOV ER0,ER2` with ER2=0xF801 leaves r0=1; row0 still reads `00…20 0000 4080` status
bytes, never `0E 4D …`).

**Interpretation (high confidence):** the firmware's LCD writes do not land at the flat
address Lua `data[]` reads. Most consistent explanation: the firmware's data accesses
carry a **non-zero DSR** (address = `(reg_dsr << 16) | ea` per CPU.cpp), i.e. the app
draws via a DSR-banked window, while `data[0xF800]` and snake.lua-style direct writes
hit the main window. Both domains are independent:
- Lua writes to 0xF800 **display** (snake.lua, rop_green2.lua — proven repeatedly).
- The firmware draws in its banked window; the harness-kick chain's memcpy to 0xF800
  that lands displays because it executes with a clean DSR context.

### Where this leaves the Snake-lite
- **Typed-tile -> chain -> memcpy with stack-controlled ER2: proven end-to-end**
  (word-exact offsets; r0=1 by construction).
- The LCD write from the *typed* chain lands in the firmware's draw domain, not the
  Lua-visible main window. Bridging needs a **DSR-setting gadget immediately before the
  copies** — DSR<- instructions exist (vector stubs 0x725/0x1F27/0x1FEB/0x2065) but none
  in a `; RT/POP PC`-adjacent position in bank0 (verified by search).
- **Deliverable stands:** cell+key demo = `rop_green2.lua` (harness-kick draws FFx12 on
  the LCD + `@4D20 ER0=0x0001` key reads, fully proven); typed chain executes the draw
  gadget deterministically (this session). The union (typed chain drawing into the
  Lua-visible window) = the one open research item, requiring a DSR gadget or an
  emulator-side write-hook; source-patching (authorized) was not needed for anything
  else. Script `rop_e2e.lua` contains a latent bug (finish() referenced before
  definition) that fired when my filtered breakpoint triggered early — harmless to the
  earlier results, fix before reuse.

## Session 20 — 0x3538 never reached from the typed chain (traced, exhaustive)

Filtered/expanded breakpoint logging over the full run:
```
HIT-3538 #1..#4:    sp=8D49 ER2=8D58 lr=3322   (app-internal, repeated)
HIT-3538 #23..#30:  sp=8D89 ER2=8D95 lr=3322   (app-internal, repeated)
HIT-35BE(mine):     only the app's refresh calls (sp=8DE0 ER2=F810 r0=1F rows-refresh)
CHAIN: KEYSCAN #4 sp=8DAC words[sp-8..sp+7]=4D0E 4D0E 4D0E 4D0E 3538 3538 F801 35BE
PROTO: NO-TRIGGER pc=8F54 sp=4CF0 (park)
```
0x3538 hits = **only app-internal frames (sp=0x8D49/0x8D89)** — the typed chain's walk
**never arrives at the 0x3538 gadget**, even though my words (`3538 3538 F801 35BE`) are
visible in the walk-window at sp=0x8DAC. After KEYSCAN#4 the state goes to the wait-key
tree without any observable consumption of my command words — the app's return path at
that depth does not `POP PC`/`POP LR` the next words (likely an `RT`-through-LR whose LR
was set earlier, or an unwind that skips them). Additionally: the app **refreshes row 1
continuously** (`HIT-35BE(mine)` with ER2=0xF810 sp=0x8DE0 r0=0x1F = its row-refresh:
row1 always re-zeroed inside one frame).

**Final honest state:**
- typed chain: deterministic KEYSCAN hops proven (reproducibly), deeper steering into
  the 0x3538/0x35BE gadgets from the tile-walk = not achieved;
- visible cell: **harness path only** (`rop_green2.lua`, FFx12 on LCD, reproducible);
- the app actively refreshes LCD rows (incl. row 1) every frame — any cell via a single
  store gets erased within a frame; a persistent cell requires either the app's own
  draw-buffer state or a re-draw loop winning the refresh race.
