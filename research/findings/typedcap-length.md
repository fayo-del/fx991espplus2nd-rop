# typedcap-length — max input-line length at 0x8154 reachable by pure key presses

Date: 2026-11-22. Agent: TypedCap. Question: with **simulated key presses only**
(`Keyboard:PressKey`, no memory writes, no ROM edits) on the fx-991ES PLUS 2nd model
(CY-845, MathIO/COMP editor, buffer at RAM 0x8154), what is the maximum
strlen(0x8154), and which single key presses insert multi-byte text templates?

## Verdict

**Max input-line length reachable by pure typing = 99 bytes** (strlen(0x8154) = 99,
NUL always at 0x81B7; nothing is ever written past it). No key sequence — singles,
multi-byte templates, template-then-singles, DEL/INS/mid-line tricks — reaches
strlen ≥ 100. Measured global max over all runs: `maxslen=99`
(`/tmp/typedcap_length5.log` DONE line, `maxseq=X t1N88`).

The editor rule (measured): **an insert — single-byte token or multi-byte template —
is accepted iff strlen + insertlen ≤ 99; otherwise it is rejected entirely** (no
truncation of the template, no partial insert, no overflow past the NUL). This is the
static cap at ROM bank0 0x655A (`CMP R1,#99; BC GE bail`) applying to the token-insert
family as well; the 0x7402 `CMP R0,#250` backstop is never approached.

Achieving sequences (all measured, strlen = 99):
- 99 single-byte keys (e.g. digit keys 0x00/0x10/0x20/… → tokens 0x31–0x39):
  phase 3a `T r100`/`T r101` all d=+0 at pre=99 — stall at exactly 99.
- 91 singles + one 9-byte base template (key 0x0D or 0x05): `X t1N91r2` pre=91 →
  post=**99** (insert +8).
- 13-byte template first (SHIFT+0x05 → 13 bytes on the empty line), then singles:
  phase 3b fills from 13 up to 99 and stalls (`T a` tail all d=+0 at pre=99).

## Method

Script: `research/CasioEmuX/typedcap_length.lua` (5 emulator runs total, ≤6 budget;
headless `SDL_VIDEODRIVER=dummy ./emulator/emulator model=models/fx991esplus2 script=typedcap_length.lua`,
16× clock, logs `/tmp/typedcap_length{,2,4,5}.log`, dump `/tmp/typedcap_dump.bin`).
Phase 1 sweeps every keycode 0x00–0x67 × {base, SHIFT+, ALPHA+, ALPHA+SHIFT+} into an
empty line (AC-reset before each probe) and dumps 0x8154 before/after. Phases 2–3 fill
the line to an exact strlen N with rotating digit keys (`fillto` steps re-press until
strlen==N, because the ROM key scan consumes ≈1 key per scan round and drops ≈half of
back-to-back presses; template chords have delivery retries). Run with
`TC_SKIP_PHASE1=1` skips the sweep (its table was identical across runs 1/2/4).

## 1. Key → inserted-bytes table (all keycodes 0x00–0x67 × 4 modifier modes)

Inserted bytes are buffer **tokens**, not ASCII. `pre` was 0 for every probe (empty
line); `count` = strlen delta. Multi-byte templates are the auto-pair/box inserts;
on a non-empty line the effective insert is template_len − 1 (head at cursor, tail
appended at line end — e.g. 13-byte template inserts +12).

#### mode `basekey` — 104 codes probed

| code | inserted bytes (hex) | count |
|---|---|---|
| b00 (0x00) | 31 | +1 |
| b01 (0x01) | 34 | +1 |
| b02 (0x02) | 37 | +1 |
| b03 (0x03) | — | +0 |
| b04 (0x04) | 60 | +1 |
| b05 (0x05) | AEBBB821B9B821B9BC | +9 |
| b06 (0x06) | — | +0 |
| b07 (0x07) | — | +0 |
| b08 (0x08) | 31 | +1 |
| b09 (0x09) | 34 | +1 |
| b0A (0x0A) | 37 | +1 |
| b0B (0x0B) | — | +0 |
| b0C (0x0C) | 60 | +1 |
| b0D (0x0D) | AEBBB821B9B821B9BC | +9 |
| b0E (0x0E) | — | +0 |
| b0F (0x0F) | — | +0 |
| b10 (0x10) | 32 | +1 |
| b11 (0x11) | 35 | +1 |
| b12 (0x12) | 38 | +1 |
| b13 (0x13) | — | +0 |
| b14 (0x14) | 5C | +1 |
| b15 (0x15) | 98B821B9 | +4 |
| b16 (0x16) | 6AB821BA21BA21B9 | +8 |
| b17 (0x17) | — | +0 |
| b18 (0x18) | 32 | +1 |
| b19 (0x19) | 35 | +1 |
| b1A (0x1A) | 38 | +1 |
| b1B (0x1B) | — | +0 |
| b1C (0x1C) | 5C | +1 |
| b1D (0x1D) | 98B821B9 | +4 |
| b1E (0x1E) | 6AB821BA21BA21B9 | +8 |
| b1F (0x1F) | — | +0 |
| b20 (0x20) | 33 | +1 |
| b21 (0x21) | 36 | +1 |
| b22 (0x22) | 39 | +1 |
| b23 (0x23) | 28 | +1 |
| b24 (0x24) | — | +0 |
| b25 (0x25) | 215EB832B9 | +5 |
| b26 (0x26) | — | +0 |
| b27 (0x27) | — | +0 |
| b28 (0x28) | 33 | +1 |
| b29 (0x29) | 36 | +1 |
| b2A (0x2A) | 39 | +1 |
| b2B (0x2B) | 28 | +1 |
| b2C (0x2C) | — | +0 |
| b2D (0x2D) | 215EB832B9 | +5 |
| b2E (0x2E) | — | +0 |
| b2F (0x2F) | — | +0 |
| b30 (0x30) | 2B | +1 |
| b31 (0x31) | 4E | +1 |
| b32 (0x32) | — | +0 |
| b33 (0x33) | 29 | +1 |
| b34 (0x34) | A0 | +1 |
| b35 (0x35) | 215EB821B9 | +5 |
| b36 (0x36) | — | +0 |
| b37 (0x37) | — | +0 |
| b38 (0x38) | 2B | +1 |
| b39 (0x39) | 4E | +1 |
| b3A (0x3A) | — | +0 |
| b3B (0x3B) | 29 | +1 |
| b3C (0x3C) | A0 | +1 |
| b3D (0x3D) | 215EB821B9 | +5 |
| b3E (0x3E) | — | +0 |
| b3F (0x3F) | — | +0 |
| b40 (0x40) | 2D | +1 |
| b41 (0x41) | 4F | +1 |
| b42 (0x42) | — | +0 |
| b43 (0x43) | — | +0 |
| b44 (0x44) | A1 | +1 |
| b45 (0x45) | 68 | +1 |
| b46 (0x46) | 215EB86031B9 | +6 |
| b47 (0x47) | — | +0 |
| b48 (0x48) | 2D | +1 |
| b49 (0x49) | 4F | +1 |
| b4A (0x4A) | — | +0 |
| b4B (0x4B) | — | +0 |
| b4C (0x4C) | A1 | +1 |
| b4D (0x4D) | 68 | +1 |
| b4E (0x4E) | 215EB86031B9 | +6 |
| b4F (0x4F) | — | +0 |
| b50 (0x50) | — | +0 |
| b51 (0x51) | — | +0 |
| b52 (0x52) | — | +0 |
| b53 (0x53) | — | +0 |
| b54 (0x54) | A2 | +1 |
| b55 (0x55) | A3 | +1 |
| b56 (0x56) | 68B821BA21B9 | +6 |
| b57 (0x57) | — | +0 |
| b58 (0x58) | — | +0 |
| b59 (0x59) | — | +0 |
| b5A (0x5A) | — | +0 |
| b5B (0x5B) | — | +0 |
| b5C (0x5C) | A2 | +1 |
| b5D (0x5D) | A3 | +1 |
| b5E (0x5E) | 68B821BA21B9 | +6 |
| b5F (0x5F) | — | +0 |
| b60 (0x60) | — | +0 |
| b61 (0x61) | 8B | +1 |
| b62 (0x62) | 74 | +1 |
| b63 (0x63) | 2E | +1 |
| b64 (0x64) | 30 | +1 |
| b65 (0x65) | — | +0 |
| b66 (0x66) | — | +0 |
| b67 (0x67) | — | +0 |

#### mode `SHIFT+key` — 104 codes probed

| code | inserted bytes (hex) | count |
|---|---|---|
| s00 (0x00) | — | +0 |
| s01 (0x01) | — | +0 |
| s02 (0x02) | — | +0 |
| s03 (0x03) | — | +0 |
| s04 (0x04) | 60 | +1 |
| s05 (0x05) | 7CBDBBB821B9B821B9B821B9BC | +13 |
| s06 (0x06) | — | +0 |
| s07 (0x07) | — | +0 |
| s08 (0x08) | — | +0 |
| s09 (0x09) | — | +0 |
| s0A (0x0A) | — | +0 |
| s0B (0x0B) | — | +0 |
| s0C (0x0C) | 60 | +1 |
| s0D (0x0D) | 7CBDBBB821B9B821B9B821B9BC | +13 |
| s0E (0x0E) | — | +0 |
| s0F (0x0F) | — | +0 |
| s10 (0x10) | — | +0 |
| s11 (0x11) | — | +0 |
| s12 (0x12) | — | +0 |
| s13 (0x13) | — | +0 |
| s14 (0x14) | — | +0 |
| s15 (0x15) | 9FBBB833B9B821B9BC | +9 |
| s16 (0x16) | 6BB821BA21B9 | +6 |
| s17 (0x17) | — | +0 |
| s18 (0x18) | — | +0 |
| s19 (0x19) | — | +0 |
| s1A (0x1A) | — | +0 |
| s1B (0x1B) | — | +0 |
| s1C (0x1C) | — | +0 |
| s1D (0x1D) | 9FBBB833B9B821B9BC | +9 |
| s1E (0x1E) | 6BB821BA21B9 | +6 |
| s1F (0x1F) | — | +0 |
| s20 (0x20) | — | +0 |
| s21 (0x21) | — | +0 |
| s22 (0x22) | — | +0 |
| s23 (0x23) | 25 | +1 |
| s24 (0x24) | 63B821B9 | +4 |
| s25 (0x25) | 215EB833B9 | +5 |
| s26 (0x26) | — | +0 |
| s27 (0x27) | — | +0 |
| s28 (0x28) | — | +0 |
| s29 (0x29) | — | +0 |
| s2A (0x2A) | — | +0 |
| s2B (0x2B) | 25 | +1 |
| s2C (0x2C) | 63B821B9 | +4 |
| s2D (0x2D) | 215EB833B9 | +5 |
| s2E (0x2E) | — | +0 |
| s2F (0x2F) | — | +0 |
| s30 (0x30) | 6C | +1 |
| s31 (0x31) | BE | +1 |
| s32 (0x32) | — | +0 |
| s33 (0x33) | 2C | +1 |
| s34 (0x34) | B0 | +1 |
| s35 (0x35) | 9FBBB821B9B821B9BC | +9 |
| s36 (0x36) | — | +0 |
| s37 (0x37) | — | +0 |
| s38 (0x38) | 6C | +1 |
| s39 (0x39) | BE | +1 |
| s3A (0x3A) | — | +0 |
| s3B (0x3B) | 2C | +1 |
| s3C (0x3C) | B0 | +1 |
| s3D (0x3D) | 9FBBB821B9B821B9BC | +9 |
| s3E (0x3E) | — | +0 |
| s3F (0x3F) | — | +0 |
| s40 (0x40) | 6D | +1 |
| s41 (0x41) | BF | +1 |
| s42 (0x42) | — | +0 |
| s43 (0x43) | — | +0 |
| s44 (0x44) | B1 | +1 |
| s45 (0x45) | 93B821B9 | +4 |
| s46 (0x46) | 57 | +1 |
| s47 (0x47) | — | +0 |
| s48 (0x48) | 6D | +1 |
| s49 (0x49) | BF | +1 |
| s4A (0x4A) | — | +0 |
| s4B (0x4B) | — | +0 |
| s4C (0x4C) | B1 | +1 |
| s4D (0x4D) | 93B821B9 | +4 |
| s4E (0x4E) | 57 | +1 |
| s4F (0x4F) | — | +0 |
| s50 (0x50) | — | +0 |
| s51 (0x51) | — | +0 |
| s52 (0x52) | — | +0 |
| s53 (0x53) | — | +0 |
| s54 (0x54) | B2 | +1 |
| s55 (0x55) | 73B821B9 | +4 |
| s56 (0x56) | 69B821BA21BA21B9 | +8 |
| s57 (0x57) | — | +0 |
| s58 (0x58) | — | +0 |
| s59 (0x59) | — | +0 |
| s5A (0x5A) | — | +0 |
| s5B (0x5B) | — | +0 |
| s5C (0x5C) | B2 | +1 |
| s5D (0x5D) | 73B821B9 | +4 |
| s5E (0x5E) | 69B821BA21BA21B9 | +8 |
| s5F (0x5F) | — | +0 |
| s60 (0x60) | — | +0 |
| s61 (0x61) | — | +0 |
| s62 (0x62) | 82 | +1 |
| s63 (0x63) | 8C | +1 |
| s64 (0x64) | B3 | +1 |
| s65 (0x65) | — | +0 |
| s66 (0x66) | — | +0 |
| s67 (0x67) | — | +0 |

#### mode `ALPHA+key` — 104 codes probed

| code | inserted bytes (hex) | count |
|---|---|---|
| a00 (0x00) | — | +0 |
| a01 (0x01) | — | +0 |
| a02 (0x02) | — | +0 |
| a03 (0x03) | — | +0 |
| a04 (0x04) | 41 | +1 |
| a05 (0x05) | — | +0 |
| a06 (0x06) | 3D | +1 |
| a07 (0x07) | — | +0 |
| a08 (0x08) | — | +0 |
| a09 (0x09) | — | +0 |
| a0A (0x0A) | — | +0 |
| a0B (0x0B) | — | +0 |
| a0C (0x0C) | 41 | +1 |
| a0D (0x0D) | — | +0 |
| a0E (0x0E) | 3D | +1 |
| a0F (0x0F) | — | +0 |
| a10 (0x10) | — | +0 |
| a11 (0x11) | — | +0 |
| a12 (0x12) | — | +0 |
| a13 (0x13) | — | +0 |
| a14 (0x14) | 42 | +1 |
| a15 (0x15) | — | +0 |
| a16 (0x16) | 3A | +1 |
| a17 (0x17) | — | +0 |
| a18 (0x18) | — | +0 |
| a19 (0x19) | — | +0 |
| a1A (0x1A) | — | +0 |
| a1B (0x1B) | — | +0 |
| a1C (0x1C) | 42 | +1 |
| a1D (0x1D) | — | +0 |
| a1E (0x1E) | 3A | +1 |
| a1F (0x1F) | — | +0 |
| a20 (0x20) | — | +0 |
| a21 (0x21) | — | +0 |
| a22 (0x22) | — | +0 |
| a23 (0x23) | — | +0 |
| a24 (0x24) | 43 | +1 |
| a25 (0x25) | — | +0 |
| a26 (0x26) | — | +0 |
| a27 (0x27) | — | +0 |
| a28 (0x28) | — | +0 |
| a29 (0x29) | — | +0 |
| a2A (0x2A) | — | +0 |
| a2B (0x2B) | — | +0 |
| a2C (0x2C) | 43 | +1 |
| a2D (0x2D) | — | +0 |
| a2E (0x2E) | — | +0 |
| a2F (0x2F) | — | +0 |
| a30 (0x30) | — | +0 |
| a31 (0x31) | — | +0 |
| a32 (0x32) | — | +0 |
| a33 (0x33) | 58 | +1 |
| a34 (0x34) | 44 | +1 |
| a35 (0x35) | — | +0 |
| a36 (0x36) | — | +0 |
| a37 (0x37) | — | +0 |
| a38 (0x38) | — | +0 |
| a39 (0x39) | — | +0 |
| a3A (0x3A) | — | +0 |
| a3B (0x3B) | 58 | +1 |
| a3C (0x3C) | 44 | +1 |
| a3D (0x3D) | — | +0 |
| a3E (0x3E) | — | +0 |
| a3F (0x3F) | — | +0 |
| a40 (0x40) | — | +0 |
| a41 (0x41) | — | +0 |
| a42 (0x42) | — | +0 |
| a43 (0x43) | 59 | +1 |
| a44 (0x44) | 45 | +1 |
| a45 (0x45) | — | +0 |
| a46 (0x46) | — | +0 |
| a47 (0x47) | — | +0 |
| a48 (0x48) | — | +0 |
| a49 (0x49) | — | +0 |
| a4A (0x4A) | — | +0 |
| a4B (0x4B) | 59 | +1 |
| a4C (0x4C) | 45 | +1 |
| a4D (0x4D) | — | +0 |
| a4E (0x4E) | — | +0 |
| a4F (0x4F) | — | +0 |
| a50 (0x50) | — | +0 |
| a51 (0x51) | — | +0 |
| a52 (0x52) | — | +0 |
| a53 (0x53) | 54 | +1 |
| a54 (0x54) | 46 | +1 |
| a55 (0x55) | — | +0 |
| a56 (0x56) | — | +0 |
| a57 (0x57) | — | +0 |
| a58 (0x58) | — | +0 |
| a59 (0x59) | — | +0 |
| a5A (0x5A) | — | +0 |
| a5B (0x5B) | 54 | +1 |
| a5C (0x5C) | 46 | +1 |
| a5D (0x5D) | — | +0 |
| a5E (0x5E) | — | +0 |
| a5F (0x5F) | — | +0 |
| a60 (0x60) | — | +0 |
| a61 (0x61) | — | +0 |
| a62 (0x62) | 81 | +1 |
| a63 (0x63) | C2 | +1 |
| a64 (0x64) | — | +0 |
| a65 (0x65) | — | +0 |
| a66 (0x66) | — | +0 |
| a67 (0x67) | — | +0 |

#### mode `ALPHA+SHIFT+key` — 104 codes probed

| code | inserted bytes (hex) | count |
|---|---|---|
| q00 (0x00) | — | +0 |
| q01 (0x01) | — | +0 |
| q02 (0x02) | — | +0 |
| q03 (0x03) | — | +0 |
| q04 (0x04) | 60 | +1 |
| q05 (0x05) | 7CBDBBB821B9B821B9B821B9BC | +13 |
| q06 (0x06) | — | +0 |
| q07 (0x07) | — | +0 |
| q08 (0x08) | — | +0 |
| q09 (0x09) | — | +0 |
| q0A (0x0A) | — | +0 |
| q0B (0x0B) | — | +0 |
| q0C (0x0C) | 60 | +1 |
| q0D (0x0D) | 7CBDBBB821B9B821B9B821B9BC | +13 |
| q0E (0x0E) | — | +0 |
| q0F (0x0F) | — | +0 |
| q10 (0x10) | — | +0 |
| q11 (0x11) | — | +0 |
| q12 (0x12) | — | +0 |
| q13 (0x13) | — | +0 |
| q14 (0x14) | — | +0 |
| q15 (0x15) | 9FBBB833B9B821B9BC | +9 |
| q16 (0x16) | 6BB821BA21B9 | +6 |
| q17 (0x17) | — | +0 |
| q18 (0x18) | — | +0 |
| q19 (0x19) | — | +0 |
| q1A (0x1A) | — | +0 |
| q1B (0x1B) | — | +0 |
| q1C (0x1C) | — | +0 |
| q1D (0x1D) | 9FBBB833B9B821B9BC | +9 |
| q1E (0x1E) | 6BB821BA21B9 | +6 |
| q1F (0x1F) | — | +0 |
| q20 (0x20) | — | +0 |
| q21 (0x21) | — | +0 |
| q22 (0x22) | — | +0 |
| q23 (0x23) | 25 | +1 |
| q24 (0x24) | 63B821B9 | +4 |
| q25 (0x25) | 215EB833B9 | +5 |
| q26 (0x26) | — | +0 |
| q27 (0x27) | — | +0 |
| q28 (0x28) | — | +0 |
| q29 (0x29) | — | +0 |
| q2A (0x2A) | — | +0 |
| q2B (0x2B) | 25 | +1 |
| q2C (0x2C) | 63B821B9 | +4 |
| q2D (0x2D) | 215EB833B9 | +5 |
| q2E (0x2E) | — | +0 |
| q2F (0x2F) | — | +0 |
| q30 (0x30) | 6C | +1 |
| q31 (0x31) | BE | +1 |
| q32 (0x32) | — | +0 |
| q33 (0x33) | 2C | +1 |
| q34 (0x34) | B0 | +1 |
| q35 (0x35) | 9FBBB821B9B821B9BC | +9 |
| q36 (0x36) | — | +0 |
| q37 (0x37) | — | +0 |
| q38 (0x38) | 6C | +1 |
| q39 (0x39) | BE | +1 |
| q3A (0x3A) | — | +0 |
| q3B (0x3B) | 2C | +1 |
| q3C (0x3C) | B0 | +1 |
| q3D (0x3D) | 9FBBB821B9B821B9BC | +9 |
| q3E (0x3E) | — | +0 |
| q3F (0x3F) | — | +0 |
| q40 (0x40) | 6D | +1 |
| q41 (0x41) | BF | +1 |
| q42 (0x42) | — | +0 |
| q43 (0x43) | — | +0 |
| q44 (0x44) | B1 | +1 |
| q45 (0x45) | 93B821B9 | +4 |
| q46 (0x46) | 57 | +1 |
| q47 (0x47) | — | +0 |
| q48 (0x48) | 6D | +1 |
| q49 (0x49) | BF | +1 |
| q4A (0x4A) | — | +0 |
| q4B (0x4B) | — | +0 |
| q4C (0x4C) | B1 | +1 |
| q4D (0x4D) | 93B821B9 | +4 |
| q4E (0x4E) | 57 | +1 |
| q4F (0x4F) | — | +0 |
| q50 (0x50) | — | +0 |
| q51 (0x51) | — | +0 |
| q52 (0x52) | — | +0 |
| q53 (0x53) | — | +0 |
| q54 (0x54) | B2 | +1 |
| q55 (0x55) | 73B821B9 | +4 |
| q56 (0x56) | 69B821BA21BA21B9 | +8 |
| q57 (0x57) | — | +0 |
| q58 (0x58) | — | +0 |
| q59 (0x59) | — | +0 |
| q5A (0x5A) | — | +0 |
| q5B (0x5B) | — | +0 |
| q5C (0x5C) | B2 | +1 |
| q5D (0x5D) | 73B821B9 | +4 |
| q5E (0x5E) | 69B821BA21BA21B9 | +8 |
| q5F (0x5F) | — | +0 |
| q60 (0x60) | — | +0 |
| q61 (0x61) | — | +0 |
| q62 (0x62) | 82 | +1 |
| q63 (0x63) | 8C | +1 |
| q64 (0x64) | B3 | +1 |
| q65 (0x65) | — | +0 |
| q66 (0x66) | — | +0 |
| q67 (0x67) | — | +0 |

**Multi-byte template keys (count ≥ 2):**

| mode+code | template bytes | count on empty line | effective insert on non-empty line |
|---|---|---|---|
| b05 / b0D | AE BB B8 21 B9 B8 21 B9 BC | 9 | +8 |
| b15 / b1D | 98 B8 21 B9 | 4 | +3 |
| b16 / b1E | 6A B8 21 BA 21 BA 21 B9 | 8 | +7 |
| b25 / b2D | 21 5E B8 32 B9 | 5 | +4 |
| b35 / b3D | 21 5E B8 21 B9 | 5 | +4 |
| b46 / b4E | 21 5E B8 60 31 B9 | 6 | +5 |
| b56 / b5E | 68 B8 21 BA 21 B9 | 6 | +5 |
| s05 / s0D / q05 / q0D | 7C BD BB B8 21 B9 B8 21 B9 B8 21 B9 BC | 13 | +12 |
| s15 / s1D / q15 / q1D | 9F BB B8 33 B9 B8 21 B9 BC | 9 | +8 |
| s16 / s1E / q16 / q1E | 6B B8 21 BA 21 B9 | 6 | +5 |
| s24 / s2C / q24 / q2C | 63 B8 21 B9 | 4 | +3 |
| s25 / s2D / q25 / q2D | 21 5E B8 33 B9 | 5 | +4 |
| s35 / s3D / q35 / q3D | 9F BB B8 21 B9 B8 21 B9 BC | 9 | +8 |
| s45 / s4D / q45 / q4D | 93 B8 21 B9 | 4 | +3 |
| s55 / s5D / q55 / q5D | 73 B8 21 B9 | 4 | +3 |
| s56 / s5E / q56 / q5E | 69 B8 21 BA 21 BA 21 B9 | 8 | +7 |

Notes: ALPHA+SHIFT (q) measured **identical** to SHIFT (s) for every code in the
emulator (the ALPHA latch is consumed by the SHIFT press / not separately mapped).
ALPHA+key inserts letters (a04→41 ‘A’ … a63→C2, a62→81). All other codes insert
0 or 1 byte (full per-code tables above).

## 2. Cap-crossing experiment: N singles + one multi-byte template, N = 80..99

Fill line to strlen = N with single-byte digit keys, then press the template once
(delivery-retried). `pre→post(d)` lists every attempt of the template press.

#### t1: 9-byte base template (key 0x0D; single key, no latch)

| N target | template attempts (pre→post, d) | outcome |
|---|---|---|
| 80 | 80→80(+0); 80→80(+0); 80→88(+8) | INSERTED +8 → strlen **88** |
| 81 | 81→81(+0); 81→81(+0); 81→89(+8) | INSERTED +8 → strlen **89** |
| 82 | 82→82(+0); 82→82(+0); 82→90(+8) | INSERTED +8 → strlen **90** |
| 83 | 83→83(+0); 83→83(+0); 83→91(+8) | INSERTED +8 → strlen **91** |
| 84 | 84→84(+0); 84→84(+0); 84→92(+8) | INSERTED +8 → strlen **92** |
| 85 | 85→85(+0); 85→85(+0); 85→93(+8) | INSERTED +8 → strlen **93** |
| 86 | 97→97(+0); 97→97(+0); 97→97(+0); 97→97(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 97) |
| 87 | 87→87(+0); 87→87(+0); 87→95(+8) | INSERTED +8 → strlen **95** |
| 88 | 99→99(+0); 99→99(+0); 99→99(+0); 99→99(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 99) |
| 89 | 89→89(+0); 89→89(+0); 89→97(+8) | INSERTED +8 → strlen **97** |
| 90 | 99→99(+0); 99→99(+0); 99→99(+0); 99→99(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 99) |
| 91 | 91→91(+0); 91→91(+0); 91→99(+8) | INSERTED +8 → strlen **99** |
| 92 | 92→92(+0); 92→92(+0); 92→92(+0); 92→92(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 92) |
| 93 | 93→93(+0); 93→93(+0); 93→93(+0); 93→93(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 93) |
| 94 | 94→94(+0); 94→94(+0); 94→94(+0); 94→94(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 94) |
| 95 | 95→95(+0); 95→95(+0); 95→95(+0); 95→95(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 95) |
| 96 | 96→96(+0); 96→96(+0); 96→96(+0); 96→96(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 96) |
| 97 | 97→97(+0); 97→97(+0); 97→97(+0); 97→97(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 97) |
| 98 | 98→98(+0); 98→98(+0); 98→98(+0); 98→98(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 98) |
| 99 | 99→99(+0); 99→99(+0); 99→99(+0); 99→99(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 99) |

Boundary: accepted iff pre ≤ 91 (= 99 − 8); at pre=91 the insert lands exactly at
strlen 99 (`X t1N91r2`: pre=91 post=99, XFULL shows NUL at 0x81B7 and zeros beyond);
at pre ≥ 92 the template is **rejected whole** (d=0 on all attempts).

#### t2: 13-byte template chord (SHIFT+0x05, effective +12 on non-empty line)

| N target | chord attempts (pre→post, d) | outcome |
|---|---|---|
| 90 | 90→90(+0); 90→90(+0); 90→90(+0); 90→90(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 90) |
| 91 | 91→91(+0); 91→91(+0); 91→91(+0); 91→91(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 91) |
| 92 | 92→92(+0); 92→92(+0); 92→92(+0); 92→92(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 92) |
| 93 | 93→93(+0); 93→93(+0); 93→93(+0); 93→93(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 93) |
| 94 | 94→94(+0); 94→94(+0); 94→94(+0); 94→94(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 94) |
| 95 | 95→95(+0); 95→95(+0); 95→95(+0); 95→95(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 95) |
| 96 | 96→96(+0); 96→96(+0); 96→96(+0); 96→96(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 96) |
| 97 | 97→97(+0); 97→97(+0); 97→97(+0); 97→97(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 97) |
| 98 | 98→98(+0); 98→98(+0); 98→98(+0); 98→98(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 98) |
| 99 | 99→99(+0); 99→99(+0); 99→99(+0); 99→99(+0) | REJECTED (d=0 on all 4 delivery attempts; strlen stays 99) |

All chord attempts at pre ≥ 90 were rejected (90+12 > 99). In runs 1/2 the same chord
inserted +12 at pre = 33..56. So the 13-byte template is accepted iff pre ≤ 87, and
even then the result is ≤ 99. **No (N, template) combination yields strlen ≥ 100** —
the template is neither truncated to fit nor inserted past the cap; it is rejected.

## 3. Boundary interactions (phase 3, run 5 + run 3)

| sequence | result (evidence lines) |
|---|---|
| pure singles to cap | stall at exactly **99**: `T r100`/`T r101` all d=+0 at pre=99 |
| template first (SHIFT+0x05, +13 on empty line), then singles | fills 13→99, then d=+0 (`T a` tail pre=99) |
| two templates back-to-back | 1st +13; 2nd **rejected** d=+0 (run 3 `T t2tpl2r1..r3`; residue `21 B9` appears past the NUL but strlen stays 13) |
| fill 99, DEL (→98), 13B template | rejected d=+0 (`B d1tpl/r1..r3` at pre=98); a single then inserts +1 → 99 (`B d1k`) |
| fill 98, DEL (→97), 13B template | rejected at pre=97 (`B e1tpl/r1..r3`); singles climb to 99 (`B e1k`) |
| fill 99, INS (SHIFT+DEL →98), 13B template | rejected at pre=98 (`B f1tpl/r1..r3`); singles → 99 (`B f1k`) |
| fill 95, LEFT×3 (mid-line cursor), 13B template | rejected at pre=95 (`B g1tpl/r1..r3`) — same rule for middle inserts; singles → 97+ (`B g1k`) |

DEL/INS only lower strlen by 1 and re-open room for exactly one more single byte;
they never let a template push past 99.

## Answer

- Key→expansion table: section 1 (416 probes; multi-byte templates listed with full
  hex; largest expansion = 13 bytes, SHIFT+0x05 / SHIFT+0x0D / ALPHA+SHIFT+0x05 /
  ALPHA+SHIFT+0x0D → `7C BD BB B8 21 B9 B8 21 B9 B8 21 B9 BC`).
- Crossing table: section 2 (N=80..99 × 9-byte base template and 13-byte chord).
- **Max input-line length by pure typing = 99 bytes** (strlen(0x8154)=99, NUL at
  0x81B7). Achieved e.g. by 99 single-byte keys, by 91 singles + key 0x0D (+8 → 99),
  or by SHIFT+0x05 first (+13) + 86 singles. Templates are rejected whole when
  strlen + insertlen > 99 (9B template: rejected at strlen ≥ 92; 13B: ≥ 88), never
  truncated, never overflowing. The 250 backstop at ROM 0x7402 is unreachable by
  typing. Consistent with MB01 (`more-bytes-01-input-cap.md`, cap 99 at ROM 0x655A).

## Artifacts

- Script: `/home/yoxu/Projects/fx991espplus2nd/research/CasioEmuX/typedcap_length.lua`
- Logs: `/tmp/typedcap_length.log` (run 1), `/tmp/typedcap_length2.log` (run 2),
  `/tmp/typedcap_length3.log` (run 3), `/tmp/typedcap_length4.log` (run 4, full sweep),
  `/tmp/typedcap_length5.log` (run 5, TC_SKIP_PHASE1=1, crossing + phase 3; DONE
  `maxslen=99 maxseq=X t1N88`)
- RAM dump: `/tmp/typedcap_dump.bin` (0x8100–0x8DFF). rom.bin and emulator untouched.
