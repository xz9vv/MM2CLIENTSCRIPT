# MM2 Client Script (`MM2CLIENTSCRIPT`)

A modular, lightweight Roblox Luau client-side scripting framework designed for Murder Mystery 2 account automation. This script runs inside your Roblox executors (e.g., Xeno) and communicates asynchronously over local WebSockets with your `MM2 Manager` desktop application.

---

## 📋 Table of Contents
- [1. Repository Structure](#1-directory-structure)
- [2. File Responsibilities & Modules](#2-file-responsibilities--modules)
- [3. Telemetry Contract (Roblox ➔ Python)](#3-telemetry-contract-roblox--python)
- [4. Command Contract (Python ➔ Roblox)](#4-command-contract-python--roblox)
- [5. Executor Loader / Execution](#5-execution-loader)

---

## 1. Directory Structure

```text
MM2CLIENTSCRIPT/
├── README.md               # Repository documentation and loading instructions
├── loader.lua              # Main bootstrapper (The only file run by the executor)
│
└── modules/
    ├── connection.lua      # WebSocket engine, auto-reconnect, and heartbeat signaling
    ├── farm.lua            # Tweening mechanics, coin collection, and death events
    ├── esp.lua             # Custom chams and 3D highlights (Coins, Murderers, Sheriffs)
    ├── optimizations.lua   # Performance, headless render, volume, and CoreGui purges
    └── unbox.lua           # Remote execution for automated crate unboxing
2. File Responsibilities & Modules
loader.lua
Purpose: The absolute entry point for your executor. It dynamically downloads, compiles, and initializes all other module files from this GitHub repository into Roblox's memory. It coordinates startup so that no code executes out of order.
modules/connection.lua
Purpose: Manages the WebSocket connection to ws://localhost:8765.
Logic:
Establishes connection on script boot.
Automatically runs an infinite 5-second reconnect loop if the connection drops.
Spawns a background task that sends a silent keep-alive Heartbeat packet every 30 seconds so Python knows the instance is still active.
Exposes a thread-safe Connection.send(payload) method that other modules use to transmit events.
modules/farm.lua
Purpose: Manages the core gameplay loop.
Logic:
Instantly fires a coin_collected packet every time the local coin count increases.
Fires full_bag when current round coin capacity (e.g., 10/10) is reached, pausing collection.
Monitors character respawns and deaths to fire status_changed (Alive / Dead).
modules/esp.lua
Purpose: Renders visual highlights.
Logic:
Draws dynamic custom highlights/chams through player characters and spawnable coins.
Responds to real-time configurations toggled on the desktop dashboard.
modules/optimizations.lua
Purpose: Keeps system resource utilization extremely low during 24/7 farming.
Logic:
Controls 3D rendering toggles (Set3dRenderingEnabled).
Manages audio mute and FPS caps (setfpscap).
Completely destroys checked HUD elements (Chat, PlayerList, Spectating) inside the game interface to save memory.
modules/unbox.lua
Purpose: Purchases crates on demand.
Logic:
Intercepts unbox events from the GUI, fires the MM2 server purchase remote, and returns the result packet to Python.
3. Telemetry Contract (Roblox ➔ Python)
All events are fired instantaneously upon occurrence and include the active username.
Event Type	Payload Format	Trigger Condition
joined	{"event": "joined", "username": "tito16"}	Instantly when the client script finishes loading.
heartbeat	{"event": "heartbeat", "username": "tito16"}	Sent in a background thread every 30 seconds.
coin_collected	{"event": "coin_collected", "username": "tito16", "coins": 450}	Instantly upon picking up any coin.
full_bag	{"event": "full_bag", "username": "tito16", "bag_count": 10}	Instantly when the round coin limit is met.
role_assigned	{"event": "role_assigned", "username": "tito16", "role": "Murderer"}	Immediately when roles are distributed at round start.
status_changed	{"event": "status_changed", "username": "tito16", "status": "Dead"}	Immediately upon character death or respawn.
round_state_changed	{"event": "round_state_changed", "username": "tito16", "phase": "InGame", "map": "Office"}	Triggers when the round transitions phases or maps.
unbox_result	{"event": "unbox_result", "username": "tito16", "status": "Success"}	Triggered after executing an unbox request.
4. Command Contract (Python ➔ Roblox)
How the client-side modules respond to real-time instructions from Python.
update_settings
Action: Adjusts farming toggles, tween speeds, Y-offsets, caps FPS, toggles headless mode, mutes volume, and deletes checked game HUD components.
force_reset
Action: Safely sets local Humanoid.Health = 0 to end rounds or exit batches cleanly.
fling_target
Action: Activates an aggressive angular-velocity physics loop on the target player until they die or fly out of bounds.
unbox
Action: Automates shop purchases and triggers the designated MM2 unbox remote event.
toggle_ui
Action: Toggles visibility of the standard Roblox MM2 screen elements.
5. Execution Loader
To run this modular framework, paste this single line inside your Roblox Executor or place it inside your Executor's auto-execute folder:
