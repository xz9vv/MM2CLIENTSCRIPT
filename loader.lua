-- =============================================================================
-- MM2CLIENTSCRIPT Bootstrapper (loader.lua)
-- GitHub: xz9vv / MM2CLIENTSCRIPT
-- =============================================================================

local repo_url = "https://raw.githubusercontent.com/xz9vv/MM2CLIENTSCRIPT/main/modules/"

-- Helper function to "import" modules dynamically from GitHub in memory
local function import(module_name)
    local url = repo_url .. module_name .. ".lua"
    local success, result = pcall(function()
        return loadstring(game:HttpGet(url))()
    end)
    
    if success and result then
        print("[Loader] Successfully imported module: " .. module_name)
        return result
    else
        warn("[Loader] Failed to import module: " .. module_name .. " | Error: " .. tostring(result))
        return nil
    end
end

-- 1. Import all modules (Each returns a clean table of functions)
local Connection    = import("connection")
local Optimizations = import("optimizations")
local Farm          = import("farm")
local ESP           = import("esp")
local Unbox         = import("unbox")

-- 2. Verify all core modules loaded correctly before launching
if Connection and Optimizations and Farm and ESP and Unbox then
    -- Share module tables globally inside the script's environment so they can call each other
    shared.Connection    = Connection
    shared.Optimizations = Optimizations
    shared.Farm          = Farm
    shared.ESP           = ESP
    shared.Unbox         = Unbox

    -- 3. Initialize modules
    Connection.start()
    Optimizations.init()
    print("[MM2CLIENTSCRIPT] All modules successfully loaded and initialized!")
else
    warn("[MM2CLIENTSCRIPT] Startup aborted: One or more critical modules failed to import.")
end
