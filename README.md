# CC Floor System

A stackable ComputerCraft Tweaked monitor wall with one main controller computer and up to 20 node computers.

Each node controls 1 advanced monitor (typically attached on `top`).

Important: your "6x7" is treated as monitor blocks, not pixels/characters. The runtime uses each wall's real character size from `monitor.getSize()` automatically.

These monitors can be local or remote peripherals reachable over the wired modem cable network.

The node network uses wired modems on the **bottom** side for controller communication.

## Features

- Up to 20 display nodes (20 monitors total)
- Unified global canvas (all node monitors act like one tall stacked display)
- Touch input from any monitor routed to main controller
- Demo switching from main computer keys
- Included demos:
  - Ripple (touch creates high-energy impact pulses that propagate, reflect, interact turbulently, then settle)
  - Game of Life (touch cells to toggle)
  - Plasma
- Distributed ripple rendering: each node computes its own ripple slice, so adding nodes increases total ripple compute capacity
- Ripple demo includes adaptive quality limits (source count/age/distance) to keep performance stable on larger floors
- Auto-start installers for node and main computers
- Auto-update on reboot: startup checks GitHub and refreshes runtime files before launch

## Wiring

### Node computer
- Advanced monitor on `top` (or one reachable monitor peripheral over wired network)
- Wired modem on `bottom` connected to wired network

### Main computer
- Wired modem on `bottom` connected to same wired network

## Install (in-game)

Enable ComputerCraft HTTP first.

### Node installer

```lua
wget run https://raw.githubusercontent.com/ob-105/CC-Floor-System/main/install_node.lua
```

The installer asks for stack index (1..20), picks one monitor peripheral (prefers `top`), writes `node_config.lua`, downloads runtime files, and creates `/startup` to run `node.lua` automatically.

Stack index convention: `1` is the bottom monitor, `2` is above it, etc.

### Main installer

```lua
wget run https://raw.githubusercontent.com/ob-105/CC-Floor-System/main/install_main.lua
```

The installer downloads main runtime files and creates `/startup` to run `main.lua` automatically.

## Auto Update

After running the latest installers, each reboot will:
- try to download fresh `common.lua` and role runtime (`node.lua` or `main.lua`) from GitHub
- run local files even if HTTP is unavailable or download fails

If you installed before this feature was added, rerun installers one time to replace your `/startup` script.

## Controls (main computer)

- `1` = Bottom To Top Line
- `2` = Ripple
- `3` = Game Of Life
- `4` = Plasma
- `R` = force rediscover nodes

## Files

- `common.lua` Shared protocol and geometry helpers
- `node.lua` Node runtime (monitor rendering + touch forwarding)
- `main.lua` Main runtime (discovery + demo simulation + frame distribution)
- `install_node.lua` Node installer and autostart setup
- `install_main.lua` Main installer and autostart setup

## Notes

- If a node disconnects, it times out automatically.
- Main controller auto-assigns contiguous stack indices to online nodes.
- For consistent visual stacking, physically arrange nodes in the same order as stack index.
