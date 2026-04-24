-- eco_trade/commands.lua

-- Helper Function: Check physical balance and handle payments
local function get_physical_balance(player)
    local inv = player:get_inventory()
    local total = 0
    for _, stack in ipairs(inv:get_list("main")) do
        local name = stack:get_name()
        if name:match("currency:minegeld") then
            local value = tonumber(name:match("_(%d+)$")) or 1
            total = total + (value * stack:get_count())
        end
    end
    return total
end

local function pay_physical(player, amount)
    local inv = player:get_inventory()
    -- This mod usually has 1, 5, 10, 20, 50, 100. We'll pay in 10s for simplicity.
    local count = math.floor(amount / 10)
    local leftover = amount % 10
    
    local s10 = ItemStack("currency:minegeld_10 " .. count)
    local s1 = ItemStack("currency:minegeld_1 " .. leftover)
    
    if inv:room_for_item("main", s10) then inv:add_item("main", s10) else minetest.add_item(player:get_pos(), s10) end
    if inv:room_for_item("main", s1) then inv:add_item("main", s1) else minetest.add_item(player:get_pos(), s1) end
end

-- 1. /sell command
minetest.register_chatcommand("sell", {
    description = "Sell held item for physical Minegeld",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        local stack = player:get_wielded_item()
        local item_name = stack:get_name()
        
        local unit_price = eco_trade.get_current_price(item_name)
        if not unit_price then return false, "Server doesn't buy this item!" end
        
        local total = unit_price * stack:get_count()
        
        local fs = "size[6,4]background[0,0;6,4;eco_bg.png;true]" ..
                   "label[1,1;Sell " .. stack:get_count() .. "x " .. item_name .. "?]" ..
                   "label[1,1.8;Payout: " .. total .. "¢ (Physical)]" ..
                   "button_exit[1,3;2,1;confirm_sell;CONFIRM]" ..
                   "button_exit[3,3;2,1;cancel;CANCEL]"
        
        minetest.show_formspec(name, "eco_trade:sell_confirm", fs)
        return true
    end
})

-- 2. /ah command
minetest.register_chatcommand("ah", {
    description = "Open the Auction House",
    func = function(name)
        eco_trade.show_ah(name, 1)
        return true
    end
})

-- 3. /ah_list command
minetest.register_chatcommand("ah_list", {
    params = "<start_bid> <buy_now> <increment> <hours>",
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        local stack = player:get_wielded_item()
        if stack:is_empty() then return false, "Hold an item!" end

        local start_bid, buy_now, inc, hours = param:match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
        if not start_bid then return false, "Usage: /ah_list <start_bid> <buy_now> <inc> <hours>" end

        local ah = minetest.deserialize(eco_trade.storage:get_string("ah_data")) or {}
        ah[tostring(os.time()) .. "_" .. name] = {
            itemstring = stack:to_string(),
            seller = name,
            price = tonumber(start_bid),
            buy_now = tonumber(buy_now),
            increment = tonumber(inc),
            end_time = os.time() + (tonumber(hours) * 3600),
        }
        eco_trade.storage:set_string("ah_data", minetest.serialize(ah))
        player:set_wielded_item(ItemStack(""))
        return true, "Listed on AH!"
    end
})

-- 4. Handling Inputs
minetest.register_on_player_receive_fields(function(player, formname, fields)
    local name = player:get_player_name()

    if formname == "eco_trade:sell_confirm" and fields.confirm_sell then
        local stack = player:get_wielded_item()
        local price = eco_trade.get_current_price(stack:get_name())
        if price then
            local total = price * stack:get_count()
            eco_trade.record_sale(stack:get_name(), stack:get_count())
            pay_physical(player, total)
            player:set_wielded_item(ItemStack(""))
            minetest.chat_send_player(name, "Sold for " .. total .. "¢")
        end
    end

    if formname == "eco_trade:ah_main" then
        if fields.next_page or fields.prev_page then
            eco_trade.show_ah(name, tonumber(fields.next_page or fields.prev_page))
            return
        end

        local ah = minetest.deserialize(eco_trade.storage:get_string("ah_data")) or {}
        for field, _ in pairs(fields) do
            if field:sub(1,4) == "bid_" then
                local id = field:sub(5)
                local entry = ah[id]
                if not entry or entry.seller == name then return end

                local balance = get_physical_balance(player)

                -- BUY NOW LOGIC
                if balance >= entry.buy_now then
                    -- Take money from buyer's inventory
                    player:get_inventory():remove_item("main", ItemStack("currency:minegeld_1 " .. entry.buy_now))
                    -- Give item to buyer
                    player:get_inventory():add_item("main", ItemStack(entry.itemstring))
                    
                    -- Pay seller (Physical return via mail/claim system or direct if online)
                    local seller_obj = minetest.get_player_by_name(entry.seller)
                    if seller_obj then pay_physical(seller_obj, entry.buy_now) 
                    else
                        -- Save to expired/unclaimed storage if offline
                        local unclaimed = minetest.deserialize(eco_trade.storage:get_string("expired:" .. entry.seller)) or {}
                        table.insert(unclaimed, "currency:minegeld_10 " .. math.floor(entry.buy_now/10))
                        eco_trade.storage:set_string("expired:" .. entry.seller, minetest.serialize(unclaimed))
                    end

                    ah[id] = nil
                    eco_trade.storage:set_string("ah_data", minetest.serialize(ah))
                    minetest.chat_send_player(name, "Bought successfully!")
                end
                eco_trade.show_ah(name, 1)
            end
        end
    end
end)
