# Tunnel Rush

An online skateboard race for up to 4 players through a flooded tunnel, built in **Godot 4.7** with its built-in high-level multiplayer (ENet).

Race head-to-head with friends, or against bots. Hold kick to build speed in three pushes, carry it across the wet floors, bomb the downhill, smash through crates, and either ride the plank over the pit or ollie the gap.

## How to play

| Action | Keyboard | Gamepad |
|---|---|---|
| Kick (hold) | W / Up | Right trigger |
| Steer | A / D | Left stick |
| Brake | S / Down | Left trigger |
| Ollie | Space | A |
| Leave race | Esc | |

**Kick rhythm:** the 1st kick gets you rolling, the 2nd builds speed, and the 3rd and every kick after hold top speed.
**Floors:** wet floors keep your speed; dry floors drag. Downhills speed you up without kicking.
**Crashes:** hitting a wall head-on costs most of your speed. Hit a crate fast enough and it smashes.
**The pit:** take the narrow plank, or ollie the 6 m gap at full speed. Fall in and you respawn at the last checkpoint.

## Multiplayer

- **Race the bots:** you plus 3 bots, offline.
- **Host an online race:** others join your IP on **UDP port 7777**. Add bots to fill the grid, then press **Start race**.
- **Join:** type the host's IP and press Join.

On the same Wi-Fi, use the host's local IP (`ipconfig` on Windows). Over the internet, the host forwards UDP 7777 on their router, or both players use a virtual LAN tool such as Tailscale.

### How it works

- A `MultiplayerSpawner` creates each racer on every peer from the same spawn data (id, grid slot, name, color).
- Each player simulates their own skater; a `MultiplayerSynchronizer` sends position and facing to everyone else. Bots run on the host.
- The host is the referee: it runs the countdown, detects finish-line crossings, and broadcasts results with reliable RPCs, so every screen shows the same times.

## Run it

1. Install Godot 4.7.
2. Open this folder in Godot and press **F5**.

### Headless testing

```bash
# Solo race vs 3 bots, self-driving, prints results
godot --headless --path . -- --solo --autopilot --quit-after-race

# Host (expects 3 racers incl. 1 bot) and a client on the same machine
godot --headless --path . -- --host --bots=1 --expect=3 --autopilot --quit-after-race
godot --headless --path . -- --join=127.0.0.1 --autopilot --quit-after-race
```

## Project layout

```
scripts/main.gd    menu, lobby, hosting/joining, spawning, camera
scripts/race.gd    race states, countdown, finish detection, results (host-authoritative)
scripts/skater.gd  skateboard physics, kick rhythm, crashes, bots, network sync
scripts/level.gd   greybox course built in code
scripts/hud.gd     speed, kicks, clock, position, results
```

## Credits

By ShabangTech. All geometry is generated in code; no third-party assets.
