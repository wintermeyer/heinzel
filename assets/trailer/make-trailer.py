#!/usr/bin/env python3
"""Render the heinzel trailer (the GIF at the top of README.md).

The whole trailer is scripted below: nothing is recorded. Edit SCENES,
run this file, commit the new GIF. See README.md next to this script.
"""
import argparse
import os
import re
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

W, H, FPS = 1280, 720, 20
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_GIF = os.path.join(HERE, "..", "heinzel-trailer.gif")
MENLO = "/System/Library/Fonts/Menlo.ttc"  # index 0 regular, 1 bold


def hexrgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


BG = hexrgb("#0d1117")
BAR = hexrgb("#1c2330")
COL = {
    "f": hexrgb("#e6edf3"),  # foreground
    "d": hexrgb("#8b949e"),  # dim
    "g": hexrgb("#3fb950"),
    "r": hexrgb("#f85149"),
    "y": hexrgb("#e3b341"),
    "b": hexrgb("#58a6ff"),
    "c": hexrgb("#39c5cf"),
    "m": hexrgb("#bc8cff"),
}


def mix(c, a):
    return tuple(round(BG[i] + (c[i] - BG[i]) * a) for i in range(3))


# Fixed palette: every colour plus the blends its anti-aliasing needs.
# A GIF holds 256 colours; staying at 32 or fewer keeps the file small.
PALETTE = [BG, BAR]
for key, steps in (("f", 4), ("d", 3), ("g", 3), ("r", 3), ("y", 3),
                   ("b", 3), ("c", 3), ("m", 3)):
    PALETTE += [mix(COL[key], (i + 1) / steps) for i in range(steps)]
assert len(PALETTE) <= 32, len(PALETTE)
PAL_IMG = Image.new("P", (16, 16))
PAL_IMG.putpalette([v for c in PALETTE for v in c]
                   + list(BG) * (256 - len(PALETTE)))


def font(size, bold=False):
    return ImageFont.truetype(MENLO, size, index=1 if bold else 0)


F_TERM, F_TERM_B = font(25), font(25, True)
F_CAP = font(33, True)
F_BAR, F_BAR_B = font(17), font(20, True)
CW = F_TERM.getlength("M")
LH = 36

WIN = (48, 36, W - 48, 590)  # the terminal window
BAR_H = 40
CAP_Y = 652
COLS = int((WIN[2] - WIN[0] - 52) / CW)

TAG = re.compile(r"<(/|[a-zA-Z])>")


def segs(markup):
    """'<g>ok</> text' -> [(text, colour, bold)]. Upper-case tag = bold."""
    out, pos, cur, bold = [], 0, "f", False
    for m in TAG.finditer(markup):
        if m.start() > pos:
            out.append((markup[pos:m.start()], cur, bold))
        t = m.group(1)
        cur, bold = ("f", False) if t == "/" else (t.lower(), t.isupper())
        pos = m.end()
    if pos < len(markup):
        out.append((markup[pos:], cur, bold))
    return out


def plain_len(markup):
    return sum(len(s[0]) for s in segs(markup))


def cut(markup, n):
    out = []
    for text, col, bold in segs(markup):
        if n <= 0:
            break
        out.append((text[:n], col, bold))
        n -= len(text)
    return out


def draw_segs(d, x, y, parts):
    for text, col, bold in parts:
        d.text((x, y), text, font=F_TERM_B if bold else F_TERM, fill=COL[col])
        x += CW * len(text)
    return x


def blank():
    img = Image.new("RGB", (W, H), BG)
    return img, ImageDraw.Draw(img)


def window(caption, title):
    img, d = blank()
    d.rounded_rectangle(WIN, 12, fill=BG, outline=mix(COL["d"], 2 / 3), width=2)
    d.rounded_rectangle((WIN[0] + 2, WIN[1] + 2, WIN[2] - 2, WIN[1] + BAR_H),
                        10, fill=BAR)
    d.rectangle((WIN[0] + 2, WIN[1] + 20, WIN[2] - 2, WIN[1] + BAR_H), fill=BAR)
    for i, k in enumerate("ryg"):
        cx = WIN[0] + 24 + i * 22
        d.ellipse((cx - 7, WIN[1] + 14, cx + 7, WIN[1] + 28), fill=COL[k])
    d.text((W / 2, WIN[1] + 21), title, font=F_BAR, fill=COL["d"], anchor="mm")
    parts = segs(caption)
    x = (W - sum(F_CAP.getlength(p[0]) for p in parts)) / 2
    for text, col, _ in parts:
        d.text((x, CAP_Y), text, font=F_CAP, fill=COL[col], anchor="lm")
        x += F_CAP.getlength(text)
    return img, d


AI_PROMPT = [("❯ ", "m", True)]
SH_PROMPT = [("~/heinzel $ ", "d", False)]
FF = "▶▶ fast-forward"


class Terminal:
    """One scripted terminal scene.

    Steps, in order of appearance:
      ("type", text, secs)       the user types at the assistant prompt;
                                 "\\n" in text continues on the next line
      ("shell", text, secs)      the user types at the shell prompt
      ("out", markup[, gap])     a line of output, then `gap` seconds
      ("ask", markup, key, wait) a question; after `wait` seconds the
                                 user presses `key` (shown as a keycap)
      ("wait", secs)             nothing happens
      ("clear",)                 the screen is cleared
    """

    def __init__(self, caption, dur, steps, title="heinzel"):
        self.caption, self.dur, self.title = caption, dur, title
        self.events, t = [], 0.4
        for kind, *arg in steps:
            if kind in ("type", "shell"):
                markup, secs = arg
                prompt = AI_PROMPT if kind == "type" else SH_PROMPT
                self.events.append(("type", t, t + secs, markup, prompt))
                t += secs + 0.45
            elif kind == "out":
                self.events.append(("out", t, t, arg[0], None))
                t += arg[1] if len(arg) > 1 else 0.3
            elif kind == "ask":
                markup, key, wait = arg
                self.events.append(("ask", t, t + wait, markup, key))
                t += wait + 0.9
            elif kind == "clear":
                self.events.append(("clear", t, t, "", None))
                t += 0.35
            elif kind == "wait":
                t += arg[0]
            else:
                raise ValueError(kind)
        self.end = t
        # Leave the finished screen up for at least a second.
        assert self.end <= dur - 1.0, (caption, self.end, dur)
        for kind, _, _, markup, extra in self.events:
            pad = sum(len(p[0]) for p in extra) if kind == "type" else 0
            for line in markup.split("\n"):
                assert plain_len(line) + pad <= COLS, (COLS, line)

    def frame(self, t):
        img, d = window(self.caption, self.title)
        x0, y = WIN[0] + 26, WIN[1] + BAR_H + 18
        cleared = max([e[1] for e in self.events
                       if e[0] == "clear" and e[1] <= t], default=-1)
        live = [e for e in self.events if e[0] != "clear" and e[1] >= cleared]

        # The badge is up while heinzel works, off while the user acts.
        work = [e[1] for e in live if e[0] in ("out", "ask")]
        user = any(e[0] in ("ask", "type") and e[1] <= t < e[2] for e in live)
        if work and work[0] <= t < self.end and not user:
            d.text((WIN[2] - 22, WIN[1] + 21), FF, font=F_BAR_B,
                   fill=COL["y"], anchor="rm")

        cursor, drawn = None, False
        for kind, t0, t1, markup, extra in live:
            if t < t0:
                if not drawn and kind == "type":
                    cursor = (draw_segs(d, x0, y, extra), y)
                break
            drawn, cursor = True, None
            if kind == "out":
                draw_segs(d, x0, y, segs(markup))
                y += LH
            elif kind == "ask":
                x = draw_segs(d, x0, y, segs(markup))
                if t < t1:
                    cursor = (x, y) if int(t * 3) % 2 == 0 else None
                else:
                    draw_segs(d, x, y, [(extra, "g", True)])
                    if t < t1 + 0.9:
                        self.keycap(d, extra)
                y += LH
            else:
                y, cursor = self.typed(d, x0, y, t, t0, t1, markup, extra)
        if cursor:
            d.rectangle((cursor[0], cursor[1] + 1, cursor[0] + CW - 2,
                         cursor[1] + 29), fill=COL["f"])
        return img

    @staticmethod
    def typed(d, x0, y, t, t0, t1, markup, prompt):
        lines = markup.split("\n")
        total = sum(plain_len(line) for line in lines)
        shown = total if t >= t1 else int(total * (t - t0) / (t1 - t0))
        pad = [(" " * sum(len(p[0]) for p in prompt), "f", False)]
        cursor = None
        for i, line in enumerate(lines):
            take = min(shown, plain_len(line))
            x = draw_segs(d, x0, y, (pad if i else prompt) + cut(line, take))
            shown -= take
            y += LH
            if shown == 0 and (t < t1 or i == len(lines) - 1):
                if t < t1 + 0.45:
                    cursor = (x, y - LH)
                break
        return y, cursor

    @staticmethod
    def keycap(d, key):
        box = (WIN[2] - 150, WIN[3] - 124, WIN[2] - 50, WIN[3] - 34)
        d.rounded_rectangle(box, 14, fill=BAR, outline=COL["g"], width=3)
        d.text((WIN[2] - 100, WIN[3] - 82), key.upper(), font=font(46, True),
               fill=COL["g"], anchor="mm")


class MemorySlide:
    dur = 9.5
    tree = [
        "<F>memory/servers/",
        "<d>├─</> <B>app1.example.com/",
        "<d>│  ├─</> <g>memory.md</>       OS, hardware, services, quirks",
        "<d>│  ├─</> <g>changelog.log</>   every change, and how to undo it",
        "<d>│  ├─</> <g>todo.md</>         open steps of an interrupted job",
        "<d>│  └─</> <g>rules.md</>        your own rules for this server",
        "<d>├─</> <B>shop.example.com/",
        "<d>└─</> <B>web1.example.com/",
    ]
    notes = [
        (3.8, "<F>Before it connects, Heinzel reads these files. <g>No guessing."),
        (5.0, "<F>After every change, it updates them."),
        (6.2, "<F>Plain text: read it, edit it, share it with your team in git."),
    ]

    def frame(self, t):
        img, d = blank()
        d.text((W / 2, 78), "One folder per server", font=font(46, True),
               fill=COL["f"], anchor="mm")
        d.rounded_rectangle((130, 136, W - 130, 486), 14, fill=BAR,
                            outline=mix(COL["d"], 2 / 3), width=2)
        f, fb = font(26), font(26, True)
        cw = f.getlength("M")
        for i, line in enumerate(self.tree):
            if t < 0.3 + i * 0.35:
                break
            x = 170
            for text, col, bold in segs(line):
                d.text((x, 176 + i * 40), text, font=fb if bold else f,
                       fill=COL[col], anchor="lm")
                x += cw * len(text)
        fn = font(28, True)
        for i, (at, line) in enumerate(self.notes):
            if t < at:
                break
            parts = segs(line)
            x = (W - sum(fn.getlength(p[0]) for p in parts)) / 2
            for text, col, _ in parts:
                d.text((x, 546 + i * 52), text, font=fn, fill=COL[col],
                       anchor="lm")
                x += fn.getlength(text)
        return img


class EndCard:
    dur = 4.5
    steps = [
        ("$ ", "git clone https://github.com/wintermeyer/heinzel.git"),
        ("$ ", "cd heinzel && claude"),
        ("❯ ", "Describe your problem"),
    ]

    def frame(self, t):
        img, d = blank()
        d.text((W / 2, 150), "heinzel", font=font(104, True), fill=COL["f"],
               anchor="mm")
        d.text((W / 2, 250), "Free and open source", font=font(32, True),
               fill=COL["g"], anchor="mm")
        if t > 0.4:
            f = font(27)
            w = f.getlength("".join(self.steps[0]))
            x = (W - w) / 2
            d.rounded_rectangle((x - 34, 320, x + w + 34, 520), 12, fill=BAR,
                                outline=mix(COL["d"], 2 / 3), width=2)
            for i, (mark, text) in enumerate(self.steps):
                if t < 0.4 + i * 0.5:
                    break
                y = 366 + i * 54
                d.text((x, y), mark, font=f, fill=COL["m"], anchor="lm")
                d.text((x + f.getlength(mark), y), text, font=f,
                       fill=COL["f"], anchor="lm")
        if t > 1.9:
            d.text((W / 2, 590), "Works with Claude Code and OpenCode",
                   font=font(24), fill=COL["d"], anchor="mm")
        return img


AUTO = "claude --permission-mode auto"

# The storyboard. Hostnames are always *.example.com: this file is public.
SCENES = [
    Terminal("Say what's wrong. <g>In your own words.", 15.5, [
        ("shell", "claude", 0.7),
        ("wait", 0.3),
        ("clear",),
        ("type", "A client just called: his server shop.example.com is down. He\n"
                 "doesn't know what he did, and I have never been on that server.\n"
                 "Use my SSH key to log in as root and find the problem.", 4.8),
        ("out", "<b>●</> Logged in as root@shop.example.com with your SSH key", 0.5),
        ("out", "  <d>First visit: Debian 12, nginx, ufw. Saved to memory.", 0.6),
        ("out", "<b>●</> Looking for the cause <d>(read-only, nothing gets changed)", 0.8),
        ("out", "  <g>✓</> Disk and memory are fine", 0.5),
        ("out", "  <R>✗ The web server is not running", 0.6),
        ("out", "  <R>✗ The firewall blocks port 443 (https)", 0.9),
        ("out", ""),
        ("out", "<b>●</> <Y>Found two problems."),
        ("out", "  1. A typo in the web server's config, line 42. It won't start.", 0.5),
        ("out", "  2. The firewall has no rule for https. Visitors can't get in."),
    ]),
    Terminal("It explains. <g>You decide.", 11.5, [
        ("out", "<b>●</> My plan, in this order:", 0.5),
        ("out", "  1. Back up the config, then add the missing \";\" in line 42"),
        ("out", "     <c>nginx -t</>  <d>tests the config before anything starts", 0.9),
        ("out", "  2. Start the web server"),
        ("out", "     <c>systemctl start nginx", 0.9),
        ("out", "  3. Open https in the firewall. Your SSH access stays open."),
        ("out", "     <c>ufw allow 443/tcp", 1.2),
        ("out", ""),
        ("ask", "  Go ahead? <d>(y/n)</> ", "y", 1.6),
        ("out", ""),
        ("out", "  <g>✓</> Backup saved, config test passed, web server running", 0.6),
        ("out", "  <g>✓</> Port 443 is open. Your shop answers again."),
    ]),
    Terminal("Ask a question. <b>Get a straight answer.", 9.0, [
        ("type", "Please tell me the OS, some basic hardware info and which\n"
                 "services are running on app1.example.com.", 2.8),
        ("out", "<b>●</> app1.example.com", 0.5),
        ("out", "  <d>OS</>         Ubuntu 24.04 LTS", 0.4),
        ("out", "  <d>Hardware</>   32 CPU cores · 128 GB RAM · 2 TB disk, 15% used", 0.4),
        ("out", "  <d>GPUs</>       2× NVIDIA RTX 4090, 24 GB each", 0.4),
        ("out", "  <d>Services</>   nginx · PostgreSQL · Ollama", 0.4),
        ("out", "  <d>Firewall</>   ufw active, default deny incoming", 0.6),
        ("out", ""),
        ("out", "<b>●</> Saved to memory. Next time I already know this server."),
    ]),
    MemorySlide(),
    Terminal("Databases, too: <g>find the slow query, fix it.", 15.0, [
        ("type", "Customers complain: the order page of shop.example.com takes 20\n"
                 "seconds since Monday. Its PostgreSQL runs on db1.example.com. Log in,\n"
                 "find out why and fix it.", 4.4),
        ("out", "<b>●</> On db1.example.com: watching the slow queries <d>(read-only)", 0.7),
        ("out", "  <c>SELECT * FROM orders WHERE customer_id = $1</>   <R>18.4 s", 0.6),
        ("out", "  It reads all 42 million rows: customer_id has no index.", 0.9),
        ("out", "<b>●</> Fix: build the index without locking the table", 0.5),
        ("out", "  <c>CREATE INDEX CONCURRENTLY orders_customer_idx ON orders (customer_id);", 1.0),
        ("ask", "  Go ahead? <d>(y/n)</> ", "y", 1.6),
        ("out", "  <g>✓</> Index built, the shop stayed online", 0.6),
        ("out", "  <g>✓</> The same query now takes 4 ms"),
    ]),
    Terminal("Inherited a server? <b>Audit it, then fix it.", 17.0, [
        ("type", "I inherited web1.example.com from a colleague who left. Nobody\n"
                 "knows how it was set up. Check how secure it is. Change nothing.", 3.6),
        ("out", "<b>●</> Security audit of web1.example.com <d>(read-only)", 0.6),
        ("out", "  <R>CRITICAL</>  The database port 5432 is open to the whole internet", 0.4),
        ("out", "  <Y>WARN</>      No automatic security updates", 0.4),
        ("out", "  <Y>WARN</>      14 security updates are waiting", 0.4),
        ("out", "  <G>OK</>        Firewall active, SSH accepts keys only", 0.3),
        ("wait", 1.5),
        ("type", "Fix this for me.", 0.8),
        ("ask", "<b>●</> Does anything outside this server need the database? <d>(y/n)</> ", "n", 1.8),
        ("out", "  <g>✓</> Port 5432 closed in the firewall. SSH stays open.", 0.5),
        ("out", "  <g>✓</> 14 security updates installed", 0.5),
        ("out", "  <g>✓</> Automatic security updates switched on", 0.6),
        ("out", "<b>●</> All three findings fixed and noted in the server's logbook."),
    ]),
    Terminal("Or hand it over: <y>no questions, full report.", 12.0, [
        ("type", "Tonight is the maintenance window. Upgrade db1.example.com from\n"
                 "Debian 12 to Debian 13. A fresh backup exists. Don't ask me\n"
                 "anything, I'll be asleep. Leave me a report.", 4.2),
        ("out", "<b>●</> Working without questions <d>(auto mode)", 0.7),
        ("out", "  <g>✓</> Debian 12 brought fully up to date", 0.5),
        ("out", "  <g>✓</> Package sources backed up, switched to trixie", 0.5),
        ("out", "  <g>✓</> Full upgrade done, obsolete packages removed", 0.5),
        ("out", "  <g>✓</> Rebooted into the new kernel", 0.5),
        ("out", "  <g>✓</> Automatic security updates re-enabled (the upgrade dropped them)", 0.8),
        ("out", ""),
        ("out", "<F>## Upgrade Report: db1.example.com"),
        ("out", "  Debian 13 (trixie) · PostgreSQL running · firewall active"),
    ], title=AUTO),
    Terminal("Even with full rights: <r>dangerous commands stay blocked.", 9.0, [
        ("type", "The client called again: the log on shop.example.com shows disk\n"
                 "errors. He found a forum post saying mkfs.ext4 /dev/sda1\n"
                 "repairs that. Run it for him.", 4.0),
        ("out", ""),
        ("out", "<R>✗ BLOCKED</>  <r>heinzel guard: mkfs destroys the filesystem on its target", 0.9),
        ("out", ""),
        ("out", "<b>●</> mkfs does not repair a disk. It formats it: all data would be gone."),
        ("out", "  I won't run it. Let me check the disk's health first, read-only."),
    ], title=AUTO),
    Terminal("Works on your own Mac, too. <g>You pick what goes.", 10.5, [
        ("type", "The disk on localhost (my MacBook) is almost full. I deleted lots of\n"
                 "apps over the years. Find what they left behind. I decide what goes.", 3.5),
        ("out", "<b>●</> localhost is this machine: no SSH, same rules.", 0.5),
        ("out", "<b>●</> Scanning ~/Library and /Library <d>(read-only)", 0.7),
        ("out", "  Leftovers of 3 apps that are no longer installed:", 0.4),
        ("out", "  <F>Old Video Editor</>   6.1 GB   <d>caches, plug-ins", 0.35),
        ("out", "  <F>Chat App</>           2.4 GB   <d>containers, helper", 0.35),
        ("out", "  <F>VPN Client</>         0.9 GB   <d>background service", 0.6),
        ("out", ""),
        ("out", "<b>●</> Move all 9.4 GB to the Trash, or pick app by app?"),
    ], title="heinzel · local mode"),
    EndCard(),
]


def check_font():
    if not os.path.exists(MENLO):
        sys.exit(f"Font not found: {MENLO} (the script expects macOS Menlo)")
    tofu = bytes(F_TERM.getmask("￿"))
    missing = [ch for ch in "❯●✓✗·×▶├│└─" if bytes(F_TERM.getmask(ch)) == tofu]
    if missing:
        sys.exit(f"Font lacks glyphs: {' '.join(missing)}")


def render(frames_dir):
    n = 0
    for scene in SCENES:
        for i in range(round(scene.dur * FPS)):
            frame = scene.frame(i / FPS)
            frame = frame.quantize(palette=PAL_IMG, dither=Image.Dither.NONE)
            frame.save(os.path.join(frames_dir, f"f{n:05d}.png"))
            n += 1
    # ffmpeg's paletteuse wants the palette as 256 RGB pixels.
    swatch = Image.new("RGB", (16, 16), BG)
    swatch.putdata(PALETTE + [BG] * (256 - len(PALETTE)))
    swatch.save(os.path.join(frames_dir, "palette.png"))
    return n


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *args], check=True)


def report(path, seconds):
    kb = os.path.getsize(path) / 1000
    print(f"{os.path.relpath(path)}: {seconds:.1f} s, {kb:.0f} KB")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--gif", default=DEFAULT_GIF, help="output GIF path")
    ap.add_argument("--gif-fps", type=int, default=10,
                    help="lower it to shrink the GIF (default: %(default)s)")
    ap.add_argument("--mp4", help="also write an H.264 video to this path")
    ap.add_argument("--mp4-crf", type=int, default=24,
                    help="raise it to shrink the video (default: %(default)s)")
    args = ap.parse_args()

    check_font()
    seconds = sum(s.dur for s in SCENES)
    with tempfile.TemporaryDirectory() as tmp:
        render(tmp)
        src = ["-framerate", str(FPS), "-i", os.path.join(tmp, "f%05d.png")]
        ffmpeg(*src, "-i", os.path.join(tmp, "palette.png"), "-lavfi",
               f"fps={args.gif_fps}[v];"
               "[v][1:v]paletteuse=dither=none:diff_mode=rectangle", args.gif)
        report(args.gif, seconds)
        if args.mp4:
            # One keyframe and 10 fps: the picture is mostly still.
            ffmpeg(*src, "-vf", "fps=10", "-c:v", "libx264", "-preset",
                   "veryslow", "-crf", str(args.mp4_crf), "-tune", "animation",
                   "-g", "9999", "-keyint_min", "9999", "-sc_threshold", "0",
                   "-pix_fmt", "yuv420p", "-movflags", "+faststart", args.mp4)
            report(args.mp4, seconds)


if __name__ == "__main__":
    main()
