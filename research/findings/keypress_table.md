# Keypress table — CY-845 ROP typed pipeline (corrected 2026-11-21)

Source of truth: `rop_e2e.lua` (typed queue + final-phase key injection) and
`rop_proto2.lua` (`setup_seq`), verified against the 2026-11-21 run logs
(`/tmp/rop_green2.now`, `/tmp/rop_proto2.now`, `/tmp/rop_e2e.now`).

**Keycode semantics:** these are the emulator's raw keyboard scan codes (see constants in
`rop_e2e.lua: SHIFT=0x07 ALPHA=0x17 MODE=0x47 CALC=0x06 EXE=0x60 AC=0x42 DEL=0x32
LEFT=0x26 DOWN=0x36; 1=0x00 2=0x10 9=0x22 ×10^x=0x62; Right(0x37); Σ key=0x56;
X/var key=0x33`). Buffer bytes read back from 0x8154 are **token/keycode bytes**, not
ASCII — do not decode them as characters (e.g. `32` = "2"-key token, `21 BA` = part of the
Σ MathIO box template, `0E 4D` = payload word 0x4D0E).

## Typed queue — `rop_e2e.lua` (verified in emulator)

Every entry is one physical key press; SHIFT/ALPHA precede their shifted key (one press
each — they are toggles). Default hold/gap: 16000 ticks hold / 20000 ticks gap (1× clock
≈ 61 ms wall per hold); chords use 16000/16000; exceptions noted.

| # | Key (physical) | Code | Hold/Gap (ticks) | Purpose |
|----|----------------|------|------------------|---------|
| 1 | SHIFT | 0x07 | 12000/12000 | warm-up w1 |
| 2 | AC | 0x42 | 12000/24000 | warm-up w2 |
| 3 | SHIFT | 0x07 | 16000/16000 | setup1 mod |
| 4 | MODE | 0x47 | 16000/16000 | setup1 (should open SETUP — **currently opens the mode menu: OPEN**) |
| 5 | 2 | 0x10 | 30000/40000 | setup1 digit-2 (LineIO select) |
| 6 | SHIFT | 0x07 | 16000/16000 | sigma-verify mod |
| 7 | Σ (shift key 0x56) | 0x56 | 16000/16000 | sigma-verify |
| 8 | SHIFT | 0x07 | 16000/16000 | setup2 mod (retry) |
| 9 | MODE | 0x47 | 16000/16000 | setup2 |
| 10 | 2 | 0x10 | 30000/40000 | setup2 digit-2 |
| 11 | SHIFT | 0x07 | 16000/16000 | sigma-verify2 mod |
| 12 | Σ (shift key 0x56) | 0x56 | 16000/16000 | sigma-verify2 |
| 13 | AC | 0x42 | 16000/24000 | clear buffer |
| 14 | ALPHA | 0x17 | 16000/16000 | X1 mod |
| 15 | X (var key 0x33) | 0x33 | 16000/16000 | X1 (expect token 0x58) |
| 16 | ALPHA | 0x17 | 16000/16000 | eq mod |
| 17 | CALC | 0x06 | 16000/16000 | `=` (expect 0x3D) |
| 18 | SHIFT | 0x07 | 16000/16000 | Sigma mod |
| 19 | Σ (shift key 0x56) | 0x56 | 16000/16000 | Σ( (expect 0x69 0xB8) |
| 20 | ALPHA | 0x17 | 16000/16000 | X2 mod |
| 21 | X (var key 0x33) | 0x33 | 16000/16000 | X2 (expect 0x58) |
| 22 | SHIFT | 0x07 | 16000/16000 | comma1 mod |
| 23 | , (shift key 0x33) | 0x33 | 16000/16000 | comma1 (expect 0x2C) |
| 24 | 1 | 0x00 | 16000/20000 | one (expect 0x31) |
| 25 | SHIFT | 0x07 | 16000/16000 | comma2 mod |
| 26 | , (shift key 0x33) | 0x33 | 16000/16000 | comma2 (expect 0x2C) |
| 27 | 1 | 0x00 | 16000/20000 | one2 (expect 0x31) |
| 28 | ×10ˣ | 0x62 | 16000/20000 | x10 (expect 0x74) |
| 29 | 9 | 0x22 | 16000/20000 | nine (expect 0x39) |
| 30 | CALC | 0x06 | 16000/24000 | CALC |
| 31 | EXE | 0x60 | 24000/30000 | EXE |
| 32 | AC | 0x42 | 16000/24000 | clear |
| 33 | Left | 0x26 | 16000/16000 | cursor-left |
| 34 | DEL | 0x32 | 16000/12000 | DEL1 |
| 35 | DEL | 0x32 | 16000/12000 | DEL2 |
| 36 | DEL | 0x32 | 16000/12000 | DEL3 |
| 37 | 2 | 0x10 | 16000/20000 | two (expect 0x32) |
| 38 | CALC | 0x06 | 16000/24000 | CALC2 |
| 39 | EXE | 0x60 | 24000/30000 | EXE2 |
| 40 | Left | 0x26 | 16000/20000 | LEFT2 |
| 41 | 1 | 0x00 | 16000/16000 | PROBE1 (must NOT insert: overflow probe) |

**Typed-queue total: 41 physical key presses** (plus 4 non-key screen-render markers).

## Final-phase key injection — `rop_e2e.lua` (verified in emulator)

Not part of the typed queue; injected directly by `Keyboard:PressKey` per tick:

| When (final_t) | Key | Code | Note |
|----------------|-----|------|------|
| 1 | Right | 0x37 | held until 16001 (KEYSCAN must see a key: ER0 ≠ 0) |
| 1 | AC | 0x42 | with Right held |
| 20001 | Left | 0x26 | held until 36001 (cursor position for copy) |
| 36001 | — | — | payload swapped into 0x8154 (Lua write, not a keystroke) |
| 40001 | EXE | 0x60 | held until 60001 → triggers the overwrite/tiling |
| 60001 | — | — | clock set to 16× for the WATCH phase |

**Total physical keypresses per `rop_e2e.lua` run: 41 + 4 = 45.**

Verified outcomes tied to these keys (2026-11-21 run log `/tmp/rop_e2e.now`):

```
PROBE1: before=2 after=2 NOT-INSERTED(good)
INPUT: typing done len=2 buf=323100BA21BA21B9...   (only tokens 32,31 landed; rest = Σ-box residue)
CHAIN: KEYSCAN #1 ER0=0000 pc=4D20 sp=8DA0 lr=2B1E ... #22 sp=8E00    (baseline rop_e2e; rop_park1/2+park: 20 hops → park)
MBE-HIT[E:35BE] sp=8DAC ER2=F801 EA=F040 r0=01 lr=2B1E src=8154 src12[8154]=0E4D0E4D0E4D0E4D0E4D0E4D   (rop_draw3: memcpy12 row-0 draw)
WATCH: t=160001 pc=4B96 sp=8D7C tiles=1194 hits=17 ...   (rop_draw3: draw + park, sp=8D7C)
```

## SETUP sequence — `rop_proto2.lua` (partially substituted variant, unverified step)

`setup_seq(first)` pushes, with hold/gap 16000/16000 (MODE/2 pushes use gap 40000):

1. SHIFT primer (0x07) — ×2 on first pass (`SHIFT-primer`, `SHIFTb`); ×3 on retry passes
2. MODE (0x47) — intended to open SETUP (**actually opens the mode menu: OPEN**)
3. 2 (0x10) — LineIO select (`LineIO-2`)

Retry handling: if the Σ test comes back boxed (`21 BA 21 BA 21 B9` tail), the script wipes
the queue and replays `setup_seq(false)` (triple SHIFT primer). Run
`/tmp/rop_proto2.now` shows one such retry (`SIGMA: boxed → retrying SETUP`) ending
`MISMATCH Sigma-test len=8 tail=69B821BA21BA21B9` — SETUP not achieved.

## Hardware plan (typed pipeline, ≥100-byte fill)

The emulator script equips the payload by Lua memory writes; real hardware must type the
fill to reach blen ≥ 100 before the swap. Fillers target `0x8154`–`0x8154+99`.

### Payload layout (0x8154 offsets)

- **Verified parked+draw payload — canonical (`rop_draw1.lua`/`rop_draw2.lua`/`rop_draw3.lua`
  2026-11-21; `rop_draw3.lua` = `rop_draw2.lua` + `W(56,0x35BE)` + `W(60,0x8154)` only,
  park at 36–39 untouched)**, 100 bytes at 0x8154:
  - offsets 0–35: `0E 4D` flood pairs (word 0x4D0E = KEYSCAN entry) — 18 pairs
  - offsets 36–39: `F2 4E F2 4E` (park word 0x4EF2 doubled)
  - offsets 40–47: `0E 4D` flood pairs resume — 4 pairs
  - offsets 48–57: **gadget head** `38 35 38 35 01 F8 BE 35 BE 35`
    (0x3538×2 = `POP ER2; POP ER8; MOV ER0,ER2; RT` entry + dst word, 0xF801 = LCD row 0
    dst, 0x35BE = memcpy12 via POP-PC at offsets 56–57)
  - offsets 58–59: `0E 4D` (the POP-PC's csr low word)
  - offsets 60–61: **`54 81`** (`W(60,0x8154)` = the memcpy's `POP EA` src → the payload
    itself), then offsets 62–99: `0E 4D` flood pairs
- **Park tail (VERIFIED, `rop_park1.lua` 2026-11-21; supersedes the earlier unverified
  0x8FD6@96–97 guess from `rop_proto2.lua`)**: park word **`0x4EF2`** — a **key-gated
  resume** in the ROM, but **NOT input-reachable in the emulator** (`rop_resume2`: the
  104-code sweep 0x00–0x67 after the park never delivers 230 — every non-AC key leaves
  r0=2/pc=4B96/hits=20 unchanged; AC (0x42) yields translated code 18, leaves the 0x8508
  spin and **derails the walk**; raw `PressKey(0xE6)` no effect) — **treat as terminal
  park in-emulator**; hardware: **[HW-unknown]** whether the 230 event is reachable
  (`PUSH LR; MOV R0,#1; BL 0x8508; CMP R0,#230 (0xE6); BC NE; POP PC`; the settled
  pc=4B96 is the spin inside 0x8508) — as bytes `F2 4E`, doubled —
  buffer offsets 36–39 =
  `F2 4E F2 4E` (kept unchanged in the canonical draw3 layout above).
  - **Tile offset rule**: `offset = (sp − 0x8D70) mod 100`; off = 36 terminates hop #20
    (`sp=8DF8` consumes offsets 36/38 → PC=0x4EF2), sp settles at 0x8DFC in RAM.
  - Park-only result (`/tmp/rop_park1.out`): 20 CHAIN hops, then 59 identical WATCH
    samples `pc=4B96 sp=8D7A tiles=1207` — clean key-gated-resume spin (pc=4B96 =
    inside 0x8508), no post-chain chaos.
  - With the draw3 head (walk shift +14, 17 hops): park still fires —
    `pc=4B96 sp=8D7C`, `tiles=1194`, `hits=17` (`/tmp/rop_draw3.out`).
  - The 0x8FD6 tail (`D6 8F` at offsets 96–97, from `rop_proto2.lua`) was an unverified
    guess that the 2026-11-21 e2e run never reached; it is superseded by the verified
    0x4EF2 park.
- Zero bytes are avoided in the payload (strcpy stops at 0x00).

## Verification status

- **Verified in emulator:** all 41 presses are DELIVERED; acceptance is run-variable —
  Run C landed only `32 31` + residue (`typing done len=2 buf=323100BA21BA21B9...`),
  Session 21 landed the full formula (`58 3D 69 B8 29 29 2C 74 BA 21 BA 32 B9`). The
  overflow state (`PROBE1 NOT-INSERTED`) and the 22-hop chain reproduced regardless.
  Typing must start immediately at boot; after ~0.25–0.4 s the app enters the 0x4EF2
  wait-key/0x8508-spin loop (0x4EF2 = key-gated resume, **not input-reachable** —
  rop_resume2: no key 0x00–0x67 delivers 230, AC (code 18) exits the spin and derails —
  terminal park in-emulator) and discards other keys — `T≤60k` works, `T≥100k` never does.
- **Unverified / OPEN:** the SHIFT+MODE → SETUP chord is unverified in the emulator
  (0x8E00 shim is one-key-per-round; see research/findings/kyb-setup.md) — **not required
  for the emulator pipeline (MathIO)**; assumed working on hardware via the raw matrix,
  **[HW-unknown]**. A persistent LCD draw **beyond the verified single memcpy12 row-0
  write** (rop_draw3: `lcd01` stays put through the remaining hops until the park; the
  parked app's refresh then erases it in the emulator; hardware persistence is inference
  via the frozen app).
- **Hardware plan only:** typing fillers to reach payload length 100 (emulator substitutes
  a Lua memory write), and any payload arrangement beyond the 100-byte window.
