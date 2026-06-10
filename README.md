# CC Floor System

A stackable ComputerCraft Tweaked monitor wall with one main controller computer and up to 20 node computers.

Each node controls 4 advanced monitors (6x7 each) mapped as logical slots:
- front
- left
- back
- right

These monitors can be local or remote peripherals reachable over the wired modem cable network.

The node network uses wired modems on the **bottom** side for controller communication.

## Features

- Up to 20 display nodes (80 monitors total)
- Unified global canvas (all node monitors act like one tall display)
- Touch input from any monitor routed to main controller
- Demo switching from main computer keys
- Included demos:
  - Ripple (touch to spawn bouncing waves)
  - Game of Life (touch cells to toggle)
  - Plasma
- Auto-start installers for node and main computers

## Wiring

### Node computer
- Wired modem on `bottom` connected to wired network
- Access to 4 advanced monitor peripherals through the wired network

### Main computer
- Wired modem on `bottom` connected to same wired network

## Install (in-game)

Enable ComputerCraft HTTP first.

### Node installer

```lua
wget run https://raw.githubusercontent.com/ob-105/CC-Floor-System/main/install_node.lua
```

The installer asks for stack index (1..20), auto-detects monitor peripheral names, writes `node_config.lua`, downloads runtime files, and creates `/startup` to run `node.lua` automatically.

### Main installer

```lua
wget run https://raw.githubusercontent.com/ob-105/CC-Floor-System/main/install_main.lua
```

The installer downloads main runtime files and creates `/startup` to run `main.lua` automatically.

## Controls (main computer)

- `1` = Ripple
- `2` = Game Of Life
- `3` = Plasma
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
