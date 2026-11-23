# more-bytes-04 — len-var / RCL-paste: can the flood period exceed 100? (2026-11-22)

Verdict up front: **NO key-reachable path makes the string at 0x8154 longer than 99 typed
bytes, and no key writes 0x81B7 (input index 99). The AC←EXE gate measures `strlen(0x8154)`,
never the len var 0x8114. Flood period = strlen at trigger = 100 max (as planted/measured in
`game-content.md`); >100 distinct bytes via a longer flood period is NEGATIVE.**

ROM: `research/CasioEmuX/models/fx991esplus2/rom.bin` (md5 c4c7d7fb…). Disasm: oki dumps
`/tmp/oki_b0.txt` (bank0) / `/tmp/oki_b1.txt` (bank1). Emulator runs (headless, 8× overclock):
`more04_lenvar.lua` (run1), `more04_lenvar2.lua` (run2), `more04_rcl.lua` (run3),
`more04_cap.lua` (run4) — logs `/tmp/mb04_run1..4.log`. 4 runs total (budget).

## (a) What the AC handler measures: strlen, by construction — code lines

The AC←EXE-path copy is a plain `strcpy`, whose length is `strlen(src)` in the copy loop
itself; no code on this path reads 0x8114:

- AC stamp caller, fn `0xBAFC`–`0xBB4A`, call site **`0xBB3A`–`0xBB42`**:
  `0xBB3A: MOV R2,#84 / 0xBB3C: MOV R3,#129` (ER2 = 0x8154 = src),
  `0xBB3E: MOV R0,#184 / 0xBB40: MOV R1,#129` (ER0 = 0x81B8 = dst),
  `0xBB42: BL 00h:02B10h` → `strcpy(0x81B8 ← 0x8154)`, **unconditional** (only gated by
  editor-state bits `TB 080FEh.6`, `TB 080F9h.7`, `080FCh==1 or bit7` at 0xBB10–0xBB38).
- Wrapper `0x2B10`: `PUSH LR / MOV ER0,ER0 / BC EQ 0x2B1E / MOV ER2,ER2 / BC EQ 0x2B20 /
  BL 0x6B58 / 0x2B1E: POP PC / 0x2B20: ST R2,[ER0] (empty-src NUL write) / POP PC`.
- Copy loop `0x6B58`–`0x6B74`: `ER10=ER2 (src), ER12=ER0 (dst)`, loop **`0x6B62: L R0,[ER10] /
  0x6B64: ST R0,[ER12] / ADD ER10,#1 / ADD ER12,#1 / MOV R0,R0 / 0x6B6C: BC NE,0x6B62`** —
  copies until the NUL. Length = strlen(0x8154), unbounded, no length argument, no 0x8114.
- Cache→input restore `0x89FA`–`0x8A0E`: `ER2=0x81B8, ER0=[ER8], BL 0x2B10` (strcpy input ←
  cache), then `0x8A0A: BL 0x2B06h` (strlen wrapper → `0xA0BE`) `0x8A0E: ST R0,08114h` —
  **0x8114 is written FROM strlen here, i.e. it is a derived value, never a length source.**
  Same pattern at `0x6E3C`, `0xC560`.
- Insert gate `0x6542`–`0x655E`: `BL 0x2B06h` (strlen([ER8])) → R1, `0x655A: CMP R1,#99 /
  0x655C: BC GE → bail / 0x655E: ST R1,08114h` — again strlen-sourced, capped <99.

The "gate" `strlen(0x8154) ≥ 100` for the stamping flood remains the differential proof
(vuln-search §3: V1 typed len 99 → no dst≥0x8300 stamps; V5 injected one byte at 0x81B7,
strlen=101, **0x8114 stayed 99**, flood fired → the gate reads the string, not 0x8114).
[INFERENCE] the flood engine's stamp loop advances dst by strlen, which is why the measured
flood in `game-content.md` is exactly period 100 phase 0 at 0x8154.

## (b) Can 0x8114 be written >99 by any key-reachable ROM path? NEGATIVE (measured)

All writes to 0x8114 (bank0; bank1 has only a read at `0x10FF4`):

| Site | Value written | Cap |
|---|---|---|
| 0x56F2, 0x7804, 0x9B12, 0xACBA, 0xC62A, 0xC9F0 | cursor deltas (R8−R4 etc.) | ≤ string length (cursor walk at 0xAC84–0xACB8 stops at string end via `BL 0x6000`; 0x9AF0 gates R5<32) |
| 0x61A2, 0x6442 (DEC [EA]) | len−1 | guarded len≠0 |
| **0x6196 (INC [EA], key 0x80F5==226 = →)** | len+1, **no immediate cap** | still bounded by the edit-context guards (0x6168–0x6186) and in practice by the cursor walk; measured never > len |
| 0x655E | strlen, `CMP R1,#99; BC GE bail` first | ≤98 |
| 0x6E3C, 0x8A0E, 0xC560 | strlen([ER8]/ER6) after restores | = strlen of an existing buffer; circular (needs a >99 string first) |
| 0xA1F4, 0xAEEC, 0xB304, 0xC53C, 0xC58A | 0 | — |
| 0x630C | `L R0,08006h` (eval reg) | eval-reg value |

Emulator evidence:
- Run 2 (`/tmp/mb04_run2.log`): on a 3-byte line, Right (0x37→token 0xE2) cycles
  `len8114 = 0,1,2,3,0,1,2,3,…` — **capped at len, wraps**; on a 70-byte line RIGHTx45 moves
  cursor 70→1→…→13 only. `maxlen8114 = 70 = len`. The 0x6196 INC never escaped the string.
- Run 4 (`/tmp/mb04_run4.log`): filled to `blen=99, len8114=99 (0x63)`; at-cap battery
  (shift, Σ(, ALPHA, X, 9, DEL, 9, ←, →, ↑, 0x24, EXE, ←, 1) → `b7=00, slen=99` at every
  sample; `DONE maxlen8114=99 maxslen=99 b7ever=0`.
→ **No key sequence writes 0x8114 > 99**, because 0x8114 is cursor/derived-strlen, and the
string length itself is capped by the insert gate `strlen<99` at 0x655A.

## (c) Max string placeable at 0x8154 in one step — measured 99 (typed cap); recall/paste = entry length ≤ 99

- Run 3 (`/tmp/mb04_run3.log`): typed 95-byte formula `1+1+…`, EXE (lastkey=F0, cache stamp
  b8=31, journal entry visible at ~0x8230/0x82F0), AC, then **↑ (0x27) recalled the whole
  95-byte entry into 0x8154 in ONE step** (`slen=95 blen=95`); **← after AC does the same**
  (run3 `T-LEFT`: slen 0→95). So the one-step paste primitive exists (↑/← history recall,
  ROM RCL/history path `0x7540`: `strcpy(0x8184←0x85AA)` at 0x755A + `strcpy([ER8]←0x8184)` at
  0x756A — **no cap at that site**) — but the pasted length = history entry length = input
  length at EXE time ≤ 99 (typed cap). RCL scancode 0x24 gave token 0x09 and pasted nothing
  (runs 1,3). ↑ into a non-empty "12" line did NOT concatenate (run2/run3: slen stayed 2).
- 250-cap token insert (0x7402: `CMP R0,#250; BC LE ok else bail 0x74FA`) is backstopped by the
  primary strlen<99 gate at 0x655A — run 4 at cap: K9/Σ(/X inserts all blocked, b7=00.
- Multi-line composer bails at ≥100/≥99 (`0xC798`/`0xC8EC: CMP R0,#100 → B 0xC9F4`;
  `0xC99A: CMP R0,#99; BC GT → 0xC9F4`) → multi-line input also ≤99 total. [INFERENCE from
  code + V1's measured 99 cap]
- DEL/INS tricks at cap: run 4 DEL-at-cap left `slen=99, b7=00` (and vuln-search V7: all 8
  DEL-dance variants hold the 99 cap; V10c/d/f: `B7CHANGE` fired **zero** times in ~2.6M
  postticks, `data[0x81B7]=00` at every sample).
- Max measured over all runs: `maxslen = 99` (run 4), `0x81B7 = 0` in every sample of every run.

## Verdict

- Gate length source: **strlen(0x8154)** (strcpy loop 0x6B62–0x6B6C; AC stamp 0xBB42; restore
  0x8A04). Len var 0x8114 is derived from strlen, never used as a copy length.
- Max string placeable at 0x8154 by keys: **99 bytes** (typed cap, 0x8114=0x63 at cap,
  measured run 4); one-step ↑/← recall places ≤99 (entry length). The in-emulator e2e
  payload's strlen=100 (period-100 flood) required harness-planted byte(s) at index ≥99 —
  on hardware, vuln-search: exactly one injected byte at 0x81B7 flips the gate (V5).
- **Flood period cannot exceed 100 from keys**: period = strlen(0x8154) at trigger; strlen
  ≥101 needs nonzero bytes at 0x81B7 AND 0x81B8 contiguous from 0x8154, and no key path
  writes 0x81B7 (b7=00 in all runs + 2.6M-tick B7CHANGE census). Even strlen=100 gives
  period exactly 100 = the measured ceiling in `game-content.md`. To get >100 distinct bytes
  you need a different mechanism (chain-computed stores, a second buffer as flood src, or a
  second trigger) — not a longer string at 0x8154.
