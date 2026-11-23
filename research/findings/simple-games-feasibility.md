# Simple Games Feasibility — fx-991ES PLUS 2nd (CY-845), verified rewrite 2026-11-22

## 0. The constraint (verified: emulator + binary 4dcb0b1c)
- Typed free-running ROP loop, ~11–19 beats/pass, zero net stack; per pass: **one memcpy12 + one key-conditional branch**. No arithmetic, no RAM counter, no variable draw address.
- Input: raw matrix KID in R2 → KEYSCAN `0x4D0E` gives key presence (1 bit) + column group Ki6 vs Ki7 (Left/Down vs Right/Up). **Only 1 clean input bit.** Four-way NOT achieved: the 0x38FC bit latches unconditionally; row-select grid unmeasured; app key service `0x8508` not callable.
- State: one latch bit `F80B.4` — the LCD status-bar "Disp" pixel (wiki Display maps F80B bit4="Disp"). Nothing else writable-and-visible is mapped.
- Display: full-screen static image via draw window `0x87D0..0x894F` + app refresh `0x35AE`; LCD keeps the image (persistent). Harness can re-kick per frame (12-frame GIF proven). Typed payload ≤4 designed rows per 100-byte tile; typing is seconds/byte (flash-walk).
- **Therefore: on hardware the only interactive effect is one visible bit over a static image. Any per-input display change is harness-only.**

## 1. What the community actually has (all fetch-verified 2026-11-22)
Every artifact is an exploit/display hack; **no playable game on fx-ES PLUS hardware was found.**
- casiocalc.wikidot.com documents: Basic Overflow (input-area cursor past 100 bytes); Hackstring (100-byte input repeated over `0x8154..0x8E00` via `strcpy(0x81B8,0x8154)` after `[AC][◀]`); Display (memory-mapped LCD `0xF800..0xF9FF`, 32×96 px, 12 bytes/row); Mode 68 and `r`-misindexing (mode-confusion display/menu glitches). None is a game.
- Forum thread 7583 p.9, post #323 (anon34): ROP tutorial — hackstring replication, gadget rules ("jump to the command right after `push lr`"), and two useful ROM calls: `0:343e` "print r2 lines on the screen using the string pointed to by er0" and `0:b654` "blinks the cursor and waits for the user to press the key shift". So the one community-verified hardware "interactive" is **draw text → wait for a key**.
- wiki Timer: a hackstring "repeatedly give[s] input = TT to hardware function 0:4640, and then increase[s] the value on the LCD screen" with wait SFR `0xF020` ("129A ≈ half cursor cycle ≈ 0.5 s") — a per-pass timing hook, page itself says details "need verification later". Not linked into our chain.
- Hackaday.io #28444 (SopaXorzTaker): code-exec project, 0 logs, no games. Itay2805/fx991es-hacking: tooling only; points to user202729/fxesplus + ZaoHan415/fxesplus (both reachable, contents unaudited).
- YouTube: search surfaced only calculator tutorials; the "Tetris for TI-83/84" video whose description mentions fx-991ES shows no ES-hardware game — **unsourced claim, not counted.** Baidu tieba threads (1735724120, 387740790) behind wiki citations not fetchable — mode-68/r claims are secondhand.

## 2. One-bit game-design literature (fetched)
- Berbank Green, "One Button Games" (Game Developer, 2005): "our button has two states: Pressed and released"; the design space lives in **timing** (release-proportional charge), **toggles**, and **context** — all need game state.
- abagames, "How to realize various actions in a one-button game" (dev.to, 2022): catalog of actions — reverse direction, teleport, split, charge-and-release, hold-to-defend. **Every one of them requires a game clock and/or held-duration measurement.** A one-button input is a design liberation on normal hardware; on our set it collapses to "branch once per pass on one bit".
- Conclusion: classical 1-button games (Flappy, Dino, timing reaction) are 1-*bit-input* but never 1-*bit-state*; they need counters and timers we do not have.

## 3. Strict table
| Candidate | Mechanic (verified quote/source) | Input | State | Verdict — missing primitive |
|---|---|---|---|---|
| Key tester (indicator-on) | Any key in scanned row → one status pixel lights; release → dark | presence bit | none | **FEASIBLE** (uses our loop verbatim) |
| Ki6/Ki7 two-way pointer | Branch picks which of two 12-byte strips the pass's memcpy12 draws (arrow ◀ vs ▶) | Ki column bit | none | **NOT (unproven) — needs an asymmetric branch that skips a POP/consumes different stack bytes** |
| Static art gallery | Typable ≤4-row full-screen payload, app refresh keeps it | none | none | **FEASIBLE** but zero interactivity |
| Harness slideshow / 12-frame GIF | Harness re-kicks `0x35AE`-style refresh with new payload per frame | none (host-driven) | host | **PARTIAL** — harness-only; hardware typing too slow per frame |
| ROM key-wait demo | `0:b654` "blinks… waits for shift" after `0:343e` print | ROM-polled key | ROM | **PARTIAL** — ROM function, not our loop; same 1-bit semantics |
| Timer sweep (wiki 0x4640) | Wait SFR `0xF020`, per-pass count on LCD | none | counter | **PARTIAL** — page unverified; we lack counter+display-of-count |
| Reaction "Toy" (moving dot, press to stop) | dot position advance + score | 1 bit | position/timer | **NOT** — old file's claim; dot motion needs a variable draw address; "one visible bit ≠ dot moves" |
| Slideshow/Selector (per-input image change) | full-screen switch per keypress | 1 bit | mode byte | **NOT** on hardware — needs second writable display path; harness-only |
| Simon / sequence-memory | record+compare key sequence | 1 bit | ≥1 byte memory | **NOT** — no writable state beyond F80B.4 |
| 2048 / Snake / Pong / Tetris / Dino / Flappy | position, RNG, gravity, score | ≥1 clean 4-way | counters+ticker | **NOT** — no counters, no timestamps, no 4-way input |
| Morse trainer | tap patterns judged | presence bit | timeout+match | **NOT** — no elapsed-time measurement |
| Coin flip / random picker | RNG fallback | none | PRNG state | **NOT** — no arithmetic or entropy source |
| Menu-style two-choice quiz | pick A/B, screen "grades" you | Ki bit | score | **NOT** — per-input image change impossible on hardware |

## 4. Top-3 honest demos (only our primitives)
1. **Key tester map** — static full-screen art: a drawn keypad grid with a single marker pixel in the status bar (F80B.4 via the latch). Chain per pass: memcpy12(art row) → KEYSCAN → conditional → set/clear `F80B.4` → loop. Player sees *exactly one pixel* answer "any key held". Not a game: no scoring, no target key feedback.
2. **One-bit indicator over static art** — same chain, art swaps labels for a target pixel; the single `F80B.4` status-bar bit (set/cleared by the key-conditional) is the only moving element. Not a game: 1 outcome, no win/lose, no positions.
3. **Harness slideshow/GIF** — emulator/host re-kicks the refresh each frame with successive payloads (12-frame GIF already proven). One frame per payload on hardware = a typing marathon, so it is a testbed demo, not an artifact. Player experience: a looping animation with **no input coupling**.

## 5. Roadmap — missing primitive → unlocked games
- **Second clean conditional bit** (measure row-select grid, or find a clean `CMP R2,#imm`; kill the 0x38FC unconditional latch) → 4-way selector → maze-steps, menu games, 2×2 mini-Simon.
- **RAM counter / increment-and-store gadget** → score, streaks, Cgame-style minigames; with the Timer hook → **reaction/rhythm trainer**, hold-duration mechanic (Green's "charged shot").
- **Timer hook**: wire ROM `0x4640` wait + `0xF020` period into the loop (wiki Timer is unverified — first task is a probe) → deterministic game clock → every abagames action type becomes viable.
- **Variable draw address** (indexable dst/src for memcpy12) → moving dot → Dino-jump-over, Pong-lite, Snake-lite corridors.
- **Writable persistent state byte** (beyond `F80B.4`) → Simon sequences, 2048-style boards, high-score persist.
- **Callable app key service `0x8508`** → decoded keycodes (0x26/0x27/0x36/0x37 arrows...) → real 4-direction games without new gadget hunting.
Each unlock composes: counter+timer gives timing games; counter+variable address gives Snake/2048-class games.

## 6. Sources (fetched 2026-11-22 unless noted)
- https://casiocalc.wikidot.com/ (index: Hackstring, Display, Basic Overflow, Mode 68, Timer, Applications of r)
- https://community.casiocalc.org/topic/7583-fx-82-83gt-115-991es-plus-hacking/page-9 (post #323)
- https://hackaday.io/project/28446-casio-fx-es-plus-reverse-engineering-project
- https://github.com/Itay2805/fx991es-hacking (links user202729/fxesplus, ZaoHan415/fxesplus — HTTP 200, unaudited)
- https://www.gamedeveloper.com/design/one-button-games (Green, 2005); https://dev.to/abagames/how-to-realize-various-actions-in-a-one-button-game-fak (2022)
- Unsourced/unfetched: tieba.baidu.com/p/1735724120 & /387740790 (mode-68, wiki-cited only); any YouTube "game" on fx-ES hardware (none found).
