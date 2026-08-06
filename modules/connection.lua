-- =============================================================================
-- MM2CLIENTSCRIPT: Connection Module (connection.lua)
-- Features: Centralized Heartbeat, Workspace Map Detector, Role Scanner, Kick Detector
-- =============================================================================

local Connection = {}

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Username = LocalPlayer.Name

-- Configuration
local WS_URL = "ws://127.0.0.1:8765"
local RECONNECT_DELAY = 5

-- Local State
local ActiveSocket = nil
local IsReconnecting = false
local CurrentAssignedRole = "Innocent"
local CurrentRoundPhase = "Lobby"

-- =============================================================================
-- 🗺️ MM2 WIKI MAP WHITELIST (Normalized to spaceless lowercase)
-- =============================================================================
local MapWhitelist = {
    "bank2", "hotel", "biolabsq", "biolab", "factory", "hospital3", "hospital3icon", 
    "hotel2", "house2", "mansion2", "milbase", "office3", "office3icon", 
    "policestation", "policestationicon", "research", "researchfacility", "workplace",
    "beachresort", "yacht", "yachtmap", "pier", "piermap", "manor", "farmhouse", 
    "mineshaft", "mineshaft2icon", "hallow2022barn", "barn", "vampirescastle", 
    "vampcastle2", "spaceship", "spaceshipmap", "workshop", "workshopmapicon", 
    "logcabin", "trainstation", "icecastle", "skilodge", "christmasinitaly", "xmasitaly", "skivillage"
}

-- =============================================================================
-- SYSTEM DETECTOR: Find Compatible WebSocket API
-- =============================================================================
local function getWebSocketLibrary()
    local lib = assert(
        WebSocket or Websocket or websocket or (syn and syn.websocket),
        "[Connection] Missing Executor WebSocket API! Your executor is not supported."
    )
    return lib
end

local WSLib = getWebSocketLibrary()

-- =============================================================================
-- PUBLIC NETWORKING METHODS
-- =============================================================================

function Connection.send(payload)
    if ActiveSocket then
        payload["username"] = Username
        local success, jsonStr = pcall(function()
            return HttpService:JSONEncode(payload)
        end)
        
        if success then
            pcall(function()
                ActiveSocket:Send(jsonStr)
            end)
        else
            warn("[Connection] Failed to encode JSON payload.")
        end
    end
end

-- =============================================================================
-- PRIVATE STATE MONITOR HELPERS
-- =============================================================================

local function getActiveMapModel()
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model") then
            local cleanName = child.Name:gsub("%s+", ""):lower()
            if table.find(MapWhitelist, cleanName) then
                return child
            end
        end
    end
    return nil
end

local function isPlayerInRound()
    return getActiveMapModel() ~= nil
end

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

local function isSheriffWeapon(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local nameLower = tool.Name:lower()
    if nameLower:find("gun", 1, true) or nameLower:find("revolver", 1, true) or nameLower:find("pistol", 1, true) then
        return true
    end
    return false
end

-- =============================================================================
-- INBOUND ROUTER: Route Python Commands to Luau Modules
-- =============================================================================
local function routeCommand(payload)
    local command = payload.command
    if not command then return end

    print("[Connection] Received command: " .. command)

    if command == "update_settings" then
        if shared.Optimizations then
            pcall(function() shared.Optimizations.applySettings(payload) end)
        end
        if shared.Farm then
            pcall(function() shared.Farm.applySettings(payload) end)
        end
        if shared.ESP then
            pcall(function() shared.ESP.applySettings(payload) end)
        end

    elseif command == "force_reset" then
        if shared.Farm then
            pcall(function() shared.Farm.forceReset() end)
        end

    elseif command == "fling_target" then
        if shared.Farm then
            pcall(function() shared.Farm.fling(payload.target_player) end)
        end

    elseif command == "unbox" then
        if shared.Unbox then
            pcall(function() shared.Unbox.trigger(payload.crate) end)
        end

    elseif command == "toggle_ui" then
        if shared.Optimizations then
            pcall(function() shared.Optimizations.toggleUI() end)
        end
    end
end

-- =============================================================================
-- CENTRALIZED BACKGROUND STATE MONITOR LOOPS
-- =============================================================================

local function runHeartbeatLoop()
    task.spawn(function()
        while ActiveSocket do
            Connection.send({["event"] = "heartbeat"})
            task.wait(30)
        end
    end)
end

local function startStateWatchers()
    -- 1. Backpack Weapon-Based Role Scanner Loop (Instant Updates!)
    task.spawn(function()
        while ActiveSocket do
            task.wait(1.5)
            pcall(function()
                if isPlayerInRound() then
                    local detectedRole = "Innocent"
                    local char = LocalPlayer.Character
                    local equipped = char and char:FindFirstChildOfClass("Tool")
                    
                    if equipped then
                        if isMurdererWeapon(equipped) then
                            detectedRole = "Murderer"
                        elseif isSheriffWeapon(equipped) then
                            detectedRole = "Sheriff"
                        end
                    end
                    
                    if detectedRole == "Innocent" then
                        local backpack = LocalPlayer:FindFirstChild("Backpack")
                        if backpack then
                            for _, item in ipairs(backpack:GetChildren()) do
                                if isMurdererWeapon(item) then
                                    detectedRole = "Murderer"
                                    break
                                elseif isSheriffWeapon(item) then
                                    detectedRole = "Sheriff"
                                    break
                                end
                            end
                        end
                    end
                    
                    if detectedRole ~= CurrentAssignedRole then
                        CurrentAssignedRole = detectedRole
                        Connection.send({
                            ["event"] = "role_assigned",
                            ["role"] = CurrentAssignedRole
                        })
                    end
                else
                    CurrentAssignedRole = "Innocent"
                end
            end)
        end
    end)

    -- 2. Dynamic Workspace-Driven Map/Round State Detector
    task.spawn(function()
        local lastPhase = ""
        while ActiveSocket do
            task.wait(1)
            pcall(function()
                local activeMap = getActiveMapModel()
                local phase = "Lobby"
                local mapName = "Voting"
                
                if activeMap then
                    phase = "InGame"
                    mapName = activeMap.Name
                end
                
                if phase ~= lastPhase then
                    lastPhase = phase
                    CurrentRoundPhase = phase
                    
                    Connection.send({
                        ["event"] = "round_state_changed",
                        ["phase"] = phase,
                        ["map"] = mapName
                    })
                    
                    if phase == "Lobby" then
                        if shared.Farm then
                            shared.Farm.CurrentCoins = 0
                        end
                        Connection.send({["event"] = "round_ended"})
                    end
                end
            end)
        end
    end)
end

-- =============================================================================
-- WS CORE CONNECTION ENGINE
-- =============================================================================

function Connection.start()
    if IsReconnecting then return end
    print("[Connection] Connecting to " .. WS_URL .. "...")

    local success, socket = pcall(function()
        return WSLib.connect(WS_URL)
    end)

    if not success or not socket then
        warn("[Connection] Connection failed. Retrying in " .. tostring(RECONNECT_DELAY) .. " seconds...")
        IsReconnecting = true
        task.wait(RECONNECT_DELAY)
        IsReconnecting = false
        return Connection.start()
    end

    ActiveSocket = socket
    print("[Connection] Successfully connected to Python backend!")

    -- 1. Fire Handshake immediately
    Connection.send({
        ["event"] = "joined",
        ["game_phase"] = "Lobby"
    })

    -- 2. Initialize Heartbeat and State Watchers
    runHeartbeatLoop()
    startStateWatchers()

    -- 3. Bind WebSocket Event Listeners
    ActiveSocket.OnMessage:Connect(function(rawMessage)
        local decodedPayload = nil
        pcall(function()
            decodedPayload = HttpService:JSONDecode(rawMessage)
        end)

        if decodedPayload then
            routeCommand(decodedPayload)
        end
    end)

    ActiveSocket.OnClose:Connect(function()
        warn("[Connection] Connection lost. Re-entering connection loop...")
        ActiveSocket = nil
        IsReconnecting = true
        task.wait(RECONNECT_DELAY)
        IsReconnecting = false
        Connection.start()
    end)
end

-- =============================================================================
-- NATIVE DISCONNECT & ERROR MONITOR (Error Code 267 Detector)
-- =============================================================================
pcall(function()
    GuiService.ErrorMessageChanged:Connect(function()
        task.wait(0.1)
        
        local errorMessage = GuiService:GetErrorMessage()
        local errorCode = GuiService:GetErrorCode()
        local errorCodeValue = errorCode and errorCode.Value or 0
        
        if errorCodeValue == 267 or errorCodeValue == 268 or errorMessage:find("267") or errorMessage:lower():find("kick") then
            print("[Connection] Disconnect detected! Message: " .. tostring(errorMessage))
            
            Connection.send({
                ["event"] = "status_changed",
                ["status"] = "Kicked"
            })
            
            task.wait(0.5)
            
            if ActiveSocket then
                ActiveSocket:Close()
                ActiveSocket = nil
            end
        end
    end)
end)

return Connection
