# Phantom Cam

A body-cam style camera for Phantom Forces. The view follows your weapon barrel, or sits on your world character with the viewmodel and hat hidden. It has no menu: it starts as soon as it loads.

## Usage

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/SoSpoof/Phantom-cam/main/phantomcam.lua"))()
```

| Key | Action |
|---|---|
| `P` | Toggle on/off |
| `End` | Unload completely and restore your normal view |

Running it again replaces the previous instance.

## Optional settings

Set this before the loadstring. Every field is optional.

```lua
getgenv().PhantomCamConfig = {
    Mode = "World character", -- or "Barrel"
    Strength = 1,             -- 0 to 1.5, how far the view turns toward the barrel
    Smooth = 0.25,            -- 0 = instant, higher = softer
    Position = 0,             -- 0 to 1, blend the camera origin toward the muzzle
    Roll = false,             -- include barrel roll
    Viewmodel = true,         -- hide first-person arms/weapon (World character)
    Hat = true,               -- hide head/hat (World character)
    Forward = 0.5,            -- camera offset from the head, in studs
    FOV = 0,                  -- 0 keeps the game's FOV
    OnlyAiming = false,       -- only active while aiming down sights
    NoScope = false,          -- disable while scoped
    ToggleKey = Enum.KeyCode.P,
    UnloadKey = Enum.KeyCode.End,
}
```

Keys can also be strings, for example `ToggleKey = "K"`.

## API

`getgenv().PhantomCam` exposes `Start`, `Stop`, `Set(key, value)`, `Active` and `Destroy`.

## Troubleshooting

The script relaunches itself inside the game's actor, so your executor needs actor support. If you see "Not inside the game's actor and no source to relaunch with", run this first:

```lua
getgenv().PC_SOURCE = game:HttpGet("https://raw.githubusercontent.com/SoSpoof/Phantom-cam/main/phantomcam.lua")
```
