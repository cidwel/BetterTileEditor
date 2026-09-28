# Contributing

## Reporting something broken

There is [a form for it](../../issues/new?template=bug_report.yml). It asks for
one thing above all the others: **a way for me to reproduce it.**

That is not bureaucracy. A tileset is a big pile of state. Terrain types, peering
bits, atlas coordinates, the shape of your own art, and these bugs nearly always
live in the combination rather than in any one setting. From a description alone
I have to rebuild your tileset by guesswork before I can even see the problem.
More often than not I rebuild one that works fine.

So, fastest first:

1. **A small demo project.** Cut it down until only the problem is left. One
   scene, one TileMapLayer, the tileset, nothing else. Zip it and drag it into
   the issue. If I can open it and watch the wrong tile appear, I can usually
   find the cause the same day.
2. **The tileset plus instructions.** Attach the `.tres` and the atlas image.
   Write out what to click, in order, starting from a blank scene.
3. **A description on its own.** I will read it and I will try. Be aware that
   this is the slow route, and some issues never get past it.

Say which terrain is involved and which cell comes out wrong. "The water looks
weird" and "the cell at (2,1) gets the bank tile instead of open water" are very
different amounts of help.

Does it happen with [the original BetterTerrain](https://github.com/Portponky/better-terrain)
too? Then report it there. Upstream is where it gets fixed for everybody.

## Sending a fix

Pull requests are welcome. A fix with a reproduction attached is the best thing
that can land in this repo. A few things worth knowing before you start:

- **Read the relevant section of [DESIGN.md](addons/better-tile-editor/DESIGN.md)
  first.** It is long, but it is organised by feature. It records why several
  things that look wrong are deliberate, and it will save you writing a patch
  that gets turned down for a reason nobody could have guessed from the code.
- **Code, comments and commit messages in English.**
- Keep new comments to one or two lines. Explain a constraint or a non-obvious
  decision; omit code narration, debugging history and conversation quotes.
- **Don't reformat what you are not changing.** A diff that is 90% whitespace
  hides the 10% that matters.
- **Say how you tested it.** Which tileset, which terrain, what you painted, what
  came out. Measurements beat opinions. Most of the decisions in this fork were
  settled by counting cells on a real map, not by arguing about them.
- Changing something upstream has too? Think about whether it belongs upstream
  instead. This fork tries to stay a superset, not a divergence.

## Licence

The Unlicense, same as upstream. Contributing puts your work in the public domain
along with the rest of it.
