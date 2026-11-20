# CY-845 hardware procedure — basic overflow by hand, unstable-byte entry, typed payload

**Ground truth status**: the operator has already reproduced the basic overflow
on the physical CY-845 calculator following
<https://casiocalc.wikidot.com/basic-overflow> (the Σ method). This document
turns that wiki method plus the repo's measured CY-845 key data into a
step-by-step hardware sheet. Everything marked **[HW-unknown]** has never been
measured on the physical calculator; the emulator's negatives (hack #7 silent
at 20k–2M-tick settles, typed ceiling 54 tokens) are explicitly NOT assumed to
hold on hardware — the real cursor flash (seconds-scale) was never modeled.

Sources:
- <https://casiocalc.wikidot.com/basic-overflow> (method, unstable-byte section)
- <https://casiocalc.wikidot.com/hackstring> (effective character range; where bytes land)
- <https://casiocalc.wikidot.com/symbol-table> (byte→glyph map, ES PLUS 1-BYTE symbols)
- `research/fxesplus/docs/hackstring-tutorial.txt` (the 91-fill + AC◀= recipe;
  header "[991ES+ and 570ES+ only]" — the byte layout is the same family)
- Repo: `docs/physical-calc.md` (measured CY-845 keymap/token atlas),
  `research/findings/cy845-rop.md` (address table: KEYSCAN `0x4D0E`, memcpy12
  `0x35BE`, POP ER2/LR/RT `0x3538`, park `0x8FD6`).

## 1. Basic overflow by hand (the wiki Σ method, CY-845 keys)

Key names ↔ repo-scancode (for cross-checking): `X`=ALPHA+`]` (0x33), `=`/`EXE`
(0x60), `Σ` = SHIFT + logab-key (0x56), `,` = SHIFT + `)` (0x33), `×10ˣ` (0x62).

1. **RESET first** (clean state): `[SHIFT] [9] [3] [=]` then `[AC]` (Reset All →
   Yes). **[HW-unknown]**: exact reset-menu digits on CY-845; keep whatever
   route the operator used successfully.
2. **LineIO**: `[SHIFT] [MODE] [2]`.
   *CY-845 emulator note*: the SETUP menu opens but digit-2 selection was inert
   every run, and Σ( still inserted the boxed MathIO template
   (`69 B8 21 BA 21 BA 21 B9`, 8 bytes vs the 1st-gen's 1-byte `69`).
   **[HW-unknown]** whether real hardware takes LineIO here. The screen tell:
   press `[SHIFT][Σ]`; if the input shows `Σ(` with **corner boxes** = LineIO
   did not take; with a bare **`Σ(`** = LineIO took (1st-gen behavior).
   The wiki method does not require LineIO to be verified — it says *go to
   LineIO*, but the operator's successful run was matched on this emulator
   without LineIO ever verified, so do not block on it — just RECORD which.
3. **Type the long formula** (at least 4 bytes longer than ƒ):
   `[ALPHA][X] [ALPHA][CALC] [SHIFT][Σ] [ALPHA][X] [SHIFT][,)][1] [SHIFT][,)][1] [×10^x][9]`
   → screen: `X=Σ(X,1,1×10⁹` (tokens `58 3D 69B8 58 2C 31 2C 31 74 39`.
   If the Σ comes with boxes, type the digits **into the boxes** as displayed;
   the exact byte composition varies (targets `58 3D 69B8 58 2C 31 2C 31 74 39`
   or the boxed variant `58 3D 69B8 21BA 58 2C 31…` — **[HW-unknown]** which
   form the cursor-decoupling needs; the operator's success run is the
   reference).
4. **Press `=`** (`EXE`). The calculator evaluates.
5. **Re-enter the short formula ƒ** — `X=Σ(X,1,1`:
   press `[◀]` until the `×10⁹` tail is gone (delete `9`, `1`, `×10ˣ` with
   `[DEL]` ×3), or retype the whole Σ formula fresh — either is the wiki's
   "reuse the previous step" note. Screen: `X=Σ(X,1,1`.
6. **Press `[CALC]` then `=`** (`EXE`). Expected: **Syntax ERROR** — the screen
   shows `Syntax ERROR` (or localized equivalent) with AC/repeat prompt.
7. **Press `▶` (right)**. The ERROR screen drops; the **cursor is now
   decoupled** (basic overflow): per the wiki, the cursor is *before index 208*
   of the input area.
8. **Verify the state (the operator's known tell)**: press `[1]`.
   Expected per the wiki basic-overflow doc: the `1` **does not appear on the
   screen** at the first position (cursor decoupled ≠ normal editing).
   If `1` appears → the state was not reached; redo from step 3 (this is the
   one screen-check the wiki gives).

## 2. Unstable-character byte entry (hack #7) — **HW-VERIFIED on the CY-845** ✅

> **2026-11-19 hardware confirmation** (operator, physical fx-991ES PLUS
> 2nd edition): typed `5`, waited for the real cursor flash, pressed `▶` —
> **the glyph advanced.** This is the first hardware-confirmed mechanism in
> this ticket; the emulator's silence (§9 of `docs/physical-calc.md`) is a
> keyboard-bridge fidelity artifact, not a firmware difference. The walk
> arithmetic below is therefore the live technique; only the *step size*
> (±1 vs table-order) remains to be read off the first walk (Sheet B).

The wiki's method (quoted): *"Enter any symbol. This should overwrite the
existing token to the right of the cursor. Do nothing, wait for the cursor to
flash. Use [◀] or [▶] to move the cursor. The symbol entered will be advanced
according to the symbol table."*

The tempo difference is the whole trick: **the flash is seconds-scale real
hardware timing**. Our emulator probe used 20k ticks (≈77 ms) and **2M ticks
(≈8 s at 1× ≈ 0.5 s wall)** — and saw nothing; the user's hardware is
authoritative that the flash-driven advance exists. Use generous waits.

**Minimal first test — enter one known byte and verify it — revised for the
invisible-glyph case (2026-11-20):**

> **2026-11-20 hardware confirmation #2** (operator, physical CY-845): in the
> decoupled overflow state, typed symbols may show **nothing on screen** —
> the operator observed `5` inserting with the top line reading like
> `< (X,1,1` (the cursor at the left, the formula tail). So in the decoupled
> state the screen is **not** evidence of insertion; the byte-level checks
> (Sheet C's data[] echoes and the flood itself) are the only verification.

**Minimal first test — revised** (screen = unreliable; walk + flood = evidence):

1. In the basic-overflow state (§1 step 8, the decoupled cursor), press `[5]`
   (type a few times if the first is eaten — each press when the cursor
   *doesn't* insert = free cursor-advance).
2. **Watch the screen for the cursor flash** (the blocky cursor blinking).
   Wait 2–3 full blink cycles (~1–3 s). *Do nothing during the wait.*
3. Press `[▶]` once. **Expected** (1st-gen behavior): the `5` becomes the
   **next symbol in the symbol table** — per the table byte-order that is `6`
   (`0x36`). Press `[▶]` again → `7` (`0x37`).
   - **If the glyph changes 5→6→7 with each ◀/▶ ⇒ byte-order (±1/press)**:
     all walk counts below are literal.
   - **If the glyph changes to something else** — table-native: *record the
     glyph sequence* (one per press, ~10 presses; photo or copy each glyph).
     This defines the map; do not guess distant jumps.
   - **If the top line reads like `< (X,1,1` and nothing seems to change** —
     the symbol may be **invisible in the decoupled state** even though it
     landed (the operator's confirmation run showed exactly this: typing `5`
     = no visible change, yet the advance worked). Try `[◀]` once and then
     `[▶]` once, watching for a DIFFERENT glyph after each — a changed glyph
     on one of them = the advance alive with the token hidden; treat the
     resulting glyph as invisible-but-present and rely on the walk counts +
     Sheet C's behavioral checks.
   - **If nothing changes on any arrow** ⇒ the flash-wait was mis-timed or
     the entered symbol never landed: repeat, waiting ≥3 blink cycles, and
     try `[◀]` once and then `[▶]` once, watching for a DIFFERENT glyph
     after each — a changed glyph on one of them = the advance alive with
     the token hidden; treat the resulting glyph as invisible-but-present
     and rely on the walk counts + Sheet C's behavioral checks.
     **[HW-unknown]** whether CY-845's flash-driven rewrite is ◀-only, both,
     or needs a longer wait.

4. **Verify the byte lands in memory** — two independent checks:
   - *Screen glyph* (§3 chart above): `0x0E` should render as a row-0 constant
     glyph (the `λcp`-region symbol — the table's 15th cell = `λcn`); note
     **[HW-unknown]** which glyph CY-845's firmware actually maps there.
   - *Behavioral*: `0x0E`/`0x4D` are not part of any screen font test on
     hardware; the decisive hardware check is the **payload run in §3** — a
     successful ROP walk = the AC◀= tiling behaving as in the emulator logs.

**Selecting the needed bytes** (assuming byte-order advance, step-3 tell; if
the tell said a different order, count moves per the recorded glyph sequence):

| Target byte | Enter | Moves from the entered symbol (assumes ±1/press, byte-ordered) |
|---|---|---|
| `0x0E` (KEYSCAN lo) | `5` (`0x35`) | **◀ × 0x27 = 39** |
| `0x4D` (KEYSCAN hi / →Y) | `5` (`0x35`) | **▶ × 0x18 = 24** |
| `0x3538` word | type `8`,`5` directly (`38 35`) | no walk needed (the pair strands typable-adjacent) |
| `0x35BE` (memcpy12) | `5` + ▶ walk to `B`…, or `BE`=SHIFT+`×`, `35`=`5` direct | `BE 35` both have keyboard sources (SHIFT+`×` = 0xBE; `5` = 0x35) |
| `0x8154` (POP EA src) | `M`=ALPHA+M-key (`0x54`), `e`=ALPHA+×10ˣ (`0x81`), `1`=5 + 4 ◀ (`0x54`→0x54-4… reality-check: 0x81→0x81-0x2D=0x54 via ◀ 45, 0x54→0x54-0x2D=0x27 then wrap? 0x54-... see note) | byte `0x54`+`0x81` direct = **typable without walk**: `M`, `e` — order `54 81` = `M` then `e` |
| `0x02B1E`/park `0x8FD6` | — | `F8`,`10`,`D6` have no keyboard source — **needs the walk** (e.g. `0xD6` from `5` = ▶ ×0xA1=161) |

*Note*: the exact advance arithmetic (±1 vs table-order) must be confirmed by
the §2.1 first test before trusting the counts; if the advance wraps past
`0x00`, count modulo 255 (the null is skipped per the wiki's "every non-null
byte is a valid symbol").

## 3. Payload placement and reaching the flood at 100

- **Input area** = `0x8154`, 100 bytes (`0x8154`–`0x81B7`). **Cache (last
  formula)** = `0x81B8` (immediately after). **Random seed + counter** =
  after that (the wiki hackstring page: `[Input 100][Cache 100][seed 8][counter 2]`).
- Bytes typed in the **normal (pre-overflow) state** land in the input area
  (`0x8154+cursor`). **Bytes typed past the overflow cursor (index ≥100) land
  in the cache region** — this is how a 100+-byte string is built by hand
  without any injection.
- **The flood condition** = the wiki: at `=` with **strlen(0x8154) ≥ 100**,
  `strcpy(0x81B8, 0x8154)` re-copies the 100-byte block over and over
  (RAM is filled to `0x8E00`, stack included = the tile flood).
- **The hand path to 100** (from `hackstring-tutorial.txt`, 1st-gen — mark
  **[HW-unknown]** for CY-845's twist that makes the emulator stall at 54):
  1. In the basic-overflow state: type **91 filler bytes** (any non-null; `1`
     × 91). The screen stop-scrolling tells (the tutorial): after 90 bytes
     `◄8901234567890|`; after 1 more `◄9012345678901|X►` — an `X►` appearing
     to the right of the cursor = the 100-byte overflow marker.
     *Watch: if extra bytes do not appear past some len, SPRINKLE the
     unstable-char technique: each fill byte can be foot-gunned by the
     flash-wait+◀▶ to become any wanted byte (per §2) — i.e. the ceiling is
     not the fill limit for a patient operator; **[HW-unknown]**.*
  2. Verify: enter 8 more bytes — characters should appear right of the
     cursor (the tutorial's verification; counts are approximate per model).
  3. **Enter the 100-char payload**: the ROP words, one byte at a time —
     typable directly per the atlas: `8 5` (the `0x3538` gadget word, 25×),
     or walked via §2 for the bytes that have no key (`0x0E`, `0x4D`, `0xF8`,
     `0x10`, `0x01`, `0xD6`).
     Recommended first payload (all-typable, 100 bytes):
     `38 35` ×50 = type `85` repeated 50 times.
     Ambitious payload (needs §2 walk): the proven address table =
     `[0E 4D]×k + [BE 35 BE 35] + [01 F8]... `[HW-unknown]** the byte-exact
     counter state needed; the emulator's proven one = `0E 4D`×50 (KEYSCAN
     self-loop, verified walk) — requires typing `0x0E`/`0x4D` via §2.
  4. **Trigger**: `[AC] [◀] [=]` — the wiki hackstring recipe = AC, LEFT, =
     (the = = EXE); = the same AC◀= the emulator's `AC ← EXE`.
- **[HW-unknown]** the CY-845 cursor machinery in the flooding phase (how the
  display behaves once the input area runs into the cache) — the emulator's
  only measured analog = the 54-byte ceiling with the fill-absorb; hardware
  (per the operator's success) presumably does not stall the same way.

## 4. Test sheet (numbered: action → expected screen → report back)

### Sheet A — first verified byte (10 min)
1. RED reset → `[SHIFT][MODE][2]` → record: does Σ( insert boxed or bare?
2. The §1 steps 3–8 (long formula → `=` → retype ƒ → `CALC` `=` → `Syntax
   ERROR` → `▶` → probe `[1]` non-insert). Record every screen.
3. §2 first test with `[5]`, ≥3 blink cycles, `[▶]`. Record: glyph before,
   glyph after, and whether each press steps one glyph.
4. Repeat with `[◀]` and a longer wait if nothing moves. Record both.

**Report back**: which glyph sequence the walk produced; whether the advance
is ±1-per-press or table-native (i.e. does `6` come after `5`, or does
`Σx²` come after `5`).

### Sheet B — byte spotting for `0x0E`/`0x4D` (15 min) — refined with exact walk arithmetic

**The walk math** (hardware case: start from the typable `5` = byte `0x35`;
each flash-verified `▶`/`◀` press advances/retreats the glyph by ONE entry):

| Target | From `0x35` | Forward ▶ count | Backward ◀ count |
|---|---|---|---|
| `0x0E` (KEYSCAN lo) | `0x35` | not reachable by ▶ without wrap | **◀ × 0x27 = 39** |
| `0x4D` (KEYSCAN hi / →Y) | `0x35` | **▶ × 0x18 = 24** | not needed |
| `0x54` (M, the `0x8154` lo) | `0x35` | ▶ × 0x1F = 31 | — |
| `0x81` (e, the `0x8154` hi) | `0x35` | ▶ × 0x4C = 76 | — |
| `0xD6` (park `0x8FD6` lo) | `0x35` | ▶ × 0xA1 = 161 | — |
| `0xF8` (LCD hi, e.g. `10 F8`) | `0x35` | wrap needed: ▶ × (0xF8−0x35) = **195** | ◀ × (0x35 + 0x100 − 0xF8) = **61** |

**Wrap rule**: the symbol table lists bytes `0x01`–`0xFF` (the null `0x00` is
skipped/invalid — the wiki: "every non-null byte is a valid symbol"). If the
glyph stuck at the walk end (= you hit `0x00`-adjacent behavior) or the run
presents a generic `@`-glyph, do a `◀`-pass to re-enter the valid range and
resume counting. If both 5→6→7 (▶) and byte-order hold for 10+ steps, treat
the table as linear-bytes-mod-256 and count wraps as ±255-equivalents
(i.e. `0xF8` from `0x35` = ▶×195 = the same as ◀×61).

**The `5`-retry rule** (insert-drop insurance): before counting, confirm the
`5` actually inserted — the screen must show the `5` glyph to the right of
the cursor where the walk will act. If the press was eaten (≈1-in-6 in the
emulator), press `5` again and re-wait for the flash. Never count moves on an
unconfirmed insert.

**Confirming ±1 vs table order** (one-time, ~2 min):
1. Insert `5` (retry per above), flash-wait (≥2–3 blink cycles).
2. Press `▶` ×3, **recording the glyph after each press**
   (photo or copy each glyph).
3. Decision:
   - `6` `7` `8` — byte-order (±1/press): all Sheet-B/C counts above are
     literal.
   - anything else — table-native: the sequence you wrote down IS the local
     map; extrapolate only by re-running (do not guess distant jumps);
     e.g. if `5`→`Σx²` (row 1 of the wiki chart = `0x10`) the step = +0xDB
     (mod 255), and you must recount every target from the observed step.
4. Report the three glyphs + whether `◀` from `5` gives `4` (byte-order
   confirmation in the other direction).
5. End the sheet by re-entering the basic-overflow state cleanly: the
   entered/walked bytes live at the decoupled cursor; **[HW-unknown]** whether
   they persist as bytes in `0x8154+` — Sheet C's runbook reads the input
   area, so keep going.

### Sheet C — the typed payload + flood (30–60 min) — one coherent sequence

**New capability (2026-11-19)**: the flash-advance is HW-VERIFIED (§2), so the
100th byte — unreachable by plain typing (the editor caps at 99 chars + NUL;
measured: `strlen=99` with the NUL at index 99) — can now be supplied by
**walking the symbol at the tail**, not by typing past the cursor: the wiki
walk *advances the entered symbol*, so a `5`-insert + walk = any byte wanted,
at every position including past the cap. The runbook assumes the Sheet-B
decision (byte-order ±1; adjust counts if table-native).

1. Reset + `[SHIFT][MODE][2]`; formula `X=Σ(X,1,1×10⁹` → `=` → re-enter ƒ →
   `CALC` `=` → `Syntax ERROR` → `▶` (Sheet A §1 steps 1–8); confirm the
   decoupled state (probe `1` does nothing).
2. **In the cursor-LEFT state (`|< (X,1,1`, inserts invisible), do NOT use the
   91-`1` fill first** — in this state presses are absorbed as free
   cursor-advances (nothing renders), so the fill would not insert: walk the
   cursor to the tail instead. Press `▶` ×3 (one per `(X,1,1` remnant token)
   until the cursor is AFTER the last token; nothing renders — expected.
3. **Type `5`, flash-wait (≥2–3 blink cycles), then walk:**
   - `▶ ×24` → the `M`-class byte `0x4D` = the KEYSCAN hi **or** `◀ ×39` →
     the row-0 λ-class = `0x0E` (the KEYSCAN lo) — the `0E 4D` word.
   - Each `5`+flash-wait+walk = **one payload byte**; the `5`-retry per the
     unconfirmed-insert rule; walk-count arithmetic per the Sheet-B table
     (wrap = modulo 255).
4. Continue to 100 bytes (`85` pairs for the all-typable variant; `0E 4D`
   pairs via the walk), proof-of-concept with 8–10 bytes first by rhythm.
5. **Trigger**: `[AC] [◀] [=]` (`EXE` = the same key; the emulator's verified
   trigger class). Expected screen (from the emulator's proven S14/S15 runs):
   immediate chaotic glyphs / screen freeze / gibberish rows (the 1499-tile
   flood + `CHAIN: KEYSCAN #1..25` @`0x4D20`, sp `0x8DA0→0x8E00`, +4/hop);
   the machine may appear hung — **`ON` resets, nothing permanent observed in
   26 emulator runs**.
6. **Fallback ladder** if nothing observable:
   a. repeat with the P1 (`85`×50) payload if P2 was used;
   b. repeat with the trigger as `[AC][◀][EXE]` spelled via the `=` key;
   c. repeat from a clean decimal LineIO state (verify Σ( bare/box first;
      record which).
7. **Report back** (the decision data): the screen at the flood (exact glyphs
   or photos), the payload variant + byte count, where the walked bytes
   visibly landed (if the top line echoed them), whether `▶` still advances
   the glyph after the 99-char cap (the walk = the live 100th-byte source),
   and any pre-flood divergence from the emulator's `len=99` cap.

**Operator state `|< (X,1,1` — the cursor at the LEFT, inserts invisible — exact instruction:**

> In this state nothing renders, but **no press is lost**: every typed key
> = a free cursor-advance (+1 index, nothing renders). Do NOT keep typing
> `5`/`1` blindly at the left — walk to the END of the formula tail first:
> press `▶` ×3 (one per `(X,1,1` remnant token) until the cursor is AFTER the
> last token, then enter the payload symbol: type `5`, wait for the cursor to
> flash (2–3 blink cycles, do nothing during), then `▶` ×24 → the glyph
> becomes the `M`-class byte `0x4D` (or `◀ ×39` for the row-0 λ-class `0x0E`);
> each walked byte = one payload byte. For the flood payload the
> `0E 4D`-word = insert `5`+walk-39◀ then `5`+walk-24▶ … per byte ≈ 65
> presses/byte ≈ 4000 presses/100 bytes — do a 4–8 byte proof-of-concept
> first (§4 fallback ladder), then `AC` `◀` `EXE`.

## 5. HW-VERIFIED ✅ (2026-11-20): the flood fired on the physical CY-845

The operator typed the 90×`1` fill + the 91st-byte + the `8`×50-class payload
+ `AC ◀ =` → the screen **frozen with almost all top indicators lit** = the
draw-buffer/LCD flood — **the typed 100-byte trigger fired on hardware**.
(Marking the earlier lines below accordingly: the 100th-byte/cache route and
the flood = **[HW-VERIFIED ✅]**; the flash-advance (§2) = the gate-passing
mechanism.)

**The visible-payload runbook (next step, exact bytes/keys):**
- With byte-order walks (from `5` = `0x35`): `0x10` = ◀×37; `0xF8` =
  ◀×61 (or a wrap ▶×195 against the skipped null); `0x54`/`0x81` = typable
  direct (`M`, `e`) — composing the **memcpy12 word `0x35BE`** (typable direct:
  `BE` = SHIFT+`×`, `35` = `5`) with **dst `0xF810`** = LCD **row 1** = the
  visible 3×3-cell/12-byte row (not all-indicators).
- Keyed layout at the right offsets (MM `POP PC` = 4 B entries; the `0x3538`
  setup; the `0x35BE` call): `[0E 4D]`-class words via Sheet-B walks,
  `35 38`-class words typed directly, `54 81` typed, `F8`-class walked.
- Trigger: `AC ◀ EXE`; the flood/chain markers = the emulator's proven
  S14/S15 class (KEYSCAN `@0x4D20`, +4/hop, 1499-tile flood), `ON` resets,
  no permanent damage.

### Sheet D — the visible-cell payload design (the operator deliverable, typed)

**The 100-byte payload** (memcpy12 `0x35BE` → dst **`0xF810`** = LCD row 1,
src = the tile `0x8154`, len 12, pattern = a visible 12-byte row, not
all-indicators). Proven base = the v4 layout (`rop_final5.lua`/`rop_e2e.lua`:
`0x3538` doubled, `0xF801`, `0x35BE`, `0x8154` at offsets ~60–68), adapted:
dst `0xF810` (`10 F8`).

**The table — offsets 60–69 (the v4 class), then the fillers:**

| offset | byte | word | key (typed / 5+◀N / 5+▶N) |
|---|---|---|---|
| 60 | 0x38 | `0x3538` lo | typed `8` |
| 61 | 0x35 | `0x3538` hi | typed `5` |
| 62 | 0x38 | `0x3538` lo (doubled) | typed `8` |
| 63 | 0x35 | `0x3538` hi (doubled) | typed `5` |
| 64 | 0x10 | `0xF810` lo | **walk**: from `0x35` = ◀×37 (`0x35−0x10 = 0x25`), not ◀×39 |
| 65 | 0xF8 | `0xF810` hi | **walk**: from `0x35` = ◀×61 (wrap) — or `1`+◀×?? — no key = walked |
| 66 | 0xBE | `0x35BE` call lo (memcpy12) | typed `BE` = SHIFT+`×` |
| 67 | 0x35 | `0x35BE` call hi | typed `5` |
| 68 | 0x54 | `0x8154` lo (src) | typed `M` |
| 69 | 0x81 | `0x8154` hi (src) | typed `e` |
| 70–99 | 0x11 | (junk, nonzero) | `1` typed |

**Corrections to the earlier wrong table** (the user's verdict): it listed
`0E`/`4D`/`D6` = the **P2 KEYSCAN-chain class** (`0x4D0E` = the KEYSCAN word,
not the memcpy cell) with the wrong walk math (`0x10` from `0x35` = **◀×37**
(`0x35−0x10 = 0x25`), not ◀×39+2; the digit `1` = `0x31`, not `0x10`). The
payload = the **v4 layout**: `W(60)=0x3538, W(62)=0x3538, W(64)=0xF810,
W(66)=0x35BE, W(68)=0x8154` → bytes **`38 35 38 35 10 F8 BE 35 54 81`** plus
the fillers, at the exact offsets the stack consumes.

**Marking recap (updated 2026-11-20):**
**[HW-VERIFIED ✅]** = the unstable-character flash-advance (hack #7 — the
first hardware-confirmed mechanism; operator-run on the physical CY-845)
**and the typed 100-byte flood** (the 91-fill + the 85×50 payload + `AC ◀ EXE`
= the screen frozen with almost all top indicators lit = the draw-buffer/LCD
flood — HW-VERIFIED ✅; recovery = ON/battery pull, no damage).
**Still [HW-unknown]** = reset-menu digits, LineIO digit-2 take, Σ template
form on hardware, per-move byte delta (±1 vs table order), fill-ceiling
markers on hardware, flood-phase display. Killed-unknowns are
marked and not silently assumed.

Cite-back anchors for the community: the wiki pages above are the method's
source; the repo's emulator measurements (ceiling 54; hack-#7 no-effect at
≤2M-tick settles = ≈0.5 s flash — consistent with the user's report that
seconds-scale hardware flash was never modeled) are all logged in
`docs/physical-calc.md` and `research/findings/cy845-rop.md`.
