# Trailer

The GIF at the top of the main README is not a recording.
`make-trailer.py` draws every frame from a storyboard inside
the script, so the trailer can be changed and rebuilt at any
time.

## Rebuild

    python3 assets/trailer/make-trailer.py

This writes `assets/heinzel-trailer.gif` and prints its length
and size. It needs macOS (for the Menlo font), Python 3 with
Pillow, and `ffmpeg`. Add `--mp4 trailer.mp4` for a video
file as well.

## Change it

Everything lives in the `SCENES` list. A terminal scene is a
caption, a length in seconds and a list of steps (typed
prompt, output line, y/n question, pause). The docstring of
the `Terminal` class lists the step kinds.

Colour markup: `<g>green</>`, `<r>red</>`, `<y>yellow</>`,
`<b>blue</>`, `<c>cyan</>`, `<d>dim</>`. An upper-case letter
makes the text bold.

Rules worth keeping:

- Hostnames are always `*.example.com`. The file is public.
- A line holds 75 characters (the script checks this), a
  screen holds 13 lines (it does not).
- The GIF should stay under 500 KB. If it grows past that,
  lower `--gif-fps` or cut a scene. Scaling the finished
  frames down with ffmpeg makes the file bigger, not smaller.
- All colours come from one fixed palette of 27. New colours
  need their anti-aliasing blends added to `PALETTE`, and the
  total must stay at 32 or below.
- One scene shows a command the taboo guard blocks. The guard
  scans whole shell command lines, so edit that scene in an
  editor, never with `sed` or a heredoc.
