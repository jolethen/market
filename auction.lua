-- eco_trade/auction.lua

-- Get the auction table from storage
local function get_ah_data()
    return minetest.deserialize(eco_trade.storage:get_string("ah_data")) or {}
end

local function save_ah_data(data)
    eco_trade.storage:set_string("ah_data", minetest.serialize(data))
end

-- Custom Expiry Logic
local function check_expiry()
    local ah = get_ah_data()
    local now = os.time()
    local changed = false

    for id, entry in pairs(ah) do
        -- Check if current time has passed the custom end_time
        if now >= entry.end_time then
            -- Move to expired storage for the seller to reclaim later
            local expired = minetest.deserialize(eco_trade.storage:get_string("expired:" .. entry.seller)) or {}
            table.insert(expired, entry.itemstring)
            eco_trade.storage:set_string("expired:" .. entry.seller, minetest.serialize(expired))
            
            ah[id] = nil
            changed = true
        end
    end

    if changed then save_ah_data(ah) end
    minetest.after(7200, check_expiry) -- Loop every 2 hours
end
minetest.after(7200, check_expiry)

-- The Grid Formspec with New Details & Balance
function eco_trade.show_ah(player_name)
    local ah = get_ah_data()
    
    -- Safely get player balance (Assuming currency mod)
    local balance = 0
    if minetest.get_modpath("currency") then
        balance = currency.get_money(player_name) or 0
    end

    -- Increased formspec size to 10.5 height to fit new info and bottom bar
    local fs = "size[10,10.5]background[0,0;10,10.5;eco_bg.png;true]" ..
               "label[3.5,0.2;--- AUCTION HOUSE ---]"

    local now = os.time()
    local x, y = 0.5, 1.0
    for id, entry in pairs(ah) do
        local item = ItemStack(entry.itemstring)
        local desc = item:get_definition().description or entry.itemstring
        
        -- Calculate how many hours are left
        local remaining_secs = entry.end_time - now
        local hours_left = math.max(0, math.floor(remaining_secs / 3600))
        
        -- Item Icon
        fs = fs .. ("item_image_button[%f,%f;1.2,1.2;%s;bid_%s;]"):format(x, y, entry.itemstring, id)
        
        -- Price, Buy Now, Increment, and Duration Labels
        fs = fs .. ("label[%f,%f;Bid: %d¢]"):format(x, y + 1.3, entry.price)
        fs = fs .. ("label[%f,%f;Buy: %d¢]"):format(x, y + 1.7, entry.buy_now)
        fs = fs .. ("label[%f,%f;Inc: %d¢]"):format(x, y + 2.1, entry.increment)
        fs = fs .. ("label[%f,%f;%dh left]"):format(x, y + 2.5, hours_left)
        
        x = x + 1.8
        -- Adjusted grid wrapping for taller listings
        if x > 8.5 then x = 0.5 y = y + 3.0 end
    end
    
    -- Bottom Balance Bar (A semi-transparent box with the text)
    fs = fs .. "box[0,9.7;10,0.8;#00000099]" 
    fs = fs .. ("label[0.5,10.1;Your Balance: %d¢]"):format(balance)
    fs = fs .. "label[6.5,10.1;Click an item to BID / BUY]"
    
    minetest.show_formspec(player_name, "eco_trade:ah_main", fs)
end
