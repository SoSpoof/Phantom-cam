local SOURCE_URL = "https://raw.githubusercontent.com/SoSpoof/Phantom-cam/main/phantomcam.lua"

local HOST = getgenv().PhantomCamHost == true
getgenv().PhantomCamHost = nil

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local MAX_TURN = 0.6
local MAX_PITCH = 1.5

for _, name in ipairs({ "PhantomCamApi", "PhantomCam" }) do
    local previous = getgenv()[name]
    if type(previous) == "table" and type(previous.Destroy) == "function" then pcall(previous.Destroy) end
    getgenv()[name] = nil
end

local Cam = {
    settings = {
        strength = 1, smoothing = 0, position = 0, roll = false, onlyAiming = false, noScope = false,
        mode = "Barrel", hideViewmodel = true, hideHat = true, forward = 0.5, fov = 0,
    },
    mods = {},
    hidden = { view = {}, hat = {} },
    scanAt = { view = 0, hat = 0 },
    amount = 0,
    running = false,
    warned = {},
    bindName = "pc" .. tostring(math.random(100000, 999999)),
    retryAt = 0,
    keys = {},
}

local function note(key, ...)
    if Cam.warned[key] then return end
    Cam.warned[key] = true
    warn("[Aster]", ...)
end

local function wrap(angle)
    return (angle + math.pi) % (math.pi * 2) - math.pi
end

local function same(a, b)
    return a.Position == b.Position and a.LookVector == b.LookVector and a.UpVector == b.UpVector
end

local function bind(name, priority, fn)
    local ok = pcall(function() RunService:BindToRenderStep(name, priority, fn) end)
    if ok then
        return function() pcall(function() RunService:UnbindFromRenderStep(name) end) end
    end
    local connection = RunService.RenderStepped:Connect(fn)
    return function() connection:Disconnect() end
end

local function cameraPriority()
    local ok, value = pcall(function() return Enum.RenderPriority.Camera.Value end)
    return (ok and type(value) == "number" and value or 200) + 1
end

function Cam.load()
    if Cam.mods.CharacterInterface then return end
    local now = os.clock()
    if now < Cam.retryAt then return end
    Cam.retryAt = now + 3
    local requireFn
    pcall(function() requireFn = getrenv().shared.require end)
    local ok, module = false, nil
    if type(requireFn) == "function" then ok, module = pcall(requireFn, "CharacterInterface") end
    if not (ok and type(module) == "table") and type(getloadedmodules) == "function" then
        pcall(function()
            for _, loaded in ipairs(getloadedmodules()) do
                if loaded.Name == "CharacterInterface" then
                    local okRequire, result = pcall(require, loaded)
                    if okRequire and type(result) == "table" then ok, module = true, result break end
                end
            end
        end)
    end
    if ok and type(module) == "table" then Cam.mods.CharacterInterface = module end
end

function Cam.weapon()
    local interface = Cam.mods.CharacterInterface
    if not interface then return nil end
    local ok, weapon = pcall(function()
        if not interface.isAlive() then return nil end
        local character = interface.getCharacterObject()
        local controller = character and character:getWeaponController()
        return controller and controller:getActiveWeapon()
    end)
    if ok and type(weapon) == "table" then return weapon end
    return nil
end

function Cam.barrel(weapon)
    if type(weapon.getBarrelCFrame) ~= "function" then return nil end
    local ok, frame = pcall(weapon.getBarrelCFrame, weapon)
    if not (ok and typeof(frame) == "CFrame") then return nil end
    local position, look = frame.Position, frame.LookVector
    if position ~= position or look ~= look then return nil end
    return frame
end

function Cam.aiming(weapon)
    if type(weapon.isAiming) ~= "function" then return false end
    local ok, state = pcall(weapon.isAiming, weapon)
    return ok and state == true
end

function Cam.zoom(weapon)
    if type(weapon.getActiveAimStats) ~= "function" then return 1 end
    local ok, stats = pcall(weapon.getActiveAimStats, weapon)
    if not ok or type(stats) ~= "table" then return 1 end
    local total = 1
    for _, stat in ipairs(stats) do
        local magnify = type(stat.sightmagspring) == "table" and stat.sightmagspring.p
        local zoom = stat.zoom
        if type(zoom) == "number" and zoom > 0 and type(magnify) == "number" then
            total = total * zoom ^ math.clamp(magnify, 0, 1)
        end
    end
    return total
end

function Cam.head()
    local ok, position = pcall(function()
        local character = game:GetService("Players").LocalPlayer.Character
        local head = character and character:FindFirstChild("Head")
        if head and head.Parent then return head.Position end
        local interface = Cam.mods.CharacterInterface
        local object = interface and interface.getCharacterObject()
        local root = object and object:getRealRootPart()
        if root then return root.Position + Vector3.new(0, 1.5, 0) end
        return nil
    end)
    if ok and typeof(position) == "Vector3" and position == position then return position end
    return nil
end

function Cam.collectView(camera)
    local list = {}
    local ok, children = pcall(camera.GetChildren, camera)
    if not (ok and type(children) == "table") then return list end
    for _, child in ipairs(children) do
        if child.ClassName == "Model" then
            local okDescendants, descendants = pcall(child.GetDescendants, child)
            for _, part in ipairs(okDescendants and descendants or {}) do
                if part:IsA("BasePart") then list[#list + 1] = part end
            end
        end
    end
    return list
end

function Cam.collectHat()
    local list = {}
    pcall(function()
        local character = game:GetService("Players").LocalPlayer.Character
        if not character then return end
        local head = character:FindFirstChild("Head")
        if head then list[#list + 1] = head end
        for _, child in ipairs(character:GetChildren()) do
            if child.ClassName == "Accessory" or child.ClassName == "Hat" then
                for _, part in ipairs(child:GetDescendants()) do
                    if part:IsA("BasePart") then list[#list + 1] = part end
                end
            end
        end
    end)
    return list
end

function Cam.restoreHidden(kind)
    for part, original in pairs(Cam.hidden[kind]) do
        pcall(function() part.LocalTransparencyModifier = original end)
    end
    Cam.hidden[kind] = {}
    Cam.scanAt[kind] = 0
end

function Cam.syncHidden(kind, want, collect, now)
    if not want then
        if next(Cam.hidden[kind]) then Cam.restoreHidden(kind) end
        return
    end
    if now < Cam.scanAt[kind] then return end
    Cam.scanAt[kind] = now + 0.25
    local store = Cam.hidden[kind]
    for _, part in ipairs(collect()) do
        if store[part] == nil then
            local ok, original = pcall(function() return part.LocalTransparencyModifier end)
            store[part] = ok and type(original) == "number" and original or 0
        end
        pcall(function() part.LocalTransparencyModifier = 1 end)
    end
end

function Cam.applyFov(camera, value)
    if camera.FieldOfView ~= Cam.fovWritten then Cam.fovGame = camera.FieldOfView end
    if value >= 20 then
        camera.FieldOfView = value
        Cam.fovWritten = value
    elseif Cam.fovWritten then
        if camera.FieldOfView == Cam.fovWritten then camera.FieldOfView = Cam.fovGame end
        Cam.fovWritten = nil
    end
end

function Cam.reset()
    Cam.amount, Cam.smoothed, Cam.smoothedPos, Cam.written = 0, nil, nil, nil
end

function Cam.step(dt)
    local camera = Workspace.CurrentCamera
    if not camera then return end
    dt = math.clamp(dt or 1 / 60, 1 / 240, 0.1)
    local current = camera.CFrame
    local frame = current
    if Cam.written and Cam.gameCFrame and same(current, Cam.written) then frame = Cam.gameCFrame end
    Cam.gameCFrame = frame

    Cam.load()
    local s = Cam.settings
    local world = s.mode == "World character"
    local now = os.clock()
    local function hiding(active)
        Cam.syncHidden("view", active and s.hideViewmodel, function() return Cam.collectView(camera) end, now)
        Cam.syncHidden("hat", active and s.hideHat, Cam.collectHat, now)
    end
    Cam.applyFov(camera, s.fov)
    local weapon = Cam.weapon()
    local barrel = weapon and Cam.barrel(weapon)
    local head = world and Cam.head()
    if not barrel and not head then
        hiding(false)
        Cam.reset()
        return
    end
    local target = 1
    local aiming = weapon and Cam.aiming(weapon)
    if s.onlyAiming and not aiming then target = 0 end
    if s.noScope and aiming and Cam.zoom(weapon) > 1.2 then target = 0 end
    Cam.amount = Cam.amount + (target - Cam.amount) * (1 - math.exp(-dt * 12))
    hiding(world and Cam.amount > 0.05)
    local idle = not world and s.strength <= 0 and s.position <= 0
    if Cam.amount < 0.002 or idle then
        Cam.smoothed, Cam.smoothedPos, Cam.written = nil, nil, nil
        return
    end
    barrel = barrel or frame

    local gx, gy, gz = frame:ToOrientation()
    local bx, by, bz = barrel:ToOrientation()
    local dx, dy = bx - gx, wrap(by - gy)
    local size = math.sqrt(dx * dx + dy * dy)
    if size > MAX_TURN then dx, dy = dx * MAX_TURN / size, dy * MAX_TURN / size end
    local rawTurn = Vector3.new(dx, dy, s.roll and wrap(bz - gz) or 0)
    local rawPos = Vector3.zero
    if not world and s.position > 0 then rawPos = frame:PointToObjectSpace(barrel.Position) * s.position end

    if Cam.smoothed and s.smoothing > 0 then
        local rate = 1 + 59 * (1 - math.clamp(s.smoothing, 0, 1)) ^ 2
        local alpha = 1 - math.exp(-dt * rate)
        Cam.smoothed = Cam.smoothed + (rawTurn - Cam.smoothed) * alpha
        Cam.smoothedPos = Cam.smoothedPos + (rawPos - Cam.smoothedPos) * alpha
    else
        Cam.smoothed, Cam.smoothedPos = rawTurn, rawPos
    end

    local k = s.strength * Cam.amount
    local turn = Cam.smoothed
    local origin = frame:PointToWorldSpace(Cam.smoothedPos * Cam.amount)
    local pitch = math.clamp(gx + turn.X * k, -MAX_PITCH, MAX_PITCH)
    local rotation = CFrame.fromOrientation(pitch, gy + turn.Y * k, gz + turn.Z * k)
    if head then
        local eye = head + rotation.LookVector * s.forward
        origin = frame.Position + (eye - frame.Position) * Cam.amount
    end
    camera.CFrame = CFrame.new(origin) * rotation
    Cam.written = camera.CFrame
end

local API = {}

function API.Start()
    if Cam.running then return true end
    Cam.reset()
    Cam.unbind = bind(Cam.bindName, cameraPriority(), function(dt)
        local ok, problem = pcall(Cam.step, dt)
        if not ok then note("step" .. tostring(problem), "PhantomCam:", problem) end
    end)
    Cam.running = true
    return true
end

function API.Stop()
    if not Cam.running then return end
    Cam.running = false
    if Cam.unbind then pcall(Cam.unbind) end
    Cam.unbind = nil
    local camera = Workspace.CurrentCamera
    if camera and Cam.written and Cam.gameCFrame then
        local ok, untouched = pcall(same, camera.CFrame, Cam.written)
        if ok and untouched then pcall(function() camera.CFrame = Cam.gameCFrame end) end
    end
    Cam.gameCFrame = nil
    if camera then pcall(Cam.applyFov, camera, 0) end
    Cam.restoreHidden("view")
    Cam.restoreHidden("hat")
    Cam.reset()
end

local LIMITS = { strength = 1.5, forward = 2, fov = 120 }

function API.Set(key, value)
    local s = Cam.settings
    if s[key] == nil then return end
    if type(s[key]) == "number" then
        value = tonumber(value)
        if not value then return end
        value = math.clamp(value, 0, LIMITS[key] or 1)
    elseif type(s[key]) == "string" then
        if value ~= "Barrel" and value ~= "World character" then return end
    else
        value = value == true
    end
    s[key] = value
end

function API.Sync(read)
    API.Set("strength", read("strength", 1))
    API.Set("smoothing", read("smooth", 0))
    API.Set("position", read("position", 0))
    API.Set("roll", read("roll", false))
    API.Set("onlyAiming", read("aiming", false))
    API.Set("noScope", read("noscope", false))
    API.Set("mode", read("mode", "Barrel"))
    API.Set("hideViewmodel", read("viewmodel", true))
    API.Set("hideHat", read("hat", true))
    API.Set("forward", read("forward", 0.5))
    API.Set("fov", read("fov", 0))
    local on = read("on", false) == true
    if on and not Cam.running then API.Start() elseif not on and Cam.running then API.Stop() end
end

function API.GameCFrame()
    if Cam.running then return Cam.gameCFrame end
    return nil
end

function API.Active()
    return Cam.running
end

function API.Destroy()
    API.Stop()
    for _, connection in ipairs(Cam.keys) do pcall(function() connection:Disconnect() end) end
    Cam.keys = {}
    if getgenv().PhantomCamApi == API then getgenv().PhantomCamApi = nil end
    if getgenv().PhantomCam == API then getgenv().PhantomCam = nil end
end

getgenv().PhantomCamApi = API

if HOST then return API end


local function standalone()
    do
        local function inGameVm()
            local ok, request = pcall(function() return getrenv().shared.require end)
            return ok and type(request) == "function"
        end
        local inActor = getgenv().PC_INACTOR
        getgenv().PC_INACTOR = nil
        if not inActor and not inGameVm() then
            local source = getgenv().PC_SOURCE
            if (type(source) ~= "string" or #source < 500) and SOURCE_URL ~= "" then
                local okGet, body = pcall(game.HttpGet, game, SOURCE_URL)
                if okGet and type(body) == "string" then source = body end
            end
            local run, list
            if type(getactorthreads) == "function" and type(run_on_thread) == "function" then
                run, list = run_on_thread, getactorthreads
            elseif type(getactors) == "function" and type(run_on_actor) == "function" then
                run, list = run_on_actor, getactors
            elseif type(getdeletedactors) == "function" and type(run_on_actor) == "function" then
                run, list = run_on_actor, getdeletedactors
            end
            if type(source) ~= "string" or #source < 500 then
                warn("[PhantomCam] Not inside the game's actor and no source to relaunch with. Set getgenv().PC_SOURCE")
            elseif not run or type(create_comm_channel) ~= "function" or type(get_comm_channel) ~= "function" then
                warn("[PhantomCam] This executor cannot run code inside actors")
            else
                local probe = [=[
                    local Channel = get_comm_channel(...)
                    local ok, request = pcall(function() return getrenv().shared.require end)
                    if ok and type(request) == "function" then Channel:Fire() end
                ]=]
                local okList, actors = pcall(list)
                local found = false
                if okList and type(actors) == "table" then
                    for _, actor in ipairs(actors) do
                        if found then break end
                        local okChannel, index, channel = pcall(create_comm_channel)
                        if okChannel and channel then
                            local function onReply()
                                if found then return end
                                found = true
                                getgenv().PC_INACTOR = true
                                pcall(run, actor, "getgenv().PC_INACTOR = true\n" .. source)
                            end
                            if not pcall(function() channel.Event:Connect(onReply) end) then
                                pcall(function() channel:connect(onReply) end)
                            end
                            pcall(run, actor, probe, index)
                        end
                    end
                    local started = os.clock()
                    while not found and os.clock() - started < 5 do task.wait(0.1) end
                end
                if found then return end
                warn("[PhantomCam] No actor with the game's modules was found")
            end
        end
    end

    local config = type(getgenv().PhantomCamConfig) == "table" and getgenv().PhantomCamConfig or {}
    local fields = {
        Mode = "mode", Strength = "strength", Smooth = "smoothing", Position = "position", Roll = "roll",
        Viewmodel = "hideViewmodel", Hat = "hideHat", Forward = "forward", FOV = "fov",
        OnlyAiming = "onlyAiming", NoScope = "noScope",
    }
    API.Set("mode", "World character")
    API.Set("smoothing", 0.25)
    for field, key in pairs(fields) do
        if config[field] ~= nil then API.Set(key, config[field]) end
    end

    local function keyOf(value, default)
        if typeof(value) == "EnumItem" then return value end
        if type(value) == "string" then
            local ok, item = pcall(function() return Enum.KeyCode[value] end)
            if ok and item then return item end
        end
        return default
    end
    local toggleKey = keyOf(config.ToggleKey, Enum.KeyCode.P)
    local unloadKey = keyOf(config.UnloadKey, Enum.KeyCode.End)

    table.insert(Cam.keys, UserInputService.InputBegan:Connect(function(input, processed)
        if processed or UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == unloadKey then
            API.Destroy()
        elseif input.KeyCode == toggleKey then
            if Cam.running then API.Stop() else API.Start() end
        end
    end))

    getgenv().PhantomCam = API
    API.Start()
end

local ok, problem = xpcall(standalone, debug.traceback)
if not ok then warn("[PhantomCam] FAILED:\n" .. tostring(problem)) end

return API
