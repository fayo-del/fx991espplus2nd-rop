# CY-845 typable token atlas (fx-991ES PLUS 2nd edition)

Every byte that can be inserted into the input buffer at `0x8154` by physical
keypresses, fully typed (no `data[]` injection). Derived from the
emulator-measured per-key atlas (`docs/physical-calc.md` §6), the CY-845 ROM
keycode tables (`keycodes[]`@0x23C6, `keycodes_shift[]`@0x29E0,
`keycodes_alpha[]`@0x18BC in `models/fx991esplus2/rom.bin`), and the E1–E9
typed experiments in this repo's `research/CasioEmuX/rop_typed_e*.lua`.

## 1-byte tokens (one keystroke = one buffer byte)

| Byte | Meaning / source key(s) |
|---|---|
| `30`–`39` | digits `0`…`9` (base!) — `0` verified typed = `30` (E2 `S z0 len=1 tail=30`) |
| `2B` `2D` | `+` `-` |
| `4E` `4F` | `×` `÷` |
| `8B` | Ans |
| `74` | ×10ˣ |
| `81` `82` | e (ALPHA+×10ˣ), π (SHIFT+×10ˣ) |
| `28` `29` | `(` `)` |
| `25` `%` | SHIFT+`(` |
| `2C` `,` | SHIFT+`)` |
| `2E` `.` | base |
| `C2` | ALPHA+`.` |
| `3A` `:` | ALPHA+fn (C万余 key 0x06) |
| `3D` `=` | ALPHA+CALC |
| `BE` `BF` | SHIFT+`×`, SHIFT+`÷` |
| `6C` `6D` | Pol( / Rec( (SHIFT+`+`/`-`) — multi-byte templates in normal mode |
| `57` | x! (SHIFT+fn 0x46) |
| `58` `59` | X, Y (ALPHA+`)`, ALPHA+0x43) |
| `41` | A (ALPHA+0x04; measured 3/3 with retries in rop_trig3) |
| `54` | M (ALPHA+M-key) |
| `B3` | SHIFT+`0` (measured, E2: inserted `B3`) |

Not insertable by any key (the "untypable byte" wall):
`00`–`0F`, `10`–`20`, `22`–`24`, `26`–`27`, `2A`, `2F`, `3B`–`3C`, `3E`–`40`,
`42`–`4C`, `4D`, `50`–`53`, `55`–`56`, `5A`–`5D`, `5F`, `61`–`67`, `6A`–`6B`,
`6E`–`73`, `75`–`80`, `83`–`8A`, `8D`–`B2`, `B4`–`B7`, `BB`–`BD`, `C0`–`C1`,
`C3`–`FF` — in particular **`0E`, `4D`, `01`, `F8`, `10`, `00`** (the deployed
KEYSCAN/RAM-pointer words) and every LCD-row byte (`F8xx`, `87xx-D0`).

## Multi-byte templates (one keystroke = several bytes; shape is state-dependent)

| Keystroke | Normal-mode insertion (measured) | Post-overflow-state landing (measured, E3–E7) |
|---|---|---|
| SHIFT+0x56 | Σ( boxed = `69 B8 21 BA 21 BA 21 B9` (8 B) | bare 2-byte token `69 B8` (or fragment class `21 BA`/`21 B9`/`BA 21 B9` once the box-fill loop stalls) |
| 0x56 | log₂( = `68 B8 21 BA 21 B9` (6 B) | bare `68 B8` |
| SHIFT+0x06 | ∫dx → d/dx( = `6B B8 …` | bare `6B B8` |
| 0x46 | √( = `21 5E B8 60 31 B9` (6 B) | — |

**Key finding (E3–E9):** in the post-`AC,←` overflow state, `Σ(` lands as the
**bare 2-byte token `69 B8`** and counts as **one token against the editor's
line cap** — the token-count expansion the 1st-edition (GY450) community used
via `cv##/cs##` tokens also exists on CY-845.

## Measured constraints

| Constraint | Value | Evidence |
|---|---|---|
| Editor line cap | **99 tokens / 99 bytes** of 1-byte tokens; typing beyond is silently dropped | E6: 384+ keypresses, buffer frozen at len=99; final 10-digit burst zero growth |
| Token-count ceiling bypass | 2-byte tokens (Σ( `69 B8`) = 1 token, 2 bytes ⇒ ~50 chords can exceed 99 *bytes* | E7/E9 |
| Landing reliability at 1× clock, 16k/16k timing | digits ≈ 1 B per 1–2 keystrokes (early 100 %, decays; absorbed strokes go into the ×10ⁿ/box pocket, never into the buffer) | E2/E3/E4 burst traces |
| Buffer persists through trigger | typed buffer (len 66–99) survives `AC,←` pre-typing order and the final EXE | E2/E5 FINAL-BUF |

## Adjacent-pair realizability

Any 2-byte word `(lo,hi)` is typeable iff `lo`–`hi` is a realizable adjacency:

- after a 1-byte token: **any** byte of the atlas (1-byte tokens are free chunks);
- inside a Σ( template: `69→B8→21→BA→21→B9` and `21→5E→B8→60→31→B9` chains
  (fixed), so words like `69B8`, `B821`, `21BA`, `BA21`, `21B9`, `215E`, `5EB8`,
  `B860`, `6031`, `31B9` materialize without extra keystrokes.

Thus gadget-word candidates for typed chains = addresses whose little-endian
bytes are both in the atlas (48 single-byte values above) with the adjacency
rule applied. Full scan results: `docs/typable-chain.md`.
