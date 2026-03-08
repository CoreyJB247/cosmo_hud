local isDriving = false
local isUnderwater = false
local wasUnderwater = nil
local wasPaused = nil
local wasDriving = nil

-- NDCore is a global injected automatically by ND_Core.
Citizen.CreateThread(function()
    while not NDCore do
        Wait(100)
    end
    if Config.UnitOfSpeed == "kmh" then
        SpeedMultiplier = 3.6
    else
        SpeedMultiplier = 2.236936
    end
end)

-- pma-voice: track voice range (1=whisper, 2=normal, 3=shout)
local voiceRange = 2
AddEventHandler('pma-voice:setTalkingMode', function(newRange)
    voiceRange = newRange
    SendNUIMessage({ action = "voice_level", voicelevel = newRange })
end)

-- pma-voice: track radio state for headset icon
AddEventHandler('pma-voice:radioActive', function(isRadioTalking)
    SendNUIMessage({ radio = isRadioTalking })
end)

-- One-time config messages after NUI is ready
Citizen.CreateThread(function()
    Wait(2000)
    if not Config.ShowStress then
        SendNUIMessage({ action = "disable_stress" })
    end
    if not Config.ShowVoice then
        SendNUIMessage({ action = "disable_voice" })
    end
    if not Config.ShowFuel then
        SendNUIMessage({ showFuel = false })
    end
end)

-- Speedometer value update (fast tick)
Citizen.CreateThread(function()
    while true do
        Wait(100)
        if isDriving and IsPedInAnyVehicle(PlayerPedId(), true) then
            local veh = GetVehiclePedIsUsing(PlayerPedId(), false)
            local speed = math.floor(GetEntitySpeed(veh) * (SpeedMultiplier or 2.236936))
            local vehhash = GetEntityModel(veh)
            local maxspeed = GetVehicleModelMaxSpeed(vehhash) * 3.6
            SendNUIMessage({ speed = speed, maxspeed = maxspeed })
        end
    end
end)

-- Driving state: only send showSpeedo when state CHANGES
Citizen.CreateThread(function()
    while true do
        Wait(1000)
        if Config.ShowSpeedo then
            local inVehicle = IsPedInAnyVehicle(PlayerPedId(), false)
                and not IsPedInFlyingVehicle(PlayerPedId())
                and not IsPedInAnySub(PlayerPedId())

            if inVehicle ~= wasDriving then
                wasDriving = inVehicle
                isDriving = inVehicle
                SendNUIMessage({ showSpeedo = inVehicle })
                if not inVehicle then
                    SendNUIMessage({ speed = 0 })
                end
            end
        end
    end
end)

-- Main HUD update
Citizen.CreateThread(function()
    while true do
        Wait(500)

        -- Oxygen: only toggle on change
        local underwater = IsPedSwimmingUnderWater(PlayerPedId())
        if underwater ~= wasUnderwater then
            wasUnderwater = underwater
            isUnderwater = underwater
            SendNUIMessage({ showOxygen = underwater })
        end

        -- Pause menu: only toggle on change
        local paused = IsPauseMenuActive()
        if paused ~= wasPaused then
            wasPaused = paused
            SendNUIMessage({ showUi = not paused })
        end

        -- Get ALL statuses in one call - each has a .status field (0-100)
        local all = exports["ND_Status"]:getStatus("hunger")
        local hunger  = (all and all.hunger  and all.hunger.status)  or 0
        local thirst  = (all and all.thirst  and all.thirst.status)  or 0
        local stamina = (all and all.stamina and all.stamina.status) or 0
        local alcohol = (all and all.alcohol and all.alcohol.status) or 0
        local stress  = 0
        if Config.ShowStress then
            stress = (all and all.stress and all.stress.status) or 0
        end

        SendNUIMessage({
            action  = "update_hud",
            hp      = GetEntityHealth(PlayerPedId()) - 100,
            armor   = GetPedArmour(PlayerPedId()),
            hunger  = hunger,
            thirst  = thirst,
            stress  = stress,
            stamina = stamina,
            alcohol = alcohol,
            oxygen  = GetPlayerUnderwaterTimeRemaining(PlayerId()) * 10,
            talking = MumbleIsPlayerTalking(PlayerId())
        })
    end
end)

-- Radar zoom + fuel update (slow tick)
CreateThread(function()
    while true do
        Wait(2000)
        SetRadarZoom(1150)

        if Config.AlwaysShowRadar then
            DisplayRadar(true)
        else
            DisplayRadar(IsPedInAnyVehicle(PlayerPedId(-1), false))
        end

        if Config.ShowFuel and isDriving and IsPedInAnyVehicle(PlayerPedId(), true) then
            local veh = GetVehiclePedIsUsing(PlayerPedId(), false)
            SendNUIMessage({
                action   = "update_fuel",
                fuel     = GetVehicleFuelLevel(veh),
                showFuel = true
            })
        end
    end
end)

-- Map / minimap setup
local x = -0.025
local y = -0.015
local w = 0.16
local h = 0.25

Citizen.CreateThread(function()
    local minimap = RequestScaleformMovie("minimap")
    RequestStreamedTextureDict("circlemap", false)
    while not HasStreamedTextureDictLoaded("circlemap") do Wait(100) end
    AddReplaceTexture("platform:/textures/graphics", "radarmasksm", "circlemap", "radarmasksm")

    SetMinimapClipType(1)
    SetMinimapComponentPosition('minimap', 'L', 'B', x, y, w, h)
    SetMinimapComponentPosition('minimap_mask', 'L', 'B', x + 0.17, y + 0.09, 0.072, 0.162)
    SetMinimapComponentPosition('minimap_blur', 'L', 'B', -0.035, -0.03, 0.18, 0.22)
    Wait(5000)
    SetRadarBigmapEnabled(true, false)
    Wait(0)
    SetRadarBigmapEnabled(false, false)

    while true do
        Wait(0)
        BeginScaleformMovieMethod(minimap, "SETUP_HEALTH_ARMOUR")
        ScaleformMovieMethodAddParamInt(3)
        EndScaleformMovieMethod()
        BeginScaleformMovieMethod(minimap, 'HIDE_SATNAV')
        EndScaleformMovieMethod()
    end
end)

RegisterCommand("togglehud", function()
    SendNUIMessage({ action = "toggle_hud" })
end, false)
