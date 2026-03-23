# Shaman Rotation Helper

Visual rotation helper addon for Turtle WoW Shamans.

This addon shows:
- one main movable icon for your next spell
- one movable reminder icon for `Elemental Mastery`
- one movable reminder icon for `Blood Fury`

It is currently built around an Elemental-style priority system using:
- `Flame Shock`
- `Molten Blast`
- `Chain Lightning`
- `Lightning Bolt`
- shield maintenance (`Water Shield`, `Lightning Shield`, or `Earth Shield`)

## Requirements

- Turtle WoW
- SuperWoW recommended and currently used for the best tracking
- English client

## Current Priority Logic

Main rotation icon:

1. `Flame Shock` if no active Flame Shock is detected on the target
2. `Molten Blast` during the Flame Shock refresh window
3. `Chain Lightning` on `Clearcasting` if enabled and off cooldown
4. selected shield if missing and shield maintenance is enabled
5. `Lightning Bolt` otherwise

Separate reminder icons:
- `Elemental Mastery` when off cooldown
- `Blood Fury` when off cooldown

## Visibility Rules

The addon shows when:
- enabled
- you are not mounted
- you have a valid neutral or hostile target
- the target is alive

## Commands

- `/srh` or `/srh config` opens the config window
- `/srh unlock` unlocks the icons for moving
- `/srh lock` locks the icons
- `/srh reset` resets icon positions
- `/srh test` shows test icons

## Config

The config window currently lets you:
- enable or disable the addon
- enable or disable Flame Shock opener
- enable or disable Molten Blast refresh
- choose whether Chain Lightning is only used on Clearcasting
- enable or disable shield maintenance
- choose shield type
- enable or disable Elemental Mastery reminder
- enable or disable Blood Fury reminder

## Notes

- The addon uses SuperWoW-friendly target GUID tracking where possible.
- Fire-immune targets are meant to be skipped for the Flame Shock / Molten Blast branch.
- This is still an in-progress addon and the timing logic is being tuned iteratively.
