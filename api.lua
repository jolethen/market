-- eco_trade/api.lua

eco_trade.prices = {}

-- 1. Load the prices.txt configuration
function eco_trade.load_prices()
    local path = minetest.get_modpath("eco_trade") .. "/prices.txt"
    local file = io.open(path, "r")
    
    if not file then
        minetest.log("error", "[eco_trade] prices.txt not found!")
        return
    end

    for line in file:lines() do
        -- Skip empty lines or comments
        if line ~= "" and not line:match("^#") then
            local name, price = line:match("([^,]+),([^,]+)")
            if name and price then
                eco_trade.prices[name:gsub("%s+", "")] = tonumber(price)
            end
        end
    end
    file:close()
end

-- 2. Calculate the dynamic price based on volume sold
function eco_trade.get_current_price(item_name)
    local base_price = eco_trade.prices[item_name]
    
    -- If the item isn't in our price list, the server doesn't buy it
    if not base_price then 
        return nil 
    end
    
    -- Get total units ever sold from Mod Storage
    local total_sold = eco_trade.storage:get_int("vol:" .. item_name)
    
    -- Logic: Drop price by 1 for every 10 stacks (640 units)
    local price_drop = math.floor(total_sold / 640)
    
    -- Ensure price never drops below 1 unit of currency
    local final_price = math.max(1, base_price - price_drop)
    
    return final_price
end

-- 3. Update the volume when a sale is completed
function eco_trade.record_sale(item_name, quantity)
    local current_vol = eco_trade.storage:get_int("vol:" .. item_name)
    eco_trade.storage:set_int("vol:" .. item_name, current_vol + quantity)
end

-- Initialize the price list immediately upon loading api.lua
eco_trade.load_prices()
