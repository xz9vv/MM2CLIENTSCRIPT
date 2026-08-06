-- =============================================================================
-- MM2CLIENTSCRIPT: Farming & Gameplay Module (farm.lua)
-- Features: 3s/20-Coin Scatter, Stable Linear Tweens, Native Lobby Spawns
-- =============================================================================

local Farm = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Username = LocalPlayer.Name

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

-- Local Anti-Trail & Physics Trackers
local TailgateTimer = 0
local forceScatter = false
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
-- DYNAMIC LOBBY & IN-ROUND SPATIAL DETECTORS (Dark Dex Assisted)
-- =============================================================================

local function teleportToLobby(hrp)
    -- Safe recursive lookup for workspace.Lobby SpawnLocation
    local lobby = Workspace:FindFirstChild("Lobby")
    if lobby then
        local spawnPart = lobby:FindFirstChild("Spawn", true) 
                          or lobby:FindFirstChild("SpawnLocation", true) 
                          or lobby:FindFirstChildOfClass("SpawnLocation", true)
        
        if spawnPart and spawnPart:IsA("BasePart") then
            hrp.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
            return true
        end
        -- Fallback: Teleport directly to center of Lobby model
        if lobby:IsA("Model") and lobby.PrimaryPart then
            hrp.CFrame = lobby.PrimaryPart.CFrame + Vector3.new(0, 3, 0)
            return true
        elseif lobby:IsA("BasePart") then
            hrp.CFrame = lobby.CFrame + Vector3.new(0, 3, 0)
            return true
        end
    end
    return false
end

local function isPlayerInLobby(hrp)
    -- Measures distance to the Lobby Spawn Location part in workspace
    local lobby = Workspace:FindFirstChild("Lobby")
    if lobby then
        local spawnPart = lobby:FindFirstChild("Spawn", true) or lobby:FindFirstChild("SpawnLocation", true)
        if spawnPart and spawnPart:IsA("BasePart") then
            local dist = (hrp.Position - spawnPart.Position).Magnitude
            return dist < 120
        end
    end
    return true -- Default to true if Lobby folder isn't found
end

local function isPlayerInRound()
    local playGui = LocalPlayer:FindFirstChild("PlayerGui")
    local mainGui = playGui and playGui:FindFirstChild("MainGUI")
    local gameFrame = mainGui and mainGui:FindFirstChild("Game")
    
    if gameFrame then
        local roleLabel = gameFrame:FindFirstChild("Role", true)
        if roleLabel and roleLabel:IsA("TextLabel") then
            -- Only count as in-game if the Main HUD is visible AND our role is loaded/assigned
            return gameFrame.Visible == true and roleLabel.Text ~= ""
        end
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

-- =============================================================================
-- STABLE LINEAR AUTO-FARMING ENGINE (One-Tween-At-A-Time)
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

            -- Safety Gate: Only allow farming if we are alive, and actively playing inside the round
            if not hrp or not hum or hum.Health <= 0 or not isPlayerInRound() or isPlayerInLobby(hrp) then
                if CurrentTween then
                    pcall(function() CurrentTween:Cancel() CurrentTween:Destroy() end)
                    CurrentTween = nil
                end
                destroyFarmPlatform()
                setNoclip(false)
                task.wait(0.5)
                continue
            end

            -- Stop farming and teleport back to Spawn if bag is full
            local full = isBagFull()
            if full then
                if CurrentTween then
                    pcall(function() CurrentTween:Cancel() CurrentTween:Destroy() end)
                    CurrentTween = nil
                end
                destroyFarmPlatform()
                setNoclip(false)
                
                -- Teleport directly back to the Lobby Spawn part
                teleportToLobby(hrp)
                task.wait(1)
                continue
            end

            local coins = getCoins()
            
            -- If no coins exist on the map, we are NOT in an active round (Intermission / Lobby / 10s Timer)
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

            -- =================================================================
            -- 🛰️ 3-SECOND COOPERATIVE SQUAD TAILGATE DETECTOR (Anti-trail)
            -- =================================================================
            local is_tailgating = false
            local our_rank = table.find(SquadMembers, Username) or 1

            for _, name in ipairs(SquadMembers) do
                if name ~= Username then
                    local other_player = Players:FindFirstChild(name)
                    local other_char = other_player and other_player.Character
                    local other_hrp = other_char and other_char:FindFirstChild("HumanoidRootPart")
                    
                    if other_hrp then
                        local dist_to_bot = (hrp.Position - other_hrp.Position).Magnitude
                        if dist_to_bot < 8 then
                            local other_rank = table.find(SquadMembers, name) or 1
                            -- To prevent both bots scattering at once, only the bot with the lower rank (higher index) scatters!
                            if our_rank > other_rank then
                                is_tailgating = true
                                break
                            end
                        end
                    end
                end
            end

            if is_tailgating then
                TailgateTimer = TailgateTimer + 0.01
                if TailgateTimer >= 3.0 then -- 3 continuous seconds of clumping
                    forceScatter = true
                    TailgateTimer = 0
                    print("[Farm] Tailgating detected for 3s. Activating 20-coin scatter skip!")
                end
            else
                TailgateTimer = 0
            end

            -- =================================================================
            -- NEAREST-COIN RESOLVER (With 20-Coin Scatter Support)
            -- =================================================================
            local coins_list = {}
            for _, coin in ipairs(coins) do
                if coin and coin:IsA("BasePart") and coin.Parent then
                    local blacklisted = BlacklistedCoins[coin]
                    if not blacklisted or tick() >= blacklisted then
                        local dist = (hrp.Position - coin.Position).Magnitude
                        table.insert(coins_list, {coin = coin, dist = dist})
                    end
                end
            end

            -- Sort all active coins on the map by distance
            table.sort(coins_list, function(a, b) return a.dist < b.dist end)

            local closestCoin = nil
            if #coins_list > 0 then
                if forceScatter then
                    -- anti-trail scatter: Skip the closest 20 coins, and target the 21st (or furthest available)
                    local target_idx = math.min(21, #coins_list)
                    closestCoin = coins_list[target_idx].coin
                    forceScatter = false
                    print("[Farm] Scattered successfully to coin index: " .. tostring(target_idx))
                else
                    closestCoin = coins_list[1].coin
                end
            end

            if closestCoin then
                local targetCFrame = closestCoin.CFrame + Vector3.new(0, YOffset, 0)
                local duration = (hrp.Position - targetCFrame.Position).Magnitude / math.clamp(TweenSpeed, 10, 100)

                BlacklistedCoins[closestCoin] = tick() + duration + 1.5

                local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
                CurrentTween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame})
                CurrentTween:Play()

                local startTime = tick()
                
                -- STABLE LINEAR PROGRESSION
                while (tick() - startTime) < duration and closestCoin and closestCoin.Parent and hum.Health > 0 and IsFarming and isPlayerInRound() and not isPlayerInLobby(hrp) do
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

return Farm
