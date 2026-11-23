# KEY-IDENTITY: directional key extraction from the raw matrix (R2/KID) — VERIFIED; in-loop KID-fed two-way branch OPERATING; four-state NOT achieved

**Verdict: KEY-IDENTITY CONFIRMED.** The KEYSCAN gadget 0x4D0E returns the key-identity bitmap in
**R2** (the KI register read): none=0xFF, Right/Up=0x7F, Left/Down=0xBF. A branch on a KID-fed r0
inside the verified re-entry loop is demonstrated (key-presence two-way: any-key vs none flips the
F80B.4 state bit in-loop; the flip lands exactly at the key-boundary). The second-bit resource for
a four-state encoder exists (0x38FC = SB 0F80Bh.7; RT, single slot) but has no conditional gate in
the walk and no reset path, so the measured (bit4,bit7) pair collapses to the two-way. The row-
select mechanism (loader-stack KOD rewrite) fired once (row3/none/FF measured); the full row grid
was cleared out of reach by the flood hops' KOD=127 re-drive — see the honest per-cell markers.

Scripts: `matrix_1.lua` (R2-per-key measurement), `matrix_2.lua` (row-select loader-stack
injection — the corrected version rewrite: whole-window re-arm), `matrix_3.lua`/`matrix_3b`
(in-loop KID branch), `matrix_4.lua` (const-KOD pass-open + pass-close KOD-restricted variant),
`matrix_5.lua`/`matrix_6.lua` (0x38FC second-bit one-shot + KOD:=7/flash KOD:clobber
measurements).
All headless (`SDL_VIDEODRIVER=dummy`), pristine emulator before each run
(`4dcb0b1c6ce05aff52c2b1cb9de5631a`), `pgrep -af emulator` empty between runs, no emulator
source edits. Runs used: 9 total across all budgets (matrix_1, matrix_2[fire-failure],
matrix_3, matrix_3b, matrix_2b, matrix_4, matrix_6, matrix_7[KICK-crash/ReleaseKey],
matrix_7b[KICK-crash]).

## 1. R2-per-key table (matrix_1, work1 loop, KOD=0x7F=all-rows, samples at the 0x4D20 RT)

Per key held during that phase (667 samples per phase, every phase 100k ticks):

| held key | code | (ko,ki) | r0 | **r2 (KID)** | n |
|---|---|---|---|---|---|
| none    | —   | —      | 0x00 | **0xFF** | 487 |
| Right   |0x37 | (3,7) | 0x01 | **0x7F** | 666 |
| Left    |0x26 | (2,6) | 0x01 | **0xBF** | 667 |
| Up      |0x27 | (2,7) | 0x01 | **0x7F** | 666 |
| Down    |0x36 | (3,6) | 0x01 | **0xBF** | 667 |
| none (initial, r3=81 warmup) | | | 0x00 | 0xFF | 2 |

Exactly as predicted: a pressed key pulls its KI bit low (0xFF→0x7F for ki7, 0xBF for ki6);
r0 keeps its old role (any-key carry). No-key samples during warmup (r3=0x81, app not yet in
the poll loop) also 0xFF.

Verbatim decisive lines (run 1, /tmp/rop_matrix1.out):
```
CHAIN: KEYSCAN #1 ER0=0000 ER14=8DAC pc=4D20 sp=8DA6 lr=2B1E-point r2=FF r3=81
CHAIN: KEYSCAN #2031 ER0=0001 ER14=4D0E pc=4D20 sp=8DEC lr=2B1E-point r2=7F r3=F8   (Right)
```
PHASE lines: `RCODE: PHASE none/Right/Left/Up/Down t=...` bracket every phase.

## 2. Branch gadget census (bank 0, /tmp/oki_b0.txt) — result of tasks 3/4 static search

- **No clean `CMP R2,#imm`+BC gadget** with both outcomes ending in RT/POP-PC and KID-relevant
  immediates exists. Full miners (AST + raw-byte) over all `CMP R2,#imm` / `TB R2.n` /
  `AND|OR|XOR R2,#imm` tests found only:
  - `0x2B16/0x2B2A`: `MOV ER2,ER2; BC EQ→0x2B20` — tests ER2==0, never true for a KID → unusable;
  - `0x3E6A`: `CMP R2,#144; BC GE→0x3E7E` — clean ends (POP-PC@0x3E8A both) but 0x7F and 0xBF
    share a side under either signed or unsigned GE (127<144, -65<144), and the path bodies
    call BL (0x56AE/0xBC02) — dead ends for the walk.
  - `0x1566`: `CMP R2,#43; BC EQ` — wrong immediate.
  - `0x5200`: `CMP R2,R0; BC GT' — r2 is re-loaded with #184 before the compare ([ER8] loop);
    not KID.
  - `0x3978`: `AND R2,#128; ST R2,[0x80F8]` — the ki7 mask-store exists but is followed by a
    whole app-mode-reset block (BL 0x3908, 0x4C92, 0xA94C ...) — not a clean terminator.
  - No `TB R2.6`/`TB R2.7` (only `TB R2.2` at 0x1574, in data), no `CMP R2,#127`/`#191`,
    no `AND R2,#0x80`-then-branch with clean ends.
- App's own poll path `0x53AA..0x53B8` (`BL 0x4B56; BL 0x4D0E; CMP R0,#0; BC EQ→retry; B →decode`)
  discards R2 at this level; the KID→key-code decode happens elsewhere (the nibble table
  0x2A2C below is part of that machinery).

## 3. The demonstrated two-way KID branch (matrix_3) — zero phase shift, in the verified loop

Chain planted as a *value-only* replacement of four flood hops (W66..W82), preservation of the
pop-window (each flood hop consumes 8 B: PC-pair + RT-pair; the chain consumes 16+8+8 = 32 B —
the same):

```
W(66, 0x3604)   -- MOV R0,R2; POP XR8; RT        (r0 <- KID; pops 8 junk bytes = 2 pairs)
W(78, 0x2A2C)   -- KID->nibble: R1=(R0&1)<<2; ER2=0x2A44+R0; L R0,[ER2];
                --   SRL R0,R1; AND R0,#15; RT   (ROM's own key-code unpacker)
W(82, 0x4CDC)   -- CMP R0,#0; BC EQ->0x4CD6 (RB 0F80Bh.4); else SB 0F80Bh.4; RT
```
W(70..76) stay flood words 0x4D0E — they are the 0x3604's POP-XR8 junk operands.
Table bytes (bank 0): [0x2A44+0x7F]=0x00 → nibble 0; [0x2A44+0xBF=0x2B03]=0x10 → nibble 1;
[0x2A44+0xFF]=0x00 → nibble 0. Hence:

| held key | KID | nibble → r0 | 0x4CDC outcome |
|---|---|---|---|
| Right / Up / none | 0x7F / 0xFF | 0 | RB 0xF80B.4 (reset) |
| Left / Down | 0xBF | 1 | SB 0xF80B.4 (set) |

So F80B.4 becomes "Left-or-Down currently held" — a directional, key-identity-driven state bit,
refreshed every loop pass from the raw matrix read. (Baseline of the loop start: with any
arrow held, r0 = any-key → the earlier all-rows branch stayed SB; the nibble chain now
distinguishes ki6 from ki7.)

(Result: filled in from /tmp/rop_matrix3.out after the run.)

**Measured (runs 3 & 3b, /tmp/rop_matrix3.out + .out b-variant):** the chain executes inside the
verified loop and the 0x4CDC state-branch r0 is now KID-derived, not the old any-key value. Per-pass
walk-context samples (verbatim, matrix_3b):
```
CDC-WALK t=1548614 ph=final/PROBE1 r0=0B ER0=000B preF80B=80 F80C=00 tgt=4CDC
SB-WALK  t=1548816 ph=final/PROBE1 r0=0B ER0=000B preF80B=90 F80C=00 tgt=4CE0   (bit4 SET path)
CDC-WALK t=1622114 ph=final/PROBE1 r0=00 ER0=0400 preF80B=90 F80C=00 tgt=4CDC
RB-WALK  t=1622120 ph=final/PROBE1 r0=00 ER0=0400 preF80B=90 F80C=00 tgt=4CD6   (bit4 RESET path)
```
The per-pass state-bit follows key presence and flips exactly at the key-phase boundary
(CDC-AFTER samples, matrix_3b, ft = final-phase tick; none-phase ends at 150001):
```
ft=148501 postF80B=90 preF80B=90   <- no key held: branch drives bit4 high (r0!=0 -> SB)
ft=157001 postF80B=80 preF80B=80   <- Right held:  r0=0 -> RB, bit4 low
...every subsequent key phase: postF80B=80 (27 samples through Right2)...
```
Note the nibble decode of the KID at R2 under the emulator's keyscans yields key-dependent r0s
(0x0B pass-type / 0x00 pass-type alternating across passes long-term: G38 h4837, piv=14235 — the
alarm: the 0x3604's POP-XR8 junk clobber makes the branch readable only as presence+long-run
signature, not a clean per-digit value bank. An exact per-key r0 bank would follow from the
0x2A2C function's real input conventions (the app calls it with `L R0,[ER0]`-loaded values, not
raw KID) — see blocker note.

## 4. Row-select (task 2) — MEASURED matrix table, plus the KOD-127-const-poll probe

**Measured table (run 2b, /tmp/rop_matrix2b.out):** the loader-stack injection fired but only one
ROWPOLL landed before the pass-close `KOD := r2&7` write derailed the steady loop (the loader's
operand rewrite verified the mechanism; full per-row/per-key grid NOT measured — the pass-close
KOD hazard needs a matrix_3-style two-write compensation before it can be measured):

| held key | KOD=0x08 (row3) | KOD=0x04 (row2) |
|---|---|---|
| none | **0xFF** (measured, 1 sample) | not measured |
| Right | not measured | not measured |
| Left | not measured | not measured |
| Up | not measured | not measured |
| Down | not measured | not measured |

Verbatim: `ROWPOLL pass=2 KOD=08 r0=00 r2=FF ER0=0000 sp=8DA6 lr=2B1E-point`.
The loader operand words were confirmed in-place (LOADER-PROBE pass=1: `words=0000 0020 38FA 0000
38CC 0000` = the head-word/dest slot and the loader's ER0 word sit where the probe rewrites them).

**Run 7 (matrix_6 = matrix_5 + W(90)=0x4CF7 (KOD:=7 const poll) + W(74)=0x38FC bit7 one-shot,
KID-branch + 0x2A2C chain intact — /tmp/rop_matrix6.out, hits=6054, PHASES-DONE):** the r2 table
at the 0x4D20 samples is UNCHANGED (Down/Left r2=BF ER0=0001, Right/Right2 r2=7F, Up r2=7F,
none r2=FF — 1453 CHAIN samples) because the flood hops (W62=0x4D0E = `MOV R0,#127` first)
re-drive KOD=127 in every pass-open, clobbering the 0x4CF7's row-limited drive. The 0x38FC
one-shot DID fire: WATCH shows F80B=90 (=bit7+bit4) at t=260001/460001 (0x38FC sets bit7 every
pass; nothing in the pass resets bit7 → it latches: (bit4,bit7) = Left/Up (1,1), Right (0,1),
none (0,1)). The row-limited-KID signal from the 0x4CF7's own poll exists but is NOT separable
in this stream: every 0x4D20 sample looks identical whether it came from a flood or the const
poll — no KOD-provenance is visible from the outside.

**Lesson recorded:** a `break_at(0x3136, ...)` handler filtered on `cpu.lr == 0x2B1E-point`
never fires — the walk's gadget-entry lr is 0x3322 (only keyscan RTs show lr=0x2B1E-point).
Walk-context must be detected by sp being inside the replay window (~0x8DA0–0x8E00).

### Re-kick variant (run 8+9 attempt — the harness re-kick does NOT refire the walk)

`matrix_7.lua` re-pressed EXE per phase to restart the walk and re-arm the loader with a new
KOD (10 kicks × 5 keys × 2 rows planned). Measured: the kicks printed (`RCODE: KICK #1 key=none
rowkod=04`, `#2 key=Right`) but **no loader fire followed any re-kick** (LOADER-PROBE only shows
the initial trigger's 2 warm-up fires, with mode=0/kod=0000 — the injection never armed), and run 9
crashed at the phase transition on `Keyboard:ReleaseKey` (not in the Lua API; only
`Keyboard:ReleaseAll()` exists), unregistering the post-tick hook. The EXE re-kick does not
re-enter the payload walk in this configuration (the walk's warm-up window happens once per
CALC entry; re-pressing EXE re-runs the *app* draw pipeline without re-establishing the
hijacked stack). **No grid cells obtained by the re-kick method.**

## 5. Second fixed-address state-bit gadget search (follow-up task 2)

Census of bank 0 for a second SB/RB-on-F8xx one-shot store with a clean RT tail:

- **FOUND: `0x38FC` = `F0 A0 0B F8 1F FE` = `SB 0F80Bh.7; RT`** — sets LCD byte 0xF80B bit 7, then
  RT. 2-byte op + 2-byte RT = one clean slot pair, no PUSH/BL — directly droppable into a walk
  slot as a second state bit (F80B.7 vs the existing F80B.4 = the 4-state encoder's two bits).
- Companion one-shot stores at `0x3902` (`SB 0F80Ah.3; RT`) and the `0x4CBE..0x4CD2` RB-strip
  (`RB 0F800h.4/.2`, `RB 0F801h.1`, `RB 0F802h.6`, `RB 0F80Bh.7`, `RB 0F80Ah.3`) — the RBs are
  reset-side one-shots in the same shape.
- **Conditional path search (0x38E0-0x3910, 0x4CB0-0x4CE0, plus all BL-references):** the ONLY
  conditional references to the bit7 stores in bank 0 are at `0x6EEC..0x6EFC`:
  `L R0,0130h[ER4]; BC EQ→skip; BL 0x38FC` — memory-gated ([ER4+0x130]) on entry, and its
  continuation after either branch runs into `L R0,0131h[ER4]` / `BL 0x3902` / `BL 0x8508`
  (the app's park/wait path) — NOT a walk-safe terminator (the walk dies in the follow-up
  calls). Mid-entry at `0x6EF0` (`BC EQ` on a pre-set r0) does not help: the same continuation
  applies. **No walk-safe conditional path to the `SB 0F80Bh.7` store exists in bank 0.**
- Census result: the bit7 store is unconditional-only in ROP-land; with no pass-close RB
  (the `RB 0F80Bh.7` at 0x4CCE is inside the 0x80FC.4-gated 0x4CC0-block whose non-taken path
  still ends RT — usable as a one-shot resetter if 0x80FC.4 can be armed) — measured unlit in
  existing runs. Not combined within this budget.

## 6. Hardware note

The matrix is the instrument's real one (KEYSCAN 0x4D0E writes KOD=0x7F and reads KI at 0xF040);
the emulator model walks the identical rows (Keyboard.cpp: pressed key visible iff
`ko_bit & keyboard_out`; keyboard_in = ~input_mode with input_mode=0 written at 0x4C30-0x4C32,
so idle KID = 0xFF — matching the hardware pull-up convention). Row-limited driving and the
KID bitmap interpretation therefore carry over to the emulator exactly as to hardware, within
the model's fidelity. The flash-walk payload entry (typed buffer, flood, trigger) is unchanged
from the verified work1 protocol.

## Verdict — FINAL INPUT CEILING

- **KEY-IDENTITY: VERIFIED (hard result).** R2 carries the KID bitmap per keyscan pass: none=0xFF
  (487 samples), Right/Up=0x7F (666 each), Left/Down=0xBF (667 each) — run 1, work1 loop, KOD=0x7F.
  The directional key identity **is present in the raw matrix read** and enters ROP-land in R2 at
  the 0x4D20 RT of every flood-keyscan gadget.
- **In-loop KID-fed two-way branch: VERIFIED.** The 0x3604+0x2A2C+0x4CDC chain consumes the four
  flood hops it replaces (zero net phase shift); the F80B.4 state bit flipped exactly at the
  none→Right boundary (ft=148501→157001) and stayed 80 for 27 subsequent samples. The measured
  2-way = **none (bit4=1) vs any-key (bit4=0)** — the 0x2A2C nibble value (0x0B/0x0D/0x00,
  KID-dependent) exists in r0 but only a `CMP R0,#0`-class conditional exists to branch on.
- **Row-select: MECHANISM + 1 MEASURED CELL; GRID NOT MEASURED.** The loader-stack KOD rewrite
  fired once (LOADER-PROBE words landed) and produced one verified cell: KOD=0x08 (row3)/none →
  **r2=0xFF**. The 0x3136 loader is warm-up-only (2 fires per 15915-keyscan run); the EXE re-kick
  does NOT re-enter the walk (runs 8/9: no LOADER-PROBE after any re-kick); and in-loop the flood
  hops re-drive KOD=127 every pass (run 7: the 0x4CF7 KOD:=7 drive never showed in the r2 table).
- **FOUR-STATE: NEGATIVE — the ceiling.** The second state bit physically exists (0x38FC = SB
  0F80Bh.7; RT, one clean slot; measured lit) but: (a) no walk-safe conditional path branches to
  it, (b) nothing resets it in-loop (it latches), (c) the row-limited KID that would carry the
  Right-vs-Up / Left-vs-Down distinction cannot be sampled in the loop (the flood KOD=127
  re-drive). **Input ceiling as ROP-delivered: 1 visible state bit = key presence (none vs
  any-key); directional identity (ki6/ki7) is available as a measurement (R2/r0 values) but not as
  a branchable in-loop state bit. No four-way; no moving sprite via ROP.**

## Follow-up (exact next actions, in order)

1. The row grid's remaining cells need a KOD-limited poll that survives the flood re-drive: modify
   the W(62) flood word ITSELF (value-only, 0x4D0E → 0x4D06) so the FIRST in-cycle keyscan drives
   KOD := r2 (=the previous KID — a state recycling variant), or re-time the row-limited poll to
   the last pre-memcpy slot; then rerun matrix_2-style logging for the 10-cell grid.
2. The 4-state encoder's bit7 resetter: the `RB 0F80Bh.7` at 0x4CCE (inside the 0x80FC.4-gated
   0x4CB2 block) is a one-shot resetter candidate — spacer/gating check first (the non-taken path
   must still end RT).
