# norte_bancada: Magazine Loader for WHIP

A placeable magazine loading machine for FiveM servers running the **WHIP framework** (whip_core + whip_gunny). Players put the machine down, load it with rounds and empty magazines, press Start, and the machine fills the magazines by itself while a screen on the model shows the progress.

> **Made for WHIP only.** This resource uses whip_core exports (containers, items, secure events, world prompts, the /whip settings page) and reads the calibers and magazines of whip_gunny. It does not work on QBCore, ESX, Qbox or ox_core without a rewrite.

> **Vibecoded.** This project was built with an AI coding assistant (Claude Code), directed and tested in game by the Norte Roleplay team. Read the code before you run it on a live server, and expect rough edges.

## Machines

| Item | Model | Magazines | How magazines go in |
|---|---|---|---|
| `norte_bancada` (Magazine Loader) | `nr_bancada_municoes` | 3 | One magazine type, side by side |
| `norte_bancada_mk2` (Magazine Loader MK2) | `nr_bancada_mk2_municoes` | 12 | 4 slots of 3, each slot its own magazine type |

Both models have a screen texture that shows a live loading page (a DUI in an industrial blueprint style): standby, loading with percentage and round count, complete.

## Features

- **Placeable item.** Using the item opens a placement preview that follows your aim. The preview tests the model box against walls, cars and objects, and only accepts flat ground. Scroll rotates, E places, C or Backspace cancels.
- **One world prompt per machine.** It shows only the options that make sense at that moment: Add or Remove rounds, Add or Remove magazines (MK2: Magazine slots > Slot 1 to 4), Start, Stop, Pack up machine.
- **Amount picker.** After choosing a round or magazine type, a single row `< 0 / 100 rounds >` changes with the left and right arrow keys (hold to speed up), and E confirms.
- **Server timed loading.** The server loads one round every `Config.MsPerRound` ms (150 by default), in steps of `Config.TickMs`. It stops when the magazines are full or the rounds run out. Stop ends it early.
- **Persistent.** Each machine is a locked WHIP container, so its contents are saved by whip_core. The list of machines is kept in the resource KVP and comes back after a restart.
- **Visible contents.** The ammo box and every magazine are drawn on the machine as local objects, fitted to the model.
- **Motor sound.** A looped motor sound plays near a working machine, with fade in and fade out.
- **Admin settings.** `/whip` > Settings > Magazine Loader changes the time per round, magazines per machine, prompt position and size, and sound volume and range, live.

## Requirements

- FiveM server artifacts with Lua 5.4 (`lua54 'yes'`)
- `whip_core` (WHIP framework, `whip_requires '1.0'`)
- `whip_gunny` (the machine reads `items/calibers.lua` and `items/magazines.lua`; magazines added by other packs through RegisterMagazine are not picked up)

## Installation

1. Copy the three folders into your resources: `norte_bancada`, `norte_bancada_props`, `norte_bancada_mk2_props`.
2. Add to `server.cfg`, after whip_core and whip_gunny:
   ```
   ensure norte_bancada_props
   ensure norte_bancada_mk2_props
   ensure norte_bancada
   ```
3. Give yourself a machine: `/whip_giveitem norte_bancada` or `/whip_giveitem norte_bancada_mk2`.

The models live in their own resources on purpose. Restarting a resource that streams a model in use crashes the clients that have it spawned. Restart `norte_bancada` freely. To restart a props resource, stop `norte_bancada` first, then restart the props, then start `norte_bancada` again.

## Admin

- `/bancada_remove` (ACE `whip.devtools`): removes the nearest machine within 5 m and gives you its contents and the machine.
- `bancada_remove all` in the server console: deletes every machine and what is inside.

## Configuration

Everything is in `norte_bancada/config.lua`:

- `Config.Types`: the machines. Label, model, magazine limit, container size, prompt point (`promptPoint`, measured in the prop's own space), screen texture, and for the MK2 the slots (`magSlots`, `perSlot`).
- `Config.MsPerRound`, `Config.TickMs`: loading speed.
- Placement: `PlaceRange`, `MinSpacing`, `PlaceReach`, `PlaceFlat`.
- Sound: `SoundRange`, `SoundVolume`, `SoundFadeIn`, `SoundFadeOut`.
- `Config.Apoios`: fallback fitting offsets for ammo boxes and magazines on the small machine.

Code comments are in Portuguese. In game text is in English.

## Known limits

- The screen replaces the model's texture, so every machine of the same model shows the nearest working machine.
- The motor sound is played through the NUI with distance volume. It is not a positional 3D sound.
- The ammo and magazine icons are loaded from whip_gunny (`https://cfx-nui-whip_gunny/html/img/items/`).

## License

Code, models, textures, icons and sound are licensed under **Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)**. You may use, share and change them with credit to Norte Roleplay. You may not sell them or use them for commercial purposes. See [LICENSE](LICENSE).
