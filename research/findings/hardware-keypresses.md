# Hardware keypresses — CY-845 (fx-991ES PLUS 2nd ed) typed runbook

Date: 2026-11-22. Scope: the EXACT physical keypress list that types the 100-byte
payload into `0x8154` and fires the `AC, ◀, EXE` trigger, plus a payload-agnostic
generator. Artifacts:

| File | Content |
|---|---|
| `research/CasioEmuX/keygen.py` | generator: payload bytes → ordered key chords (direct chords + hack-#7 walks) |
| `research/CasioEmuX/ref_payload_runbook.md` | flat ordered table for the reference payload (506 rows incl. wait rows), md5 `5faa9fe7249d21d1dc6c6fde2fcf4c74` |
| `research/CasioEmuX/ref_payload_schedule.lua` | Lua schedule of the same list (consumed by the replay harness) |
| `research/CasioEmuX/ref_payload_safe_runbook.md` / `..._safe_schedule.lua` | `--safe` variant (emulator-measured chords only, more walk presses) |
| `research/CasioEmuX/keypress_replay.lua` | typed-replay verification harness (no `data[]` writes) |
| `research/CasioEmuX/probe_schedule.lua`, `probe2_schedule.lua` | chord-probe schedules used in the verification runs |

Reference payload (rop_e2e.lua, md5 `5faa9fe7249d21d1dc6c6fde2fcf4c74`, 100 bytes,
zero-free): `0E4D`×24 + `38 35 38 35 01 F8 BE 35 54 81` (offsets 48–57) + `0E4D`×21.
Swap in GameBuild's game payload with the same generator:
`python3 keygen.py --payload-hex <hex> --out game_payload` (or `--payload-file`).

## 1. Keymap derivation (byte → physical key chord)

Sources: ROM keycode tables `base/shift/alpha_keycodes.txt` (repo root; the ROM
`keycodes[]@0x23C6`, `keycodes_shift[]@0x29E0`, `keycodes_alpha[]@0x18BC` dumps),
physical key grid `models/fx991esplus2/model.lua`, and the emulator-measured atlas
(`docs/physical-calc.md` §6).

* **Table index**: `ix(code) = (code & 0xF)*8 + (code >> 4)` = `ki*8 + ko` — verified
  against 34/34 measured anchors (e.g. `1`=0x00→`31`, `2`=0x10→`32`, `9`=0x22→`39`,
  `×10ˣ`=0x62→`74`, `)`=0x33→base `29`/shift `2C`/alpha `58`, `CALC`=0x06 alpha→`3D`).
* **Physical keys**: the 49 scancodes bound in model.lua's button grid (all 8×8
  matrix slots except 0x50/0x51/0x52/0x65-0x67/0x70-0x77).
* **Direct chord** for byte `b`: any physical code with table entry `b`
  (base = 1 press; SHIFT+key / ALPHA+key = 2 presses, modifier is a latched toggle).
* **Confidence**: `measured` = byte confirmed to land at 0x8154 by that chord in the
  emulator (physical-calc.md §6 + our run 1 below); `table-only` = present in the ROM
  table but NOT delivered by the emulator's one-key-per-round keyboard shim
  (SHIFT+1→`01`, fn0x13→`F8` — see §5; on hardware the keyface follows the ROM
  table, Sheet-A/B of docs/hardware-procedure.md arbitrates).
* **Untypeable by any chord** (checked: all 256 entries × 3 tables + all measured
  templates): in particular **`0x0E` and `0x4D`** — no key produces them. These are
  delivered on hardware by the **hack-#7 walk (HW-VERIFIED 2026-11-19)**: type a seed
  symbol, wait for the cursor flash (≥1 blink period ≈ 1.5–3 s), then each
  flash-verified `▶`(0x37)/`◀`(0x26) press advances the entered symbol by one
  symbol-table entry (byte-order assumption, Sheet-B tell: `5`→`6`→`7`). Walk
  arithmetic: from seed `s`, target `b`: `d=(b-s) mod 255`; `d≤127` → `▶×d`, else
  `◀×(255-d)` (null `0x00` skipped, wrap mod 255).
* **2-byte templates** (measured, post-AC,◀ state): SHIFT+Σ(0x56) → `69 B8 …`
  (8-byte box `69 B8 21 BA 21 BA 21 B9` in MathIO), log(0x56) → `68 B8 …`,
  SHIFT+CALC → `6B B8`.

Chords used by the reference payload:

| Byte | Chord (physical keys) | Scancodes | Presses | Confidence |
|---|---|---|---|---|
| `38` | `8` | 0x12 | 1 | measured |
| `35` | `5` | 0x11 | 1 | measured |
| `01` | SHIFT + `1` | 0x07, 0x00 | 2 | table-only (emulator shim drops it) |
| `F8` | fn key 0x13 (matrix ko=1,ki=3; row {0x03,0x13,`(`,`)`,…}, 2nd key) | 0x13 | 1 | table-only |
| `BE` | SHIFT + `×` | 0x07, 0x31 | 2 | measured |
| `54` | ALPHA + M+ key | 0x17, 0x53 | 2 | measured |
| `81` | ALPHA + `×10ˣ` | 0x17, 0x62 | 2 | measured |
| `0E` | **walk**: fn 0x24 (seed `09`), flash-wait, `▶×5` | 0x24, 0x37×5 | 6 | walk (HW-verified mechanism) |
| `4D` | **walk**: `×` (seed `4E`), flash-wait, `◀×1` | 0x31, 0x26 | 2 | walk |

**Phase A — entry recipe (41 presses, rop_e2e.lua typed queue verbatim, T≈1 after reset) + trigger prefix:**

| # | key (scancode) | # | key (scancode) | # | key (scancode) |
|---|---|---|---|---|---|
| 1 | SHIFT w1 (0x07) | 2 | AC w2 (0x42) | 3 | SHIFT (0x07) |
| 4 | MODE (0x47) | 5 | 2 (0x10) | 6 | SHIFT (0x07) |
| 7 | Σ verify1 (0x56) | 8 | SHIFT (0x07) | 9 | MODE (0x47) |
| 10 | 2 (0x10) | 11 | SHIFT (0x07) | 12 | Σ verify2 (0x56) |
| 13 | AC clear (0x42) | 14 | ALPHA (0x17) | 15 | X `)` (0x33) |
| 16 | ALPHA (0x17) | 17 | `=` CALC (0x06) | 18 | SHIFT (0x07) |
| 19 | Σ( (0x56) | 20 | ALPHA (0x17) | 21 | X `)` (0x33) |
| 22 | SHIFT (0x07) | 23 | `,` SHIFT+`)` (0x33) | 24 | 1 (0x00) |
| 25 | SHIFT (0x07) | 26 | `,` (0x33) | 27 | 1 (0x00) |
| 28 | ×10ˣ (0x62) | 29 | 9 (0x22) | 30 | CALC (0x06) |
| 31 | EXE (0x60) | 32 | AC (0x42) | 33 | ◀ (0x26) |
| 34 | DEL (0x32) | 35 | DEL (0x32) | 36 | DEL (0x32) |
| 37 | 2 (0x10) | 38 | CALC (0x06) | 39 | EXE (0x60) |
| 40 | ◀ (0x26) | 41 | **PROBE 1 (0x00)** — must NOT insert | 42 | AC (0x42) |
| 43 | ◀ (0x26) | 44 | DEL (0x32) — clears the `32` residue (run 3) |  |  |

(Steps 42–44 = trigger prefix `AC, ◀` + one `DEL`: run 3 below shows the DEL clears
the `32` residue so the payload starts exactly at 0x8154 offset 0.)


**Phase B — payload (100 bytes at 0x8154), 374 presses + 90 flash-waits:**

| offsets | byte | keys per byte | presses |
|---|---|---|---|
| 0–47 (even/odd) | `0E` / `4D` | fn0x24, wait, ▶×5 / `×`, wait, ◀×1 | 24×(6+2) = 192 |
| 48 | `38` | `8` | 1 |
| 49 | `35` | `5` | 1 |
| 50 | `38` | `8` | 1 |
| 51 | `35` | `5` | 1 |
| 52 | `01` | SHIFT, `1` | 2 |
| 53 | `F8` | fn 0x13 | 1 |
| 54 | `BE` | SHIFT, `×` | 2 |
| 55 | `35` | `5` | 1 |
| 56 | `54` | ALPHA, M+ key (53) | 2 |
| 57 | `81` | ALPHA, ×10ˣ (62) | 2 |
| 58–99 (even/odd) | `0E` / `4D` | as above | 21×8 = 168 |

**Phase C — trigger (2 presses):** hold `▶` (0x37, makes KEYSCAN see a key → r0=1),
then `EXE` (0x60). (This is the tail of the proven `AC, ◀, EXE` trigger; the AC,◀
were already pressed at steps 43–44 before the payload.)

**Totals:** 41 + 3 + 374 + 2 = **420 physical keypresses** (+ 90 flash-waits,
timing gaps, not presses) with ROM-table seeds; **1356 presses** with `--safe`
(measured-only seeds). Fewest-possible note: the flood word `0E 4D` dominates; each
pair costs 8 presses minimum (6+2) because `0E`/`4D` have no chord — the walk is the
only hardware route (hack #7).

## 3. Timing notes (hardware)

* Start typing within **~0.25–0.4 s of ON/reset** (T≈1 after reset); later keys are
  eaten by the boot key-clear/park spin (keypress_table.md).
* Key hold ≈ 16 000 ticks @1× ≈ **60 ms**, gap ≈ 16–20k ticks ≈ 60–77 ms —
  human-pressable; chords (SHIFT/ALPHA + key) as two presses ~60 ms apart.
* Each hack-#7 walk byte: press seed, **do nothing for ≥1 cursor-flash period
  (~1.5–3 s, 2–3 blink cycles)**, then the arrow presses (~60 ms each). Never count
  arrows on an unconfirmed seed insert (≈1-in-6 eaten); re-press the seed and
  re-wait.
* Confirm the walk is byte-ordered (±1/press) once with `5`→`6`→`7` on `▶`
  (Sheet-B tell); if table-native, recount all targets from the recorded glyph
  sequence. Wrap counts mod 255 (null skipped).
* After the trigger the machine may look hung/frozen with indicators lit — that is
  the flood+chain; `ON` resets, no permanent damage (HW-verified).

## 4. Typed-replay verification (emulator, no memory writes; 3 runs, budget ≤4)

Harness `keypress_replay.lua`: rop_e2e recipe at T=1 → AC, ◀ → keygen schedule
(`Keyboard:PressKey` only) → hold ▶ + EXE → watch 0x4D20/tiles. Logs:
`/tmp/kp_probe1.log`, `/tmp/kp_ref1.log`, `/tmp/kp_probe2.log`.

**Run 1 — chord probe** (`probe_schedule.lua`, 15 entries). Verbatim:
```
KEY PROBE1 len=2 tail=323100BA21BA21B900000000
KEY P001 8 [direct 38] len=2 tail=323800000000000000000000
KEY P003 1 [SHIFT+1 -> 01 (table-only)] len=3 tail=323835000000000000000000   <- 01 did NOT land
KEY P004 fn 0x13 [-> F8 (table-only)]   len=3 tail=323835...                   <- F8 did NOT land
KEY P005 × [SHIFT+x -> BE (measured)] len=4 tail=323835BE0000000000000000
KEY P007 M+ key [ALPHA+M -> 54] len=6 tail=323835BE3554000000000000
KEY P008 ×10ˣ [ALPHA+x10 -> 81] len=7 tail=323835BE3554810000000000
KEY P009 log/Σ [SHIFT+Sigma] len=15 tail=BE35548169B821BA21BA21B9   <- 8-byte box
KEY P014 ▶(walk) len=15 ...   <- arrows do not insert (they move the cursor)
VERDICT: NO-TRIGGER scan_hits=0 h3538=414 len=15
```
→ measured chords land byte-exact; `01`/`F8` chords and walk arrows do not land
in-emulator (shim/flash fidelity limits).

**Run 2 — the exact reference-payload schedule** (`ref_payload_schedule.lua`, 460
entries / 374 payload presses), typed after AC,◀. Verbatim:
```
KEY P001 fn 0x24 [seed 09 (fn 0x24)] len=1 tail=320000000000000000000000   <- first divergence:
KEY P003..P007 ▶×5 [walk → 0E]          len=1 tail=3200...                    walk needs the HW flash
KEY P008 × [seed 4E (×)] len=1 tail=3200...  (cursor moved; seed 4E lands only later)
TYPED: all 507 actions done T=15252508 len=15 buf100=4E4E4E324E4E4E353531BE54744E4E0000…
TRIGGER: RIGHT+EXE pressed T=15252509 len=15 buf100=4E4E4E324E4E4E353531BE54744E4E…
VERDICT: NO-TRIGGER scan_hits=0 h3538=5300 len=15 tiles0E4D=0 tiles3835=0 floodok=427/338
```
Landed-window md5 `ef884ddcbf9058a18922ef978b5d083c` ≠ reference
`5faa9fe7249d21d1dc6c6fde2fcf4c74` — **first divergence is payload offset 0**
(byte `0E`): the walk cannot fire in-emulator (the flash-driven symbol advance
needs the real seconds-scale cursor flash; kyb_h7findings.md: advance cell
0x8224/25 ticks natively but the cursor-at-208 precondition is never reached).
Only measured-chord bytes landed (`4E`,`35`,`31`,`BE`,`54`,`74`…); the buffer then
froze at len=15 (absorb), so the ≥100 flood gate is unreachable by pure typing in
this harness.

**Run 3 — DEL/residue + typed-ceiling probe** (`probe2_schedule.lua`, 87 entries):
```
KEY P001 DEL [after AC-f/LEFT-f] len=0 tail=000000000000000000000000   <- DEL clears the 32 residue
KEY P002 8 len=1 tail=3800...   KEY P003 5 len=2 tail=3835...          <- payload now starts at offset 0
KEY P006 DEL len=3 tail=383538...                                       <- DEL deletes one byte mid-fill
TYPED: all 130 actions done T=4332131 len=43 buf100=383538383838…
VERDICT: NO-TRIGGER scan_hits=0 h3538=1450 len=43 tiles3835=1 floodok=261/504
```
→ with only measured chords the typed buffer ceilings at len=43 in this harness
(prior E-runs: 99 max) — **always < 100, so the strcpy flood cannot be reached by
pure typing in the emulator** (matches the definitive physical-calc.md §7 verdict).
The flood itself is verified (a) in-emulator with the payload present at 0x8154 —
rop_e2e.lua, 25+ KEYSCAN hops, 1499 tiles, span 0x8154..0x8DFF period-100 — and
(b) **HW-VERIFIED typed on the physical CY-845** (docs/hardware-procedure.md §5:
typed 100-byte trigger fired, screen froze with indicators lit).

## 5. Untypeable bytes, substitutes, re-encode

* Bytes with **no chord in any ROM keycode slot** (all 256×3 entries scanned) and
  not in any measured template: `0x0E`, `0x4D` (plus most of `00–20`, `42–4C`, `5A–80`,
  `83–B2`, `C0–FF` …). For the reference payload only **`0x0E` and `0x4D`** matter
  (the `0x4D0E` KEYSCAN flood word). No typed-only substitute preserves the chain
  (typable-chain.md verdict); on hardware they are delivered by the hack-#7 walk
  (§1), seeds `09`→`▶×5` for `0E` and `4E`→`◀×1` for `4D`.
* `0x01` (SHIFT+`1`) and `0xF8` (fn 0x13) are **table-only**: the emulator shim does
  not deliver them (run 1). Nearest measured substitutes: `0x01`→`0x31` (`1` key,
  walk `◀×48` if the true byte is needed), `0xF8`→`0x74` (×10ˣ, walk `◀×132`) —
  or walk them directly (keygen `--safe` does exactly this). If a payload must be
  emulator-verifiable end-to-end, re-encode those bytes to measured chords and
  adjust the chain words accordingly.
* Re-encode example: flood word `0x4D0E` → fully-direct `0x3538` sled (bytes `38 35`
  = keys `8`,`5`, measured) is the best all-direct typed payload, but the flood
  gate still needs strlen ≥ 100 which pure typing cannot reach in-emulator
  (run 3; HW-VERIFIED on hardware).

## 6. Generator usage

```
cd research/CasioEmuX
python3 keygen.py --ref --out ref_payload                 # reference payload
python3 keygen.py --payload-hex <100-byte hex> --out game_payload
python3 keygen.py --payload-file payload.bin --safe --out game_safe   # measured chords only
# outputs: <out>_runbook.md (flat ordered table), <out>_schedule.lua, <out>_summary.txt
# replay: KEYGEN_SCHED=<out>_schedule.lua SDL_VIDEODRIVER=dummy \
#   ./emulator/emulator model=models/fx991esplus2 script=keypress_replay.lua
```
