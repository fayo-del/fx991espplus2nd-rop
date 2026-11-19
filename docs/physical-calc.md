# CY-845 typed-ROP exploit — physical keypress sequence

Derived from `research/CasioEmuX/rop_e2e.lua` (the deterministic end-to-end
emulator flow; reproduced independently twice, here and in the Session-15
verification) cross-checked against `research/findings/cy845-rop.md`
(Sessions 4–19). Token bytes below are **empirically measured in the emulator**
(`research/CasioEmuX/rop_enum.lua`, `rop_sto.lua`, `rop_typed85.lua`) and
cross-validated against the ROM keycode tables and the community symbol table.

## 0. Verification status

| Item | Status |
|---|---|
| Scancode→keymap (49 physical keys) | ROM-verified (`keycodes[]` @0x23C6, `shift` @0x29E0, `alpha` @0x18BC) AND emulator-typed-verified |
| Token bytes per key × {base, SHIFT, ALPHA} | **emulator-measured (this work, §6)** — every key typed, bytes dumped at input buffer 0x8154 |
| STO / double-modifier (SHIFT+ALPHA, ALPHA+SHIFT) | emulator-measured: **all 16 combos insert nothing** |
| Payload bytes `0E 4D`×50 / v4 draw words | `0E`, `4D`, `01`, `0xF8`, `0x10` — **no typed source** (§2); `54`(M), `81`(e), `35`/`38` (digits) ARE typable. The deployed payload = `data[]`-injected only |
| Typed full-chain execution | **NOT demonstrated**; pre-patch typed ceiling = 54 tokens at 1×; post-patch the digit-select and post-dance typing work, but LineIO stays boxed and hack-#7 advance is still silent (§9) — so the ≥100-byte trigger remains unreachable typed **in the emulator**; the hardware procedure (`docs/hardware-procedure.md`) exists for the real board |
| Hack #7 unstable-byte symbol-advance | **WIKI-exact test negative in the emulator even post-patch**: `▶/◀` walks with 2.5M-tick (≈4 s) settles never advance the entered byte (§9); the hardware Sheet-A test arbitrates whether it is flash-cadence or a real firmware difference |
| Emulator keyboard bridge | **root cause found and patched** (§9): Casio-emu mode never drove the KID matrix post-boot; the (+31-line, 3-file) matrix-drive + report-retention patch restores digit-select, post-dance typing, and handshake re-arm |
| Everything above on physical hardware | **never run** — emulator-only |

No step in this document has been confirmed on a physical CY-845.

## 1. Key reference (scancode → physical key)

From `keycodes[]` @ROM 0x23C6 (byte-identical to GYX per session 4, byte-verified
here against `models/fx991esplus2/rom.bin`):

| Row (KI) | Scancodes (col = KO<\<4) and keys |
|---|---|
| 0 | 0x00=`1` 0x10=`2` 0x20=`3` 0x30=`+` 0x40=`-` 0x60=`EXE`/= |
| 1 | 0x01=`4` 0x11=`5` 0x21=`6` 0x31=`×` 0x41=`÷` 0x61=`Ans` |
| 2 | 0x02=`7` 0x12=`8` 0x22=`9` 0x32=`DEL` 0x42=`AC`/ON 0x62=`×10ˣ` |
| 3 | 0x03=`∫dx` 0x13=`∫dx→`? 0x23=`(` 0x33=`)` 0x43=`S⇔D`? 0x53=`%`/`,`? 0x63=`.` |
| 4 | 0x04=`√` 0x14=`x²` 0x24=`RCL` 0x34=fn 0x44=fn 0x54=`S⇔D`? |
| F | 0x06=`CALC` 0x16=fn 0x46=fn 0x56=`Σ`/`log₂(` 0x07=`SHIFT` 0x17=`ALPHA` 0x47=`MODE` 0xFF=`ON/AC` |
| nav | 0x26=`←` 0x36=`↓` 0x27=`↑` 0x37=`→` |

Modifier chord pattern (from `rop_e2e.lua`): press modifier (0x07/0x17),
release, press key — the firmware latches the modifier. Typing must start at
T≈0 (Session-10's delivery window) and the SETUP menu (SHIFT, MODE, `2`)
must open first. Timing = 16000-tick hold / 20000-tick gap at 1× clock
(~60 ms / ~77 ms).

## 2. THE PAYLOAD VERDICT — cargo bytes `0E 4D`×50 are **NOT typable**

The `rop_e2e.lua` payload (0x4D0E = the KEYSCAN gadget address, little-endian
`0E 4D` ×50) is **`data[]`-injected** at `PAY_IN=0x8154`, never typed. The
v4/v5 draw words (`38 35`, `10 F8`, `BE 35`, `54 81`) are likewise injected.

**Definitive token-table verdict (both sources checked):**

1. **ROM keycode tables** (raw dump, `rom.bin` @0x23C6 keycodes / 0x29E0 shift
   / 0x18BC alpha — 64 slots each = the full 8×8 scancode matrix):
   **no slot holds `0x0E` or `0x4D`** in any table. (`0x4D` would be the →Y
   arrow in the wiki symbol table row 4 — the GYX-family `->Y` STO-arrow —
   and the CY-845 `keycodes_alpha[]` has no `4D` entry; verified byte-exact:
   the alpha row is `41 42 43 44 45 46` (A–F) + `58 59 54 C2` (X/Y/M/:,) only.)
2. **Wiki symbol table** (casiocalc.wikidot.com/symbol-table, ES PLUS series):
   byte `0x0E` = a **physics-constant symbol in row 0** (λ-region, the `mᵣ/λcp`
   class — the constants-menu slot) and `0x4D` = **→Y** in row 4 — both live in
   *table regions with no CY-845 keyface binding*, consistent with (1).
3. **Emulator enumeration** (all 49 keys × base/SHIFT/ALPHA + 16 SHIFT+ALPHA /
   ALPHA+SHIFT double-modifier combos typed, each token dumped at 0x8154):
   **0x0E and 0x4D never appear** (0/E and 4/D hits = NONE across 130
   typed samples).

**The closest typable payload does not reach an executing ROP chain.** The
`0x3538` gadget word (`POP ER2; POP LR; MOV ER0,ER2; RT`) is fully
typable — digits `8`/`5` = bytes `38`/`35` — and my `rop_typed85.lua` test
**confirms those bytes land adjacently** (`38 35 38 35 38 35 38 35 …` in the
input buffer). But the 100-byte strlen-0x8154 overflow trigger is unreachable
typed: (a) post-dance ordering (the `rop_e2e` head, then digits): the input
locks after the `CALC EXE AC ← DEL×3 2 CALC EXE ←` probe state; digits
absorb into the ×10ⁿ-exponent pocket at a ~44-54 token ceiling (measured:
`len=54`, then no growth). (b) pre-dance ordering: the exponent-field absorbs
everything (`len=9`, the Σ template + 2 only, nothing more) — the S7
"1-in-4 landed invisible absorb" case, measured at 0 here.

**The `115esp2` community lead — checked and closed (2026-11-19 web search):**
`115esp2` = the fx-115ES PLUS **2nd edition** (same CY-845 board; per the
casiocalc thread #506-507 the 115ES-PLUS differs from 570VN-PLUS in modes, and
per e-Gadget blog-entry-775 the "2nd edition" line = the 2019+ anti-counterfeit
refresh). Searched: casicalc forum (all 13 pages of the ES-PLUS hacking
thread, 2016-2025), GitHub (fxesplus / Itay2805/fx991es-hacking / ZaoHan415
fork — all 1st-generation), casicalc.wikidot.com, tieba.baidu (p/3395822027
post-collection, p/1800667172, p/2793407170 = 1st-gen), Reddit, Hackaday,
archive/FX-e-Gadget. Findings:
- the only fx-991ES-PLUS-**2nd-edition** owner in the hacking thread
  (LTVA, post #442, 2020-10-02): *"I haven't entered any hackstrings yet"* —
  their work pivoted to JTAG/ISP/programmator reflash, no typed string;
- post #514 (2024-10-08, lantern): *"the post says it's ES-PLUS only... this
  forum is dead lol"* — i.e. the community typed hackstrings remain
  1st-edition-only (GY450; the tutorial header: "[991ES+ and 570ES+ only]");
- no repository, wiki page, forum thread, video transcript, or archived
  document contains a typed hackstring for the 2nd edition / CY-845.
The 2nd-edition exploit state matches this repo's: overflow reachable, but no
published typed payload exists.

**Exact ip3 replica** (`rop_typed_ip3.lua` — `input_path3.lua` reproduced
verbatim: `SetClockSpeed(8)`, 16k/40k long settles, primer chords, 91×`'1'`
fillers at the original positions, then 50×(`8`,`5`) typed, then `AC ← EXE`):

```
CHECKPOINT: after F91 len=7 buf=32292929292C7400…
CHECKPOINT: payload-end len=7 buf=32292929292C7400…
INPUT: typing done len=9 buf=69B85858BA21BA21B9…
INPUT: len@F91=7 len@payload=7 maxlen=9
WATCH: t=… pc=4B96 sp=8D74 tiles(38 35)=0 h3538=… h4d20=0
PROTO: END pc=4B96 sp=8D22 h3538=796 h4d20=0 maxlen=9
```

— **the `blen≥100` from the S6/S7 notes is NOT reproducible with
input_path3's own configuration in this environment** (at 8× overclock the
91 fillers land as 1-drop-class: `len@F91=7`; all 100 payload presses: zero).
The comment in `input_path3.lua` (`"the 91 fillers ... len=16 after F91"`,
Session 7) already documented the same failure mode once.

## 2b. Hack #7 (unstable byte) — WIKI-exact test on CY-845: still negative

`rop_h7b.lua` implements the wiki method literally (`casiocalc.wikidot.com/
basic-overflow`): warm-up → SETUP → the formula `X=Σ(X,1,1×10⁹` → `CALC`
`EXE` `AC` `←` (**no DEL dance**) → 12×`'1'` advance probes, each sampled →
**1M-tick flash wait** (16× clock, back to 1× before every key) → `Σ(`
inserts ×3 (retried, sampled) → `▶`/`◀` walks each followed by a **2M-tick
flash wait** and a sample → second `Σ(` round → final dumps. Exact stdout
(`/tmp/h7b2.log`):

```
H7[after-AC-LEFT]:   len=0  buf=00…           ext=00…  far=00…   (no error state; formula wiped)
H7[adv1..adv12]:     len=1→11 (5-of-6 land)  buf= 31 31 31 …  ext/far = 00 everywhere
H7[sym1..sym3]:      len=19→24→29  (Σ-templates insert AT THE CURSOR END:
                     …31 31 69 B8 21 BA 21 BA 21 B9, 68 B8… ×3)
H7[movr1..3/movl1]:  len=29 UNCHANGED, buffers byte-identical    ← the flash walks did nothing
H7[sym2.1..3]:       len=36→41 (more Σ( at the cursor end)
H7[final]:           len=41  input=31×11 69B8 68B8×3 21BA 69B8 68B8…  cache=00×100  far=00×100
```

- **Cursor advance = plain typing** (each `'1'` = +1 index; the buffer grows
  1→41); the Σ-templates insert at the walked cursor END (the §2b earlier
  "index-2 rewrite" was the post-`MOV-L` cursor, reproducible here as the
  end-of-run insert).
- **The cache area (0x81B8+) never fills in this flow** — the
  `strcpy(0x81B8,0x8154)` tiling never fires (no `Syntax ERROR` state
  reached: `after-AC-LEFT` shows `len=0`; the e2e-style dance is what
  produced `PROBE1 NOT-INSERTED`).
- **The symbol-table advance (the #7 core) does NOT manifest** on CY-845:
  after inserts, `▶`/`◀` walks with 2M-tick (≈16-frame) flash waits change
  **zero bytes** — three successive walks, byte-identical samples. The wiki
  claims the advance is a wait-for-flash effect; on CY-845 there is no
  effect even at 2M-tick settles.
- **No `0E`/`4D` ever appeared** at any sample (`buf/ext/far` = `00`-blocks
  except the typed content).

**The `0x3538` gadget word (`8`,`5` = `38 35`) consists of fully typable
adjacent bytes that land correctly** (§7), and `0x54` (`M`) is also typable
(`ALPHA` + M-key). The bytes with **no typed source at all**: `0x0E`, `0x4D`,
`0x01`, `0xF8`, `0x10` — i.e. the KEYSCAN word (`0E 4D`), the row-1 dst word
(`10 F8`) and the `01` half of the `0xF801` ER2 word cannot be typed; the
`0x3538`/`0x35BE`/`0x8154` words could be composed (`35 38`×2, `BE`+`35`,
`54`+`81` via `ALPHA`+M and `ALPHA`+×10ˣ) but the chain layout requires the
untypable words interleaved, so no typed-only equivalent of the deployed
payload exists.

## 3. Digital keypress sequence (the *typed* part of the verified end-to-end run)

45 physical keypresses, all verified against `rop_e2e.lua`'s `push`/`chord`
calls (see Session 15-verification for the full reproduced run:

1. `SHIFT` (warm-up, T≈0)
2. `AC` (warm-up)
3. `AC` (warm-up 2 — coverage for the eaten-first-key window)
4. `SHIFT`
5. `MODE` (SETUP opens)
6. `2` (LineIO attempt — **inert in every run**; Σ left boxed)
7. `SHIFT`
8. `Σ` key (Sigma verify #1 — expected `69 B8 21 BA 21 BA 21 B9` boxed)
9. `SHIFT`
10. `MODE` (SETUP retry)
11. `2`
12. `SHIFT`
13. `Σ` key (Sigma verify #2)
14. `AC` (clear)
15. `ALPHA` + `)` → `X` (`58`)
16. `ALPHA` + `CALC` → `=` (`3D`)
17. `SHIFT` + `Σ` key → `Σ(` template (`69 B8 21 BA 21 BA 21 B9`)
18. `ALPHA` + `)` → `X`
19. `SHIFT` + `)` → `,` (`2C`)
20. `1` (`31`)
21. `SHIFT` + `)` → `,`
22. `1`
23. `×10ˣ` → (`74`)
24. `9` (`39`)
25. `CALC`
26. `=`/`EXE`
27. `AC`
28. `←`
29. `DEL`
30. `DEL`
31. `DEL`
32. `2`
33. `CALC`
34. `=`/`EXE`
35. `←`
36. `1` (**the probe — must NOT insert**; overflow-state tell)
37. `→` **held** (forces `r0=1` for the memcpy single-iteration)
38. `AC`
39. `←`
40. *(payload 0x0E 4D×50 loaded at 0x8154 — by `data[]` injection in the
    emulator; there is **no** typed equivalent per §2)*
41. `EXE` (trigger — the strcpy tiles the stack, the ROP chain walks)

Then the emulator's watch phase (not a physical step): `SetClockSpeed(16)`,
breakpoint-instrumented runs measure `CHAIN: KEYSCAN #1..#25`,
`pc=0x4D20`, `sp=0x8DA0→0x8E00` (+4/hop), `tiles=1499` (the S15-verification
re-produced these exactly).

## 4. Screen-state expectations per phase

| After | Screen |
|---|---|
| boot + warm-up | idle input line |
| `SHIFT MODE` | SETUP menu opens on LCD row 2 (first press may be eaten; retry) |
| `2` | unchanged (digit-select inert on CY-845) |
| setup chords + `AC` | blank input line |
| formula typed (15–24) | `X=Σ(X,1,1×10⁹` visible |
| the dance (25–35) | `=`-processing, cursor decoupled; `X=Σ(X,1,1×10⁹` visible |
| probe `1` (36) | **nothing happens** = basic-overflow state confirmed |
| final `AC` `←` `EXE` + payload (37–41) | evaluator wakes; tiles flood; KEYSCAN chain executes; final `pc` parks in the `0x8F4A-8F54` wait-key tree (harmless) or degrades into post-exhaustion chaos (`pc=0x3276/0x8E00…, sp=0x0000/0xFFF0` = the machine may **look hung**; `ON` resets; **no permanent damage** — all broken states recover on power cycle) |

## 5. Key-press count

45 physical keypresses (36 in the "type/setup" class + 4 final-phase + 2
warm-up `AC`s + 3 retry/verify Σ-chords per the e2e doubling). 0 payload
bytes typed; 100 payload bytes = `data[]`-injected.

## 6. Full measured token atlas (emulator-verified, this work)

Bytes below are what each key *inserted at 0x8154* (base = no modifier; S =
SHIFT+key; A = ALPHA+key; "—" = nothing inserted):

| Key (scan) | base | SHIFT | ALPHA |
|---|---|---|---|
| `1` 0x00 | `31` | — | — |
| `2` 0x10 | `32` | — | — |
| `3` 0x20 | `33` | — | — |
| `+` 0x30 | `2B` | `6C` (Pol() | — |
| `-` 0x40 | `2D` | `6D` (Rec() | — |
| `EXE` 0x60 | — (control) | — | — |
| `4` 0x01 | `34` | — | — |
| `5` 0x11 | `35` | — | — |
| `6` 0x21 | `36` | — | — |
| `×` 0x31 | `4E` | `BE` | — |
| `÷` 0x41 | `4F` | `BF` | — |
| `Ans` 0x61 | `8B` | — | — |
| `7` 0x02 | `37` | — | — |
| `8` 0x12 | `38` | — | — |
| `9` 0x22 | `39` | — | — |
| `DEL` 0x32 | — (control) | — | — |
| `AC` 0x42 | — (control) | — | — |
| `×10ˣ` 0x62 | `74` | `82` (π) | `81` (e) |
| `∫dx`/fn1 0x06/0x16 | — | `6B B8` (d/dx() | `3A` (`:`) |
| `√^`-fn 0x46 | `21 5E B8 60 31 B9` | `57` (x!) | — |
| `log₂(`/Σ 0x56 | `68 B8 21 BA 21 B9` | `69 B8 21 BA 21 BA 21 B9` (Σ() | — |
| `(` 0x23 | `28` | `25` (`%`) | — |
| `)` 0x33 | `29` | `2C` (`,`) | `58` (X) |
| `.` 0x63 | `2E` | `8C` (Ran#) | `C2` |
| `X`-sib 0x43 | — | — | `59` (Y) |
| `A`-var 0x04 | — | — | `41` (A; retries needed — single-shot enum missed it, lands 3/3 with retry) |
| `M` 0x53 | — | — | `54` (M) |
| `CALC` 0x06 | — (control) | — | `3D` (`=`) |
| nav 0x26/0x27/0x36/0x37 | — | — | — |
| `SHIFT`/`ALPHA`/`MODE` | — (control) | — | — |

2-byte tokens: `69 B8` (Σ(), `6B B8` (d/dx(), `68 B8...` (log-template) —
none contains `0E` or `4D`, nor any pair-concatenation that produces them.

## 7. The typed-only payload experiment (measured, negative)

Three configurations measured, exact stdout in the logs
(`/tmp/typed85.log`, `/tmp/ip3typed.log`, `/tmp/h7b.log`):

| Config | Clock | Ordering | Result (exact stdout) |
|---|---|---|---|
| `rop_typed85.lua` (e2e head, typed `85`×50 after PROBE1, `AC ← EXE`) | 1× | post-dance | `INPUT: done len=54 buf=32 31 38 35 38 35 38 35 38 35 38 38 38 …`; `HIT-3538` ×1714 all the app's own (`lr=3322`); `h4d20=0` |
| `rop_typed85.lua` (same head, 90 digits before the dance) | 1× | pre-dance | `INPUT: done len=9 buf=32 69B8 21BA 21BA 21B9 …` — exponent pocket absorbs everything (0 fillers landed); `PROTO: END pc=3562 sp=8D51 tiles=-1` |
| `rop_typed_ip3.lua` (input_path3 verbatim + typed `85`×50) | 8× | input_path3 | `len@F91=7 … maxlen=9`; `PROTO: END pc=4B96 sp=8D22 h3538=796 h4d20=0 maxlen=9` — fillers do NOT land at 8× |

**Measured typed byte ceiling = 54 tokens total** (the ~44-digit absorb above
the 10-token formula at 1×; the ceiling ties to post-`PROBE1` typing). The
exploit needs `strlen(0x8154) ≥ 100`. **No tested ordering/config reaches it
typed.** Per-byte: the only fully-typable adjacent ROP-relevant word is
`38 35` (= digits `8`,`5` = the `0x3538` gadget word after the 4-byte POP-PC
consume pattern); `0x54` (M) and `0x81` (e) also typable individually.

**DEFINITIVE LIMIT (all triggers tested):** no trigger copies ≤54 typed
bytes into the stack. The 100-byte strcpy is the only observed stack-tiling
copy on CY-845, and it requires `strlen(0x8154) ≥ 100` — unreachable typed
(§7, §7d). The `A`/`M`/digits `8`/`5` bytes are typable, but every shorter
trigger (A^0-class eval, 1÷3(4) auto-paren, Pol(/Integral-templates) ran
**without any stack-tile copy** (`tiles(38 35)=0`, `h4d20=0` — diffs are
eval state-keeping). A physical typed-ROP exploit on CY-845 requires either
a previously-unknown shorter-copy trigger or a previously-unknown ≥100-byte
typed-entry state (e.g. a working LineIO box-fill / unstable-char advance);
none exists in this repository, in the emulator, or in any public artifact
searched (§2, §2b).

## 7d. Shorter-overflow triggers with typable payload — all negative

`rop_trig3.lua` (1× clock; per-test RAM diff-scan 0x8100..0x8E7F, 38-35 tile
count past 0x8240, @0x3538/@0x4D20 classes). Exact stdout `/tmp/trig3.log`:

| Test | Typed keys | Result (exact) |
|---|---|---|
| 1. `A^0`-class (tieba A^0法; tieba p/2767270777 is 403-blocked, reconstructed) | `ALPHA`+`√`-row-key (0x04) ×3, the `^`-template key (0x46) ×2, `1` (bug: 0x00=1, not 0), `EXE`, `AC`, `←`, 28×(`8`/`5`), `AC ← EXE` | `A` lands 3/3 (`buf=41 41 41…`) — **`A` var is typable** (`ALPHA`+0x04→`41`; the one-shot enum §6 missed it via drop). Template 0x46 inside the run = `5E B8 60 31 B9` fragment-shifts. `TRIG[A0-EXE]: diff=426 tiles(38 35)=0 blen=9 pc=3484 sp=8D4D h3538=144 h4d20=0`; post-trigger `regions 8C38-8D1F/8D28-8DE1` = eval state-keeping only |
| 2. `1÷3(4)` auto-paren (the tiplanet no-Σ method) | `1` `÷` `3` `(` `4` `)` `EXE LEFT` + 28×(`8`/`5`) + `AC ← EXE` | **did not even type** — `TRIG[T2-EXE]: diff=5 tiles=0 blen=9 pc=4B96` (idle; the old test-1 buffer intact). `TRIG[T2-EXE2]: diff=225 tiles=0 blen=9 pc=3484 sp=8D4D h4d20=0` — the EXE2 evaluated with whatever was in the buffer; the stack diffs again = `=`-processing state-keeping, no 0x8220+ tiles |
| 3. `Pol(`-template | `SHIFT`+`+` (6C Pol() + 24×(`8`/`5`) + `AC ← EXE` | `TRIG[T3-EXE]: diff=220 tiles=0 blen=9 pc=3484 sp=8D4D h3538=884 h4d20=0` — same eval-state pattern, no tiling |

**Critical sub-finding — the `3538`-word is context-bound**: inside
template-box states (x^box / ×10ⁿ exponent pocket), the `8` presses insert as
box-fragment fills (`…60 31 38 38 38 38 B9 31`) with the `5` press rejected —
the clean adjacent `38 35` pairs form **only in the plain-formula state**
(§7's positive landing). Since every candidate shorter trigger ends inside a
template-box, the typed `0x3538` sled cannot be combined with any of them.

**Chain classes**: `h4d20 = 0` in every test; all `@0x3538` hits carry the
app's own signature (`lr=3322`, sp=8D33-8D5F). **No trigger ties the ≤54-byte
typed input to any stack-tile copy.**

## 9. Emulator keyboard-fidelity — root cause found, patched, and verified

**Diagnosis chain** (instrumented `0x8E00-0x8E02` handshake + per-tick PC
histograms, `kyb_menu_diag.lua`; then a bank-0/bank-1 disassembly rebuild from
`oki-u8-disas.cpp` — heads-up: the shipped `oki-u8-disas.cpp` needs
`#include <cstdint>` and `-std=c++17`):

```
READY-WRITE 01 (in=80 out=10)          <- once, at boot, carrying the SHIFT report
READY-READS 20000/40000/60000          <- ~60k boot-phase polls, then SILENCE forever
PCMAP menu-idle  { 75C0:6600, 75C2:4400, 35C4:512, ... }   (refresh/render loop)
PCMAP during-2   { 4B96:59579 + 4B70-4B9A/98xx/7Cxx ~0.6% }  (EXI0 wake, re-park)
PCMAP after-2    { 4B96:80000 }   INPUTBUF len=0   (digit-2 inert)
```

- `0x4B96` disassembled = `NOP; NOP; RT` **with `LR=0x4B96`: a
  3-instruction self-loop, not a key decoder** (corrects the earlier
  "wait-key(103)" reading; `0x4B70-0x4C00` = I/O config + delay helpers,
  no `0x8E00` access).
- **The real post-boot input path = bank-1 direct-matrix polling**, found at
  file-offset `0x16658+`: `PUSH LR / MOV R1,#3 / LEA 0xF040h / L R0,[EA] /
  BC EQ / AND R0,#24 (blocks KI3/KI4) / BC NE / ADD R1,#-1 / BC NE(loop)`,
  i.e. `0xF040` polled ~4× per key with debounce, vectoring through the
  `0x98xx` key map.

**The patch (emulator `src/Peripheral/Keyboard.cpp`, `PressButton`)** — in
Casio-emu mode (`real_hardware=0`) a Lua/UI keypress only fed the boot-window
handshake (`keyboard_in_emu/out_emu` + EXI0), leaving the KID matrix dead.
Now `PressButton` also drives the matrix:

```cpp
// (emu-mode branch, after the existing report handling)
if (button.pressed) { keyboard_out = button.ko_bit; keyboard_out &= 0x3FF; }
else                { keyboard_out = 0; }
RecalculateKI();
```

(`RecalculateKI` already composes active-low `keyboard_in` from
`keyboard_out` + the pressed button's `ki_bit` and is what the ROM's
`0xF040` reads consume.) Three rebuild cycles + 5 verification runs
(`kyb_menu_diag`, `kyb_fidelity`, `/tmp/menudiag*.log`, `FID`-lines below).

**Verified results on the patched build (exact stdout, `kyb_fidelity8.lua`):**

```
READY-WRITE 01/00 pairs restart            <- handshake re-arms constantly; per-key
FID[setup-done] len=1 in=32…               <- SETUP digit-2 now INSERTS ('2' = 32)
    (unpatched: setup menu + '2' = INPUTBUF len=0 in all runs)
FID[sigma-1]   len=9  in=32 69B8 21BA 21BA 21B9
FID[after-dance] len=21 …  ext=3269B8583D69B829292C74BA21BA21B9BA21BA21B9…  (cache copy!)
FID[probe1]    len=21 (21→21: the decoupled no-insert state visible)
FID[sym5]      len=21→22 …B9 35           <- post-dance typing LANDS ('5' = 0x35)
FID[final]     len=22 …BA21 BA21 B9 35 00
```

**What is fixed:** post-boot key delivery, SETUP digit-select, and
post-dance typing at the decoupled cursor.
**Remains unfaithful:** (1) LineIO still not engaged — Σ( stays in the boxed
8-byte form (`69 B8 21 BA 21 BA 21 B9`) across every patched-build attempt;
the digit-2 lands but the SETUP page-1 selection does not flip the input
mode — likely a second SETUP-menu quirk on CY-845 (per Session 11/12 the
menu digit-select was flatly inert pre-patch; the operator's hardware
behaviour should arbitrate what the LCD page ordering is); (2) the hack-#7
flash-advance: with `▶`/`◀` walks bracketed by 2.5M-tick (≈4 s at 8×)
settle-waits, the entered `35` byte never advances (`goR1/R2/L1/R3`
samples byte-identical) — the flash rewrite path is still not exercised by
this keyboard bridge, or CY-845's flash cadence is genuinely different.
**[HW-unknown]** which of those two it is; the hardware test (Sheet A of
`docs/hardware-procedure.md`) arbitrates.

## 8. Sources / discrepancies vs the original brief

- All 45 keys verified against `rop_e2e.lua`'s `push`/`chord` list (§3).
- Discrepancies vs the previous version of this doc: none in the key list;
  the fillers ("91×'1'") do not exist in `rop_e2e.lua` (owned by the older
  `rop_proto`/`input_path` scripts); the payload is injected, never typed
  (§2 — now proven impossible to type).
- The v4 draw words land in the firmware's DSR-banked LCD window (Session 19),
  not the Lua-visible `0xF800` — the row-0 draw remains unresolved without a
  DSR gadget regardless of payload delivery.
- **`0E 4D` typed = DEFINITIVE NO** (three independent sources agree: the ROM
  keycode tables, the wiki symbol table, and the live 130-sample enumeration).
- **Physics test**: never run (emulator-only). The typed chain has never
  executed in any run in this repository.
