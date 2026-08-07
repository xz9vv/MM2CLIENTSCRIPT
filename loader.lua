-- =============================================================================
-- MM2CLIENTSCRIPT: Optimized Asynchronous Parallel Loader (V2)
-- Features: Parallel Downloading, Safe Compilation, Shared Memory Mounting
-- =============================================================================

local HttpService = game:GetService("HttpService")

-- Pre-configured to match your repository
local GITHUB_USERNAME = "xz9vv"
local GITHUB_REPO = "MM2CLIENTSCRIPT"
local GITHUB_BRANCH = "main"

local BASE_URL = "https://raw.githubusercontent.com/" .. GITHUB_USERNAME .. "/" .. GITHUB_REPO .. "/" .. GITHUB_BRANCH .. "/"

local ModulePaths = {
    Optimizations = "modules/optimizations.lua",
    Connection    = "modules/connection.lua",
    ESP           = "modules/esp.lua",
    Farm          = "modules/farm.lua",
    Unbox         = "modules/unbox.lua"
}

local downloadedCode = {}
local finishedCount = 0
local totalFiles = 5

print("[Loader] Initiating parallel download sequence...")

-- Helper to safely download files in parallel threads
local function downloadParallel(moduleName, repoPath)
    task.spawn(function()
        local fileURL = BASE_URL .. repoPath
        local success, code = pcall(function()
            return game:HttpGet(fileURL)
        end)
        
        if success and code and #code > 0 then
            downloadedCode[moduleName] = code
        else
            warn("[Loader] Failed to download module: " .. moduleName)
        end
        
        finishedCount = finishedCount + 1
    end)
end

-- Fire off all 5 downloads simultaneously
for name, path in pairs(ModulePaths) do
    downloadParallel(name, path)
end

-- Non-blocking yield loop (keeps game running smoothly while downloading)
while finishedCount < totalFiles do
    task.wait(0.1)
end

print("[Loader] All modules downloaded. Compiling and mounting to shared memory...")

-- 1. Compile Optimizations and mount to shared.Optimizations
if downloadedCode.Optimizations then
    local success, func = pcall(loadstring, downloadedCode.Optimizations)
    if success and func then
        local runSuccess, returnedModule = pcall(func)
        if runSuccess and returnedModule then
            shared.Optimizations = returnedModule
            print("[Loader] Mounted Optimizations to shared.")
        end
    end
end

-- 2. Compile Connection and capture its return value to start it
local ConnectionModule = nil
if downloadedCode.Connection then
    local compileSuccess, func = pcall(loadstring, downloadedCode.Connection)
    if compileSuccess and func then
        local runSuccess, returnedModule = pcall(func)
        if runSuccess and returnedModule then
            ConnectionModule = returnedModule
            shared.Connection = returnedModule
            print("[Loader] Mounted Connection to shared.")
        end
    end
end

-- 3. Compile ESP and mount to shared.ESP
if downloadedCode.ESP then
    local success, func = pcall(loadstring, downloadedCode.ESP)
    if success and func then
        local runSuccess, returnedModule = pcall(func)
        if runSuccess and returnedModule then
            shared.ESP = returnedModule
            print("[Loader] Mounted ESP to shared.")
        end
    end
end

-- 4. Compile Farm and mount to shared.Farm
if downloadedCode.Farm then
    local success, func = pcall(loadstring, downloadedCode.Farm)
    if success and func then
        local runSuccess, returnedModule = pcall(func)
        if runSuccess and returnedModule then
            shared.Farm = returnedModule
            print("[Loader] Mounted Farm to shared.")
        end
    end
end

-- 5. Compile Unbox and mount to shared.Unbox
if downloadedCode.Unbox then
    local success, func = pcall(loadstring, downloadedCode.Unbox)
    if success and func then
        local runSuccess, returnedModule = pcall(func)
        if runSuccess and returnedModule then
            shared.Unbox = returnedModule
            print("[Loader] Mounted Unbox to shared.")
        end
    end
end

-- Initialize Connection
if ConnectionModule and ConnectionModule.start then
    ConnectionModule.start()
    print("[Loader] Active. Connected modules successfully initialized.")
else
    warn("[Loader] Critical Failure: Connection module failed to initialize.")
end
