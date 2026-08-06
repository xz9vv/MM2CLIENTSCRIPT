-- =============================================================================
-- MM2CLIENTSCRIPT: Unboxing Module (unbox.lua)
-- Features: Remote Purchase and Unboxing for Event and Standard Crates
-- =============================================================================

local Unbox = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local ShopRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Shop")
local BuyItemNew = ShopRemotes:WaitForChild("BuyItemNew") -- RemoteFunction
local OpenCrate = ShopRemotes:WaitForChild("OpenCrate")   -- RemoteFunction

-- Crate Configuration Mapping
local CrateConfig = {
    -- Standard Direct-Purchase Boxes (No Key Required)
    ["Knife Box 1"] = { Crate = "KnifeBox1", Key = nil, Currency = "Coins" },
    ["KnifeBox1"]   = { Crate = "KnifeBox1", Key = nil, Currency = "Coins" },
    ["Gun Box 1"]   = { Crate = "GunBox1", Key = nil, Currency = "Coins" },
    ["GunBox1"]     = { Crate = "GunBox1", Key = nil, Currency = "Coins" },
    
    -- Summer 2026 Event Boxes (Requires Key Purchase)
    ["Summer 2026 Box"] = { Crate = "Summer2026Box", Key = "SummerKey2026", Currency = "Shells" },
    ["Summer2026Box"]   = { Crate = "Summer2026Box", Key = "SummerKey2026", Currency = "Shells" }
}

-- Triggers the unboxing sequence on-demand from connection.lua / Python
function Unbox.trigger(rawCrateName)
    task.spawn(function()
        local config = CrateConfig[rawCrateName]
        if not config then
            -- Safe Fallback: Strip spaces, assume Coins, assume no key is required
            local cleanName = rawCrateName:gsub("%s+", "")
            config = { Crate = cleanName, Key = nil, Currency = "Coins" }
            warn("[Unbox] Crate configuration not found for '" .. tostring(rawCrateName) .. "'. Using fallback: " .. cleanName)
        end

        local success = false
        local resultItem = nil

        -- Case A: Crate requires a KEY to be purchased first (e.g. Summer 2026 Box)
        if config.Key then
            print("[Unbox] Attempting to buy key: " .. config.Key .. " using " .. config.Currency)
            local buySuccess, buyError = BuyItemNew:InvokeServer(config.Key, config.Currency)
            
            if buySuccess == true then
                print("[Unbox] Key purchased successfully. Unboxing " .. config.Crate .. "...")
                task.wait(1.0) -- Small delay to prevent rate limiting
                
                local unboxResult = OpenCrate:InvokeServer(config.Crate)
                if unboxResult then
                    resultItem = tostring(unboxResult)
                    success = true
                end
            else
                warn("[Unbox] Key purchase failed. Server returned: " .. tostring(buyError or buySuccess))
            end

        -- Case B: Direct purchase Crate (e.g. Knife Box 1)
        else
            print("[Unbox] Attempting to buy crate directly: " .. config.Crate .. " using " .. config.Currency)
            local buySuccess, buyError = BuyItemNew:InvokeServer(config.Crate, config.Currency)
            
            if buySuccess == true then
                print("[Unbox] Crate purchased successfully. Unboxing...")
                task.wait(1.0) -- Small delay to prevent rate limiting
                
                local unboxResult = OpenCrate:InvokeServer(config.Crate)
                if unboxResult then
                    resultItem = tostring(unboxResult)
                    success = true
                end
            else
                warn("[Unbox] Crate purchase failed. Server returned: " .. tostring(buyError or buySuccess))
            end
        end

        -- Transmit telemetry back to Python matching the exact telemetry contract in the README
        if shared.Connection then
            shared.Connection.send({
                ["event"] = "unbox_result",
                ["status"] = success and "Success" or "Failure",
                ["item"] = resultItem or "None",
                ["crate"] = config.Crate
            })
            print("[Unbox] Sent unbox_result to Python: " .. (success and "Success" or "Failure"))
        else
            warn("[Unbox] Connection module not found in shared memory. Telemetry skipped.")
        end
    end)
end

-- Force-mount to shared so connection.lua can find it instantly
shared.Unbox = Unbox

return Unbox
