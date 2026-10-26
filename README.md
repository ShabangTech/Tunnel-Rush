# Tunnel Rush

An online skateboard race for up to 4 players through a flooded tunnel, built in **Godot 4.7** with its built-in high-level multiplayer (ENet).

You ride as a **Big Head Panda**. Race head-to-head with friends or against bots: build speed in three kicks, carry it across the wet floors, then drop into **The Drop**, an 8-second freestyle slope with three kickers. Every trick you land there turns into a speed boost at the bottom. After that, dodge the zombies clawing out of the floor and the bats swooping at your head, smash through crates, and ride the plank over the pit (or ollie it).

## How to play

| Action | Keyboard | Gamepad |
|---|---|---|
| Kick (hold) | W / Up | Right trigger |
| Steer | A / D | Left stick |
| Brake | S / Down | Left trigger |
| Ollie | Space | A |
| Flip trick (air) | E | X |
| Grab, hold (air) | F | Y |
| Style trick (air) | R | B |
| Spin, hold (air) | Q | RB |
| Trick variation | W/A/S/D and/or Shift | stick + LB |
| Trick list | Tab (hold) | Back |
| Leave race | Esc | |

### The trick book

25 air tricks plus spins. Add a direction (W/A/S/D) and/or Shift to the trick button for the variation:

| | none | W | A | S | D |
|---|---|---|---|---|---|
| **E** | Kickflip | Varial Kickflip | Heelflip | Impossible | Pop Shove-it |
| **Shift+E** | Double Kickflip | 360 Flip | Inward Heelflip | Hardflip | Laser Flip |
| **F** | Indy | Nosegrab | Melon | Tailgrab | Method |
| **Shift+F** | Stalefish | Rocket Air | Benihana | Madonna | Christ Air |
| **R** | Airwalk | Ollie North | Judo | Body Varial | Superman |

**Spins:** hold Q and let go; the spin finishes on the next half turn: 180, 360, 540, 720, 900 or 1080. An odd number of half turns lands you riding fakie.
**Combos:** every extra trick in the same jump adds 50% to its points. Land mid-trick and you **bail**.

**Kick rhythm:** the 1st kick gets you rolling, the 2nd builds speed, and the 3rd and every kick after hold top speed.
**Floors:** wet floors keep your speed; dry floors drag. Downhills speed you up without kicking.
**The Drop:** the moment you enter the slope an 8-second freestyle timer starts. Your freestyle points become a speed boost (up to +11 km/h) when it ends.
**Crashes:** hitting a wall head-on costs most of your speed. Hit a crate fast enough and it smashes.
**Zombies** rise out of cracks in the floor, shamble into the lane and sink again on an 8-second cycle. Run into one and you lose speed. **Bats** swoop down to head height and spook you.
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
- The panda's animation state (kick, lean, spins, board flips, grab and style poses, bails) is synced, so everyone sees everyone's tricks.
- Zombies and bats move on the shared race clock, so they're in the same place on every screen with no extra network traffic.

## Run it

1. Install Godot 4.7.
2. Open this folder in Godot and press **F5**.

### Headless testing

```bash
# Solo race vs 3 bots, self-driving, prints results
godot --headless --path . -- --solo --autopilot --quit-after-race --log-tricks

# Host (expects 3 racers incl. 1 bot) and a client on the same machine
godot --headless --path . -- --host --bots=1 --expect=3 --autopilot --quit-after-race
godot --headless --path . -- --join=127.0.0.1 --autopilot --quit-after-race
```

## Project layout

```
scripts/main.gd    menu, lobby, hosting/joining, spawning, camera
scripts/race.gd    race states, countdown, finish detection, results (host-authoritative)
scripts/skater.gd  skateboard physics, kick rhythm, tricks, freestyle, hazards, bots, sync
scripts/tricks.gd  the trick book: 25 tricks, spins, points
scripts/panda.gd   the Big Head Panda model and all its animation
scripts/level.gd   the course, kickers, zombies and bats, built in code
scripts/hud.gd     speed, kicks, clock, position, results
```

## Credits

By ShabangTech. Every model, including the panda, zombies and bats, is generated in code; no third-party assets.
