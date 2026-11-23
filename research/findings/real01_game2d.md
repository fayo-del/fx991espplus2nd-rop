# real01_game2d.md — REAL 2-D playable game from the typed hackstring → ROP chain (PROVEN in emulator)

Date: 2026-11-22. Agent: `RealGame2D`. Script: `research/CasioEmuX/real01_game2d.lua`
(base: `game_snake.lua` — proven 48-pass loop skeleton + typed trigger of `rop_e2e.lua`).
Logs: `/tmp/real01_run6.out` (decisive), `/tmp/real01_run7.out` (determinism pair).
Artifacts in `research/CasioEmuX/`: `real01_payload.bin`, `real01_frame{3,6,…,48}.raw/.png`.
No emulator source edits; `rom.bin` untouched.

## Verdict

**SUCCESS — a real 2-D playable game runs from the typed trigger.** The chain executes a
self-sustaining loop for **48 passes** (`PROTO: GAME2D-LOOP hits=22 pc=4CD6 sp=8DB6 ER14=8DA8 piv=322 cdcw=48`).
Each work pass: polls the keyboard itself (KEYSCAN 0x4D0E → r2 = KID), **loads a persistent
position byte POS from RAM 0x8BBD, adds a key-dependent delta, stores POS back**, and renders
a 12-byte cell to the LCD at **dst = ER2 = 0xF8|POS'** via memcpy12 (0x35BE, src self-slides
+12 B/pass). Measured POS trajectory (initial 0x10 from the payload flood): `10 → 91 → 92 → D3 → 54 → 55 → 56`,
and dst at each render: `F891 → F892 → F8D3 → F854 → F855 → F856` — the cell is on **row 9, row 9,
row 13, row 5, row 5, row 5** (dst/16), i.e. it visibly moves in 2-D under key control.
Runs 6 and 7 (identical script + key schedule) produced **byte-identical evidence streams**
(md5 `db3152b3d43a719bb93de2aff177b975` over WMBE/PASS/KEYSCHED/PROTO/LOAD/STORE lines) and identical
payload md5 → **deterministic**.

## The game (rules)

- **Controls (hardware player):** hold **Right (0x37) or Up (0x27)** → KID 0x7F → POS += 0x81
  (≈ 8 rows down + 1 col); hold **Left (0x26) or Down (0x36)** → KID 0xBF → POS += 0x41
  (≈ 4 rows down + 1 col); **no key** → KID 0xFF → POS += 0x01 (drift 8 px right).
  The chain samples the held arrow by itself every pass — one held arrow is the whole input;
  no per-pass keystrokes needed.
- **State:** POS = one byte at RAM 0x8BBD (initial 0x10 = payload byte 65 via the flood mapping
  (0x8BBD−0x8154)%100 = 65). dst = 0xF800 + POS; the cell is the 12-byte bar written at dst
  (row = POS/16, col = POS%16; the bar wraps the row edge when col > 4 — visible as a split bar).
- **Win/lose (judged on the LCD, honestly):** the zero-byte ban forbids erase bytes, so the bar
  leaves a persistent trail (old rows stay lit — see frames). A playable rule on hardware: keep
  the bar's row inside a chosen band (e.g. rows 4–11); score = passes with row in band. The chain
  has no compare gadget, so no in-chain score/collision — same limit as game-snake.md.
- **Limits:** 2 distinguishable KID groups in-loop (7F vs BF vs FF — actually 3 states here since
  the delta is computed from raw KID, not a branch); POS wraps mod 256 (dst stays in 0xF800–0xF8FF,
  top 16 rows, always valid LCD writes ≤ 0xF90A); park 0x4EF2 remains terminal in-emulator.

## Per-pass mechanism (steady loop; tiles = payload words at (addr−0x8154)%100)

Walk per pass (from pivot, tile@0x8DAA/0x8DAE): b=58/62 keyscan 0x4D0E (r0=presence, r2=KID) →
b=66 0x4CDC pass event (F80B.4 key pixel + harness pass counter) →
b=70 `0x3722 POP ER0; POP PC` (op W74=0x8BBD) → **ER0 = 0x8BBD** (r2=KID survives) →
b=76 `0x16E0C (b1) L R0,[ER0]; POP PC` → **r0 = POS** →
b=80 `0x4AA8 SUB R0,R2; SUBC R1,R3; RT` → **r0 = POS − KID = POS'** (deltas: 7F→+0x81, BF→+0x41, FF→+0x01 mod 256) →
b=84 `0x3066 POP ER14; POP PC` (op W88=0x8BBD) → **ER14 = 0x8BBD** (store pointer; restored later by skeleton loader W30) →
b=90 `0x10470C (b1) ST R0,[ER14]; …; RT` → **mem[0x8BBD] = POS'** (persists; side-stores at 0x8BBE–0x8BC2 harmless) →
b=94 `0x49C2 POP ER2; POP PC` (op W98=0xF80C) → **r3 = 0xF8** →
b=0 `0x4292 MOV R2,R0; POP PC` → **r2 = POS' ⇒ ER2 = 0xF8|POS' = dst** →
b=4 `0x39CA MOV R0,#1; RT` → memcpy loop count 1 →
b=8 `0x35BE memcpy12` (EA ← W12 = 0x8240, self-slides +12/pass) → draws the 12-byte cell at dst →
post-memcpy skeleton W24/W28/W30/W32/W36… → pivot 0x75DE re-syncs SP → next pass.

Gadget table (new vs game-snake; all verified in this run, both banks):

| addr | bank | disasm | role |
|---|---|---|---|
| 0x3722 | 0 | `POP ER0; POP PC` | POS pointer into ER0 (survives keyscan's r2 write) |
| 0x16E0C | 1 | `L R0,[ER0]; POP PC` | r0 := mem[ER0] (load POS) |
| 0x4AA8 | 0 | `SUB R0,R2; SUBC R1,R3; RT` | r0 := POS − KID |
| 0x3066 | 0 | `POP ER14; POP PC` | store pointer (skeleton loader reused) |
| 0x10470C | 1 | `ST R0,[ER14]; ST R8..R4,[FP+1..5]; RT` | mem[ER14] := r0 (store POS') |
| 0x49C2 | 0 | `POP ER2; POP PC` | r3 := 0xF8 (dst high byte) |
| 0x4292 | 0 | `MOV R2,R0; POP PC` | r2 := POS' ⇒ ER2 = 0xF8\|POS' |
| 0x39CA | 0 | `MOV R0,#1; RT` | memcpy count = 1 |
| 0x35BE | 0 | memcpy12 | render cell at ER2 from EA |

Key design points discovered this session: the KEYSCAN clobbers r2 (= ER2 low byte) and ER0,
so the POS pointer must live in ER0/ER14 set **after** the keyscan; `POP XR12` pops only 4 bytes
(opcode table `0xF02E` → register_size 4); the screen region drops writes at `offset%16 ≥ 12`
(invisible bytes read 0 / writes ignored — Screen.cpp), so POS cannot live in the LCD; mid-RAM
0x8BBD is flooded (period 100) and never walked, and chain writes there persist post-trigger.

## Payload (100 B at 0x8154, zero-free, floods 0x8154–0x8DFF period 100 phase 0)

md5 `a53b3894e57984fa67b89f8ab7b075f0` (`real01_payload.bin`), `PAYLOAD: len=100 zerofree=true`:
```
92420E4DCA390E4DBE350E4D40820E4D0E4D0E4D0E4D0E4D66300E4DAC8D6630AC8DA88DDE75DE75F24EDE75
66300E4DAC8D0E4D0E4D0E4DA88D0E4D8EF20E4D0E10DC4C0E4D22370E4DBD8B0C6E0101A84A0E4D6630
0E4DBD8B0C470101C2490E4D0CF8
```
Distinct bytes (35): `01 0C 0E 10 22 30 35 37 39 40 42 47 49 4A 4C 4D 4E 66 6E 75 82 8B 8D 8E 92 A8 AC BD BE C2 CA DC DE F2 F8` — all zero-free; plain-key tokens per the
`docs/typable-tokens.md` atlas cover `30 35 37 39 40 42 47 49 4A 4C 4D 4E 82 BE 8B 8D 92 C2 CA DC DE F8 AC A8 66 6E 75`;
the rest are walk-reachable on hardware per `docs/esp-autotyper.md` (in-emulator the pre-trigger
equip at 0x8154 is the documented stand-in; the TRIGGER (AC,←,EXE) and all PLAYER arrows are pure
`Keyboard:PressKey`). EA src word 0x8240 high byte 0x82 ∈ hardware-typable set ✓.

## Decisive evidence (run 6, `/tmp/real01_run6.out`)

Trigger provenance: `PROBE1: before=2 after=2 NOT-INSERTED(good)`, `PAYLOAD: len=100 zerofree=true`,
typed head + AC/←/EXE via PressKey → strcpy flood → chain; after the trigger **zero data[] writes**.

LOAD/STORE trace (walk-only probes at the bank-1 gadgets) — POS persists and accumulates in RAM 0x8BBD:
```
LOAD#1  sp=8DC0 ER0=8BBD (mem=10) r2=7F     STORE#1  sp=8DCE ER14=8BBD r0=91
LOAD#6  sp=8DC0 ER0=8BBD (mem=91) r2=FF     STORE#6  sp=8DCE ER14=8BBD r0=92
LOAD#11 sp=8DC0 ER0=8BBD (mem=92) r2=BF     STORE#11 sp=8DCE ER14=8BBD r0=D3
LOAD#16 sp=8DC0 ER0=8BBD (mem=D3) r2=7F     STORE#16 sp=8DCE ER14=8BBD r0=54
LOAD#21 sp=8DC0 ER0=8BBD (mem=54) r2=FF     STORE#22 sp=8DCE ER14=8BBD r0=55
```
Delta check: 0x10−0x7F=0x91 ✓, 0x91−0xFF=0x92 ✓, 0x92−0xBF=0xD3 ✓, 0xD3−0x7F=0x54 ✓, +1, +1 ✓.

Render (WMBE = memcpy entry, walk-only) — dst = 0xF8|POS', EA self-slides +12:
```
WMBE#1  pass=6  ER2(dst)=F891 r2=91 easlot=8240 POS=91
WMBE#6  pass=14 ER2(dst)=F892 r2=92 easlot=824C POS=92
WMBE#11 pass=20 ER2(dst)=F8D3 r2=D3 easlot=8258 POS=D3
WMBE#16 pass=26 ER2(dst)=F854 r2=54 easlot=8264 POS=54
WMBE#21 pass=34 ER2(dst)=F855 r2=55 easlot=8270 POS=55
WMBE#26 pass=42 ER2(dst)=F856 r2=56 easlot=827C POS=56
```
Per-pass table (pass, KID sampled at 0x4CDC, POS at pass start, held key): POS 10→91→92→D3→54→55→56 over
48 passes; work passes at 6/14/20/26/34/42 with dst rows 9/9/13/5/5/5 (see table above; full 48-row table in the log).

PNG frames (`real01_frameN.png`, 96×32): the cell bar is visibly on **row 9** (frame9:
`de75de75f24ede7566300e4d` at dst F891), **row 13** (frames 21–45: `00008ef20e4d0e10dc4c0e4d` at F8D3),
**row 5** (frames 27–48: bar at F854→F856, wrapping to row 6). Old cells stay lit (trail).
Frame md5s (raw): frame3/6 `babdc87a…`, frame9/12 `5a2cf187…`, frame15/18 `2532e82c…`, frame21/24 `64e069ac…`,
frame27/30/33 `efbf7d47…`, frame36/39/42 `e1f35956…`, frame45/48 `4a657965…` (png md5s in the conversion log);
frames differ exactly at key-phase boundaries.

Determinism: runs 6 & 7 → identical evidence-stream md5 `db3152b3d43a719bb93de2aff177b975`, identical
payload md5 `a53b3894e57984fa67b89f8ab7b075f0`, identical final state `final-POS=56`, same PROTO line.

## Run budget / honesty

7/8 runs used: runs 1–5 were layout iterations, each failing at a measured first divergence
(run 1: POS stored at LCD 0xF9FC — screen region drops writes at offset%16≥12, POS always read 0;
run 2–3: POS at 0x8BB5 but the head+keyscan clobbered ER2's low byte (r2=KID), so load/store went to
0x8B|KID — found via LOAD/STORE probes; run 4–5: `POP XR12` pops 4 B not 8 B (opcode table 0xF02E,
register_size 4) so the walk landed on a garbage tile and parked — found via POPC walk trace).
Run 6 = decisive 48-pass evidence run; run 7 = determinism pair. In-emulator the payload equip at
0x8154 pre-trigger is the documented stand-in for the hardware autotyper delivery; the trigger and
player input are typed keys only.
