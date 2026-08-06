-- =============================================================================
-- MM2CLIENTSCRIPT: Farming & Gameplay Module (farm.lua)
-- Manages character movements, resets, flinging, and coin bag telemetry.
-- =============================================================================

local Farm = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- Local Farming Configurations (Synced via Python)
local IsFarming = false
local TweenSpeed = 30
local YOffset = 1.5

-- Local State Trackers
local CurrentCoins = 0
local MaxBagCapacity = 10
local LastStatus = "Alive"

-- =============================================================================
-- YOUR VERIFIED DARK DEX PATHWAY (Coin Bag Sensor)
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
                                        -- Dynamically parse "current/capacity" (e.g., "7/10") to avoid hardcoding limits
                                        local current, capacity = coinsLabel.Text:match("(%d+)/(%d+)")
                                        if current and capacity then
                                            return tonumber(current), tonumber(capacity)
                                        end
                                        
                                        -- Fallback if the UI string format is altered
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

-- =============================================================================
-- PUBLIC INTERFACE METHODS
-- =============================================================================

function Farm.forceReset()
    -- Character Suicide command to coordinate Clean Exits
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.Health = 0
        print("[Farm] Clean Exit Reset applied successfully.")
    end
end

function Farm.fling(targetRole)
    """
    Locates the target player in-game and launches an aggressive 
    velocity-based physics exploit to fling them off the map.
    """
    task.spawn(function()
        local targetPlayer = nil
        
        -- Locate the target player (Looks for whoever holds the MM2 Knife)
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                if p.Backpack:FindFirstChild("Knife") or p.Character:FindFirstChild("Knife") then
                    targetPlayer = p
                    break
                end
            end
        end

        if not targetPlayer or not targetPlayer.Character then 
            print("[Farm] Fling target not found or dead.")
            return 
        end

        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")

        if root and targetRoot then
            print("[Farm] Executing fling target loop on: " .. targetPlayer.Name)
            local originalPos = root.CFrame
            
            -- Setup angular body velocity
            local bodyVelocity = Instance.new("BodyAngularVelocity")
            bodyVelocity.MaxTorque = Vector3.new(1, 1, 1) * 9e9
            bodyVelocity.AngularVelocity = Vector3.new(0, 99999, 0)
            bodyVelocity.Parent = root
            
            root.CanCollide = false
            
            -- Keep warping on target for up to 5 seconds or until they die
            local duration = 5
            while duration > 0 and targetPlayer.Character and targetPlayer.Character:FindFirstChildOfClass("Humanoid") do
                local targetHum = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
                if not targetHum or targetHum.Health <= 0 then break end
                
                root.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 0.2)
                task.wait(0.05)
                duration = duration - 0.05
            end
            
            -- Clean up physics properties
            bodyVelocity:Destroy()
            root.CanCollide = true
            root.CFrame = originalPos
        end
    end)
end

function Farm.applySettings(settings)
    -- Map settings directly to local configuration variables
    if settings.farm_enabled ~= nil then IsFarming = settings.farm_enabled end
    if settings.tween_speed ~= nil then TweenSpeed = settings.tween_speed end
    if settings.offset ~= nil then YOffset = settings.offset end
end

-- =============================================================================
-- BACKGROUND WATCHERS (Event-Driven Telemetry)
-- =============================================================================

-- 1. Real-Time Coin Bag Telemetry Loop
task.spawn(function()
    while true do
        task.wait(0.2) -- Check at 5Hz interval to ensure instant updates without lag
        pcall(function()
            local current, capacity = getExactBagCoinCount()
            MaxBagCapacity = capacity

            -- If the coin count increased, immediately notify Python
            if current > CurrentCoins then
                CurrentCoins = current
                
                if shared.Connection then
                    shared.Connection.send({
                        ["event"] = "coin_collected",
                        ["coins"] = CurrentCoins,
                        ["target"] = 1000
                    })
                    
                    -- If bag hits capacity, notify Python immediately so we can register "Bag Full"
                    if CurrentCoins >= MaxBagCapacity then
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

-- 2. Character Death/Respawn Status Change Loop
task.spawn(function()
    while true do
        task.wait(1)
        pcall(function()
            local char = LocalPlayer.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            local status = "Alive"
            
            if not humanoid or humanoid.Health <= 0 then
                status = "Dead"
            end
            
            -- If character state changed, transmit instantly
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

-- Listen for round-end resets to zero our round bag counter
task.spawn(function()
    while true do
        task.wait(2)
        pcall(function()
            -- If we are confirmed to be back in the lobby, reset our round coin counter
            if shared.Connection and shared.Connection.current_round_phase == "Lobby" then
                CurrentCoins = 0
            end
        end)
    end
end)

return Farm
