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
        if now >= entry.end_time then
            local expired = minetest.deserialize(eco_trade.storage:get_string("expired:" .. entry.seller)) or {}
            table.insert(expired, entry.itemstring)
            eco_trade.storage:set_string("expired:" .. entry.seller, minetest.serialize(expired))
            ah[id] = nil
            changed = true
        end
    end

    if changed then save_ah_data(ah) end
    minetest.after(7200, check_expiry)
end
minetest.after(7200, check_expiry)

-- The Grid Formspec with Pagination & Balance
function eco_trade.show_ah(player_name, page)
    page = page or 1
    local ah = get_ah_data()
    
    -- 1. 101% REAL BALANCE CHECK
    local balance = 0
    if minetest.get_modpath("currency") then
        -- Try multiple ways to get the balance depending on the currency mod version
        balance = currency.get_money(player_name) or (currency.players and currency.players[player_name]) or 0
    end

    -- 2. PAGINATION LOGIC
    local list = {}
    for id, data in pairs(ah) do
        data.id = id
        table.insert(list, data)
    end
    -- Sort by time so newest items are first
    table.sort(list, function(a, b) return a.end_time > b.end_time end)

    local items_per_page = 8 -- Fits nicely in the grid
    local total_pages = math.max(1, math.ceil(#list / items_per_page))
    if page > total_pages then page = total_pages end
    
    local start_idx = ((page - 1) * items_per_page) + 1
    local end_idx = math.min(start_idx + items_per_page - 1, #list)

    local fs = "size[10,11]background[0,0;10,11;eco_bg.png;true]" ..
               "label[3.0,0.2;--- AUCTION HOUSE (Page " .. page .. "/" .. total_pages .. ") ---]"

    local now = os.time()
    local x, y = 0.8, 1.0
    
    for i = start_idx, end_idx do
        local entry = list[i]
        local remaining = entry.end_time - now
        local hours_left = math.max(0, math.floor(remaining / 3600))
        
        fs = fs .. ("item_image_button[%f,%f;1.2,1.2;%s;bid_%s;]"):format(x, y, entry.itemstring, entry.id)
        fs = fs .. ("label[%f,%f;Bid: %d¢]"):format(x, y + 1.3, entry.price)
        fs = fs .. ("label[%f,%f;Buy: %d¢]"):format(x, y + 1.7, entry.buy_now)
        fs = fs .. ("label[%f,%f;Inc: %d¢]"):format(x, y + 2.1, entry.increment)
        fs = fs .. ("label[%f,%f;%dh left]"):format(x, y + 2.5, hours_left)
        
        x = x + 2.2
        if x > 8.5 then x = 0.8 y = y + 3.2 end
    end

    -- 3. PAGE BUTTONS
    if page > 1 then
        fs = fs .. ("button[0.5,9.0;2,1;prev_page;%d]"):format(page - 1)
        fs = fs .. "label[0.5,8.8;Back]"
    end
    if page < total_pages then
        fs = fs .. ("button[7.5,9.0;2,1;next_page;%d]"):format(page + 1)
        fs = fs .. "label[7.5,8.8;Next Page]"
    end
    
    -- 4. BALANCE BAR
    fs = fs .. "box[0,10.2;10,0.8;#000000aa]" 
    fs = fs .. ("label[0.5,10.6;Your Balance: %d¢]"):format(balance)
    fs = fs .. "label[6.0,10.6;Click an item to BID or BUY]"
    
    minetest.show_formspec(player_name, "eco_trade:ah_main", fs)
end
