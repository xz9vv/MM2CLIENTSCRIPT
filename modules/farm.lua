-- =============================================================================
-- MM2CLIENTSCRIPT: Farming & Gameplay Module (farm.lua)
-- Features: Active Round-Player Checks, Dynamic Lobby Gate, Instant Touch
-- =============================================================================

local Farm = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

-- Shared Global Settings (Synced from Python)
local IsFarming = false
local TweenSpeed = 30
local YOffset = 1.5
local SquadMembers = {} -- List of other bot usernames sent dynamically by Python

-- Cooperative State Memory
local BlacklistedCoins = setmetatable({}, { __mode = "k" }) -- Weak-keys prevent memory leaks
local CurrentCoins = 0
local LastStatus = "Alive"
local CurrentRoundPhase = "Lobby"

-- Caching Positions and Anchors
local LobbyCFrame = nil -- Captured instantly on bootup so we can teleport back to lobby safely
local farmPlatform = nil
local cachedCoinContainer = nil
local CurrentTween = nil

-- =============================================================================
-- WORKSPACE PATHFINDING COIN SCANNER (Your Caching Method)
-- =============================================================================

local function findCoinContainer()
    if cachedCoinContainer and cachedCoinContainer.Parent then
        return cachedCoinContainer
    end
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
-- YOUR VERIFIED DARK DEX PATHWAY (Coin Bag UI Reader with 40/50 Fallbacks)
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
                                        if num then return num, 40 end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return 0, 40
end

local function isBagFull()
    local current, capacity = getExactBagCoinCount()
    return current >= capacity
end

-- =============================================================================
-- DYNAMIC LOBBY & IN-ROUND SPATIAL DETECTORS
-- =============================================================================
local function isPlayerInLobby(hrp)
    -- Measures distance to our captured bootup spawn coordinates.
    if not LobbyCFrame then return true end
    local dist = (hrp.Position - LobbyCFrame.Position).Magnitude
    return dist < 120
end

local function isPlayerInRound()
    -- Evaluates if the local player is actively playing in the round.
    -- In MM2, the 'Game' HUD frame is ONLY visible if you are playing.
    local playGui = LocalPlayer:FindFirstChild("PlayerGui")
    local mainGui = playGui and playGui:FindFirstChild("MainGUI")
    local gameFrame = mainGui and mainGui:FindFirstChild("Game")
    if gameFrame then
        return gameFrame.Visible == true
    end
    return false
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
-- WEAPON & ROLE DETECTORS (Using Backpack weapon-name scanning)
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

        while active and IsFarming do
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

            hrp.AssemblyAngularVelocity = Vector3.new(0, 150, 0)
            hrp.AssemblyLinearVelocity = Vector3.new(0, -100, 0)

            hrp.CFrame = mHRP.CFrame * CFrame.new(math.random(-25, 25)/100, 2.0, math.random(-25, 25)/100)
            
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
            if CurrentTween then
                pcall(function() CurrentTween:Cancel() CurrentTween:Destroy() end)
                CurrentTween = nil
            end
            destroyFarmPlatform()
            setNoclip(false)
        end
    end
    if settings.tween_speed ~= nil then TweenSpeed = settings.tween_speed end
    if settings.offset ~= nil then YOffset = settings.offset end
    if settings.squad_members ~= nil then SquadMembers = settings.squad_members end
end

-- =============================================================================
-- DYNAMIC AUTO-FARMING ENGINE (Re-targeting & Anti-trail)
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

            -- Safety Gate: Only allow farming logic if we are actively playing in the round!
            -- If we are spectating or dead, wait patiently.
            if not hrp or not hum or hum.Health <= 0 or not isPlayerInRound() then
                if CurrentTween then
                    pcall(function() CurrentTween:Cancel() CurrentTween:Destroy() end)
                    CurrentTween = nil
                end
                destroyFarmPlatform()
                setNoclip(false)
                task.wait(0.5)
                continue
            end

            -- Lobby Teleportation upon Full Bag capacity
            local full = isBagFull()
            if full then
                if CurrentTween then
                    pcall(function() CurrentTween:Cancel() CurrentTween:Destroy() end)
                    CurrentTween = nil
                end
                destroyFarmPlatform()
                setNoclip(false)
                
                if LobbyCFrame then
                    hrp.CFrame = LobbyCFrame
                end
                task.wait(1)
                continue
            end

            local coins = getCoins()
            
            -- If no coins exist on the map, we are NOT in a active farming round
            if #coins == 0 then
                if CurrentTween then
                    pcall(function() CurrentTween:Cancel() CurrentTween:Destroy() end)
                    CurrentTween = nil
                end
                destroyFarmPlatform()
                setNoclip(false)
                task.wait(0.5)
                continue
            end

            -- LATE-JOIN TELEPORTATION RECOVERY:
            -- If we are in the lobby, but the game GUI says we are actively in-game (and coins exist),
            -- instantly blink onto the map so we don't slowly fly across the skybox!
            if isPlayerInLobby(hrp) then
                print("[Farm] Active round detected while bot is in lobby. Teleporting onto map...")
                pcall(function()
                    hrp.CFrame = coins[1].CFrame + Vector3.new(0, 5, 0)
                end)
                task.wait(0.5)
                continue
            end

            setNoclip(true)
            local platform = createFarmPlatform()
            platform.CFrame = hrp.CFrame * CFrame.new(0, -3.5, 0)

            -- Locate nearest active coin
            local closestCoin = nil
            local minDistance = math.huge

            for _, coin in ipairs(coins) do
                if coin and coin:IsA("BasePart") and coin.Parent then
                    local blacklisted = BlacklistedCoins[coin]
                    if not blacklisted or tick() >= blacklisted then
                        local dist = (hrp.Position - coin.Position).Magnitude
                        
                        -- Anti-trail/Scatter checking: Is another squad member targeting this coin?
                        local too_close_to_bot = false
                        for _, p in ipairs(Players:GetPlayers()) do
                            if p ~= LocalPlayer and table.find(SquadMembers, p.Name) and p.Character then
                                local bHRP = p.Character:FindFirstChild("HumanoidRootPart")
                                if bHRP and (bHRP.Position - coin.Position).Magnitude < 8 then
                                    too_close_to_bot = true
                                    break
                                end
                            end
                        end
                        
                        if not too_close_to_bot and dist < minDistance then
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
                local nextRetargetCheck = tick() + 0.15 -- Run check at 6.6Hz to completely eliminate CPU spikes!
                
                while (tick() - startTime) < duration and closestCoin and closestCoin.Parent and hum.Health > 0 and IsFarming and not isPlayerInLobby(hrp) and isPlayerInRound() do
                    if farmPlatform and farmPlatform.Parent then
                        farmPlatform.CFrame = hrp.CFrame * CFrame.new(0, -3.5, 0)
                    end

                    local currentDist = (hrp.Position - closestCoin.Position).Magnitude
                    
                    -- Instant Touch Proximity Check
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
                    
                    -- Throttled Dynamic Re-targeting Check
                    local now = tick()
                    if now >= nextRetargetCheck then
                        nextRetargetCheck = now + 0.15 -- Throttle
                        
                        local nearest_check_coins = getCoins()
                        local possible_closer_coin = nil
                        local possible_closer_dist = math.huge
                        
                        for _, c in ipairs(nearest_check_coins) do
                            if c and c:IsA("BasePart") and c ~= closestCoin and c.Parent then
                                local d = (hrp.Position - c.Position).Magnitude
                                if d < possible_closer_dist then
                                    possible_closer_dist = d
                                    possible_closer_coin = c
                                end
                            end
                        end
                        
                        -- Re-target if a newly found coin is significantly closer (e.g., spawned 5 studs closer)
                        if possible_closer_coin and possible_closer_dist < currentDist - 5 then
                            pcall(function() CurrentTween:Cancel() end)
                            break
                        end
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
        task.wait(0.5)
        pcall(function()
            local char = LocalPlayer.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            local status = "Dead"
            
            if humanoid and humanoid.Health > 0 then
                status = "Alive"
            end
            
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
            local playGui = LocalPlayer.PlayerGui:FindFirstChild("MainGUI")
            local lobbyFrame = playGui and playGui:FindFirstChild("Lobby")
            local statusLabel = lobbyFrame and lobbyFrame:FindFirstChild("Timer")
            
            if statusLabel then
                local currentText = statusLabel.Text
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

-- Capture Lobby Spawning Coordinates on Initial Bootup (Guarantees zero-guess teleportation)
task.spawn(function()
    pcall(function()
        local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local hrp = char:WaitForChild("HumanoidRootPart", 10)
        if hrp then
            LobbyCFrame = hrp.CFrame
            print("[Farm] Lobby Spawning Coordinates successfully cached in memory.")
        end
    end)
end)

return Farm
