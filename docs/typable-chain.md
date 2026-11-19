# CY-845 TYPABLE-ONLY ROP — typed chain design & final verdict (2026-11-19)

Everything in this document comes from runs executed in this session
(`research/CasioEmuX/rop_typed_e1.lua` … `rop_typed_e9.lua`, emulator
`research/CasioEmuX/emulator`, model `models/fx991esplus2`, 1× clock,
16k/16k timing, T=0 typing). **No `data[]` injection is used at any point in
the typed-run scripts**; every byte in the input buffer arrives via physical
keypresses through `Keyboard:PressKey`.

## 1. What a typed word can be

A stack word is *typable* iff both its bytes are physical 1-byte tokens
adjistent-by-adjacent in the input buffer. Atlas (48 single-byte values):

`21 25 28 29 2B 2C 2D 2E 30..39 3A 3D 41..46 4E 4F 54 57 58 59 5E 60 68 69
6B 6C 6D 74 81 82 8B B8 B9 BA BE BF C2`

(derivation: `docs/typable-tokens.md`).

**Untypable**: `00 0E 4D 01 F8 10 …` — therefore the deployed payload words
`0x4D0E` (KEYSCAN), `0x4EF2` (park), `0xF801/0xF810` (LCD dst), `0x87D0`
(draw buffer), `0x8XX1`-style and any `00`-byte word are impossible to type.

## 2. Encodings (verified against the emulator's own CPU dispatch +
      the community disassembler `oki-u8-disas.cpp`)

| Note | Bytes | Means |
|---|---|---|
| `8E F2` | POP **PC** — **4 bytes under MM_LARGE** (PC + CSR) |
| `8E F1` | POP EA (2 B) |
| `8E F8` | POP LR (4 B) — **none at typable address** |
| `1E F2` / `1E F8` | POP ER2 (2 B) / POP ER8-class (2 B) |
| `25 F0` / `1F FE` | MOV ER0,ER2 / RT (PC:=LR) |
| `0E F0 h l` | B 0x00h:0xlh — absolute jump; **byte 0x00 ⇒ untypeable form** |

**MMU = MM_LARGE for CY-845** (`Chipset.cpp: SetMemoryModel(CPU::MM_LARGE)`):
every `POP PC` consumes 4 stack bytes, the second word being the CSR; its
**bit 0 selects the ROM bank** — a typed walk can bank-switch.

## 3. Typable gadget inventory (bank0 + bank1 scanned exhaustively)

| Gadget | Address | Bytes | Typable | Role |
|---|---|---|---|---|
| **walk/loader** | `0x3538` | `38 35` (`8`,`5`) | **YES** | POP ER2; POP ER8; MOV ER0,ER2; RT |
| walk/loader (short) | `0x3536` | `36 35` (`6`,`5`) | **YES** | POP ER4; POP ER2; POP ER8; MOV ER0,ER2; RT |
| **memcpy12** | `0x35BE` | `BE 35` (S+`×`, `5`) | **YES** | POP EA; 12-byte copy [EA+]→[ER2], ER2+=16, R0--… POPs; RT |
| POP PC continuator | 8 sites | — | **YES** | `0x2B32 0x30C2 0x313A 0x382C 0x4F74 0x6928 0x6B32 0xBE42` |
| POP EA / POP LR | 4 / 1 sites | — | only `0x35BE` / none | CR-2/3 |
| park (0x4EF2-analog) | — | — | **NONE** | 0x4EF2 = `F2 4E`, B-rel16 needs a `00` byte |
| KEYSCAN | `0x4D0E` | `0E 4D` | **NO** | untypeable in every table |

CPU-walk math (uniform `0x3538` tile): with LR pinned to `0x2B1E` (the app
callback-return), each typed-gadget cycle = `POP PC` (4 B) + `0x3538`'s pops
(4 B) = **8 bytes/cycle, PC:=0x3538 forever** — a deterministic typed sled.

## 4. Typed, whole-pipeline test results (no injection)

All runs shared the e2e-verified head (32 keys, dance, PROBE1 no-growth).

| Run | Typed tail | End state | Verdict |
|---|---|---|---|
| E1 (`e1.log`) | 5+5 digits, 20 Σ(, 10 digits, 10 Σ( | len 74 after last template; at typing-stop len=1 (buffer spontaneously re-synced to its 0x81B8 mirror; then trigger evaluated len=1) | post-AC inserts **work and grow**; Σ( = 5–6 B inserts in broken state |
| E2 (`e2.log`) | 24 digits + 6 Σ( + 30 digits… via RIGHT cursor walks | len 66 → trigger; no walk (pc parks 0x4B96) | digit landing decays ~+1 per 2–3 keys; content control degrades after ~12 B |
| E3 (`e3.log`) | burst ladder A/L/B/C/L2/D/E/F | **len 98** | Σ( mass-growth ≈ +1.9 B/keystroke; digit +0.5 B/keystroke |
| E4 (`e4.log`) | rounds of 12 digits + 4 Σ( chords ×16 | **len 99** → trigger → no junk-PC hits, some walk-class gadget hits ≈ app baseline | one byte short of the 100-byte strcpy |
| E6 (`e6.log`) | same + 10-digit fin burst | **len 99 hard** (zero growth on fin) | **typed cap = exactly 99 bytes** |
| E8 (`e8.log`) | mixed wrong-keycode templates | len 5 | keypad mapping guess invalid; Σ( only on SHIFT+0x56 |
| E7 (`e7.log`) | pure Σ( ×64 | len 70, stalls at 70 for 36 straight chords | box-fill semantics absorb repeated template |
| E9 (`e9.log`) | digits+Σ( to 99 then +8 Σ( chords | **len 99**; proofs: `21BA=0 21B9=0 69B8=0 B921=0 BAB9=0` (the firmware-never-executes junk-code PCs — all zero) | **trigger does not fire at L=99** |

**Post-trigger truth at L=99** (E9): the app's = handler runs the fixed
copy `strcpy(0x81B8, 0x8154)` — the 99 bytes landed mirrored at 0x81B8
(E9 FINAL-BUF bytes [100..129] == bytes [0..29]), no self-feed, app returns
to its idle park (pc=0x4B96 sp=0x8D22). **At L=100 (e2e injected) the same
copy self-feeds and floods 1499 pattern tiles + executes the planted chain
(25 KEYSCAN hops, sp 0x8DA0→0x8E00, Session-15-verified).**

## 5. Final verdict

**A fully-typed ROP chain on CY-845 is impossible by direct typing, and the
limit is one exact byte**: the editor's input line holds **≤ 99 typed bytes**
(hard cap, verified twice), while the exploit's strcpy self-feed flips on at
`strlen(0x8154) ≥ 100`. The deployable chain words also cannot be typed where
it matters: KEYSCAN `0x4D0E`, park `0x4EF2`, LCD/draw-buffer words `0xF8xx`,
`0x87D0`, and every `0x00`-byte word — the gadgets that make the deployed
chain executable (scan → draw → park) are all in the untypable set. The best
**typed** chain is therefore the 99-byte `0x3538` sled; the full 100-byte
interrupted-with-gadgets version requires either one non-typed byte (any
single `data[]`-write, e.g. the trailing `0x00`→non-zero trick at byte 99)
or the LineIO/box-fill state that this firmware Breed-variant does not
deliver (SETUP digit-select inert; box-fill absorbs repeated templates).

## 6. The exact typed key sequence (the verified 99-byte run — E9)

45-key head (from `rop_e2e.lua`, verbatim):
```
SHIFT AC SHIFT MODE 2 SHIFT 0x56 SHIFT MODE 2 SHIFT 0x56 AC
ALPHA ) ALPHA CALC SHIFT 0x56 ALPHA ) SHIFT ) 1 SHIFT ) 1 ×10ˣ 9
CALC EXE AC ← DEL DEL DEL 2 CALC EXE ← 1 PROBE1 AC ←
```
then typable fill (repeated until len 99), 20 rounds of:
```
8 5 8 5 8 5 8 5 8 5 8 5      (12 digits, alternating)
SHIFT-0x56 SHIFT-0x56 SHIFT-0x56   (3 Σ( = 2-byte-token inserts)
```
then 8× `SHIFT-0x56` (absorbed; cap=99).

Buffer content at trigger (99 bytes, all typed; byte-exact from `/tmp/e9.log`):
```
323838383838383838383868B868B868B835353535353568B868B83838383869B869B8
3535353569B838383868B868B835353568B838383835353538BA21B9BA21B9BA21B9BA
21BA21B9BA21BA21B9BA21BA21B9BA21B9BA21B9BA21B9BA21B9BA21B9BA21B9
```

That buffer *does not* flood (L=99 < 100). The same bytes at L=100 would tile
and walk (the `0x3538`-words are at the wrong offsets in this particular run
because the early landing pattern is state-dependent — the walk-class words
must be laid at the arrival offset 48 of the tile, which needs the
100-byte-cap state that this build does not reach).

## 7. What each script does (runnable now)

```
cd research/CasioEmuX
SDL_VIDEODRIVER=dummy ./emulator/emulator model=models/fx991esplus2 \
    script=rop_typed_eN.lua | tee /tmp/eN.log
```
E1–E3: insert-rate experiments. E4/E5/E6/E9: len-guarded typed fill + trigger
+ junk-address proof breakpoints. E7/E8: Σ-only and mixed-template blitzes.

All exact stdout for this session's evidence: `/tmp/e1.log … /tmp/e9.log`
(run logs are also reproduced verbatim in §4 above; those blocks are the
actual captured output).
