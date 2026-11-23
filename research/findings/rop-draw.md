# Typed-chain memcpy12: payload bytes landed on LCD row 0 — draw milestone closed

Date: 2026-11-21. Base script: `rop_draw2.lua` → copy `rop_draw3.lua`. One run of the
`fx991esplus2` model (1× clock until the 16× watch kicked in at final_t≥60001); bank-aware
breaks (`break_at` keys on `(csr << 16) | pc`, so keys in this log look like `csr:addr`,
e.g. `E:35BE` = csr=0xE, pc=0x35BE, i.e. a bank-1 ROM fetch mapped from the CSR register).

Payload change only (line 273 of the script, after the standard flood write):

```lua
W(48, 0x3538) W(50, 0x3538) W(52, 0xF801) W(54, 0x35BE) W(56, 0x35BE) W(60, 0x8154)
```

Design: 0x3538 gadget sets dst ER2 ← 0xF801 and r0 = 1 (single 16-byte stride copy of 12
bytes); pop at sp=0x8DA8 now loads PC ← 0x35BE (word 56/57) instead of the flood (any
RAM-posture word between them is skipped); the memcpy's `POP EA` takes the source pointer
from `word[0x8DAC]` = 0x8154 = the chain-controlled source = the payload buffer;
`word[0x8DAE]` = flood (0x4D0E) keeps the flood word immediately after the copy.

## Verbatim key lines (`/tmp/rop_draw3.out`)

    G38-HIT[8:3538] sp=8DA4 ER2=81FF ER0=0000 r0=00 lr=2B1E
    PPC-2B1E #9:    sp=8DA0 lr=2B1E nxt=3538 3538 F801 35BE
    PPC-2B1E #10:   sp=8DA8 lr=2B1E nxt=8154 4D0E 4D0E 4D0E
    MBE-HIT[E:35BE] sp=8DAC ER2=F801 EA=F040 r0=01 lr=2B1E src=8154 src12[8154]=0E4D0E4D0E4D0E4D0E4D0E4D
    PPC-2B1E #10:   sp=8DA8 lr=2B1E nxt=35BE 4D0E 8154 4D0E

- `MBE-HIT[E:35BE]` — the memcpy12 gadget executed **from the typed chain** with
  **dst ER2 = 0xF801 (LCD row 0)** and r0=1 (single 16-byte-stride copy of 12 bytes = one
  LCD row segment). Entered from the walk with lr=0x2B1E; `EA=F040` is the stale
  pre-`POP EA` value (last KEYSCAN's `LEA 0xF040` — the gadget's `POP EA` executes right
  after this break, loading the src pointer). `src=8154` = my sampler's read of
  `word[sp]=0x8154`, i.e. the pointer that `POP EA` then loads: the chain-controlled
  source pointer = the payload buffer.
- `src12[8154]=0E4D0E4D0E4D0E4D0E4D0E4D` — exactly the payload's first 12 bytes (`0E 4D ×6`),
  as designed.
- After the copy, every subsequent CHAIN hop's `lcd01` readback =
  `0E4D0E4D0E4D0E4D0E4D000000000000000000000000|0000000000000000` — **the payload's first
  12 bytes live on LCD row 0 (0xF801..0xF80C)**. draw2's `lcd01` was all-zero row 0 — the
  draw is new in this run and is ours.
- `G38-HIT[8:3538] sp=8DA4 ER2=81FF ...` — the 0x3538 gadget ran with csr=8 (flash
  `0x8:3538`, resolves to the same bank-0 code), as predicted from word[0x8DA2]=0x3538 →
  csr bit 3.

## Post-copy walk

```
PPC-2B1E #11: sp=8DBA lr=2B1E nxt=4D0E 4D0E 4D0E 4D0E   (flood march resumes)
CHAIN: KEYSCAN #17 … sp=8DFC …
PROTO: NO-TRIGGER hits=17 pc=4B96 sp=8D7C
PROTO: final-buf 0E4D0E4D… len=100
```

Entry #2 sp = **8DBE** (+0x0E = +14 vs draw2's 8DB0) = exactly the memcpy's EA/return
consumption; the walk resumed the flood march at the aligned pair 0x8DC2 (nxt=4D0E-flood),
17 hops to the same park.

## Status matrix (updated)

| Capability | Status |
|---|---|
| Proof-of-execution only (harness) | VERIFIED |
| Typed chain: keyscan hop + return | VERIFIED |
| Typed chain: keyscan + RAM write | SUPERSEDED — chain performs a RAM→LCD copy |
| Typed chain: keyscan + memcpy LCD row 0 write | VERIFIED |
| Persistent on-screen artifact (park holds) | not yet (draw is transient under the app's parked refresh) |
| SETUP/LineIO-yielded chain triggers | OPEN |
| Snake-lite game loop | OPEN (needs SETUP + persistent row-0 draw) |

Next levers: (a) LCD persistence — park the CPU with the payload resident elsewhere or
re-trigger the chain via the SETUP route; (b) gadget search for a conditional-transfer
gadget on r0 (the KEYSCAN result) to branch the walk on key state — the natural next
milestone for Snake-lite input.
