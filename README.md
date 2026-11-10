# The Snake Fella: x68 Assembly Snake Game

A Snake game written in Motorola 68000 assembly for the [EASy68K](http://www.easy68k.com/) editor, assembler and simulator. It goes beyond classic Snake by adding a small set of "alternative physics" systems: fuel, shields with wall-wrapping, a random solar-flare event and a speed boost.

## Features

| System | How it works |
|---|---|
| **Difficulty select** | Choose Easy, Medium or Hard at startup. Only `1`, `2` or `3` are accepted, and any other input is ignored. |
| **Fuel** | Fuel drains at 0.5 per tick. Each piece of food restores 20, up to a maximum of 100. Running out of fuel ends the game. |
| **Shields and wall wrap** | Crossing the edge of the grid wraps the snake to the opposite side and costs one shield. Running into your own body also costs a shield. A hit with no shields left ends the game. |
| **Solar flare** | Each tick has a 1-in-32 chance of starting a flare. The border flashes yellow and green for about 2 seconds as a warning, then turns solid yellow while the flare is active and your controls are reversed. A cooldown of about 7 seconds follows before another flare can start. |
| **Speed boost** | Press Space to boost for up to 5 ticks at half the normal delay. Boosting costs 3 extra fuel per tick. Press Space again to cancel early. Boost won't start if you don't have enough fuel. |
| **Increasing speed** | Every piece of food eaten speeds the game up, down to a fixed minimum delay. The snake grows to a maximum length of 30 segments. |

### Difficulty levels

| Level | Shields | Starting fuel | Speed |
|---|---|---|---|
| 1: Easy | 3 | 100 | Slow |
| 2: Medium | 2 | 75 | Medium |
| 3: Hard | 1 | 50 | Fast |

## Controls

| Key | Action |
|---|---|
| Arrow keys | Steer |
| Space | Toggle speed boost |
| `Q` / `q` | Quit |

Esc is not used to quit because the EASy68K simulator intercepts it before the program sees it.

## Running the game

You'll need **EASy68K**, which runs on Windows. It also works on macOS and Linux through Wine or a Windows virtual machine.

**From source:**

1. Open `hahayeahman.X68` in the EASy68K editor.
2. Assemble it with **Project → Assemble Source** (F9).
3. Click **Execute** to open the program in the Sim68K simulator, then press **Run** (F9).

**Without assembling:** open Sim68K directly and load `hahayeahman.S68`. This file is the pre-assembled program.

The game opens a 640 × 640 window divided into a 32 × 32 grid of 20-pixel cells.

### Sound

The game plays a sound effect called `opps.wav` when you eat food, lose a shield or die. The program looks for this file in the same folder it runs from. Without it, the game still runs, just silently.

## Repository contents

| File | Description |
|---|---|
| `hahayeahman.X68` | Assembly source code |
| `hahayeahman.L68` | Assembler listing: the source annotated with memory addresses and machine code |
| `hahayeahman.S68` | Assembled program in Motorola S-record format, ready to load into Sim68K |

## Technical notes

- **Keyboard input** is read by polling TRAP #15 task 19 once per game tick rather than through a keyboard interrupt. This avoids a supervisor stack crash caused by an `RTE` executed with no interrupt frame on the stack.
- **Graphics** use EASy68K's TRAP #15 drawing tasks, with double buffering (task 92) to reduce flicker. Colours are defined in EASy68K's `$00BBGGRR` format.
- **Sound** is loaded and played with TRAP #15 tasks 71 and 72.
- **Timing** is based on a busy-wait delay loop. As a result, the game speed and the approximate durations of the solar flare depend on the speed of the host machine.
- The program is assembled to run from `$1000`.