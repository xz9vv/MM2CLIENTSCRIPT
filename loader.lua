-- =============================================================================
-- MM2CLIENTSCRIPT Bootstrapper (loader.lua)
-- GitHub: xz9vv / MM2CLIENTSCRIPT
-- =============================================================================

local repo_url = "https://raw.githubusercontent.com/xz9vv/MM2CLIENTSCRIPT/main/modules/"

-- Helper function to "import" modules dynamically from GitHub in memory
local function import(module_name)
    local url = repo_url .. module_name .. ".lua"
    
    -- 1. Fetch raw code from GitHub
    local fetch_success, content = pcall(function()
        return game:HttpGet(url)
    end)
    
    if not fetch_success or not content then
        warn("[Loader] Failed to download module: " .. module_name .. " (Verify repository is Public)")
        return nil
    end
    
    -- 2. Compile raw code into executable function
    local func, compile_error = loadstring(content)
    if not func then
        warn("[Loader] Syntax Error in " .. module_name .. ": " .. tostring(compile_error))
        return nil
    end
    
    -- 3. Execute compilation safely to extract return table
    local run_success, result = pcall(func)
    if not run_success then
        warn("[Loader] Runtime Error inside " .. module_name .. ": " .. tostring(result))
        return nil
    end
    
    print("[Loader] Successfully imported module: " .. module_name)
    return result
end

-- Import all modules (Each returns a clean table of functions)
local Connection    = import("connection")
local Optimizations = import("optimizations")
local Farm          = import("farm")
local ESP           = import("esp")
local Unbox         = import("unbox")

-- Verify all core modules loaded correctly before launching
if Connection and Optimizations and Farm and ESP and Unbox then
    -- Share module tables globally inside the script's environment so they can call each other
    shared.Connection    = Connection
    shared.Optimizations = Optimizations
    shared.Farm          = Farm
    shared.ESP           = ESP
    shared.Unbox         = Unbox

    -- Initialize modules
    Connection.start()
    Optimizations.init()
    print("[MM2CLIENTSCRIPT] All modules successfully loaded and initialized!")
else
    warn("[MM2CLIENTSCRIPT] Startup aborted: One or more critical modules failed to import.")
end
