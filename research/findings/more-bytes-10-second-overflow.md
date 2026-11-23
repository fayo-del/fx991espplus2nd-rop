# more-bytes-10 — second overflow from the chain: can the chain re-enter the input path and fire a second copy? (2026-11-22)

Agent: `MB10SecondOverflow`. Scripts: `research/CasioEmuX/more10_second.lua` (run 1),
`more10_tile.lua` (run 2), `more10_plant.lua` (run 3). Logs: `/tmp/more10_run1.out`,
`/tmp/more10_run2.out`, `/tmp/more10_run3.out`. Dumps: `/tmp/more10_run1_*.bin`,
`/tmp/more10_run2_*.bin`, `/tmp/more10_run3_{hop1,pre_flood2,post_flood2,final}.bin`.
3 decisive emulator runs (a 4th crashed on a Lua nil before any measurement).
Typed trigger = `rop_e2e.lua` recipe verbatim; payload = pure `0x4D0E` flood
(+ `W(84)=0x73A2` in run 2). No emulator source edits; `rom.bin` untouched.

## Disassembly answers (step 1) — input-path entries

- Key scan loop: **0x529A** (loops `0x53AA: MOV ER0,#20; BL 0x4B56 (KO); BL 0x4D0E (KEYSCAN)`;
  result class in R6, scan pair stored `0x52CE: ST ER0,0x80F2`).
- App key service: **0x8508** (called by the 0x4EF2 park and 0x5210/0x521A wrappers);
  known NEGATIVE as a raw chain callee (`rop-game.md`: wrecks the walk, sp→0x4CF0).
- Key-action dispatcher: **0x9932** (called from 0x65A2 with ER0=state ptr; polls key via
  `0x994C: BL 0x65AA` → `0x65B0: BL 01h:01064h` = real **0x11064**; calls the insert at
  **`0x9CFA: BL 0x73A2`**).
- Token-insert function (the 0x7402 family): **0x73A2** — `PUSH LR; BL 0x5230; ADD SP,#-4;
  BL 0x11064 (token); … 0x7402: CMP R0,#250; BC LE / bail 0x74FA; memmove-insert
  0x7448/0x7474/0x7492/0x74B0 (dst = editor staging 0x829E.., token byte from stack temp
  ~0x8D9F); exit 0x74FA: B 0x5238 (MOV SP,ER14; POP XR4; POP QR8; POP PC)`.
  Buffer ptr var **0x812C = 0x8154** (measured at hop #1), cursor 0x8113=00, len var
  0x8114=01, last-key byte 0x80F5=F0 (stale = EXE).
- Commit copies: **0x984C** `strcpy(0x8154 ← 0x81B8)` (the visible input write),
  **0xBB42** `strcpy(0x81B8 ← 0x8184)` (AC stash), AC-stamp flood = wrapper **0x2B10**
  (dst=0x81B8, src=0x8154, strlen≥100 gate) — all via `BL 00h:02B10h`.

## (a) Do keys pressed during the chain modify 0x8154? — **NO (measured)**

Run 1 (`more10_second.lua`), chain hops #3–#9 with one key held per hop
(0x00,0x10,0x22,0x26,0x37,0x42,0x60 = digits/arrows/AC/EXE):

```
HOP#3..HOP#9 (key .. held since prev hop):
  (a) buf-diff: NO-CHANGE 8154-81B7
  (a) low-diff: NO-CHANGE 8100-8153
```

Every key, 0x8154..0x81B7 and 0x8100..0x8153 byte-identical to the hop-#1 flood.
(Consistent with MB06: post-trigger keys give 0 persistent content bytes; only the
KID bitmap in r2 at each KEYSCAN hop and 0x80F5-unchanged.) The chain runs only the
KEYSCAN gadget; no firmware input path is active.

## (b) Can the chain enter the input handler and change 0x8154? — **handler reachable, but 0x8154 itself: NO (measured)**

- Run 1, hop #9 teleport `pc=0x73A2, lr=0x2B1E` with key 0x00 held: `PATH-73A2` fired
  (h73 3→4) but the insert **bailed** (strlen(0x8154) is unbounded post-flood → the
  0x7402/0x74FA path; h74fa +9, h2b10 +18 spam) and the walk died into purgatory
  (pc≈0x515x, sp=0x0409). buf-diff at hop #10: NO-CHANGE.
- Run 2, payload tile `W(84)=0x73A2` (bytes `A2 73 0E 4D` → PC=0x73A2, CSR word 0x4D0E →
  bank 0) consumed by the walk at hop #10, key 0x00 held from hop #2, NUL planted at
  0x8186 (strlen=50): `PATH-73A2` fired **from the walk** (h73 3→4), insert engine ran
  (`PATH-7448` +7 memmoves), and the held key's token **0x31 landed at 0x8DCB** (stack
  temp) with staging buffer 0x829E..0x82CE shifted (`0x829E..: 0000…0e4d…3a`). But
  **0x8154..0x81B7: NO-CHANGE** at hops #11/#12 — 0x73A2 writes the staging area, not
  0x8154; the visible commit `strcpy(0x8154←0x81B8)` lives in the caller (0x984C /
  0x9932 flow), which the chain does not reach intact. The walk then died before hop #13
  (purgatory pc≈0x8F4x sp=0x4CF0) because the inserted token byte 0x31 at 0x8DCB
  **overwrote a future walk tile** (hop #13's tile at 0x8DC8–0x8DCB).

Verdict (b): the chain *can* POP PC into the insert handler and a held key's token is
inserted (staging + stack temp), but **0x8154 is not modified by that entry**, and a raw
entry corrupts the walk within ~3 hops. (Tile bytes A2 73 are typeable: base+alpha tables.)

## (c) Second copy from the chain with a new string at 0x8154 — **YES (measured), >100 distinct bytes**

Run 3 (`more10_plant.lua`), pure-flood chain:

1. hop #2 — teleport into **memcpy12 0x35BE** with the walk slot as `POP EA`:
   `EA=0x23C6` (ROM keycodes table), `r0=8`, `ER2=0x8154`, `lr=0x2B1E`, `pc=0x35BE`.
   Result at hop #3: **76 bytes at 0x8154..0x8187 planted** with ROM bytes
   (`3132332B2D00F000343536 4E…4F008B00373839FEE60074 00…EAF82829FAEE2E0060F609A0…A1A230 00…`),
   and the walk **survived** (hops #3–#6 kept firing, ended pc=0x4D20 sp=0x8DC2).
   Span mismatches vs the P1 period: **98 of 3244** → the flood periodicity is broken
   over the planted region while all P1 replicas beyond stay intact.
2. hop #4 — teleport into the **strcpy wrapper 0x2B10** with `ER0=0x81B8` (dst),
   `ER2=0x8154` (src), `lr=0x2B1E`, `pc=0x2B10` = the AC-stamp copy fired again from
   the chain. Measured effect (dump diff pre_flood2→post_flood2): `0x81B8..0x81BD`
   changed `b2bab8babeba` → `31 32 33 2B 2D 00` = exactly `strcpy(0x81B8←0x8154)` copying
   the new string (bounded at 6 bytes by the NUL at 0x8159, strlen(0x8154)=5).
3. Count after the second copy: **span mismatches vs P1 = 102** (98 planted + stack
   scratch) → distinct attacker-influenced byte positions in 0x8154..0x8DFF
   ≈ **100 (P1 period) + 102 ≈ 202 > 100**. Distinct byte *values* in span: 67
   (post-plant) vs 2 for the pure `0E4D` flood.

So the "200 distinct bytes" outcome is real, but via **coexistence, not re-tiling**: the
second copy from the chain fires, and because the planted string is NUL-terminated
(strlen 5), the copy is bounded and lands at 0x81B8.. while the P1 replicas
(0x8154..0x81B7 planted region aside, everything beyond) remain. If the planted string
were zero-free for ≥100 bytes, the same 0x2B10 call would re-tile the whole span with
the new string (identical mechanics to the proven original trigger flood) → 100
distinct of the *new* string, P1 gone — i.e. a full second flood does NOT give 200;
the bounded (NUL-containing) second copy does.

## Answers

- **(a) NO** — measured, run 1: no key (0x00/0x10/0x22/0x26/0x37/0x42/0x60) changes any
  byte of 0x8154..0x81B7 or 0x8100..0x8153 during the chain.
- **(b) PARTIAL/NO for 0x8154** — measured, runs 1–2: the chain can enter the insert
  handler 0x73A2 (teleport or payload tile `W(84)=0x73A2`, bytes A2 73 0E 4D) and a held
  key's token is staged (token 0x31 → 0x8DCB, staging 0x829E shifted), but 0x8154 is not
  written by the handler (commit copy 0x8154←0x81B8 is in the caller 0x9932/0x984C), and
  the raw entry corrupts the walk within ~3 hops (token byte hits a future tile).
- **(c) YES** — measured, run 3: with a new string planted at 0x8154 (chain memcpy12,
  EA=0x23C6, r0=8 → 76 new bytes) the chain fires the second strcpy
  `0x2B10(0x81B8←0x8154)` → new string written at 0x81B8.. → **102 mismatches vs the
  P1 period over 0x8154..0x8DFF ≈ 202 distinct controlled positions (>100 ceiling
  broken)**. A zero-free ≥100-byte plant would instead re-tile everything with the new
  string (100 distinct, P1 overwritten) [INFERENCE: same strlen≥100 flood mechanics as
  the proven original trigger; only the from-chain entry was measured here].

## Hardware notes / honesty

- In-emulator, the teleports set `cpu.pc/registers` from Lua break handlers; the
  hardware-equivalent chain tiles exist and are typeable where noted: `0x35BE` tile
  `BE 35` (base/shift + base/alpha), `0x73A2` tile `A2 73` (base+alpha), `0x2B10` tile
  `10 2B` (alpha/shift + base), dst word `0x8154` = `54 81` (typeable). The EA word
  `0x23C6` (`C6 23`) is **not** typeable on hardware — on hardware the memcpy12 src must
  be a zero-free typeable word (RAM 0x81xx–0x8Cxx per game-content.md), so the planted
  content would come from payload rotations, not ROM. The mechanism (chain → memcpy12
  → 0x8154, chain → 0x2B10 second copy, bounded coexistence >100 distinct) is
  emulator-proven regardless of src.
- The planted ROM bytes contain 0x00 (that is what bounded the second copy at 6 bytes);
  a zero-free plant needs a zero-free src.
- Run budget: 3 decisive runs (run1 a+b-teleport, run2 b-tile, run3 c); one early crash
  (nil `T`, no measurement).
