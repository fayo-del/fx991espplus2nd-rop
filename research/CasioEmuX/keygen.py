#!/usr/bin/env python3
"""keygen.py — CY-845 (fx-991ES PLUS 2nd ed) payload -> physical keypress generator.

Maps a zero-free 100-byte payload (the bytes that must land at 0x8154..0x81B7)
to an ordered list of physical keypresses on the real calculator:

  * direct chord: a byte present in one of the ROM keycode tables
    (base_keycodes.txt / shift_keycodes.txt / alpha_keycodes.txt at the repo
    root, indexed by matrix slot ix = ki*8 + ko, ki = code&0xF, ko = code>>4)
    at a scancode bound to a physical key  ->  [optional SHIFT/ALPHA] + key.
  * walk (hack #7, HW-verified 2026-11-19): byte not in any keycode slot ->
    type a seed chord (a typeable byte near the target), wait for the cursor
    flash (>= 1 blink period, ~1.5-3 s on hardware), then press Right(0x37)/
    Left(0x26) N times: each flash-verified arrow press advances the entered
    symbol by one symbol-table entry (byte-order assumption, Sheet-B tell).

Usage:
  python3 keygen.py [--payload-hex HEX] [--payload-file F] [--ref]
                    [--safe] [--out PREFIX]
Defaults to the reference payload (rop_e2e.lua, md5 5faa9fe7249d21d1dc6c6fde2fcf4c74).

Outputs:
  PREFIX_runbook.md     ordered keypress table (step, key, byte, confidence)
  PREFIX_schedule.lua   Lua schedule consumed by keypress_replay.lua
  PREFIX_summary.txt    counts + untypeable-byte report
"""
import argparse, hashlib, os, sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # repo root
SHIFT, ALPHA = 0x07, 0x17

def load_tables():
    tabs = {}
    for n in ("base", "shift", "alpha"):
        tabs[n] = [int(t, 16) for t in open(os.path.join(REPO, f"{n}_keycodes.txt")).read().split()]
    return tabs

def ix(code):  # matrix slot index used by the ROM keycode tables
    return (code & 0xF) * 8 + ((code >> 4) & 0xF)

# 49 physical keys (models/fx991esplus2/model.lua button grid)
PHYS = [0x02,0x12,0x22,0x32,0x42, 0x01,0x11,0x21,0x31,0x41,
        0x00,0x10,0x20,0x30,0x40, 0x64,0x63,0x62,0x61,0x60,
        0x05,0x15,0x25,0x35,0x45,0x55, 0x04,0x14,0x24,0x34,0x44,0x54,
        0x03,0x13,0x23,0x33,0x43,0x53, 0x06,0x16,0x46,0x56, 0x07,0xFF,0x17,0x47,
        0x26,0x27,0x36,0x37]

NAME = {
    0x00:"1",0x10:"2",0x20:"3",0x30:"+",0x40:"-",0x60:"EXE (=)",
    0x01:"4",0x11:"5",0x21:"6",0x31:"×",0x41:"÷",0x61:"Ans",
    0x02:"7",0x12:"8",0x22:"9",0x32:"DEL",0x42:"AC/ON",0x62:"×10ˣ",
    0x64:"0",0x63:".",0x23:"(",0x33:")",0x06:"CALC",0x56:"log/Σ key",
    0x46:"fn key 0x46 (F7 row)",0x07:"SHIFT",0x17:"ALPHA",0x47:"MODE",0xFF:"ON",
    0x26:"◀ (Left)",0x27:"↑ (Up)",0x36:"↓ (Down)",0x37:"▶ (Right)",
    0x03:"fn 0x03",0x13:"fn 0x13",0x43:"fn 0x43",0x53:"M+ key (0x53)",
    0x05:"fn 0x05",0x15:"fn 0x15",0x25:"fn 0x25",0x35:"fn 0x35",0x45:"fn 0x45",0x55:"fn 0x55",
    0x04:"fn 0x04",0x14:"fn 0x14",0x24:"fn 0x24",0x34:"fn 0x34",0x44:"fn 0x44",0x54:"fn 0x54",
    0x16:"fn 0x16 (F6)",
}

# Emulator-measured landings (docs/physical-calc.md §6 atlas, rop_typed_e* runs):
# bytes confirmed to land at 0x8154 by a chord in the emulator.
MEASURED = set([0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x2B,0x2D,0x4E,0x4F,
                0x8B,0x74,0x81,0x82,0x28,0x29,0x25,0x2C,0x2E,0xC2,0x3A,0x3D,
                0xBE,0xBF,0x6C,0x6D,0x57,0x58,0x59,0x41,0x54,0xB3])
# multi-byte templates measured in the post-AC,◀ overflow state
TEMPLATES = {0x69: ("SHIFT+log/Σ", [(SHIFT,0x56)], [0x69,0xB8]),
             0x68: ("log key",   [(None,0x56)],    [0x68,0xB8]),
             0x6B: ("SHIFT+CALC",[(SHIFT,0x06)],   [0x6B,0xB8])}

REF_PAYLOAD = bytes.fromhex("0E4D"*24 + "3835" + "3835" + "01F8" + "BE35" + "5481" + "0E4D"*21)
REF_MD5 = "5faa9fe7249d21d1dc6c6fde2fcf4c74"

# Entry recipe (rop_e2e.lua typed queue, verified) — 41 presses.
# (code, label) ; chords are expanded to modifier+key presses.
RECIPE = [
    (0x07,"SHIFT w1"),(0x42,"AC w2"),
    (0x07,"SHIFT"),(0x47,"MODE"),(0x10,"2"),
    (0x07,"SHIFT"),(0x56,"Σ verify1"),
    (0x07,"SHIFT"),(0x47,"MODE"),(0x10,"2"),
    (0x07,"SHIFT"),(0x56,"Σ verify2"),
    (0x42,"AC clear"),
    (0x17,"ALPHA"),(0x33,"X"), (0x17,"ALPHA"),(0x06,"= (CALC)"),
    (0x07,"SHIFT"),(0x56,"Σ("), (0x17,"ALPHA"),(0x33,"X"),
    (0x07,"SHIFT"),(0x33,","), (0x00,"1"), (0x07,"SHIFT"),(0x33,","), (0x00,"1"),
    (0x62,"×10ˣ"),(0x22,"9"),
    (0x06,"CALC"),(0x60,"EXE"),(0x42,"AC"),(0x26,"◀"),
    (0x32,"DEL"),(0x32,"DEL"),(0x32,"DEL"),(0x10,"2"),
    (0x06,"CALC"),(0x60,"EXE"),(0x26,"◀"),(0x00,"PROBE 1"),
]
# Trigger after the payload is typed: hold ▶ (KEYSCAN r0=1), then EXE.
TRIGGER = [(0x37,"▶ hold (r0=1)"),(0x60,"EXE trigger")]

def build_direct(tabs, safe):
    """byte -> list of (presses, conf, [(mod,code)], name) candidates, physical keys only."""
    direct = {}
    for mod, mname in (("base",None),("shift",SHIFT),("alpha",ALPHA)):
        for code in PHYS:
            b = tabs[mod][ix(code)]
            if not b: continue
            conf = "measured" if b in MEASURED else "table-only"
            if safe and conf != "measured": continue
            presses = 1 if mname is None else 2
            direct.setdefault(b, []).append((presses, conf, [(mname, code)],
                (NAME.get(code, f"0x{code:02X}")) + ("" if mname is None else f" with {'SHIFT' if mname==SHIFT else 'ALPHA'}")))
    for b in direct:
        direct[b].sort(key=lambda c: (c[0], c[1] != "measured"))
    return direct

def walk_steps(byte, direct, safe, wait_ticks=200000):
    """hack-#7 walk encoding: seed chord + flash-wait + N arrow presses."""
    best = None
    for s, cands in direct.items():
        for presses, conf, ch, name in cands:
            d = (byte - s) % 255
            if d == 0:
                continue  # that's the direct case
            if d <= 127: arrows, code, direction = d, 0x37, "▶"
            else:        arrows, code, direction = 255 - d, 0x26, "◀"
            cost = presses + arrows
            if best is None or cost < best[0]:
                best = (cost, s, presses, conf, ch, name, arrows, code, direction)
    if best is None:
        return None
    cost, s, presses, conf, ch, name, arrows, code, direction = best
    steps = []
    for mod, code_ in ch:
        steps.append({"kind":"key","mod":mod,"code":code_,"name":NAME.get(code_,f"0x{code_:02X}"),
                      "seed":s,"conf":conf,"note":f"seed {s:02X} ({name})"})
    steps.append({"kind":"wait","ticks":wait_ticks,"note":f"cursor flash wait before walk ({direction}×{arrows} to {byte:02X})"})
    for i in range(arrows):
        steps.append({"kind":"key","code":code,"name":NAME[code],"walk":True,
                      "note":f"walk {direction} #{i+1}/{arrows} → {byte:02X}"})
    return steps, cost

def encode(payload, tabs, safe=False, wait_ticks=200000):
    direct = build_direct(tabs, safe)
    steps, report = [], []
    for off, b in enumerate(payload):
        if b == 0:
            report.append(f"offset {off}: byte 00 is NOT typeable (strcpy terminator) — payload invalid")
            continue
        if b in direct:
            presses, conf, ch, name = direct[b][0]
            for mod, code in ch:
                steps.append({"kind":"key","mod":mod,"code":code,"name":NAME.get(code,f"0x{code:02X}"),
                              "byte":b,"conf":conf,"note":f"direct chord → {b:02X} ({name})"})
            report.append(f"offset {off:2d}: byte {b:02X} direct chord ({name}), {presses} press(es), {conf}")
        elif b in TEMPLATES:
            name, ch, bytes_ = TEMPLATES[b]
            report.append(f"offset {off:2d}: byte {b:02X} via 2-byte template {name} → {' '.join(f'{x:02X}' for x in bytes_)} (measured)")
            steps.append({"kind":"template","chords":ch,"bytes":bytes_,"conf":"measured","note":name})
        else:
            w = walk_steps(b, direct, safe, wait_ticks)
            if w is None:
                report.append(f"offset {off:2d}: byte {b:02X} UNTYPEABLE (no chord, no seed) — no substitute possible")
                continue
            wsteps, cost = w
            for st in wsteps: st["byte"] = b
            steps.extend(wsteps)
            seed = wsteps[0].get("seed", "?")
            report.append(f"offset {off:2d}: byte {b:02X} NO direct chord → hack-#7 walk from seed {seed:02X}, "
                          f"{cost} presses (incl. seed), flash-wait + arrows")
    return steps, report, direct

def keypress_count(steps):
    # each key entry = 1 press, +1 if it carries a SHIFT/ALPHA modifier press
    return sum(1 + (1 if s.get("mod") else 0) for s in steps if s["kind"] == "key")

def emit_runbook(steps, payload, out, extra_recipe=True):
    lines = []
    n = 0
    def row(step):
        nonlocal n
        n += 1
        if step["kind"] == "wait":
            return f"| {n} | — WAIT {step['ticks']} ticks — | — | {step['note']} |"
        mod = step.get("mod")
        key = f"{'SHIFT ' if mod==SHIFT else 'ALPHA ' if mod==ALPHA else ''}{step['name']}"
        code = step["code"]
        b = step.get("byte")
        return f"| {n} | {key} (0x{code:02X}) | 0x{code:02X} | {('0x%02X'%b) if b is not None else '—'} | {step.get('note','')} |"
    lines.append("# Hardware runbook — generated by keygen.py")
    lines.append(f"\nPayload md5: `{hashlib.md5(payload).hexdigest()}` ({len(payload)} bytes at 0x8154)")
    lines.append("\n| step | physical key (scancode) | code | byte landed | note |")
    lines.append("|---|---|---|---|---|")
    if extra_recipe:
        for code, label in RECIPE:
            n += 1
            lines.append(f"| {n} | {label} (0x{code:02X}) | 0x{code:02X} | — | entry recipe (rop_e2e.lua) |")
        for code, label in [(0x42,"AC"),(0x26,"◀"),(0x32,"DEL")]:
            n += 1
            lines.append(f"| {n} | {label} (0x{code:02X}) | 0x{code:02X} | — | trigger prefix AC ◀ (overflow state) |")
    for s in steps:
        lines.append(row(s))
    if extra_recipe:
        for code, label in TRIGGER:
            n += 1
            lines.append(f"| {n} | {label} (0x{code:02X}) | 0x{code:02X} | — | trigger |")
    lines.append(f"\n**Total physical keypresses: {len(RECIPE)+3+keypress_count(steps)+len(TRIGGER)}** "
                 f"(recipe {len(RECIPE)} + AC,◀,DEL 3 + payload {keypress_count(steps)} + trigger {len(TRIGGER)}); "
                 f"{sum(1 for s in steps if s['kind']=='wait')} flash-waits are timing gaps, not keypresses. Table rows above: {n} (waits included).")
    open(out, "w").write("\n".join(lines) + "\n")

def emit_schedule(steps, out):
    L = ["-- generated by keygen.py — do not edit",
         "-- each entry: {code=, mod=, name=, byte=, note=} ; kind=wait entries carry ticks=",
         "return {"]
    for s in steps:
        if s["kind"] == "wait":
            L.append(f'  {{kind="wait", ticks={s["ticks"]}, note="{s["note"]}"}},')
        elif s["kind"] == "template":
            L.append(f'  {{kind="template", chords={{{...}}}, bytes={{...}}, note="{s["note"]}"}},')
        else:
            mod = s.get("mod")
            modstr = "nil" if mod is None else f"0x{mod:02X}"
            b = s.get("byte")
            bstr = "nil" if b is None else f"0x{b:02X}"
            walk = ", walk=true" if s.get("walk") else ""
            L.append(f'  {{kind="key", code=0x{s["code"]:02X}, mod={modstr}, byte={bstr}, name="{s["name"]}"{walk}, note="{s.get("note","")}"}},')
    L.append("}")
    open(out, "w").write("\n".join(L) + "\n")

def emit_summary(report, steps, payload, out):
    untypable = [r for r in report if "UNTYPEABLE" in r or "NO direct chord" in r]
    txt = ["# keygen summary", f"payload md5 {hashlib.md5(payload).hexdigest()} len {len(payload)}",
           f"payload keypresses: {keypress_count(steps)}",
           f"full runbook presses (recipe+AC,◀,DEL+payload+trigger): {len(RECIPE)+3+keypress_count(steps)+len(TRIGGER)}",
           "", "## per-offset encoding"] + report + \
          ["", "## walk-only bytes (hack #7 needed on hardware)"] + \
          [r for r in report if "NO direct chord" in r] or ["(none)"]
    open(out, "w").write("\n".join(txt) + "\n")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--payload-hex", default=None)
    ap.add_argument("--payload-file", default=None)
    ap.add_argument("--ref", action="store_true", help="use the reference payload (default)")
    ap.add_argument("--safe", action="store_true", help="only emulator-measured chords/seeds")
    ap.add_argument("--wait", type=int, default=200000, help="flash-wait ticks per walk (hardware: >=1 blink period ~1.5-3 s)")
    ap.add_argument("--out", default="keypress_out")
    a = ap.parse_args()
    if a.payload_file:
        payload = bytes.fromhex(open(a.payload_file).read().strip())
    elif a.payload_hex:
        payload = bytes.fromhex(a.payload_hex.replace(" ", ""))
    else:
        payload = REF_PAYLOAD
    assert hashlib.md5(payload).hexdigest() == REF_MD5 or a.payload_hex or a.payload_file, "ref md5 mismatch"
    print(f"payload: len={len(payload)} md5={hashlib.md5(payload).hexdigest()}")
    tabs = load_tables()
    steps, report, direct = encode(payload, tabs, safe=a.safe, wait_ticks=a.wait)
    for r in report: print(r)
    kc = keypress_count(steps)
    total = len(RECIPE) + 3 + kc + len(TRIGGER)
    print(f"payload keypresses: {kc}   full runbook: {total} presses "
          f"(recipe {len(RECIPE)} + AC,◀,DEL 3 + payload {kc} + trigger {len(TRIGGER)})")
    zero = [i for i, b in enumerate(payload) if b == 0]
    if zero: print("WARNING zero bytes at offsets", zero, "(strcpy terminates — payload must be zero-free)")
    emit_runbook(steps, payload, a.out + "_runbook.md")
    emit_schedule(steps, a.out + "_schedule.lua")
    emit_summary(report, steps, payload, a.out + "_summary.txt")
    print("wrote", a.out + "_runbook.md", a.out + "_schedule.lua", a.out + "_summary.txt")

if __name__ == "__main__":
    main()
