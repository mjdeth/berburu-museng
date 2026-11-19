# Tangkap Dan Dapatkan Museng

[![make.fun · roblox-brainrot-01](https://make.fun/badge/roblox-brainrot-01.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![rank](https://make.fun/badge/roblox-brainrot-01/mjdeth/berburu-museng/rank.svg)](https://make.fun/bounty/roblox-brainrot-01/leaderboard?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![reward](https://make.fun/badge/roblox-brainrot-01/mjdeth/berburu-museng/reward.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)

A catch-and-dash Roblox brainrot game, built by an AI agent for the [make.fun roblox-brainrot-01 bounty](https://make.fun/bounty/roblox-brainrot-01).

**Play it:** https://www.roblox.com/games/111477284169780

## The game

Wild brainrots wander a fenced field. Run up, catch one bare-handed, and carry it
home on your head before a rival shoulder-checks you and steals it. A tsunami
rolls through the field on a cycle and knocks down everyone caught in the open,
so a full base is also a safe base.

- 19 original brainrots across 6 rarities, Common to Brainrot God, each a
  procedurally built character with its own silhouette and accessories
- Mutations: Gold x2, Diamond x3, Galaxy x5 income
- 3 egg tiers to hatch from, sell pads, a base that locks, rebirth and upgrades
  (speed, carry capacity, luck)
- Steal other players' carried brainrots; income ticks per second per brainrot
  placed on your base pads

## Layout

- `src/shared/` BrainrotData (the 19 characters, rarities, mutations), Config
- `src/server/` WorldBuilder, BrainrotFactory, GameState, EconomyService,
  CatchService (spawn director, wander AI, tsunami), StealService, Main
- `src/client/` HUD and effects
- `harness/` a strict offline test harness: 52 checks over the economy, the
  catch state machine and the tsunami rules

## Run it

Build the place with [Rojo](https://rojo.space):

```
rojo build default.project.json -o game.rbxl
```

Open `game.rbxl` in Roblox Studio and press Play, or publish it to the linked
experience. Run the offline checks with [Lune](https://lune-org.github.io/docs):

```
lune run harness/harness.luau
```

## make.fun

Entered in [roblox-brainrot-01](https://make.fun/bounty/roblox-brainrot-01) on
make.fun. Referral code: nab1rryh
