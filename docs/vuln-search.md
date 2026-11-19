# CY-845 keyboard-reachable vulnerability search — 2026-11-19

Scope: typed/keyboard-only trigger that reaches a stack copy with ≤54 typed
tokens, or a ≥100-byte typed input state — i.e. bypass the measured 54-token
ceiling and the untypable `0E`/`4D` payload bytes. All experiments in
`research/CasioEmuX` emulator, CY-845A ROM
(md5 c4c7d7fb89d0fd07cc0196d642682d83). Scripts retained: `rop_v1.lua`,
`rop_v1b.lua`, `rop_v2.lua`, `rop_v3.lua`, `rop_v4.lua`, `rop_v5.lua`,
`rop_v6.lua`, `rop_v7.lua`, `rop_v8.lua`, `rop_v9.lua`; logs `/tmp/v*.log`.

## 0. Verdict up front

| Question | Answer (measured) |
|---|---|
| 54-token typed ceiling | **OBSOLETE** — the ceiling was an artifact of the pre-dance/post-dance ordering, not a wall. Post-`AC`,`←` (the `AC-f`/`LEFT-f` state) typed input reaches **hard cap 99 bytes** (V1, V1b: identical 99 from five independent head states). |
| ≥100-byte typed input state | **NOT reached.** Cap = 99 bytes = cursor/len var 0x8114 = 0x63; byte 0x81B7 (input index 99) is never written by any typed mechanism tested. The tiling gate is measurably `strlen(0x8154) ≥ 100` (V1 vs V5 differential). |
| Shorter stack copy (≤54 tokens) | **None exists among tested triggers.** `A^0`, `1÷3(4)`, `Pol(` (prior `rop_trig3`), ∫( head, STAT/EQN/TABLE rows, 8 DEL-dance variants — `h4d20 = 0` in every run. |
| Untypable `0E`/`4D` | Still untypable (no new token source found). The `0x3538` word remains the only typeable gadget word; the sled problem is unchanged. |
| Render-echo overruns (`dst=0x8138/0x8168…` copies) as the 100th-byte path | **NEGATIVE** (V10c/d/e/f census + per-tick `0x81B7` oracle: zero crossings ever observed; the AC stamp's write starts at 0x81B8; the window echoes never fire crossing; details §4a) |

Top candidate (still blocked by exactly one byte): the **typed 99-byte
post-dance fill + `[AC][←][EXE]` trigger** — the full mechanism (decoupled
state, insert lock, cache stamping, AC/←/EXE trigger) is keyboard-executed and
reproduced end-to-end; V9 shows the identical state completes against the
injected sled (`h4d20=4`, chain executed, park `pc=0x8F4A`); the missing
100th byte at 0x81B7 is the only gap.

## 1. Item 1 — LineIO box-fill / 2-byte-token entry (measured)

1. **SETUP never opens in-emulator.** `[SHIFT][MODE]` (30k-tick holds) leaves
   the LCD blank (V1b SCREEN dumps: no menu rows); the following `2` types as
   a digit into the formula (V1b: `a1-sigv` bytes `32 69 B8 21 BA 21 BA 21 B9`
   — the `32` is the stray `2`). `Σ(` therefore always inserts the 8-byte
   **MathIO boxed template** `69 B8 21 BA 21 BA 21 B9`
   (`SIGMA: bare=false boxed=true` in every e2e-era run, reconfirmed V1b).
   LineIO bare-Σ( = 2 bytes) was never available; the token-economy plan
   ("box-fill → 2 bytes per token → >54 tokens") is unreachable.
2. **Post-dance lock + insert** (E-series, reproduce in V1): after the
   `CALC EXE AC ← DEL×3 2 CALC EXE ←` dance, `AC-f`→`LEFT-f` then typing:
   - landed profile (V1): digits land ~100% early, decay to 0-at-cap;
     `Σ(` chords land +5..+8 bytes each, 2-of-4 later, 0-at-cap;
   - the 99 cap is hit after ~9 rounds and **no key class crosses it**:
     V1b margin matrix (~105 margin keystrokes): `1/8/5`, x^box (0x46 →
     `21 5E B8 60 31 B9`, 6 B), d/dx( (S+0x16), `Σ(` (S+0x56), Pol( (S+0x30),
     Rec( (S+0x40), log₂( (0x56 base), Ran# (S+0x63), Ans (0x61), X (A+0x33),
     e (A+0x62), ×10ˣ (0x62), "," (S+0x33), `▶`/`◀` walks, DEL-then-digit —
     **all zero landings at len=99** (blen stays 99 for the whole watch).
3. **Σ-blitz** (peer E7/E8 runs, `/tmp/e7.log`, `/tmp/e8.log`): 60+ pure
   `Σ(` chords post-AC cap at **len=70** (template internals replace themselves);
   the E8 variant caps at len=5. `4D20=0`, `21BA/69B8/B921/BAB9` gadget-proof
   counters all 0.
4. **Cursor/len vars at the cap** (V1b margin): `0x8114 = 0x63` (99) — the
   editor's byte-length ceiling is enforced exactly one byte before the area
   boundary; `0x8113 = 0x00` throughout.

## 2. Item 2 — shorter stack copies / tiling measurements

| Trigger / state | Result (measured) | Source |
|---|---|---|
| `A^0`-class eval | `diff=426`, `tiles(38 35)=0`, no decoupling; `A` var typable (`ALPHA`+0x04 → 41) | prior `rop_trig3` |
| `1÷3(4)` auto-paren | no decoupling; eval-state diffs only (225/426 B), tiles 0 | prior `rop_trig3` |
| `Pol(` template | same eval-state pattern, no tiling | prior `rop_trig3` |
| ∫( head (`X=∫(X,…)`) | **head not typable**: `SHIFT+0x03` inserts nothing (`SIGV: key=03 len=0`); fill still capped 99 | V2 |
| STAT/EQN/TABLE row editors (MODE-digit editors) | typed rows land `0x8154` **and mirror into cache `0x81B8+`** (V3: `8154=35 81B8=35`; row journal records at `0x8230+`, ~13 B stride), but rows cap at **len=61** with ~50% landing rate — no editor state exceeds the 99 COMP cap; journal rows never reach 0x8300+ stamps from this state | V3, V4 |
| Syntax-ERROR page entry (`=` → ERROR → `AC` → `←`, **no CALC**) | typing works **without** the DEL-dance (`EXE-ERR: len=11, PROBE1: len=11` inserts); fill → same **99 cap**; cache = formula mirror. A second, simpler entry state, same ceiling | V6 |
| 8 DEL-dance variants (DEL×4, empty-tail, walk×3, double-dance, "22" tail, L/R roundtrip, no-head-AC) | all reproduce the same family (probe-land + fill in stride ≤53 in the short fills); **no variant breaks the cap or produces a stack copy** | V7 |
| Mode-68 reset-race (`[SHIFT][9][3][EXE]` + ON at +2k..+96k ticks) | **negative**: config intact (`0x80F9=0xC1` after race; the ON windows did not split the reset on CY-845 in-emulator); fill afterwards = plain 99 cap, `h4d20=0` | V8 |
| Fraction/mixed, constant memory | not separably reachable as entry states in this emulator build; covered indirectly by the row-editor class (same editors) | [INFERENCE] |

No candidate produced `h4d20 > 0` or any 0x3538/0x4D20-class stack tile.

## 3. Item 3 — the `strcpy` length source (measured)

The trigger-time copy is now pinned by the in-ROM breakpoint logger at the
inner copy loop `0x6B62` (`0x2B10` smart_strcpy → `0x6B58`):

- **The AC save**: `strcpy(dst=0x81B8, src=0x8154)`, length = `strlen(0x8154)`.
  V1 (len 99): copies fire all through the trigger; **no** `dst ≥ 0x8300`
  journal copies. V5 (injected sled, `strlen=101`): same save **plus hundreds
  of journal-replay stamps** `dst=0x830E/0x8311/0x834D/0x8398, src=0x8154,
  srclen=101` (logger capped at 300) → **the gate for the stamping flood = 
  `strlen(0x8154) ≥ 100`** — differential proof (V1 vs V5), no inference.
  V9 (full trace, budget 3000, e2e sled injected on the identical typed-99
  state): stamp aggregate `dst=0x810E×1212, 0x814D×1211, 0x834D×117,
  0x830E×115, 0x8135×81, 0x8138×54, 0x81BE/0x8181/0x81F8/0x8154×27 each`,
  `tiles=1510`, and the **chain executed** (`h4d20 = 4` in a 3M-tick watch —
  vs 50+ in e2e's longer watch; final `pc=0x8F4A` = the wait-key park, the
  harmless terminal state per `docs/physical-calc.md` §4). The typed-99 state
  plus exactly one injected byte pair flips the gate onto the same mechanism.
- The stamp copies match the row-record stride observed in the row editors
  (~13 B entries at `0x8230+`, `0x829F+` in V3) — the tiling engine is the
  same replay/journal stasher. [INFERENCE] The stack reach (0x8D00+, the e2e
  chain) comes from the repeated restore/dir-side copies with the contaminated
  cache; V5's post-`t=1.05M` `pc=0x8170→0xBF1x/0x7C9x, sp=0x10F1/0x1101`
  (runaway/chaos) shows the stack IS corrupted by the 101-byte state, while
  the e2e sled aligns the POP-PC entries so the corruption becomes a chain.
- Other `0x81B8`-callers catalogued (all `strcpy([ER8]editor-len, 0x81B8)`
  restores, e.g. `0x507E/0x509C` (input ← cache), `0x5C9E`
  (mode-0x80F9==0x88 branch: input ← cache), `0x6E26`, `0x7CFA`, `0x8A04`,
  `0x984C`): the restore direction copies **from** the cache with its length —
  a cache filled ≥100 nonzero bytes would propagate, but every typed source of
  cache content (row mirror: ≤61; AC stamp: ≤100 incl. NUL) stays < 100.
- **Alternative `0x81B8` fill sources**: RCL/history, program memory,
  Ans-chaining traverse different buffers (`0x85AA` echo site at `0x7554`,
  draw-buffer `0x87D0`); none write 0x81B8..0x821B directly. The two observed
  paths into the cache = (a) the AC-stamp (bounded by the 99-typed cap) and
  (b) the row-editor mirror (bounded by the 61-typed cap). → **closed for now**.

## 4. Input-state bugs writing past 0x8154 with ≤54 tokens

### 4a. Re-examination: render-echo overruns as a path to 0x81B7 — NEGATIVE (measured 2026-11-19, V10a–f)

Full census at the copy-loop exit `0x6B6E` (registers `ER8`=dst,
`ER10`=post-advanced src; true length recounted; per-tick `0x81B7` transition
watcher `B7CHANGE` active; raw dumps `0x81A0..0x81C8` at every trigger key):

| Copy class (measured) | Fires when | Write range | Crosses 0x81B7? |
|---|---|---|---|
| per-keystroke cache echo | every trigger key processing | `dst=0x8398 ← src=0x81B8, len=11` (writes `0x8398..0x83A3`) | No |
| **AC stamp** | every AC/blink processing (~20k copies logged uncapped) | `dst=0x81B8 ← src=0x8154, len=strlen(0x8154)=99` — writes `0x81B8..0x821B` (99 bytes + NUL at `0x821B`); cache verified = typed bytes (`c8B8=32383838`) | **No — dst starts at 0x81B8** |
| V1-class window echoes (`dst=0x8132/0x8135/0x8138/0x8168/0x8169 ← src=0x8154`) | redraw-coincident only (frame-phase dependent; 0 occurrences in 3 fresh V1-exact reruns vs 84 logged in the original V1 sample) | with `len=99` would write `0x8168..0x81CB` → WOULD cross; with short src, writes only the low window | Never observed crossing: `B7CHANGE` fired **zero** times in ~2.6M postticks across V10c/d/f; `data[0x81B7]=00` at every echo sample and at all four `[AC][←][EXE][EXE]` keys |

- The `0x8168+99=0x81CB` algebra is correct, but the class either never fires
  at full length or its overrun is consumed within the same tick — the
  per-tick oracle and the copy-exit census (which samples `data[0x81B7]`
  after each copy) both read `00` through every run. V1's `len=99` blen read
  (first NUL at 0x81B7) also bounds it: a crossing write would have moved the
  NUL, contradicting the measured watch lines.
- **No timing hole**: the echo/stamp/stamp-repeats all run inside single
  postticks; `AC`/`←`/`EXE` ordering variants (`[AC][←][EXE][EXE]`, EXE-only,
  Right-held) all sample `b7=00`, `strlen(0x8154)=99` at every key.
- The `0x85AA` echo (`0x7554`: `strcpy(0x85AA, 0x8154)`, also
  len=strlen(0x8154)) is spatially irrelevant to the gate: it writes
  `0x85AA..0x860D`, away from `0x81B7/0x81B8`.
- Flood check: `h4d20 = 0` in every census run; no chain-class activity.

Scripts/log: `rop_v10.lua` (budgeted census), `rop_v10b/c/d/e/f.lua`
(filtered + corrected-decode reruns), `/tmp/v10.log v10b.log v10c.log
v10d.log v10e.log v10f.log`. **Conclusion: the echo-overrun family is not a
keyboard-only path to the 100th byte.**

### 4b. Other writes past 0x8154

- Control-flow outcome with ≤54/99 typed tokens: unchanged — nothing typed
  changed control flow in any run (`h4d20=0` everywhere); control-flow changes
  require injected bytes (see §3, V5/V9).
- Trigger sequence `[AC][←][EXE][EXE]`, `EXE` alone (E4), reset-race (V8),
  Right-held (V9) — nothing typed changed control flow; control-flow-changing
  runs require the injected bytes: V5's shifted sled corrupted the stack into
  chaos (`h4d20=0`; `[0E 4D][11 11]` POP-PC consumption lands on
  `pc=0x4D0E` only at even alignment, junk words derail [INFERENCE]), while
  V9's aligned e2e sled executed the chain (`h4d20=4`) from the identical
  typed state.

## 5. Ranked candidates (typed-only exploit search)

1. **Typed 99-byte fill + `[AC][←][EXE]`** (V1/V1b; best-developed block).
   Exact keys: e2e head (`X=Σ(X,1,1×10⁹`, 45-key dance already in
   `docs/physical-calc.md` §3), then `AC` `←`, then alternating `8`/`5` digits
   ×12 + `Σ(` chords ×4 per round (cap reached at round ~9; V1 measured
   profile in §1.2), then `AC` `←` `EXE`.
   **Blocker: 1 byte** — `0x81B7` never becomes nonzero from typing; the
   stamping gate needs `strlen ≥ 100`. V5 proved that *injecting* that one
   byte (data[]) flips the gate on the identical typed state.
2. **Restore-side propagation** (`0x507E/0x509C/0x5C9E` input ← cache):
   needs the cache ≥100 nonzero bytes (= cache-side ≥100-byte state); every
   keyboard source caps lower (99 stamp / 61 mirror). [INFERENCE] A mode where
   the cache mirror is ≥100 (e.g. a submode of the row editor storing longer
   records) would close it — none found among MODE-menu states sampled.
3. **Mode-68 / reset-race** — negative in-emulator at 6 ON windows; on
   physical HW the race window differs (interrupt latency). Untested there.
4. **Untypable-byte problem** — unchanged: `0E 4D`/`10 F8`/`01 F8-class` words
   remain without any keyboard source (see `docs/physical-calc.md` §2/');
   even with ≥100 bytes the chain needs a typeable-gadget-only or
   placeholder-only layout. The one typeable adjacent word `38 35` (`0x3538`)
   cannot interleave with the rest of the chain (prior finding stands).

## 6. Repro commands

```
cd research/CasioEmuX
SDL_VIDEODRIVER=dummy ./emulator/emulator model=models/fx991esplus2 script=rop_v1.lua   # fill->99 + trigger (typeable, no injection)
SDL_VIDEODRIVER=dummy ./emulator/emulator model=models/fx991esplus2 script=rop_v1b.lua  # margin matrix + SETUP screens + true-len strcpy logger
SDL_VIDEODRIVER=dummy V2IDX=1 ./emulator/emulator model=models/fx991esplus2 script=rop_v2.lua  # INT head
SDL_VIDEODRIVER=dummy ./emulator/emulator model=models/fx991esplus2 script=rop_v3.lua   # STAT cartography
SDL_VIDEODRIVER=dummy ./emulator/emulator model=models/fx991esplus2 script=rop_v4.lua   # row-editor caps
SDL_VIDEODRIVER=dummy ./emulator/emulator model=models/fx991esplus2 script=rop_v5.lua   # injected strlen=101 differential
SDL_VIDEODRIVER=dummy ./emulator/emulator model=models/fx991esplus2 script=rop_v6.lua   # Syntax-ERROR entry
SDL_VIDEODRIVER=dummy ./emulator/emulator model=models/fx991esplus2 script=rop_v7.lua   # dance variants
SDL_VIDEODRIVER=dummy ./emulator/emulator model=models/fx991esplus2 script=rop_v8.lua   # reset-race
SDL_VIDEODRIVER=dummy ./emulator/emulator model=models/fx991esplus2 script=rop_v9.lua   # full tiling trace w/ e2e sled
SDL_VIDEODRIVER=dummy ./emulator/emulator model=models/fx991esplus2 script=rop_v10.lua  # echo census (budgeted); b/c/d/e/f = filtered/corrected reruns
```

Logs: `/tmp/v1.log v1b.log v2a.log v3.log v4.log v5.log v6.log v7.log v8.log
v9.log`, plus peer runs `/tmp/e1..e8.log`.
Chain/gadget cross-reference: `research/findings/cy845-rop.md`; exploit-terrain
table: `research/fxesplus/docs/known-exploits.md`.
