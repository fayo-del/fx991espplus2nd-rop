# more-bytes-01 — Is the 0x8154 input buffer really capped at 100 bytes of TYPED content?

Date: 2026-11-22. Agent: MB01InputCap. Question: max strlen/dumped length achievable at
0x8154 by **pure keyboard typing** (no memory writes) in every entry mode.

**Verdict: typed cap = 99 bytes (strlen(0x8154) = 99, NUL at 0x81B7). No measured
mode/path exceeds it. The "100-byte payload" of the known ceiling is the 100-byte
*buffer window* (0x8154–0x81B7) reached in-emulator only via the Lua-planted payload
(rop_e2e.lua swaps it in at final_t==36001, "Lua write, not a keystroke"); pure typing
saturates at 99 and the strlen≥100 flood gate is therefore NOT reachable by typing
alone in the emulator.** Extra controlled bytes elsewhere: only replicas — the AC
stamp mirrors the same ≤99 bytes to the cache 0x81B8+ (measured 99 nonzero bytes at
0x81B8–0x829D), and the 2nd-line editor buffer 0x829E–0x82CE stayed all-zero at
slen=99 in MathIO (no multi-line second line at another address in COMP).

## 1. Static cap sites (bank-0 dump /tmp/oki_b0.txt)

- **0x655A–0x655E — the real cap**: `L ER0,[ER8]; BL 02B06 (strlen); MOV R1,R0; …
  CMP R1,#99; BC GE,06510 (bail, return 0); ST R1,08114h`. The editor insert path
  recomputes strlen of the input and rejects the insert once strlen ≥ 99 → max
  strlen = 99. (0x8114 itself turned out to be the *cursor position* in the measured
  runs — it dropped on LEFT — the prior "len var cap 99" is this same #99 constant.)
- **0x7402–0x7406 — 250 backstop**: token-insert family `CMP R0,#250; BC LE; else bail
  074FA`. Reachable only if the editor length already exceeds ~250; no typed path
  found that gets there (measured stall at 99).
- 0x8113: separate counter, capped against a register (0x5050 `CMP R0,R1; BC LE; ST
  R1`), gated on 0x80F5==224 — not the input length.
- 0x6192: `LEA 08114h; INC [EA]` gated on 0x80F5==226 (screen 0xE2) — an uncapped
  increment path, but 0xE2 was never observed in the MathIO runs (0x80F5 seen:
  E4/E6/ED/F0/2B/32…); [INFERENCE] some other screen (possibly a non-COMP editor)
  uses it, and its buffer is not necessarily 0x8154.
- All other 0x8114/0x8113 writes (0x56F2, 0x61A2, 0x630C, 0x6E3C, 0x77F6/0x7804,
  0x8A0E, 0x950A, 0x9B12, 0xA1F4, 0xACBA, 0xAEEC, 0xB304, 0xC5xx, 0xC9F0, bank1
  0xFF4/0x329E/0x4412) are resets (ST 0), cursor stores, or post-copy strlen
  recomputes — no cap bypass.
- Copy paths into/out of 0x8154 (sec-firmware-copies.md census): strcpy
  0x5C9E (0x8154←0x81B8 cache), 0x755A (0x8154←0x85AA history), 0x509C/0x8A04
  (0x81B8←0x8154 stamp), 0x8C06 (template insert) — all *replace* semantics, src bounded
  by the stored history/cache content which itself is ≤ typed ≤ 99. The only strcat
  into the 0x8154 family (0x5292) takes a render-temp src [INFERENCE: display path].

## 2. Measured table (emulator, model fx991esplus2, headless, ≤4 runs)

| # | Run (script) | Mode / path | Max strlen@0x8154 | Notes / evidence |
|---|---|---|---|---|
| 1 | more01_cap.lua | MathIO append, 150 filler keys (12k holds, ~50% delivery) | 73 (run cut by timeout, cap not reached) | tokens observed: 0x00→31, 0x10→32, 0x20→33, 0x01→34, 0x11→35, 0x21→36, 0x02→37, 0x12→38, 0x22→39, 0x63→2E, 0x40→2D, 0x41→4F. Dump /tmp/mb01_cap_dump.bin md5 c24efa1cbc08dd05b39f8072bebc29c3 |
| 2 | more01_cap2.lua | MathIO append to cap (30k holds) + at-cap probes: LEFT×3+key, DEL+key, SHIFT+DEL(INS)+key, mid-line SHIFT+key ×9 candidates | **99, never 100** (`DONE: maxlen=81 maxslen=99`) | stall at slen=99 (Dp31-04…Dp64-06 all slen=99); no pc=4D20/flood. 2nd-line buf 0x829E-0x82CE NZ=0; cache 0x81B8-0x829D NZ=99 (AC stamp replica). Dump /tmp/mb01_cap2_dump.bin md5 0a0f34823ce30f0fa6ea7ee589667145 |
| 3 | more01_sweep.lua | all codes 0x00-0x67 base + SHIFT+ + ALPHA+ (104+~46+~46 probes) | per-key insert ≤13 B | token map: 1-byte tokens {30-39, 2E, 74, 8B, 28, 72, 5C, A1, 68, A2, A3, 2B, BE, 2C, 6D, BF, 82, 8C, B3, B0, B1, B2, 25, 57, letters 41-5A via ALPHA, 3D, 3A, 81, C2}; multi-byte templates up to 13 B (e.g. s05→7C BD BB B8 21 B9 B8 21 B9 B8…). SHIFT+0x40 → 1-byte token 0x6D (RCL), no direct paste |
| 4 | more01_modes.lua | SETUP chord attempt + RCL/history phase + MODE digits (crashed on a Lua pattern bug in the logger after mode 1; RCL/SETUP data captured) | 53 in the partial run | SETUP (SHIFT+MODE,2) did NOT open (SU-sigma slen=0, 0x80F5=E4 = mode menu — matches kyb-setup.md: chord undeliverable through the 0x8E00 shim). RCL: EXE stored "+2" to history; SHIFT+0x40 on empty input → inserts token 0x6D only (slen=1); mid-line SHIFT+0x40 at slen=49 → no growth. SHIFT+EXE → 0x80F5=ED, no insert |

Mode-by-mode verdict (acceptance table):

| Mode / path | Max typed len @0x8154 | Proven how |
|---|---|---|
| MathIO (COMP, default) append | **99** | run 2: slen saturates at exactly 99, 12+ further keys at cap all rejected (Dp31-04…Dp64-06) |
| MathIO middle insert (LEFT+key) | ≤99 | run 2 B-midK1 / D-midrcl*: insert at cursor still gated by the same #99 check |
| DEL / INS (SHIFT+DEL) then type | ≤99 | run 2 B-del/B-afterdel, B-ins/B-afterins: normal gated inserts |
| RCL / history paste | ≤99 (replace, no append) | run 4 R-rcl40 = 1-byte token 0x6D; paste path is strcpy-replace (0x5C9E/0x755A), src ≤99; run 2 C-rcl*/D-midrcl* never exceeded 99 |
| AC stamp to cache 0x81B8 | 99 replica bytes (not distinct) | run 2 final: NZ(0x81B8-0x829D)=99 |
| Multi-line 2nd line (0x829E-0x82CE) | **0 bytes** in MathIO | run 2 final: NZ(0x829E-0x82CE)=0 at slen=99 — COMP scrolls the single 0x8154 buffer, no second typed line |
| LineIO via SETUP (SHIFT+MODE,2) | NOT MEASURABLE in emulator | run 4 + kyb-setup.md: chord never delivered through the one-key-per-round 0x8E00 shim; [INFERENCE] hardware LineIO uses the same editor/0x655A #99 cap — no static path found with a higher cap (only the 250 backstop, unreachable from typing) |
| MODE-menu modes 2-9 (STAT etc.) | [INFERENCE] same ≤99 | run 4 crashed (logger bug) after mode 1; static: all modes share the 0x8154 editor + 0x655A cap; no per-mode larger buffer found in the 0x8114 write census |

## 3. Answer

- **Max typed bytes at 0x8154 = 99** (strlen 99, NUL at 0x81B7; buffer window 0x8154-0x81B7
  = 100 bytes of which the 100th is always NUL when filled by typing). Measured, not
  inferred: run 2 `maxslen=99` across append / middle-insert / DEL / INS / RCL-paste
  attempts; cap constant found statically at 0x655A (`CMP R1,#99; BC GE → bail`).
- **No mode/path exceeds it**: cache 0x81B8 gets only a strcpy replica (≤99 B);
  multi-line second buffer 0x829E is empty in COMP; LineIO unreachable in-emulator
  (shim limitation, documented in kyb-setup.md) with no static evidence of a higher cap;
  MODE-menu modes unmeasured past mode 1 (run 4 logger crash) but share the same editor
  cap code [INFERENCE].
- Consequence for the >100-distinct-bytes goal: **pure typing yields at most 99
  distinct bytes, all inside 0x8154-0x81B6** (plus zero-free constraint from
  typeable tokens). The 100-distinct-byte ceiling of game-content.md is the buffer
  size; the flood period post-trigger equals strlen(0x8154), so typing alone caps the
  ROP/game payload at 99 distinct bytes — reaching 100 requires the non-typed plant
  (emulator) or a yet-unfound hardware path. [INFERENCE: on hardware the SHIFT+MODE
  chord works, but LineIO's editor still goes through the same insert routine —
  unverified.]

## 4. Artifacts

- Scripts: `research/CasioEmuX/more01_cap.lua`, `more01_cap2.lua`, `more01_sweep.lua`,
  `more01_modes.lua` (absolute: /home/yoxu/Projects/fx991espplus2nd/research/CasioEmuX/).
- Logs: /tmp/mb01_cap.log, /tmp/mb01_cap2.log, /tmp/mb01_sweep.log, /tmp/mb01_modes.log.
- Dumps: /tmp/mb01_cap_dump.bin (md5 c24efa1cbc08dd05b39f8072bebc29c3),
  /tmp/mb01_cap2_dump.bin (md5 0a0f34823ce30f0fa6ea7ee589667145) — RAM 0x8100-0x8DFF.
- rom.bin untouched (never edited); emulator binary untouched.
