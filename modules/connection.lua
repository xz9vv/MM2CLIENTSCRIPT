-- =============================================================================
-- MM2CLIENTSCRIPT: Connection Module (connection.lua)
-- Manages WebSocket networking, auto-reconnect, and native error detectors.
-- =============================================================================

local Connection = {}

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local Username = LocalPlayer.Name

-- Configuration
local WS_URL = "ws://127.0.0.1:8765" -- Bypasses localhost DNS resolving for speed
local RECONNECT_DELAY = 5

-- Local State
local ActiveSocket = nil
local IsReconnecting = false

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
    -- Appends the local username and sends a JSON payload up to Python thread-safely.
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
-- INBOUND ROUTER: Route Python Commands to Luau Modules
-- =============================================================================
local function routeCommand(payload)
    local command = payload.command
    if not command then return end

    print("[Connection] Received server command: " .. command)

    -- 1. Real-time Configurations Sync
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

    -- 2. Clean Exit Resets
    elseif command == "force_reset" then
        if shared.Farm then
            pcall(function() shared.Farm.forceReset() end)
        end

    -- 3. Fling Tactic Exploits
    elseif command == "fling_target" then
        if shared.Farm then
            pcall(function() shared.Farm.fling(payload.target_player) end)
        end

    -- 4. Shop Unboxing Actions
    elseif command == "unbox" then
        if shared.Unbox then
            pcall(function() shared.Unbox.trigger(payload.crate) end)
        end

    -- 5. HUD Screen Toggles
    elseif command == "toggle_ui" then
        if shared.Optimizations then
            pcall(function() shared.Optimizations.toggleUI() end)
        end
    end
end

-- =============================================================================
-- HEARTBEAT & CONNECTION LOGIC
-- =============================================================================

local function runHeartbeatLoop()
    task.spawn(function()
        while ActiveSocket do
            Connection.send({["event"] = "heartbeat"})
            task.wait(30)
        end
    end)
end

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

    -- 2. Initialize Heartbeat keep-alives
    runHeartbeatLoop()

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
        task.wait(0.1) -- Wait for UI error text to fully render
        
        local errorMessage = GuiService:GetErrorMessage()
        local errorCode = GuiService:GetErrorCode()
        local errorCodeValue = errorCode and errorCode.Value or 0
        
        -- Detect Error 267, Error 268, or any explicit 'kick' keywords
        if errorCodeValue == 267 or errorCodeValue == 268 or errorMessage:find("267") or errorMessage:lower():find("kick") then
            print("[Connection] Disconnect detected! Message: " .. tostring(errorMessage))
            
            -- 1. Notify Python immediately so the Queue Manager knows we were kicked
            Connection.send({
                ["event"] = "status_changed",
                ["status"] = "Kicked"
            })
            
            task.wait(0.5)
            
            -- 2. Hard close the WebSocket so the server registers the disconnect cleanly
            if ActiveSocket then
                ActiveSocket:Close()
                ActiveSocket = nil
            end
        end
    end)
end)

return Connection
