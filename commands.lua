-- eco_trade/commands.lua

-- 1. /sell command (Server Shop)
minetest.register_chatcommand("sell", {
    description = "Sell held item to the server (Prices fluctuate!)",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        local stack = player:get_wielded_item()
        local item_name = stack:get_name()
        
        local unit_price = eco_trade.get_current_price(item_name)
        if not unit_price then return false, "Server doesn't buy this item!" end
        
        local total = unit_price * stack:get_count()
        
        local fs = "size[6,4]background[0,0;6,4;eco_bg.png;true]" ..
                   "label[1,1;Sell " .. stack:get_count() .. "x " .. item_name .. "?]" ..
                   "label[1,1.8;Total Payout: " .. total .. "¢]" ..
                   "button_exit[1,3;2,1;confirm_sell;CONFIRM]" ..
                   "button_exit[3,3;2,1;cancel;CANCEL]"
        
        minetest.show_formspec(name, "eco_trade:sell_confirm", fs)
        return true
    end
})

-- 2. /ah command (Player Market)
minetest.register_chatcommand("ah", {
    description = "Open the Auction House",
    func = function(name)
        eco_trade.show_ah(name, 1) -- Open on page 1
        return true
    end
})

-- 3. /ah_list command
minetest.register_chatcommand("ah_list", {
    params = "<start_bid> <buy_now> <increment> <duration_hours>",
    description = "List held item on Auction House",
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        local stack = player:get_wielded_item()

        if stack:is_empty() then
            return false, "Hold an item to list it!"
        end

        local start_bid, buy_now, inc, hours = param:match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
        if not start_bid then
            return false, "Usage: /ah_list <start_bid> <buy_now> <inc> <hours>"
        end

        start_bid, buy_now, inc, hours = tonumber(start_bid), tonumber(buy_now), tonumber(inc), tonumber(hours)
        if hours > 72 then hours = 72 end

        local ah = minetest.deserialize(eco_trade.storage:get_string("ah_data")) or {}
        local auction_id = tostring(os.time()) .. "_" .. name
        
        ah[auction_id] = {
            itemstring = stack:to_string(),
            seller = name,
            price = start_bid,
            buy_now = buy_now,
            increment = inc,
            end_time = os.time() + (hours * 3600),
        }

        eco_trade.storage:set_string("ah_data", minetest.serialize(ah))
        player:set_wielded_item(ItemStack(""))
        return true, "Item listed for " .. hours .. " hours!"
    end
})

-- 4. Formspec Input Handling
minetest.register_on_player_receive_fields(function(player, formname, fields)
    local name = player:get_player_name()

    -- SELL LOGIC
    if formname == "eco_trade:sell_confirm" and fields.confirm_sell then
        local stack = player:get_wielded_item()
        local item_name = stack:get_name()
        local price = eco_trade.get_current_price(item_name)
        
        if price then
            local total = price * stack:get_count()
            eco_trade.record_sale(item_name, stack:get_count())
            if minetest.get_modpath("currency") then currency.add_money(name, total) end
            player:set_wielded_item(ItemStack(""))
            minetest.chat_send_player(name, "Sold for " .. total .. "¢!")
        end
    end

    -- AH LOGIC
    if formname == "eco_trade:ah_main" then
        -- Pagination
        if fields.next_page or fields.prev_page then
            local page = tonumber(fields.next_page or fields.prev_page) -- We'll pass the num in the button
            eco_trade.show_ah(name, page)
            return
        end

        local ah = minetest.deserialize(eco_trade.storage:get_string("ah_data")) or {}
        for field, _ in pairs(fields) do
            if field:sub(1,4) == "bid_" then
                local id = field:sub(5)
                local entry = ah[id]
                if not entry then return end
                if entry.seller == name then
                    minetest.chat_send_player(name, "You cannot buy your own item!")
                    return
                end

                local balance = 0
                if minetest.get_modpath("currency") then balance = currency.get_money(name) or 0 end

                -- Logic: Try to Buy Now first, if not enough, try to Bid
                if balance >= entry.buy_now then
                    -- Buying Logic
                    if minetest.get_modpath("currency") then
                        currency.remove_money(name, entry.buy_now)
                        currency.add_money(entry.seller, entry.buy_now)
                    end
                    local inv = player:get_inventory()
                    if inv:room_for_item("main", ItemStack(entry.itemstring)) then
                        inv:add_item("main", ItemStack(entry.itemstring))
                        ah[id] = nil
                        eco_trade.storage:set_string("ah_data", minetest.serialize(ah))
                        minetest.chat_send_player(name, "Purchased successfully!")
                    else
                        minetest.chat_send_player(name, "Inventory full!")
                    end
                elseif balance >= (entry.price + entry.increment) then
                    -- Bidding Logic
                    entry.price = entry.price + entry.increment
                    entry.last_bidder = name
                    eco_trade.storage:set_string("ah_data", minetest.serialize(ah))
                    minetest.chat_send_all("New bid on " .. entry.itemstring .. ": " .. entry.price .. "¢")
                else
                    minetest.chat_send_player(name, "Not enough money to bid or buy!")
                end
                eco_trade.show_ah(name, 1) -- Refresh
            end
        end
    end
end)
