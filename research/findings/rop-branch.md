# Typed-ROP milestone 4: key-conditional branch gadget — key value leakers into the executed stream

**Verdict: SUCCESS.** The 0x4CDC gadget (CMP R0,#0 / BC EQ → RB 0F80Bh.4 / SB 0F80Bh.4) executes
mid-walk from the typed flood march, and the SB/RB outcome tracks a key held during the walk:
TEST 1 (Right held) flipped LCD F80B `0x80 → 0x90` (bit 4 SET) exactly inside the gadget's
hop window; TEST 2 (no key, byte-for-byte identical walk) left F80B at `0x80`. r0 at the CMP
is the KEYSCAN scan result of the immediately preceding hop (`r0=01` held / `r0=00` none).
Scripts: `rop_br1.lua` (test 2), `rop_br1_hold.lua` (test 1 shim: sets `BR1_HOLD="1"` global,
dofiles rop_br1.lua). Base: `rop_draw3.lua` final-phase + flood-march payload; md5 `fed27f1a9b3e9a9c426160384bfc0b55` (untouched).

## Commands run (2 runs, both `timeout 240`-terminated by design — all decisive evidence lands by `WATCH t=160001`)

```
cd /home/yoxu/Projects/fx991espplus2nd/research/CasioEmuX && SDL_VIDEODRIVER=dummy timeout 240 ./emulator/emulator model=models/fx991esplus2 script=rop_br1_hold.lua  # Test 1 (exit 124)
pgrep -af emulator   # empty before each run
cd /home/yoxu/Projects/fx991espplus2nd/research/CasioEmuX && SDL_VIDEODRIVER=dummy timeout 240 ./emulator/emulator model=models/fx991esplus2 script=rop_br1.lua           # Test 2 (exit 124)
```
Log: `/tmp/rop_br1_t1c.out` (held), `/tmp/rop_br1_t2b.out` (no key).

## Fix history (why the first br1 invocation was NO-TRIGGER *)

1. **EXE never pressed** — old code ran `Keyboard:PressKey(0x37)` (Right) where draw3 runs
   `Keyboard:PressKey(0x60)` (EXE) at `final_t==40001`: the chain never started (prior
   `tiles=40/41 pc=4B96 sp=8D74`). Fixed.
2. **os.getenv unreliable here** — first held attempt used an env-var switch
   (`ROP_BR1_HOLD=1`); the emulator process never saw it (`WATCH: 16x hold=none`). Replaced
   with a global flag set by the `rop_br1_hold.lua` shim.
3. **Branch-word placement (in the headed payload) was a CSR slot** — first real chain run
   (no-head variant of the old payload) showed the walk consumed W(76)=0x4CDC as csr
   (`PPC-2B1E #11: sp=8DBA nxt=4D0E 4CDC 4D0E 4D0E`, break counts all zero). The user's
   minimal no-head payload moved the walk base to sp=0x8DA0, which makes W(76) a genuine
   hop start (see trace below).

## Gadget table

| addr | encoding/asm | condition | outcome |
|---|---|---|---|
| 0x4CDC | `CMP R0,#0` + `BC EQ,0x4CD6` | r0 = KEYSCAN result of the previous hop | r0≠0 falls through to 0x4CE0; r0=0 branches to 0x4CD6 |
| 0x4CD6 | RB 0F80Bh.4; RT | branch target (no key) | clears F80B bit 4 (or leaves it), RT = pop (pc,csr) from march → march continues |
| 0x4CE0 | SB 0F80Bh.4; RT | fall-through (key held) | sets F80B bit 4 (0x10), RT → march continues |
| 0x2B1E | (arrival gadget) POP PC | warhead hop | pops pc=word[sp], csr=word[sp+2]; lr stays 0x2B1E through the march |

Alternate 0x4CF2/D7C variant rejected — bank-clobbered (task note). Bank-aware breaks are
required: `break_at` matches `(csr<<16)|(pc&~1)` (`lua-common.lua`); break keys in the sampler
are `csr:addr`.

## Payload (typed at 0x8154, len=100)

- `0E 4D` flood (0x4D0E = KEYSCAN + csr word) at all even offsets — the ROP data stack.
- `W(36,0x4EF2) W(38,0x4EF2)` — park doubled (0x4EF2 = park head; ends the march).
- `W(76,0x4CDC)` — branch gadget on a hop start. No head/memcpy → no r0 clobber between
  the KEYSCAN hop and the CMP.

## Hop alignment (measured, no-head walk)

| hop / event | verbatim evidence |
|---|---|
| walk entry at sp=0x8DA0, hop starts 0x8DA0+4k (offsets 48, 52, … 72, 76) | `CHAIN: KEYSCAN #1 … sp=8DA0` → `#7 … sp=8DB8` → `PPC-2B1E #15: sp=8DB8 nxt=4D0E 4D0E 4CDC 4D0E` |
| hop at 0x8DBC pops pc=W(76)=0x4CDC → gadget executes mid-march, lr=0x2B1E | `CDC-WALK[lr=2B1E] t=1548627 sp=8DC0 r0=01 … cnt=1` (×6 hits held; ×8 no-key) |
| march resumes | `CHAIN: KEYSCAN #9 … sp=8DC4 nxt=4CDC 4D0E …` |
| march ends | `PROTO: NO-TRIGGER hits=22 pc=4B96 sp=8D7A`, park `WATCH: … tiles=1329 hits=22 … g38=21 gbe=480 store=480` (both runs identical) |

## Decisive lines — TEST 1 (Right held through the walk)

```
WATCH: 16x hold=RIGHT
CHAIN: KEYSCAN #8 ER0=0001 pc=4D20 sp=8DBC lr=2B1E … lcd01=…40004000408000…   ← F80B=0x80
CDC-WALK[lr=2B1E] t=1548627 sp=8DC0 r0=01 ER0=0001 preF80B=80 F80C=00 cnt=1   ← CMP sees r0=0x01
CHAIN: KEYSCAN #9 ER0=0001 pc=4D20 sp=8DC4 lr=2B1E … lcd01=…40004000409000…   ← F80B=0x90: BIT 4 SET (SB)
```

## Decisive lines — TEST 2 (no key released-all, walk identical)

```
WATCH: 16x hold=none
CHAIN: KEYSCAN #8 ER0=0000 pc=4D20 sp=8DBC lr=2B1E … lcd01=…40004000408000…   ← F80B=0x80
CDC-WALK[lr=2B1E] t=1548627 sp=8DC0 r0=00 ER0=0000 preF80B=80 F80C=00 cnt=1   ← CMP sees r0=0x00
CHAIN: KEYSCAN #9 ER0=0000 pc=4D20 sp=8DC4 lr=2B1E … lcd01=…40004000408000…   ← F80B stays 0x80: BIT 4 CLEAR (RB)
```

Both runs: every KEYSCAN entry sp, the CDC sp (8DC0), tiles (1329), g38/gbe/store counters
IDENTICAL — the only divergence at the gadget is r0 (0x01 vs 0x00), and only the r0=01 run
writes F80B.4. `final-F80B=00` in both (app refresh reclaims the LCD after park — expected;
the decisive read is the in-walk KEYSCAN #8→#9 window).

## Status matrix (updated)

| Capability | Status |
|---|---|
| Typed chain: no memory side effects | SUPERSEDED |
| Typed chain: keyscan hop + return | SUPERSEDED |
| Typed chain: keyscan + RAM write / memcpy12 LCD row-0 draw | SUPERSEDED (draw3: VERIFIED) |
| **Key-conditional branch inside the walk (r0 + CMP + SB/RB)** | **SUCCESS** |
| Persistent on-screen artifact | not yet (draw is transient under the parked refresh) |
| Loop / SP pivot | OPEN — untested candidates: 0x2D5C, 0x5238, 0x75DE, 0x10F4C |

## Next step (loop / SP pivot — NOT tested this turn)

The gadget proves key-value flow into conditionals inside the march. For a loop (re-run the
march without retyping), the open problem is bouncing SP back into the payload window after
the park: candidates logged by the prior worker are the SP-pivot gadgets at **0x2D5C,
0x5238, 0x75DE, 0x10F4C** (LEA/ADD SP-imm shapes) — none executed or disassembled this turn;
a follow-up should bank-aware-break those addresses and read regs at first hit during the
same 0x4D0E-flood walk, then pivot SP to 0x8DA0+4k to replay the march with the 0x4CDC state
(bit4 held) doubling as a loop counter.
