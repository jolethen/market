-- eco_trade/api.lua

eco_trade.prices = {}

-- 1. Load the prices.txt configuration
function eco_trade.load_prices()
    local path = minetest.get_modpath(minetest.get_current_modname()) .. "/prices.txt"
    local file = io.open(path, "r")
    
    if not file then
        minetest.log("error", "[eco_trade] prices.txt not found!")
        return
    end

    eco_trade.prices = {}
    for line in file:lines() do
        if line:trim() ~= "" and not line:match("^#") then
            local name, price = line:match("([^,]+),([^,]+)")
            if name and price then
                -- Store base price (Ensuring it starts as a multiple of 5)
                local val = tonumber(price)
                eco_trade.prices[name:trim()] = math.floor(val / 5) * 5
            end
        end
    end
    file:close()
end

-- 2. Calculate the dynamic price
function eco_trade.get_current_price(item_name)
    local base_price = eco_trade.prices[item_name]
    if not base_price then return nil end
    
    local total_sold = eco_trade.storage:get_int("vol:" .. item_name)
    
    -- Logic: Drop price by 5¢ for every 50 stacks (3200 units)
    -- This ensures we always stay in multiples of 5
    local price_drop = math.floor(total_sold / 3200) * 5
    
    -- Ensure price never drops below 5¢
    local final_price = math.max(5, base_price - price_drop)
    
    return final_price
end

-- 3. Update volume and timestamp on sale
function eco_trade.record_sale(item_name, quantity)
    local current_vol = eco_trade.storage:get_int("vol:" .. item_name)
    eco_trade.storage:set_int("vol:" .. item_name, current_vol + quantity)
    -- Record exactly when this item was last sold
    eco_trade.storage:set_int("last_sale:" .. item_name, os.time())
end

-- 4. Recovery Logic (Runs once every hour)
-- Checks if items should start getting more expensive again
local function recover_prices()
    local now = os.time()
    for item_name, base_price in pairs(eco_trade.prices) do
        local last_sale = eco_trade.storage:get_int("last_sale:" .. item_name)
        local current_vol = eco_trade.storage:get_int("vol:" .. item_name)
        
        -- If item hasn't been sold in over 1 hour and volume is > 0
        if current_vol > 0 and (now - last_sale) >= 3600 then
            -- Reduce volume by 10% of the total needed for a price bracket
            -- This ensures it fully recovers in 10 hours (10% * 10 = 100%)
            local recovery_amount = 320 -- 10% of 3200
            local new_vol = math.max(0, current_vol - recovery_amount)
            
            eco_trade.storage:set_int("vol:" .. item_name, new_vol)
        end
    end
    -- Run again in 1 hour (3600 seconds)
    minetest.after(3600, recover_prices)
end

-- Start the recovery loop and load prices
minetest.after(3600, recover_prices)
eco_trade.load_prices()
