# more-bytes-02 — pre-trigger stash: how much of UNFLOODED RAM (0x8000–0x8153) can typing control, and does it survive the AC,←,EXE flood?

Date: 2026-11-22. Agent MB02PreStash. 4 emulator runs (budget used: 4/4), model `fx991esplus2`,
headless. Scripts: `research/CasioEmuX/more02_run1.lua` … `more02_run4.lua`; raw dumps
`research/CasioEmuX/mb02_r{1..4}_<tag>_low.bin` (340 B each, base 0x8000) and `mb02_r1_*_sfr.bin`.

Run roles:
- **r1** — exact `rop_e2e.lua` typed recipe + trigger (fired: KEYSCAN hop #1 `sp=8DA0`, PROBE1 NOT-INSERTED). Dumps A(pristine)/B(formula)/B1(after 1st EXE)/B2(pre-trigger)/C(post-flood).
- **r2** — typed `123456789012345` + CALC,EXE (Ans eval), then (broken) STO attempts; trigger did NOT fire (NO-TRIGGER, polluted buffer) — used for pre-trigger control diffs only.
- **r3** — MODE-menu sweep digits 1–8 with row entry `11 EXE 22 EXE` per mode + trigger (fired, `sp=8DA0`). Dumps A, M1..M8, B, C.
- **r4** — typed `123456789012345` EXE (dump N1), AC, typed `987654321098765` EXE (dump N2), then the proven rop_e2e tail + trigger (fired, `sp=8DA0`). Dumps A,B,N1,N2,B2,B3,C. **N1-vs-N2 diff = the content-controlled byte set; C = survival.**

## Verdict (measured)

**Unflooded RAM = 0x8000–0x8153 (340 B). The strcpy flood never writes there** (r1/r3/r4 B→C diffs
contain only the 7 trigger-path bytes below), **but typing+eval controls up to 36 bytes' values, of which
6 bytes survive the full AC,←,EXE trigger with attacker-chosen content: `0x8029, 0x8078, 0x8079,
0x807A, 0x807B, 0x8080`.** So the distinct-controlled-byte ceiling is **100 (payload @0x8154+) + 6 = 106**,
where the 6 extra bytes are decimal-nibble-packed (each byte = two digits → values 0x00–0x99 with both
nibbles ≤ 9, i.e. 100 values per byte, not 256) and sit at 0x8078–0x8080/0x8029, readable by the chain
(e.g. as memcpy12 src EA=0x8078, even-aligned, inside RAM).

## 1. The flood itself never touches 0x8000–0x8153

B3 (final_t==1, pre-flood) vs C (first KEYSCAN hop, post-flood), identical in all 3 firing runs:

| addr | pre-flood | post-flood | cause |
|---|---|---|---|
| 0x80F5 | 31 | F0 | last-key byte ← trigger's EXE |
| 0x8114 | 02/03 | 01/02 | editor len var ← trigger processing |
| 0x8115 | 0C | 06 | cursor ← trigger's ← |
| 0x8118 | 0C | 06 | cursor copy ← trigger's ← |
| 0x8129 | 01 | 00 | app flag ← trigger path |
| 0x8140 | 02 | 00 | Ans/result flag ← trigger path |
| 0x8149 | 01 | 00 | Ans/result byte ← trigger path |

(r1 additionally had 0x8140 02→00, 0x8149 01→00; r3 had no 0x8140/0x8149 change. 303/340 bytes are
identical pristine-vs-post-flood.) **All other sub-0x8154 bytes are flood-immune** — survival losses
come only from the trigger *key processing*, never from the strcpy tiling (which starts at 0x8154).

## 2. What typing changes below 0x8154, and what is attacker-VALUE-controlled

r4 A→N2 (15 digits typed + EXE): **76 bytes** in 0x8000–0x8153 change. r4 N1 vs N2 (two different
15-digit numbers): **36 bytes differ → content-controlled**:

| block | addrs | role (measured) |
|---|---|---|
| eval scratch | 0x8011–0x8018 (8 B) | number encoding, clobbered by tail's EXE |
| eval scratch 2 | 0x8021–0x8029 (9 B) | number encoding; only 0x8029 survives |
| flags/exp | 0x8050, 0x8057–0x8059 | clobbered by tail |
| **digit echo / mantissa fragment** | **0x8078–0x8080** | **SURVIVES flood** (N2: `06 54 32 10 00 05` = nibble-packed digits of 987654321098765) |
| cursor | 0x8115 | attacker-set via ←/→ pre-trigger, clobbered by trigger (→06) |
| Ans/result display | 0x8140–0x8148 (9 B) | number encoding, clobbered by tail's EXE (→00/02) |

r1 (standard recipe): 40 bytes change A→B2; of those, **33 survive the flood unchanged**, but they are
firmware-set flags/pointers (0x8104=01, 0x812C-0x812D=ptr 0x8154, 0x805C-0x805D=ptr 0x8226, …), not
attacker-chosen values. The only attacker-chosen scalar bytes in r1 were len 0x8114 (0–99), cursor
0x8115/0x8118, last-key 0x80F5 — **all four are rewritten by the trigger path** (→ 01 / 06 / 06 / F0),
so **0 of them survive with an attacker value**.

Survival of the 36 content bytes (r4 N2→C): **6 survive** — 0x8029=02, 0x8078=06, 0x8079=54,
0x807A=32, 0x807B=10, 0x8080=05; the other 30 are clobbered by the trigger tail's own EXE evaluation
(Ans/display/scratch blocks zeroed or rewritten).

## 3. Other modes (r3)

MODE + digit 1…8 with row entry (`11 EXE 22 EXE`) per mode: dumps M2…M8 are **byte-identical to M1** —
no mode switch / row entry wrote anything new below 0x8154 (buffer stayed `32 32` COMP-style).
Combined with vuln-search V3/V4 (STAT/EQN/TABLE row editors land at 0x8154 and mirror 0x81B8+ — i.e.
inside the flooded span): **other modes contribute 0 additional controllable bytes below 0x8154**.
[INFERENCE: in-emulator menu navigation is chord-limited (kyb-setup.md), so mode coverage leans on
vuln-search's row-editor measurements; measured here: no sub-0x8154 writes from the mode sweep.]

## 4. 0x8E00–0x8E02 shim and SFR 0xF000+ (r1 samples)

- **0x8E00–0x8E02 = emulator keyboard handshake** (query/KI/KO, one key per round): values observed
  `01 04 10` (last key AC), `01 04 04` (K9), `01 01 40` (EXE), `00 00 00` idle, **post-flood `0E 00 00`**.
  They reflect only the last consumed key and are zeroed after read → **0 persistent attacker bytes**.
- **SFR 0xF040–0xF04C (KI/KO/KID/KOD)**: Lua reads show KID=0xFF idle; in-chain KEYSCAN read
  `r2=FF` at hop #1 (no keys held); KOD 0xF046=0x7F appears post-flood only because the chain's own
  0x4D10 wrote it. 0xF00C/0xF00D and 0xF022/0xF023 echo the last key-handler pc per press. These are
  live key-state/event echoes, outside RAM, **not attacker content bytes** (while typing they mirror the
  single held key; post-trigger input is locked — PROBE1 NOT-INSERTED in r1/r4).

## 5. Answer table

| addr(s) | controlled by | survives flood? |
|---|---|---|
| 0x8114 (len), 0x8115/0x8118 (cursor), 0x80F5 (last-key) | typed length, ←/→ position, last key | **N** — trigger path rewrites (01/06/06/F0) |
| 0x8011–0x8018, 0x8021–0x8028, 0x8050, 0x8057–0x8059, 0x8140–0x8148 | typed number via EXE (Ans/eval/display encoding) | **N** — clobbered by trigger tail's EXE |
| **0x8029, 0x8078–0x8080 (6 B)** | **typed digits (last evaluated number), nibble-packed** | **Y** — r4 N2==C at these addrs, flood-immune |
| 33 firmware flags/pointers (r1) | firmware side effects of typing | Y but not attacker-chosen values |
| other modes' row/matrix data | — | n/a below 0x8154: none written (r3); ≥0x8154 is flooded |
| 0x8E00–0x8E02, SFR 0xF000+ | last held key only / key-event echo | not content; 0 persistent attacker bytes |

**Verdict number: 6 distinct attacker-controlled bytes survive in unflooded RAM (0x8029, 0x8078–0x8080),
all decimal-nibble-limited → total distinct controlled bytes = 100 + 6 = 106.** The flood ceiling of
"100 distinct bytes" is beaten only marginally and only via the digit-echo block; the freely-chosen
(zero-free typeable) payload bytes remain exactly the 100 at 0x8154–0x81B7. If the question counts only
free-value bytes: **0 extra** survive (len/cursor/last-key/Ans are all rewritten by the trigger path).

Artifacts: `research/CasioEmuX/more02_run{1..4}.lua`, `mb02_r{1..4}_*_low.bin`, `mb02_r1_*_sfr.bin`,
logs `/tmp/mb02_r3.log`, `/tmp/mb02_r4.log`.
