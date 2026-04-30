# mc2026

Paper 1.21.x Minecraft server, Dockerized via [`itzg/minecraft-server`](https://github.com/itzg/docker-minecraft-server). Runs on a Linux host at `/srv/mc/`. This repo (`C:\projects\mc2026`) holds the compose file, plugin configs, and operational scripts — not the live world data.

## Layout (on the Linux server)

```
/srv/mc/
├── docker-compose.yml      # service definition
├── mc-data/                # bind-mounted to /data inside the container
│   ├── server.properties
│   ├── world/  world_nether/  world_the_end/  lennu_maailm/
│   ├── plugins/            # active plugin jars + per-plugin config dirs
│   ├── ops.json  whitelist.json  banned-*.json
│   └── logs/
├── plugins/                # drop-in folder, copied into mc-data/plugins on start
└── backup-weekly.sh
```

Web UIs (when running):

| Service   | Port | URL                               |
|-----------|------|-----------------------------------|
| Java      | 25565 tcp | `mc-host:25565`              |
| Bedrock   | 19132 udp | (Geyser) `mc-host:19132`     |
| squaremap | 8080  | `http://mc-host:8080`            |
| Plan      | 8804  | `http://mc-host:8804`            |
| RCON      | 25575 | container-internal only, do not expose |

## Daily operations (run from `/srv/mc/` on the server)

### Start
```bash
docker compose up -d
docker compose logs -f mc        # watch boot, Ctrl+C when you see "Done (Xs)!"
```

### Stop
```bash
docker compose stop mc           # graceful (sends RCON `stop` first)
```
Or from inside the game / rcon: `save-all` then `stop`.

### Restart
```bash
docker compose restart mc        # same container, same config
```
Use `docker compose up -d` instead if you edited `docker-compose.yml` — `restart` does **not** pick up env-var or mount changes.

### View logs
```bash
docker compose logs -f mc                       # live tail
docker compose logs mc --tail=200 | grep -i error
```

### Run server commands (RCON)
```bash
docker compose exec mc rcon-cli                 # interactive console
docker compose exec mc rcon-cli list            # one-shot
docker compose exec mc rcon-cli save-all
```

### Attach to live console (read + write, careful)
```bash
docker attach mc-paper
# Detach with: Ctrl+P, Ctrl+Q   ← do NOT press Ctrl+C (kills the JVM)
```

## Configuration

### Server config
- `docker-compose.yml` — memory, ports, MC version pin, env vars (`ENABLE_RCON`, `RCON_PASSWORD`, etc.). Changing this requires `docker compose up -d` to take effect.
- `mc-data/server.properties` — vanilla server settings (gamemode, view distance, MOTD, …). Edit, then `docker compose restart mc`.
- `mc-data/bukkit.yml`, `paper-global.yml`, `paper-world-defaults.yml`, `spigot.yml` — Paper/Spigot tuning. Edit, then restart.

### Plugin config
Per-plugin folders live in `mc-data/plugins/<PluginName>/`. Edit on the server, then either:
- `docker compose exec mc rcon-cli <plugin>:reload` (if the plugin supports it — e.g. `lp reload`, `wg reload`, `ess reload`), or
- `docker compose restart mc` for plugins without a reload command.

Plugin configs are version-controlled in this Windows repo. Keep `/srv/mc/mc-data/plugins/<Plugin>/` and the repo in sync (commit changes from the server, or pull repo changes onto the server).

### Adding a plugin
1. Drop the **Bukkit/Paper** build of the jar (not Fabric or Forge) into `/srv/mc/mc-data/plugins/`.
2. `docker compose restart mc`
3. Verify in logs: `docker compose logs mc --tail=200 | grep -i <PluginName>`
4. Confirm it's listed: `docker compose exec mc rcon-cli plugins`

### Removing a plugin
1. `docker compose stop mc`
2. Delete the jar from `/srv/mc/mc-data/plugins/`. Optionally delete its config dir.
3. `docker compose start mc`

## Updates

### Update Paper / image
The compose file currently uses `itzg/minecraft-server:latest` and `VERSION: "LATEST"` — meaning Paper auto-updates on every container recreate. To pull the newest published image:
```bash
docker compose pull mc
docker compose up -d              # recreates the container with the new image
```
**Pin versions** for stability — edit `docker-compose.yml`:
```yaml
image: itzg/minecraft-server:java21
environment:
  VERSION: "1.21.11"
```
Then `docker compose up -d`.

### Update a plugin
1. Download the new jar (matching your MC version).
2. Replace the old jar in `/srv/mc/mc-data/plugins/`.
3. `docker compose restart mc`
4. Tail logs and confirm the new version line appears.

### Update the OS / Docker
Standard Linux maintenance — `apt update && apt upgrade`, then `docker compose up -d` to bring the server back if Docker was restarted.

## Backups

`backup-weekly.sh` runs the weekly snapshot (cron'd on the server). For a manual snapshot before risky changes:
```bash
docker compose exec mc rcon-cli save-all
docker compose stop mc
tar czf /srv/mc/backups/manual-$(date +%F).tgz -C /srv/mc mc-data
docker compose start mc
```

## Plugin guides

### Chunky — pre-generating chunks

Generates chunks ahead of time so players don't lag the server when exploring. Auto-throttles when TPS drops, so it's safe to leave running.

Basic flow (run via `docker compose exec mc rcon-cli <command>` or in-game with `/`):

```
chunky world world           # select the world to generate
chunky center 0 0            # center of the area (usually spawn)
chunky radius 5000           # blocks from center; 5000 = ~10k×10k area
chunky start                 # begin
chunky progress              # see %, ETA, chunks/sec
chunky pause                 # halt without losing progress
chunky continue              # resume
chunky cancel                # stop and discard progress
```

Sensible radii per world: overworld `5000`, nether `1000` (nether coords are 8× compressed), end `2000`. Run for each world separately.

Tuning in `mc-data/plugins/Chunky/config.yml`:
- `max-load` (default `8.0`) — auto-pauses when system load exceeds this. Lower = more conservative.
- `silent` — set `true` to stop progress spam in chat/console.

### squaremap — live web map

Renders the world to PNG tiles and serves them at `http://mc-host:8080`. By default it only re-renders chunks that get **loaded by a player or modified** — chunks Chunky generates while no one is around stay blank on the map.

After Chunky finishes, force a render of the existing chunks:

```
squaremap fullrender world
squaremap fullrender world_nether
squaremap fullrender world_the_end
squaremap fullrender lennu_maailm
```

Other useful commands:

```
squaremap status                              # queue length, chunks/sec
squaremap pause world                         # stop rendering a world
squaremap resume world
squaremap radiusrender <world> <radius> [x z] # render a specific area
squaremap cancelrender <world>                # cancel a queued fullrender
```

Doing Chunky and squaremap fullrender simultaneously works but doubles disk I/O — run them sequentially for less impact.

Map config: `mc-data/plugins/squaremap/config.yml` (web port, render threads), per-world tuning in `mc-data/plugins/squaremap/<world>.yml`.

### Health checks while either is running

```
docker compose exec mc rcon-cli tps             # 20.0 = healthy, <15 = lag
docker compose exec mc rcon-cli chunky progress
docker compose exec mc rcon-cli squaremap status
```

## Troubleshooting

| Symptom | Check |
|---|---|
| Container won't start | `docker compose logs mc --tail=100` for stack traces |
| Plugin missing after restart | jar in wrong folder, wrong loader (Fabric/Forge instead of Bukkit), or version mismatch — see `[ERROR]` lines at boot |
| `rcon-cli: connection refused` | `ENABLE_RCON: "TRUE"` and `RCON_PASSWORD` set in compose; container restarted with `up -d` not `restart` |
| Players can't connect | Firewall on host (25565/tcp, 19132/udp); `whitelist on` with player not whitelisted; `online-mode` mismatch |
| Lag spikes near border | Pre-generate chunks with Chunky: `chunky world world; chunky radius 5000; chunky start` |
| Map not rendering new areas | squaremap renders only loaded chunks — pre-gen the area or have a player visit |

## Plugins currently installed

Pre-gen / utility: Chunky, WorldEdit, WorldGuard, WorldGuardExtraFlags, Multiverse-Core
Permissions / economy: LuckPerms, Vault, Essentials
Protection / logging: GriefPrevention, CoreProtect, InventoryRollbackPlus
QoL: ChestSort, ClickMobs, DynamicLights, Graves, Harbor, SimpleSitAnimation
Cross-play: Geyser-Spigot, floodgate
Monitoring: squaremap, Plan, spark
