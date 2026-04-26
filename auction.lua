-- eco_trade/auction.lua

local function get_ah_data()
    return minetest.deserialize(eco_trade.storage:get_string("ah_data")) or {}
end

local function save_ah_data(data)
    eco_trade.storage:set_string("ah_data", minetest.serialize(data))
end

function check_expiry()
    local ah = get_ah_data()
    local now = os.time()
    local changed = false

    for id, entry in pairs(ah) do
        if now >= entry.end_time then
            local winner = entry.last_bidder or entry.seller
            local winner_storage = minetest.deserialize(eco_trade.storage:get_string("expired:" .. winner)) or {}
            table.insert(winner_storage, entry.itemstring)
            eco_trade.storage:set_string("expired:" .. winner, minetest.serialize(winner_storage))
            
            if entry.last_bidder then
                local seller_storage = minetest.deserialize(eco_trade.storage:get_string("expired:" .. entry.seller)) or {}
                table.insert(seller_storage, "MONEY:" .. entry.price)
                eco_trade.storage:set_string("expired:" .. entry.seller, minetest.serialize(seller_storage))
            end
            ah[id] = nil
            changed = true
        end
    end
    if changed then save_ah_data(ah) end
    minetest.after(300, check_expiry)
end
minetest.after(300, check_expiry)

-- Bidding Popup with Dollar/Cent Display
function eco_trade.show_bid_window(player_name, auction_id)
    local ah = get_ah_data()
    local entry = ah[auction_id]
    if not entry then return end

    local d = math.floor(entry.price / 100)
    local c = entry.price % 100
    local price_text = (d > 0 and d .. "$ " or "") .. (c > 0 and c .. "¢" or "")
    if price_text == "" then price_text = "0¢" end

    local fs = "size[6,5]background[0,0;6,5;eco_bg.png;true]" ..
               "label[0.5,0.5;Item: " .. entry.itemstring .. "]" ..
               "label[0.5,1.2;Current Bid: " .. price_text .. "]" ..
               "label[0.5,1.6;Min Increment: " .. entry.increment .. "¢]" ..
               "field[0.8,3.2;4.5,1;bid_amount;Enter Bid (in cents):;]" ..
               "button[0.5,4.2;2.3,0.8;place_bid;PLACE BID]" ..
               "button[3.2,4.2;2.3,0.8;buy_now;BUY NOW]"
    
    minetest.show_formspec(player_name, "eco_trade:bid_popup:" .. auction_id, fs)
end

function eco_trade.show_ah(player_name, page)
    page = page or 1
    local ah = get_ah_data()
    local player = minetest.get_player_by_name(player_name)
    if not player then return end
    
    local balance = 0
    local inv = player:get_inventory()
    for _, stack in ipairs(inv:get_list("main")) do
        local n = stack:get_name()
        local count = stack:get_count()
        if n == "currency:minegeld" then balance = balance + (100 * count)
        elseif n:match("currency:minegeld_cent_") then
            balance = balance + (tonumber(n:match("cent_(%d+)$")) or 0) * count
        elseif n:match("currency:minegeld_") then
            balance = balance + (tonumber(n:match("_(%d+)$")) or 0) * 100 * count
        end
    end

    local list = {}
    for id, data in pairs(ah) do data.id = id table.insert(list, data) end
    table.sort(list, function(a, b) return a.end_time > b.end_time end)

    local items_per_page = 8 
    local total_pages = math.max(1, math.ceil(#list / items_per_page))
    local start_idx = ((page - 1) * items_per_page) + 1
    local end_idx = math.min(start_idx + items_per_page - 1, #list)

    local fs = "size[10,11]background[0,0;10,11;eco_bg.png;true]" ..
               "label[3.2,0.2;--- AUCTION HOUSE (" .. page .. "/" .. total_pages .. ") ---]"

    local now = os.time()
    local x, y = 0.8, 1.0
    for i = start_idx, end_idx do
        local entry = list[i]
        local hours_left = math.max(0, math.floor((entry.end_time - now) / 3600))
        local d = math.floor(entry.price / 100)
        local c = entry.price % 100
        local disp = (d > 0 and d .. "$ " or "") .. (c > 0 and c .. "¢" or "")

        fs = fs .. ("item_image_button[%f,%f;1.2,1.2;%s;select_%s;]"):format(x, y, entry.itemstring, entry.id)
        if entry.seller == player_name then
            fs = fs .. ("label[%f,%f;Owned by you]"):format(x, y + 1.3)
        else
            fs = fs .. ("label[%f,%f;Bid: %s]"):format(x, y + 1.3, disp)
            fs = fs .. ("label[%f,%f;%dh left]"):format(x, y + 1.7, hours_left)
        end
        x = x + 2.2 if x > 8.5 then x = 0.8 y = y + 3.0 end
    end

    if page > 1 then fs = fs .. ("button[0.5,9.2;2,0.8;prev_page;%d]"):format(page - 1) end
    if page < total_pages then fs = fs .. ("button[7.5,9.2;2,0.8;next_page;%d]"):format(page + 1) end
    
    local bal_d = math.floor(balance / 100)
    local bal_c = balance % 100
    local bal_str = (bal_d > 0 and bal_d .. " $ " or "") .. (bal_c > 0 and "and " .. bal_c .. " ¢" or "")
    if bal_str == "" then bal_str = "0 ¢" end

    fs = fs .. "box[0,10.2;10,0.8;#000000aa]" 
    fs = fs .. ("label[0.3,10.6;Wallet: %s]"):format(bal_str)
    fs = fs .. "button[6.5,10.3;3,0.6;claim_items;RECLAIM ITEMS / MONEY]"
    
    minetest.show_formspec(player_name, "eco_trade:ah_main", fs)
end
