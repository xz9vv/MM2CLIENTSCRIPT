-- =============================================================================
-- MM2CLIENTSCRIPT: Farming & Gameplay Module (farm.lua)
-- Manages smooth tweening, noclip, anti-trail, instant touch, and void flings.
-- =============================================================================

local Farm = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- Shared Global Settings (Synced from Python)
local IsFarming = false
local TweenSpeed = 30
local YOffset = 1.5

-- Cooperative State Memory
local BlacklistedCoins = setmetatable({}, { __mode = "k" }) -- Weak-keys prevent memory leaks
local forceScatterPivot = false
local scatterPivotSource = nil
local CurrentCoins = 0
local LastStatus = "Alive"
local CurrentRoundPhase = "Lobby"

-- Platform, Tween, & Container Caches
local farmPlatform = nil
local cachedCoinContainer = nil
local CurrentTween = nil

-- =============================================================================
-- WORKSPACE PATHFINDING COIN SCANNER
-- =============================================================================

local function findCoinContainer()
    if cachedCoinContainer and cachedCoinContainer.Parent then
        return cachedCoinContainer
    end
    -- Dynamically locate MM2's active map coin folder
    local container = Workspace:FindFirstChild("CoinContainer", true) or Workspace:FindFirstChild("Coin_Container", true)
    if container then
        cachedCoinContainer = container
    end
    return container
end

local function getCoins()
    local container = findCoinContainer()
    if container then
        return container:GetChildren()
    end
    return {}
end

-- =============================================================================
-- YOUR VERIFIED DARK DEX PATHWAY (Coin Bag UI Reader)
-- =============================================================================
local function getExactBagCoinCount()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if playerGui then
        local mainGui = playerGui:FindFirstChild("MainGUI")
        if mainGui then
            local gameFrame = mainGui:FindFirstChild("Game")
            if gameFrame then
                local coinBags = gameFrame:FindFirstChild("CoinBags")
                if coinBags then
                    local container = coinBags:FindFirstChild("Container")
                    if container then
                        local coin = container:FindFirstChild("Coin")
                        if coin then
                            local currencyFrame = coin:FindFirstChild("CurrencyFrame")
                            if currencyFrame then
                                local icon = currencyFrame:FindFirstChild("Icon")
                                if icon then
                                    local coinsLabel = icon:FindFirstChild("Coins")
                                    if coinsLabel and coinsLabel:IsA("TextLabel") then
                                        local current, capacity = coinsLabel.Text:match("(%d+)/(%d+)")
                                        if current and capacity then
                                            return tonumber(current), tonumber(capacity)
                                        end
                                        local num = tonumber(coinsLabel.Text:match("%d+"))
                                        if num then return num, 10 end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return 0, 10
end

local function isBagFull()
    local current, capacity = getExactBagCoinCount()
    return current >= capacity
end

-- =============================================================================
-- PHYSICS PLATFORM & NOCLIP UTILITIES
-- =============================================================================

local function setNoclip(state)
    task.spawn(function()
        local char = LocalPlayer.Character
        if char then
            for _, child in ipairs(char:GetDescendants()) do
                if child:IsA("BasePart") then
                    child.CanCollide = not state
                end
            end
        end
    end)
end

local function createFarmPlatform()
    if farmPlatform and farmPlatform.Parent then return farmPlatform end
    
    local part = Instance.new("Part")
    part.Name = "LocalFarmPlatform"
    part.Size = Vector3.new(8, 1, 8)
    part.Color = Color3.fromRGB(0, 0, 0)
    part.Material = Enum.Material.SmoothPlastic
    part.CanCollide = true
    part.Anchored = true
    part.CastShadow = false
    part.Parent = Workspace

    farmPlatform = part
    return part
end

local function destroyFarmPlatform()
    if farmPlatform then
        pcall(function() farmPlatform:Destroy() end)
        farmPlatform = nil
    end
end

-- =============================================================================
-- FOOLPROOF WEAPON & ROLE DETECTOR
-- =============================================================================

local function isMurdererWeapon(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local nameLower = tool.Name:lower()
    
    if nameLower:find("knife", 1, true) or nameLower:find("blade", 1, true) or nameLower:find("dagger", 1, true) or nameLower == "bat" then
        return true
    end
    if tool:FindFirstChild("KnifeServer") or tool:FindFirstChild("KnifeClient") then
        return true
    end
    return false
end

local function getPublicMurderer()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local equipped = player.Character:FindFirstChildOfClass("Tool")
            if equipped and isMurdererWeapon(equipped) then
                return player
            end
            local backpack = player:FindFirstChild("Backpack")
            if backpack then
                for _, item in ipairs(backpack:GetChildren()) do
                    if isMurdererWeapon(item) then
                        return player
                    end
                end
            end
        end
    end
    return nil
end

-- =============================================================================
-- PUBLIC INTERFACE & COMMAND COOPERATIVE SYSTEMS
-- =============================================================================

function Farm.forceReset()
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.Health = 0
        print("[Farm] Clean Exit Reset applied successfully.")
    end
end

function Farm.fling()
    local targetPlayer = getPublicMurderer()
    if not targetPlayer then return end

    task.spawn(function()
        local desiredPhysics = PhysicalProperties.new(100, 0.3, 0.5)
        local active = true

        while active do
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")

            local mChar = targetPlayer.Character
            local mHRP = mChar and mChar:FindFirstChild("HumanoidRootPart")
            local mHum = mChar and mChar:FindFirstChildOfClass("Humanoid")

            if not hrp or not mHRP or not hum or hum.Health <= 0 or not mHum or mHum.Health <= 0 then
                break
            end

            if mHRP.Position.Y < -20 then break end

            setNoclip(true)
            hum.PlatformStand = true

            if hrp.CustomPhysicalProperties ~= desiredPhysics then
                hrp.CustomPhysicalProperties = desiredPhysics
            end

            hrp.AssemblyAngularVelocity = Vector3.new(0, 999999, 0)
            hrp.AssemblyLinearVelocity = Vector3.new(0, -2500, 0)

            hrp.CFrame = mHRP.CFrame * CFrame.new(math.random(-50, 50)/100, 2.5, math.random(-50, 50)/100)
            
            RunService.Heartbeat:Wait()
        end

        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = false end
        if hrp then
            hrp.AssemblyAngularVelocity = Vector3.new(0,0,0)
            hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
        end
    end)
end

function Farm.applySettings(settings)
    if settings.farm_enabled ~= nil then 
        IsFarming = settings.farm_enabled 
        if IsFarming then
            Farm.start()
        else
            -- Cleanly abort any active tweens immediately if farm is toggled off
            if CurrentTween then
                pcall(function() 
                    CurrentTween:Cancel() 
                    CurrentTween:Destroy() 
                end)
                CurrentTween = nil
            end
            destroyFarmPlatform()
            setNoclip(false)
        end
    end
    if settings.tween_speed ~= nil then TweenSpeed = settings.tween_speed end
    if settings.offset ~= nil then YOffset = settings.offset end
end

-- =============================================================================
-- SMOOTH AUTO-FARMING LOOPS
-- =============================================================================

local activeFarmingLoop = false
function Farm.start()
    if activeFarmingLoop then return end
    activeFarmingLoop = true

    task.spawn(function()
        while IsFarming do
            task.wait(0.01)

            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")

            if not hrp or not hum or hum.Health <= 0 then
                if CurrentTween then
                    pcall(function() CurrentTween:Cancel() CurrentTween:Destroy() end)
                    CurrentTween = nil
                end
                destroyFarmPlatform()
                setNoclip(false)
                task.wait(0.5)
                continue
            end

            -- Stop and exit back to lobby if the bag is full
            local full = isBagFull()
            if full then
                if CurrentTween then
                    pcall(function() CurrentTween:Cancel() CurrentTween:Destroy() end)
                    CurrentTween = nil
                end
                destroyFarmPlatform()
                setNoclip(false)
                local lobbySpawn = Workspace:FindFirstChild("Lobby") and Workspace.Lobby:FindFirstChild("Spawn")
                if lobbySpawn then
                    hrp.CFrame = lobbySpawn.CFrame + Vector3.new(0, 3, 0)
                end
                task.wait(1)
                continue
            end

            setNoclip(true)
            local platform = createFarmPlatform()
            platform.CFrame = hrp.CFrame * CFrame.new(0, -3.5, 0)

            local coins = getCoins()
            if #coins == 0 then
                task.wait(0.5)
                continue
            end

            -- Locate nearest active coin
            local closestCoin = nil
            local minDistance = math.huge

            for _, coin in ipairs(coins) do
                if coin and coin:IsA("BasePart") and coin.Parent then
                    local blacklisted = BlacklistedCoins[coin]
                    if not blacklisted or tick() >= blacklisted then
                        local dist = (hrp.Position - coin.Position).Magnitude
                        if dist < minDistance then
                            minDistance = dist
                            closestCoin = coin
                        end
                    end
                end
            end

            if closestCoin then
                local targetCFrame = closestCoin.CFrame + Vector3.new(0, YOffset, 0)
                local duration = minDistance / math.clamp(TweenSpeed, 10, 100)

                BlacklistedCoins[closestCoin] = tick() + duration + 1.5

                local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
                CurrentTween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame})
                CurrentTween:Play()

                local startTime = tick()
                while (tick() - startTime) < duration and closestCoin and closestCoin.Parent and hum.Health > 0 and IsFarming do
                    if farmPlatform and farmPlatform.Parent then
                        farmPlatform.CFrame = hrp.CFrame * CFrame.new(0, -3.5, 0)
                    end

                    -- Proximity check for instant touch collection
                    local currentDist = (hrp.Position - closestCoin.Position).Magnitude
                    if currentDist <= 1.5 then
                        pcall(function()
                            CurrentTween:Cancel()
                            if firetouchinterest then
                                firetouchinterest(hrp, closestCoin, 0)
                                task.wait()
                                firetouchinterest(hrp, closestCoin, 1)
                            end
                        end)
                        break
                    end
                    RunService.Heartbeat:Wait()
                end
                
                if CurrentTween then
                    pcall(function() CurrentTween:Destroy() end)
                    CurrentTween = nil
                end
            end
        end
        destroyFarmPlatform()
        setNoclip(false)
        activeFarmingLoop = false
    end)
end

-- =============================================================================
-- BACKGROUND TELEMETRY LOOPS
-- =============================================================================

-- 1. Real-Time Coin Bag Telemetry Loop
task.spawn(function()
    while true do
        task.wait(0.2)
        pcall(function()
            local current, capacity = getExactBagCoinCount()
            if current > CurrentCoins then
                CurrentCoins = current
                if shared.Connection then
                    shared.Connection.send({
                        ["event"] = "coin_collected",
                        ["coins"] = CurrentCoins,
                        ["target"] = 1000
                    })
                    if CurrentCoins >= capacity then
                        shared.Connection.send({
                            ["event"] = "full_bag",
                            ["bag_count"] = CurrentCoins
                        })
                    end
                end
            end
        end)
    end
end)

-- 2. Character Death Status Change Tracker
task.spawn(function()
    while true do
        task.wait(1)
        pcall(function()
            local char = LocalPlayer.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            local status = (humanoid and humanoid.Health > 0) and "Alive" or "Dead"
            
            if status ~= LastStatus then
                LastStatus = status
                if shared.Connection then
                    shared.Connection.send({
                        ["event"] = "status_changed",
                        ["status"] = LastStatus
                    })
                end
            end
        end)
    end
end)

-- 3. Game State / Round Reset Listener
task.spawn(function()
    local lastPhase = ""
    while true do
        task.wait(1)
        pcall(function()
            local timerValue = ReplicatedStorage:FindFirstChild("Timer")
            local statusValue = ReplicatedStorage:FindFirstChild("Status")
            
            if statusValue then
                local currentText = statusValue.Value
                local phase = "InGame"
                local mapName = "Unknown"
                
                if currentText:match("Intermission") then
                    phase = "Intermission"
                elseif currentText:match("Voting") then
                    phase = "Voting"
                elseif currentText:match("ended") then
                    phase = "Lobby"
                end
                
                local mapFolder = Workspace:FindFirstChild("Normal") or Workspace:FindFirstChild("Sandbox")
                if mapFolder and mapFolder:GetChildren()[1] then
                    mapName = mapFolder:GetChildren()[1].Name
                end

                if phase ~= lastPhase then
                    lastPhase = phase
                    CurrentRoundPhase = phase
                    
                    if shared.Connection then
                        shared.Connection.send({
                            ["event"] = "round_state_changed",
                            ["phase"] = phase,
                            ["map"] = mapName
                        })
                    end
                    
                    if phase == "Lobby" then
                        CurrentCoins = 0
                        if shared.Connection then
                            shared.Connection.send({["event"] = "round_ended"})
                        end
                    end
                end
            end
        end)
    end
end)

return Farm
