```lua
-- optional, set BEFORE loading (every field is optional)
getgenv().PhantomCamConfig = {
    Mode = "World character", -- or "Barrel"
    Strength = 1,
    Smooth = 0.25,
    Position = 0,
    Roll = false,
    Viewmodel = true, -- hide first-person arms/weapon (World character)
    Hat = true,       -- hide head/hat (World character)
    Forward = 0.5,
    FOV = 0,          -- 0 keeps the game's FOV
    OnlyAiming = false,
    NoScope = false,
    ToggleKey = Enum.KeyCode.P,
    UnloadKey = Enum.KeyCode.End,
}

loadstring(game:HttpGet("https://raw.githubusercontent.com/WhyWKey/linoria/main/phantomcam.lua"))()
```
