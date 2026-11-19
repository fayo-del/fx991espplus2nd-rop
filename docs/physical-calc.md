# CY-845 typed-ROP exploit — physical keypress sequence

Derived strictly from `research/CasioEmuX/rop_e2e.lua` (the deterministic
end-to-end emulator flow, reproduced verbatim in the Session-15 verification)
cross-checked against `research/findings/cy845-rop.md` (Sessions 4–19).
Every key below was verified against a `push(...)`/`chord(...)` call in the
script; token encodings are verified only for the emulator keymap
(`keycodes[]` in the CY-845 model), **not on physical hardware**.

## 0. Verification status of this document

| Item | Status |
|---|---|
| Scancodes / hold-gap timings | emulator-verified (CY-845 model `keycodes[]` at ROM `0x23C6`; every press reproduced in the Session-15 re-run) |
| Screen states | emulator-verified (`render_screen` dumps of `0xF800..`) |
| Payload bytes `0E 4D`×50 + v4 draw words | **`data[]`-injected, NOT typed** (see §4) |
| Full exploit chain (overflow → tiled stack → 25-step ROP walk) | emulator-verified, reproducible (`Session 15-verification` in `cy845-rop.md`) |
| Everything above on a physical fx-991ES PLUS 2nd edition | **never run**; hardware keymap is assumed identical to GYX (ROM `0x23C6` table, byte-identical per Session 4) |

No step in this document has ever been confirmed on a physical CY-845.

## 1. Key reference (scancode → physical key, CY-845/GYX-identical map)

| Scancode | Physical key | Notes in `rop_e2e.lua` |
|---|---|---|
| `0x07` | `SHIFT` | modifier, left of `'` |
| `0x17` | `ALPHA` | modifier, right of `'` |
| `0x47` | `MODE` | (SETUP when shift-held) |
| `0x06` | `CALC` | |
| `0x60` | `EXE` / `=` | |
| `0x42` | `AC` (= ON, one key) | |
| `0x32` | `DEL` | |
| `0x26` | `←` (left arrow) | |
| `0x37` | `→` (right arrow) | held: forces `r0=1` in memcpy |
| `0x36` | `↓` | SETUP page-down (Session 12) |
| `0x56` (shift) | `Σ` (SHIFT + log`ab`/Σ key) | bare → `69 B8`; boxed → `+ 21 BA` |
| `0x33` | `X` (ALPHA + `)` key) | → `0x58` |
| `0x62` | `×10ˣ` | → `0x74` |
| `0x00`/`0x10`/`0x22` | `1` / `2` / `9` | → `0x31` / `0x32` / `0x39` |

Modifier rule discovered during the e2e work (Session 14/18): **the first
SHIFT after a boot/AC transition is eaten** — open SETUP with
`[SHIFT][MODE]` again if the menu did not render.

## 2. Setup — LineIO attempt (and its known failure)

1. **`SHIFT`** — warm-up press at `T≈0` (`"w1"`, 12000-tick hold). Boot keys
   are unreliable; this primer is harmless either way.
2. **`AC`** (`"w2"`, 12000-tick hold, 24000 gap) — screen: idle input line.
3. **`SHIFT` + `MODE`** (chord, 16000/16000) — SETUP menu opens. LCD row 2
   changes to the rendered menu (`Session 11`: row2 `10044840E38038040400038E`).
   *Expect nothing (first-press rule); repeat this step if the menu did not open.*
4. **`2`** (`"setup1-digit2"`, 30000 hold) — intended: page-1 digit-select = LineIO.
   **On CY-845 this digit-select is INERT in every run** (Session 11: "the `2`
   keystroke changed nothing"; Session 12: rows identical before/after a 60k-tick
   digit-2 hold). *DOWN + EXE navigates this menu* (Session 12) but whether the
   selection landed = LineIO remains unproven.
5. **`SHIFT` + `Σ`** (`"sigma-verify"`, chord) — the Σ-tell. Typed repeat is
   **boxed** (`len=8 bare=false boxed=true`, i.e. `69 B8 21 BA 21 BA 21 B9`) —
   the LineIO form never takes effect in the emulator.
6. **`SHIFT` + `MODE`** (retry chord, `"setup2"`) and **`2`** (`"setup2-digit2"`)
   — the Session-12 DOWN+EXE variant is the alternative; same result.
7. **`SHIFT` + `Σ`** (`"sigma-verify2"`) — second check (same `boxed=true`).
8. **`AC`** (`"AC-clear"`) — clear; screen: blank input line.

No Fix/Norm keys exist anywhere in `rop_e2e.lua`. **Discrepancy vs the brief**:
the prompt's "LineIO (`SHIFT MODE 2`)" step is in the script, but the resulting
Σ-tell stayed `boxed=true` in the emulator — LineIO was never demonstrated on
CY-845; the overflow fires anyway (input-locked `PROBE1 NOT-INSERTED` state).

## 3. The formula — `X=Σ(X,1,1×10⁹` (exact keys)

| # | Key(s) | Script call | Token(s) inserted |
|---|---|---|---|
| 9 | `ALPHA` + `)` (X) | `chord(ALPHA, 0x33, "X1")` | `58` |
| 10 | `ALPHA` + `CALC` (=) | `chord(ALPHA, CALC, "eq")` | `3D` |
| 11 | `SHIFT` + `Σ` key | `chord(SHIFT, 0x56, "Sigma")` | `69 B8` |
| 12 | `ALPHA` + `)` (X) | `chord(ALPHA, 0x33, "X2")` | `58` |
| 13 | `SHIFT` + `)` (,) | `chord(SHIFT, 0x33, "comma1")` | `2C` |
| 14 | `1` | `push(K1, "one")` | `31` |
| 15 | `SHIFT` + `)` (,) | `chord(SHIFT, 0x33, "comma2")` | `2C` |
| 16 | `1` | `push(K1, "one2")` | `31` |
| 17 | `×10ˣ` | `push(KX10, "x10")` | `74` |
| 18 | `9` | `push(K9, "nine")` | `39` |

Screen: `X=Σ(X,1,1×10⁹` rendered on the input line (Session-15 verified signal:
`X=Σ(X,1,1×10⁹` = `58 3D 69B8 58 2C 31 2C 31 74 39`).

## 4. The trigger dance `CALC` `=` `AC` `←` `DEL×3` `2` `CALC` `=` `←`

| # | Key(s) | Script call | Purpose / observed effect |
|---|---|---|---|
| 19 | `CALC` | `push(CALC)` | |
| 20 | `EXE`/=` | `push(EXE)` | evaluator processes the Σ-formula |
| 21 | `AC` | `push(AC)` | clear |
| 22 | `←` | `push(LEFT)` | **cursor decouples** → the Syntax-ERROR / overflow state |
| 23–25 | `DEL` `DEL` `DEL` | `push(DEL) ×3` | wipe the tail (12000 hold / 12000–20000 gaps each) |
| 26 | `2` | `push(K2, "two")` | third parameter → `2` |
| 27 | `CALC` | `push(CALC, "CALC2")` | |
| 28 | `EXE`/=` | `push(EXE, "EXE2")` | |
| 29 | `←` | `push(LEFT, "LEFT2")` | |
| 30 | `1` (**probe**) | `push(K1, "PROBE1")` | **must NOT insert** — `blen()` unchanged = the basic-overflow tell. Session 15: `before=2 after=2 NOT-INSERTED(good)` ✔ |

**The payload is `data[]`-injected, never typed** — this answers the brief's
CRITICAL question. At `final_t==36001` the script writes the whole payload
straight into the input buffer:

```lua
for e = 0, 49 do data[PAY_IN+e*2] = 0x0E; data[PAY_IN+e*2+1] = 0x4D end   -- PAY_IN = REPL_IN
W(60, 0x3538); W(62, 0x3538); W(64, 0xF801); W(66, 0x35BE); W(68, 0x8154)
```

i.e. `0E 4D`×50 = the v4 draw words (`0x3538` doubled, `0xF801`, `0x35BE`,
`0x8154`), all 100 bytes non-zero. **No typed path exists for `0x0E`/`0x4D` on
CY-845**: the GYX token table (`f14_tokens.asm`) maps `0x0E`/`0x4D` as GYX
*token-index* entries (`cs14`, `sto_y`) with no confirmed CY-845
scancode→token encoding; the fxesplus multibyte-insert technique
(`known-exploits.md` row 8) is explicitly **"NOT ES PLUS — EX/CW generation
only … Not applicable to CY-845"**; the only CY-845 typed-token avenue is the
row-7 unstable-character technique (`casiocalc.wikidot.com` #enter-unsupported
/ tieba p/3114375974) — **[INFERENCE], blacklist unknown on CY-845, not
attempted in any run**. The v4 draw words (`F810`, `35BE`, `8154`) likewise
have no known typed encoding. The closest typable payload candidate would be a
community-sled style token stream (the `cv##`/`cs##` multibyte names of
`docs/demo-program.txt`) — none exists verified for CY-845 in this repo.

## 5. Final trigger — `AC` `←` `EXE`

| Step | Key(s) | Notes |
|---|---|---|
| 31 | `→` **held** (final phase, `0x37` held across 16001 ticks) | forces `r0=1` → single memcpy iteration (Session 17/18: ER2=`0xF801` ⇒ `MOV ER0,ER2` leaves `r0=1`) |
| 32 | `AC` | "AC←" (final phase) |
| 33 | `←` | "←" |
| 34 | *(payload already in RAM via `data[]` injection)* | |
| 35 | `EXE` | trigger fires; the strcpy floods the stack with `0E 4D` pairs |

(In the Session-14 run the payload sat between AC and EXE as the plain
"AC ← [payload] EXE"; `rop_e2e.lua` is the v5 layout — `→`-held + `AC` + `←`
before the injection, `EXE` after.)

## 6. Expected screen state after each phase

| Phase | Screen state |
|---|---|
| boot + warm-up (`SHIFT`, `AC`) | idle input line |
| `SHIFT MODE` → SETUP | menu renders on LCD row 2 (verified) or nothing (first press eaten — retry) |
| digit-`2` | nothing changes (Menu digit-select inert on CY-845) |
| setup chords + `AC` | blank input line |
| formula typed | `X=Σ(X,1,1×10⁹` visible |
| `CALC EXE AC ←` | cursor at the first position (decoupled / overflow state), input locked; after the dance: still `X=Σ(X,1,1×10⁹` displayed |
| probe `1` | **must not insert** (`NOT-INSERTED(good)`) |
| payload injected + final `AC ← EXE` | evaluator wakes (Session 12: `pc=0xD488…`); then the tiled stack walks — `CHAIN: KEYSCAN #1..#25` at `0x4D20` (sp `0x8DA0→0x8DFC`), post-exhaustion `pc` ends in `0x3276/0x8E00…` (chaos) or the wait-key tree at `pc=0x8F4A-8F54` (Session 17 run 2) |

**Warning — chain exhaustion / hang**: after tile exhaustion (sp→`0x8E00`)
the register/stack state degrades into the post-chain chaos
(`pc=0x3276/0x8E00…, sp=0x0000/0xFFF0`) — the calculator may **look hung**
(Session 16 run 2: "FROZEN for 3.4M ticks" — a safe, harmless ROM loop). The
payload's tail entries should be `D6 8F` (the wait-key park at `0x8FD6`) to
land cleanly. **`ON` resets everything**; no permanent damage observed in any
run (all broken states recovered via reset; nothing outlives a power cycle).

## 7. Totals and discrepancies

**Total: 45 physical keypresses** (33 typed keys + 4 final-phase presses with
the `→`-held/`AC`/`←`/probe step + 2 setup retries ×2 chords + DEL×3 + the
final 4) and **0 typed payload bytes** — all 100 payload bytes are
`data[]`-injected.

**Discrepancies vs the brief:**
1. *"the fillers"* (`91×'1'` in earlier scripts) — **absent from
   `rop_e2e.lua`** (the injected payload provides the length; the typed buffer
   stays locked at `blen()=2`). Earlier scripts needed `blen()≥100` fillers
   before the trigger.
2. *"the payload bytes were typed"* — **they never are**: the full `0E 4D`×50 /
   v4 draw words are `data[]`-injected (script, `final_t==36001`). No CY-845
   token encoding for `0x0E`/`0x4D`/v4 exists (§4).
3. *LineIO (`SHIFT MODE 2`)* — in the script, but the digit-2 menu-select is
   **inert on CY-845**; the Σ-tell stays `boxed=true`, and the overflow fires
   without LineIO ever being verified. LineIO is an unresolved step, not a
   working prerequisite.
4. *The final `AC ← EXE`* — correct as stated, but `rop_e2e.lua` adds the
   **held `→`** before `AC` (forces `r0=1` for a single memcpy iteration) and
   injects the payload between `←` and `EXE`.
5. The v4 draw words land in the firmware's **DSR-banked LCD window**, not in
   the Lua-visible `0xF800` main window (Session 19 row-0 write contradiction):
   the row-0 12-byte draw stays unresolved without a DSR gadget.

**Sources**: `research/CasioEmuX/rop_e2e.lua` (verbatim re-run, Session
15-verification in `research/findings/cy845-rop.md`); keymap/hold-gap per its
`push`/`chord` default timings (16000 hold / 20000 gap at 1× clock; ≥3 SDL
frames per key — the deterministic-landing rule). Hardware = **never verified**
(emulator-only results; assumed GYX-identical keymap).
