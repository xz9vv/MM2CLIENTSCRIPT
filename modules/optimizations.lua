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

-- =============================================================================
-- PRIVATE UTILITY METHODS
-- =============================================================================

-- Safely mutes/unmutes all sounds in the game workspace and SoundService
local function setMuteState(should_mute)
    pcall(function()
        -- Setting AmbientReverb is a safe backup, but we can directly adjust SoundService volume
        SoundService.MainVolume = should_mute and 0 or 1
    end)
    -- Fallback: Loop through existing active game sounds
    pcall(function()
        for _, obj in ipairs(game:GetDescendants()) do
            if obj:IsA("Sound") then
                obj.Volume = should_mute and 0 or (obj:GetAttribute("OriginalVolume") or obj.Volume)
            end
        end
    end)
end

-- Safely search and disable specific MM2 MainGUI elements recursively (No guessing)
local function safeHideFrame(guiName)
    pcall(function()
        local mainGui = LocalPlayer.PlayerGui:FindFirstChild("MainGUI")
        if mainGui then
            -- Searches recursively for any frame matching the checked HUD name
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

function Optimizations.toggleUI()
    """
    Toggles the master visibility of the entire screen interface (MainGUI).
    """
    pcall(function()
        local mainGui = LocalPlayer.PlayerGui:FindFirstChild("MainGUI")
        if mainGui then
            mainGui.Enabled = not mainGui.Enabled
            print("[Optimizations] Screen UI visibility toggled: " .. tostring(mainGui.Enabled))
        end
    end)
end

function Optimizations.applySettings(settings)
    """
    Applies incoming real-time optimization parameters from Python.
    """
    -- 1. Headless 3D Render Toggle (Reduces GPU usage to 0% when true)
    if settings.opt_headless ~= nil then
        pcall(function()
            RunService:Set3dRenderingEnabled(not settings.opt_headless)
            print("[Optimizations] Headless mode set to: " .. tostring(settings.opt_headless))
        end)
    end

    -- 2. Master FPS Cap Adjustment
    if settings.opt_fps_cap ~= nil then
        pcall(function()
            if setfpscap then
                setfpscap(settings.opt_fps_cap)
                print("[Optimizations] FPS capped at: " .. tostring(settings.opt_fps_cap))
            end
        end)
    end

    -- 3. Game Mute State
    if settings.opt_mute ~= nil then
        setMuteState(settings.opt_mute)
        print("[Optimizations] Audio mute state: " .. tostring(settings.opt_mute))
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
    
    -- Cache original sound volumes at start so we can unmute accurately
    pcall(function()
        for _, obj in ipairs(game:GetDescendants()) do
            if obj:IsA("Sound") and not obj:GetAttribute("OriginalVolume") then
                obj:SetAttribute("OriginalVolume", obj.Volume)
            end
        end
    end)
end

return Optimizations
