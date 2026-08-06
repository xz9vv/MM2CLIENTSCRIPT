-- =============================================================================
-- MM2CLIENTSCRIPT: Optimizations Module (optimizations.lua)
-- Manages 3D rendering states, FPS capping, game volume, and HUD purges.
-- =============================================================================

local Optimizations = {}

local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer

-- Local caching states to prevent redundant execution and eliminate FPS spikes
local CurrentMuteState = nil
local CurrentHeadlessState = nil
local CurrentFPSCap = nil

-- =============================================================================
-- PRIVATE UTILITY METHODS
-- =============================================================================

-- Safely mutes/unmutes game audio using a non-blocking threaded queue
local function setMuteState(should_mute)
    task.spawn(function()
        -- Try Executor MasterVolume bypass first (100% instant and lag-free)
        local success = pcall(function()
            UserSettings().GameSettings.MasterVolume = should_mute and 0 or 1
        end)
        if success then 
            print("[Optimizations] Master volume bypass applied successfully.")
            return 
        end
        
        -- Fallback: Threaded non-blocking local muter
        pcall(function()
            SoundService.MainVolume = should_mute and 0 or 1
        end)

        local targets = {SoundService, workspace, Players}
        local counter = 0
        
        for _, service in ipairs(targets) do
            for _, obj in ipairs(service:GetDescendants()) do
                if obj:IsA("Sound") then
                    obj.Volume = should_mute and 0 or (obj:GetAttribute("OriginalVolume") or obj.Volume)
                end
                
                counter = counter + 1
                -- Yield every 100 sounds to spread CPU load across frames and prevent FPS freezing
                if counter % 100 == 0 then
                    task.wait()
                end
            end
        end
    end)
end

-- Safely search and disable specific MM2 MainGUI elements recursively
local function safeHideFrame(guiName)
    pcall(function()
        local mainGui = LocalPlayer.PlayerGui:FindFirstChild("MainGUI")
        if mainGui then
            local frame = mainGui:FindFirstChild(guiName, true)
            if frame and frame:IsA("GuiObject") then
                frame.Visible = false
            end
        end
    end)
end

-- =============================================================================
-- PUBLIC INTERFACE METHODS
-- =============================================================================

-- Toggles the master visibility of the entire screen interface (MainGUI).
function Optimizations.toggleUI()
    pcall(function()
        local mainGui = LocalPlayer.PlayerGui:FindFirstChild("MainGUI")
        if mainGui then
            mainGui.Enabled = not mainGui.Enabled
            print("[Optimizations] Screen UI visibility toggled: " .. tostring(mainGui.Enabled))
        end
    end)
end

-- Applies incoming real-time optimization parameters from Python.
function Optimizations.applySettings(settings)
    -- 1. Headless 3D Render Toggle (Reduces GPU usage to 0%)
    if settings.opt_headless ~= nil and settings.opt_headless ~= CurrentHeadlessState then
        CurrentHeadlessState = settings.opt_headless
        pcall(function()
            RunService:Set3dRenderingEnabled(not CurrentHeadlessState)
            print("[Optimizations] Headless mode set to: " .. tostring(CurrentHeadlessState))
        end)
    end

    -- 2. Master FPS Cap Adjustment
    if settings.opt_fps_cap ~= nil and settings.opt_fps_cap ~= CurrentFPSCap then
        CurrentFPSCap = settings.opt_fps_cap
        pcall(function()
            if setfpscap then
                setfpscap(CurrentFPSCap)
                print("[Optimizations] FPS capped at: " .. tostring(CurrentFPSCap))
            end
        end)
    end

    -- 3. Game Mute State (State Cached: Prevents double-scans on other slider movements)
    if settings.opt_mute ~= nil and settings.opt_mute ~= CurrentMuteState then
        CurrentMuteState = settings.opt_mute
        setMuteState(CurrentMuteState)
        print("[Optimizations] Audio mute state: " .. tostring(CurrentMuteState))
    end

    -- 4. Dynamic HUD Deletions & Purges
    if settings.opt_delete_ui and settings.opt_purged_huds then
        local huds = settings.opt_purged_huds
        
        -- Roblox Native CoreGuis
        pcall(function()
            if huds.chat then
                StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
            end
            if huds.leaderboard then
                StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
            end
            if huds.core_gui then
                StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
            end
        end)

        -- MM2 Specific Screen Elements (Searched recursively)
        if huds.spectate then safeHideFrame("Spectate") end
        if huds.trading then safeHideFrame("Trading") end
        if huds.progress then safeHideFrame("CoinBag") end
    end
end

function Optimizations.init()
    print("[Optimizations] Module loaded successfully.")
    
    -- Threaded startup caching: prevents freezing the client during initial injection
    task.spawn(function()
        local counter = 0
        for _, obj in ipairs(game:GetDescendants()) do
            if obj:IsA("Sound") and not obj:GetAttribute("OriginalVolume") then
                obj:SetAttribute("OriginalVolume", obj.Volume)
            end
            counter = counter + 1
            if counter % 150 == 0 then
                task.wait()
            end
        end
    end)
end

return Optimizations
