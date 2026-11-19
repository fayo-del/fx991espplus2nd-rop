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

## 2. Unstable-character byte entry (hack #7, hardware-specific tempo)

The wiki's method (quoted): *"Enter any symbol. This should overwrite the
existing token to the right of the cursor. Do nothing, wait for the cursor to
flash. Use [◀] or [▶] to move the cursor. The symbol entered will be advanced
according to the symbol table."*

The tempo difference is the whole trick: **the flash is seconds-scale real
hardware timing**. Our emulator probe used 20k ticks (≈77 ms) and **2M ticks
(≈8 s at 1× ≈ 0.5 s wall)** — and saw nothing; the user's hardware is
authoritative that the flash-driven advance exists. Use generous waits.

**Minimal first test — enter one known byte and verify it:**

1. In the basic-overflow state (§1 step 8, the decoupled cursor), press `[5]`
   (type a few times if the first is eaten — each press when the cursor
   *doesn't* insert = free cursor-advance).
2. **Watch the screen for the cursor flash** (the blocky cursor blinking).
   Wait 2–3 full blink cycles (~1–3 s). *Do nothing during the wait.*
3. Press `[▶]` once. **Expected** (1st-gen behavior): the `5` to the right of
   the cursor becomes the **next symbol in the symbol table** — per the table
   byte-order that is `6` (`0x36`). Press `[▶]` again → `7` (`0x37`).
   - **If the glyph changes 5→6→7 with each ◀/▶ ⇒ the advance is by
     byte-order** — report it; the payload walk is then trivially countable
     (see below).
   - **If the glyph changes to something else**, that is the table's real
     order — *record the glyph sequence* (one glyph per press, ~10 presses).
     It is what §3's byte-selection must be derived from. The reference glyph
     chart is <https://casiocalc.wikidot.com/symbol-table> (ES PLUS section,
     printed in byte order starting `mᴘ mₙ me mµ a₀ h μɴ μʙ ℏ α re λc γᴘ
     λcp λcn / Σx² Σx n Σy² …`).
   - **If nothing changes** ⇒ the flash-wait was mis-timed or the entered
     symbol never landed: repeat, waiting ≥3 blink cycles, and try `[◀]`.
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

### Sheet B — byte spotting for `0x0E`/`0x4D` (15 min)
1. In the basic-overflow state, type a run of `1`s (say 20) — note at what
   count the display behavior changes (input-area full vs cache spill).
2. Enter `5`, flash-wait, walk `▶` 28 times. Report the final glyph.
   If byte-walk: the glyph should be `M` (`0x4D` = `→Y`-region on the wiki
  chart; the CY-845 display = the ROW-4 cell 13). Walk `◀` 39 instead for the
   `0x0E`-region glyph (row 0, the λ-class).
3. If the glyph chart shows the wrong glyph at that count, the advance = the
   table-native order: dump ~10 consecutive glyphs and stop — that defines
   the map.

### Sheet C — the typed payload + flood (30–60 min)
1. §3 path: 91×`1` fills (record the screen counters at 90/91 and the `X►`
   marker), then the payload:
   - **first**: the all-typable `85` ×50 (= `38 35`×50; no byte-walk needed).
   - **second**: the `0E 4D`×50 (each byte via §2 walk — 39◀ or 24▶ from `5`;
     ~63 walks per byte ×50 = tedious; do 4–8 bytes first to prove the flood,
     then continue by the counted pattern).
2. `[AC] [◀] [=]`. Expected (from the emulator's verified runs — S14/S15):
   the screen may *change chaotically / freeze / show gibberish* (the tile
   flood + the ROP walk); `CHAIN: KEYSCAN #1..25` in the emulator = the
   hardware equivalent = **calculator appears to hang or flicker**; ON
   resets; **no permanent damage** in any emulator run (all states recover).
3. Fallback: if nothing observable happens, repeat Sheet C once with the
   `[AC] [◀] [=]` instead typed as `[AC][◀][EXE]` (the = = the same physical key).
4. **Report back**: the screen text/behavior at the flood (exact glyphs or a
   photo), which payload variant was entered, and the byte count; any
   divergence from the emulator's PROBE1/ceiling behavior.

Marking recap: **[HW-unknown]** = reset-menu digits, LineIO digit-2 take,
Σ template form on hardware, flash-advance direction/order, per-move byte
delta, fill-ceiling on hardware, flood-phase display. Killed-unknowns are
marked and not silently assumed.

Cite-back anchors for the community: the wiki pages above are the method's
source; the repo's emulator measurements (ceiling 54; hack-#7 no-effect at
≤2M-tick settles = ≈0.5 s flash — consistent with the user's report that
seconds-scale hardware flash was never modeled) are all logged in
`docs/physical-calc.md` and `research/findings/cy845-rop.md`.
