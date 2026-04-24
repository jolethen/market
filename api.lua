-- eco_trade/api.lua

eco_trade.prices = {}

-- 1. Load the prices.txt configuration
function eco_trade.load_prices()
    -- Dynamically get the modpath so it never crashes if the folder is renamed
    local path = minetest.get_modpath(minetest.get_current_modname()) .. "/prices.txt"
    local file = io.open(path, "r")
    
    if not file then
        minetest.log("error", "[eco_trade] prices.txt not found at " .. path)
        return
    end

    -- Clear existing prices before reloading
    eco_trade.prices = {}

    for line in file:lines() do
        -- Skip empty lines, whitespace-only lines, or comments
        if line:trim() ~= "" and not line:match("^#") then
            local name, price = line:match("([^,]+),([^,]+)")
            if name and price then
                -- Strip whitespace from the item name for a clean lookup
                eco_trade.prices[name:gsub("%s+", "")] = tonumber(price)
            end
        end
    end
    file:close()
    minetest.log("action", "[eco_trade] Loaded " .. #eco_trade.prices .. " prices from prices.txt")
end

-- 2. Calculate the dynamic price based on volume sold
function eco_trade.get_current_price(item_name)
    -- Check if the item name is an alias (important for some Minetest mods)
    local real_name = minetest.registered_aliases[item_name] or item_name
    local base_price = eco_trade.prices[real_name]
    
    -- If the item isn't in our price list, the server doesn't buy it
    if not base_price then 
        return nil 
    end
    
    -- Get total units ever sold from Mod Storage
    local total_sold = eco_trade.storage:get_int("vol:" .. real_name)
    
    -- Logic: Drop price by 1¢ for every 10 stacks (640 units) sold to the server
    local price_drop = math.floor(total_sold / 640)
    
    -- Ensure price never drops below 1¢
    local final_price = math.max(1, base_price - price_drop)
    
    return final_price
end

-- 3. Update the volume when a sale is completed
function eco_trade.record_sale(item_name, quantity)
    local real_name = minetest.registered_aliases[item_name] or item_name
    local current_vol = eco_trade.storage:get_int("vol:" .. real_name)
    eco_trade.storage:set_int("vol:" .. real_name, current_vol + quantity)
end

-- Initialize the price list immediately
eco_trade.load_prices()
