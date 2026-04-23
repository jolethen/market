-- eco_trade/auction.lua

-- Get the auction table from storage
local function get_ah_data()
    return minetest.deserialize(eco_trade.storage:get_string("ah_data")) or {}
end

local function save_ah_data(data)
    eco_trade.storage:set_string("ah_data", minetest.serialize(data))
end

-- 2-Hour Expiry Logic
local function check_expiry()
    local ah = get_ah_data()
    local now = os.time()
    local changed = false

    for id, entry in pairs(ah) do
        -- 259,200 seconds = 72 hours
        if now - entry.time > 259200 then
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

-- The Grid Formspec
function eco_trade.show_ah(player_name)
    local ah = get_ah_data()
    local fs = "size[10,9]background[0,0;10,9;eco_bg.png;true]" ..
               "label[3.5,0.2;--- AUCTION HOUSE ---]" ..
               "label[0.5,8.5;Click an item to BID / BUY]"

    local x, y = 0.5, 1.0
    for id, entry in pairs(ah) do
        local item = ItemStack(entry.itemstring)
        local desc = item:get_definition().description or entry.itemstring
        
        -- Item Icon
        fs = fs .. ("item_image_button[%f,%f;1.2,1.2;%s;bid_%s;]"):format(x, y, entry.itemstring, id)
        -- Price Label
        fs = fs .. ("label[%f,%f;%d¢]"):format(x, y + 1.2, entry.price)
        
        x = x + 1.5
        if x > 8.5 then x = 0.5 y = y + 1.8 end
    end
    
    minetest.show_formspec(player_name, "eco_trade:ah_main", fs)
end
