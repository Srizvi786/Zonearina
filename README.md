# ZoneRoyale

Offline battle royale for Android (Godot 4.3). 12 fighters drop in, blue zone shrinks, last one standing wins. No server, no login, 100% offline.

## Features
- Plane drop + parachute landing (tap minimap to pick zone)
- Third-person shooting: rifle / SMG / sniper
- Loot: ammo, meds, helmet, vest, grenades, extended mag
- Shrinking blue zone with escalating damage
- 11 AI bots (rushers, campers, loot runners) + Easy/Normal/Hard
- Mobile controls: left stick move, right side aim, FIRE/JUMP/AIM/RLD/BOMB buttons
- HUD: HP, ammo, kills, alive count, zone timer, compass, minimap, kill feed
- Procedural SFX (no audio files)

## Install APK (Android)
1. GitHub repo -> **Actions** tab -> wait for `Build ZoneRoyale APK`
2. Open the run -> bottom **Artifacts** -> download `ZoneRoyale-apk`
3. Unzip, install `ZoneRoyale.apk` (allow unknown sources)

Or use **Releases** after running `Release ZoneRoyale APK` workflow (direct APK download link).

## Controls
| Action | Touch | Keyboard |
|---|---|---|
| Move | Left virtual stick | WASD |
| Aim | Right-side drag | Q/E or mouse |
| Fire | FIRE button | Space / left click |
| Jump | JUMP button | Space |
| Reload | RLD button | R |
| Crouch | CRCH button | - |
| Grenade | BOMB button | - |
| Heal | MED / BND / DRK | - |

## Package
- App name: ZoneRoyale
- Package: `com.zoneroyle.game`
- Engine: Godot 4.3 (MIT)

## Note
Original battle-royale-inspired game. Not affiliated with any existing branded title.
