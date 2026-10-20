# Talents Forge

**A minimal talent build planner that lives inside the game's own talent window.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![Version](https://img.shields.io/badge/version-1.1.0-brightgreen)
![WoW](https://img.shields.io/badge/WoW-Forever-f8b700)
![Interface](https://img.shields.io/badge/interface-16001-555)

> **Client support.** Built for **WoW Forever** (interface `16001`). Forever serves Classic
> content from the Midnight 12.x client and runs talents through the modern `C_Traits`
> system, which is what Talents Forge reads. It has not been tried on other clients.

Plan your talents before you spend a single point. Talents Forge draws a small chip at the top
of the talent window and puts rings and level badges on your talents. There is no extra
window to open and nothing to learn: click a talent to plan it, and the order you click in is
the order you take the points.

<!--
Screenshots: drop images into docs/ and reference them here, e.g.
![Planning a build](docs/plan.png)
-->

## Features

- **Plan inside the talent window.** Left-click a talent to plan a point, Shift-click to plan
  every rank, right-click to remove one (Shift-right-click removes them all). Planning never spends real points.
- **Order matters.** A plan is a list of points in the order you take them. Every planned
  talent shows the level you take it at, and a level slider shows the build as it stands at
  any level. Clicking with the slider part-way inserts the point at that spot.
- **Tooltips at your planned rank.** In Edit mode, hovering a talent with several ranks shows what
  it does at the rank you have planned, and what the next rank adds.
- **A flourish when a talent is full.** The point that fills a talent gives it a quick gold flash
  and pops its count.
- **Little touches.** Each point you plan sends a soft ring out of the talent. A talent your point has
  opened wakes up, with a spark running along the way to it. The next talent in Guide mode has a slow
  shine sweeping over it (and the menu can dim all the others). A scrubbed-away point stays visible as a
  ghost, finishing a plan throws sparks from the chip, and the menu and dialogs glide in. The edit-mode
  effects (rings, flashes, sparks) can be switched off from the menu.
- **Guide mode.** Pick *Guide* and a single talent glows: your next point in the selected
  plan. It follows what you have actually bought, in any order, so the glow always points at
  the first planned point you have not covered yet.
- **Other classes.** Browse any class's three trees in the game's own style and plan on them
  the same way, with the game's talent art and background.
- **Import and export.** Share a build as a short `TFG1:` string. Imports are checked against
  the talent tree before they are accepted, and a build for another class opens that class's
  tree first.
- **Plans belong to your account.** A plan made on one character is there on all the others.

## Usage

Open your talents and click the chip at the top of the window.

| Mode | What you see |
|---|---|
| **Off** | Just the chip. The talent window looks like stock. |
| **Guide** | One talent glows: your next point. The chip names it and the level you take it at. |
| **Edit** | Plan points by clicking talents. Rings and level badges show the whole plan, and a bar adds the level slider, Import, Export and Clear. |

In the chip's menu: pick, create, rename (at the right of a plan's row) and delete (asks
twice) plans, import and export builds, and browse other classes.

Teal ring: planned and not bought yet. Gold ring: planned and already bought. The badge is
the level you take the talent at.

| Command | What it does |
|---|---|
| `/tforge mode off\|guide\|edit` | Switch mode. |
| `/tforge reset` | Put the chip and the bar back in their default spots (Shift-drag moves them). |

## Build strings

A build string starts with `TFG1:` and carries the points in order. Talents are stored by
spell id, so a string survives the game renumbering its talent nodes between builds. A string
carries its class, and a build for the wrong class is refused with a message.

## Bugs and ideas

Open an [issue](https://github.com/SokratisV/TalentsForge/issues). If something looks wrong in
the talent window, a screenshot helps a lot.

## License

[MIT](LICENSE).
