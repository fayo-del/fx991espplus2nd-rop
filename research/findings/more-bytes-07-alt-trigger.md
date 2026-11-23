# more-bytes-07 — alternative triggers & longer copies for the 0x8154 flood (MB07AltTrigger)

Date: 2026-11-22. Question: is `AC,<-,EXE` on a ≥100-byte 0x8154 the only/longest
stack-reaching copy? What else fires the journal-replay stamps, and does any site copy
LONGER strings? Max single-copy length and max distinct bytes per trigger, measured.

Method: one script `research/CasioEmuX/more07_alt.lua` (scenario via `more07_scn.txt`),
4 headless runs (budget used: 4/4), logs `/tmp/mb07_base.out`, `/tmp/mb07_base2.out`,
`/tmp/mb07_long.out`, `/tmp/mb07_alt.out`. Typed queue = `rop_e2e.lua` verbatim (41 keys,
reaches the locked overflow state, `PROBE1: len=2 ...` in every run). Loggers:
strcpy wrapper `0x2B10` (per call, site=`lr`), inner copy loop `0x6B62` (per word —
this is where the flood actually runs), strcat `0xCB5E`, memmove `0x5108`, memcpy12
`0x35BE`, POP PC `0x2B1E`, KEYSCAN `0x4D20`. Payload planted at 0x8154 by Lua (harness
convention as in all prior milestones); all payload bytes distinct and zero-free.
ROM untouched, no emulator source edits.

## Headline answers (measured)

1. **EXE alone fires the whole flood — AC and ← are NOT required.** With a 101-byte
   distinct payload planted at 0x8154 (post-typed-queue state), a single `EXE` press
   produced: `h62=9737` word-writes at `0x6B62`, `stack62calls=1037` copy runs touching
   ≥0x8C60, `maxdst62=0x8E65` (writes past RAM end 0x8DFF are dropped by the MMU),
   `maxend62=0x8E66`, wrapper call `S@50A0 dst=81B8 src=8154 len=101`, `pops=2`, final
   `pc=4B96` (park spin) — `/tmp/mb07_alt.out` lines 7-14. Identical flood to the
   canonical `AC,←,EXE` (`/tmp/mb07_base2.out`: `h62=9742`, `stack62calls=1557`,
   `maxend62=8E67`, `pops=4`, park). In the canonical run, AC (pressed while
   strlen=2) and ← fired only the bounded restore `S@6E2A dst=8154 src=81B8 len=1` ×2;
   everything else fired at EXE.
2. **Max single-copy length = `strlen(0x8154)`, not capped at 101.** The cache stamp
   (site `0x509C`, logged `lr=0x50A0`, `strcpy(dst=0x81B8, src=0x8154)`) copied
   **len=204** when 204 distinct bytes were planted (`/tmp/mb07_long.out` line 19:
   `WRAP site=50A0 dst=81B8 src=8154 len=204 end=8284`), vs len=101 with a 100-byte
   plant. So the single copy grows with the input string, unbounded in principle.
3. **BUT the flood period is pinned at 100 by the stamp's overlap geometry, so the
   100-distinct-byte ceiling is geometric, not the editor's 99 cap — longer input does
   NOT break it.** `dst(0x81B8) − src(0x8154) = 0x64 = 100`: the byte-forward strcpy
   re-tiles the source with period 100 as it copies. Measured with a 204-distinct-byte
   plant: `MB07-ANALYZE END-long: plen=204 match=100/3244 firstbad=100 ... distinct=116`
   — only the 100 bytes at 0x8154..0x81B7 survive distinctly; everything from 0x81B8
   on is the period-100 replica (`stackmatch=0/416` against the 204-extension, i.e.
   the stack is flooded with the period-100 content, `stack62=1036`, park reached).
   **Max distinct attacker bytes per trigger = 100** (plus ≤16 non-payload firmware
   bytes in unflooded holes 0x8100-0x8153 — not attacker-controlled). NEGATIVE on
   "more distinct bytes via a longer 0x8154 string" through this trigger family.
4. **No other copy primitive fired.** strcat `0xCB5E`: 0 calls in all 4 runs (so its
   unbounded `len=dst+src` growth, incl. the `0x8BF6` stack-buffer append, is not
   keyboard-reachable in these states — measured for AC/EXE paths). memmove `0x5108`:
   0 calls. memcpy12 `0x35BE`: 188 calls, all app-screen refresh (`lr=9F48`,
   `dst=0xF8xx`) — **no SFR/LCD write from copies, no RAM dst** (consistent with census
   §4: no copy site computes dst ≥0xF000 from input).
5. **The flood's bulk writes do not pass the strcpy wrapper**: `0x6B62` saw 9737-9742
   word-hits while `0x2B10` saw only 2-4 calls and `0x6B58` (run 1) only 4 — the stamps
   enter the inner loop directly (computed jump / post-smash chain; `lr=2B1E` at the
   hits). Per-word dst histogram tops at `8E65x3, 8E64x3, …` — each flood address
   written ~3×.

## Table — key-seq → copy measurement (all runs: 41-key typed queue first, payload planted at 0x8154)

| Key sequence (payload present) | 0x6B62 word-writes | wrapper (0x2B10) calls | max single-copy len | max end (dst+len) | stack ≥0x8C60 | chain | verdict |
|---|---|---|---|---|---|---|---|
| `EXE` only, strlen=101 (`alt`) | 9737 | 2 × `S@50A0` len=101 (dst=0x81B8) | **101** | 0x8E66 | **yes, 1037 runs** | pops=2 → park 0x4B96 | **FLOOD — AC/← not needed** |
| `AC,←,EXE`, strlen=101 (`base`) | 9742 | 2 × `S@6E2A` len=1 (pre-plant, AC/←) + 2 × `S@50A0` len=101 (at EXE) | **101** | 0x8E67 | **yes, 1557 runs** | pops=4 → park | FLOOD (canonical) |
| `AC,←,EXE`, strlen=204 (`long`) | 9742 | 2 × `S@50A0` **len=204** (dst=0x81B8, end=0x8284) | **204** | 0x8E66 | yes, 1037 runs | pops=4 → park | FLOOD, but period pinned 100 → distinct stays 100 |
| `AC` alone (strlen=2, pre-plant) | 0 | 2 × `S@6E2A` len=1 (dst=0x8154←0x81B8) | 1 | 0x8155 | no | no | bounded restore only |
| `RCL`, `MODE`, `DOWN`, `ON`, type-after-AC | not run (4-run budget spent) | — | — | — | — | — | [INFERENCE] census §2: RCL sites `0x755A/0x756A` copy ≤typed len, row editors ≤61; no 0x6B62 flood was observed without EXE in any run |

## "Type 100, AC, then MORE, then ←, EXE" — second distinct block?

- Post-overflow-state input is **locked**: `PROBE1: len=2` NOT-INSERTED (typed queue,
  all runs); post-flood `blen=101` frozen (`/tmp/mb07_alt.out` line 9-11) — typing after
  the trigger does not append.
- Even if a second distinct block were appended before the copy, it **cannot raise
  distinct bytes above 100**: measured `long` run — 204 distinct bytes planted, flood
  still period 100 (`match=100/3244 firstbad=100`), because the `0x81B8←0x8154` overlap
  re-tiles with period 0x64. The 100-byte ceiling is the stamp's dst−src distance, not
  an input cap.

## Site list — stack/SFR-reaching copies and their key (step 1)

- Only the journal/cache tiling engine reaches ≥0x8C60 (measured: 1037-1557 copy runs
  per trigger, dst up to 0x8E65). Entry key: **EXE** (`=`/0x60) with
  `strlen(0x8154) ≥ 100` in the locked editor state — the only flood trigger observed.
  The pointer-dst strcpy sites of census §2 (`0x6E26`, `0x7CFA`, `0x8A04`, `0x50AC`,
  `0x756A`, `0x99A8/0x99EC`) are the flood's participants, not independent triggers.
- SFR: none — measured no copy dst ≥0xF000 in any run; memcpy12 dst=F8xx is the
  display refresh only.

## Files

- Script: `research/CasioEmuX/more07_alt.lua` (+ `more07_scn.txt` scenario selector:
  `base|long|alt|typemore`; the `typemore` phase exists in the script but was not run —
  budget).
- Logs: `/tmp/mb07_base.out`, `/tmp/mb07_base2.out`, `/tmp/mb07_long.out`, `/tmp/mb07_alt.out`.

## Bottom line

`AC,←,EXE` is **not** the only trigger — **EXE alone** fires the identical
stack-smashing flood (9737 word-copies, 1037 stack-reaching runs, chain parked). The
longest single copy is `strlen(0x8154)` (measured 204 > 101), but the cache stamp's
`dst−src=100` overlap re-tiles the payload with period 100, so **max distinct
attacker-controlled bytes per trigger remains 100** — the ceiling is geometric
(0x81B8−0x8154), and no keyboard-reachable path measured here (strcat/memmove never
fire; RCL/MODE/ON bounded per census) exceeds it. To beat 100 distinct bytes you need a
different mechanism than the 0x8154→0x81B8 stamp family (e.g. chain-computed stores via
the bank-1 `ST QR0,[EA]` family, or a second buffer whose copies don't overlap
periodically) — not a longer input string.
