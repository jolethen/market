-- eco_trade/commands.lua

-- /sell command
minetest.register_chatcommand("sell", {
    description = "Sell held item to the server",
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

-- /ah command
minetest.register_chatcommand("ah", {
    description = "Open the Auction House",
    func = function(name)
        eco_trade.show_ah(name)
        return true
    end
})

-- Handling Formspec Inputs
minetest.register_on_player_receive_fields(function(player, formname, fields)
    local name = player:get_player_name()

    -- 1. Handle Sell Confirmation
    if formname == "eco_trade:sell_confirm" and fields.confirm_sell then
        local stack = player:get_wielded_item()
        local item_name = stack:get_name()
        local price = eco_trade.get_current_price(item_name)
        
        if price then
            local total = price * stack:get_count()
            eco_trade.record_sale(item_name, stack:get_count())
            
            -- Integration with currency mod
            if minetest.get_modpath("currency") then
                currency.add_money(name, total)
            end
            
            player:set_wielded_item(ItemStack(""))
            minetest.chat_send_player(name, "Transaction complete: +" .. total .. "¢")
        end
    end

    -- 2. Handle AH Bidding (Clicking an item in the grid)
    if formname == "eco_trade:ah_main" then
        for field, _ in pairs(fields) do
            if field:sub(1,4) == "bid_" then
                local auction_id = field:sub(5)
                -- Here you would trigger a secondary formspec to enter a bid amount
                minetest.chat_send_player(name, "Bidding logic for ID " .. auction_id .. " goes here.")
            end
        end
    end
end)
minetest.register_chatcommand("ah_list", {
    params = "<start_bid> <buy_now> <increment> <duration_hours>",
    description = "List held item on Auction House",
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        local stack = player:get_wielded_item()

        if stack:is_empty() then
            return false, "Hold an item to list it!"
        end

        -- Extract the 4 numbers from the command
        local start_bid, buy_now, inc, hours = param:match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
        
        if not start_bid then
            return false, "Usage: /ah_list <start_bid> <buy_now> <increment> <duration_hours>"
        end

        start_bid, buy_now, inc, hours = tonumber(start_bid), tonumber(buy_now), tonumber(inc), tonumber(hours)

        -- Cap at 72 hours for server sanity
        if hours > 72 then hours = 72 end

        local ah = minetest.deserialize(eco_trade.storage:get_string("ah_data")) or {}
        local auction_id = tostring(os.time()) .. "_" .. name
        
        ah[auction_id] = {
            itemstring = stack:to_string(),
            seller = name,
            price = start_bid,
            buy_now = buy_now,
            increment = inc,
            end_time = os.time() + (hours * 3600), -- Current time + hours converted to seconds
        }

        eco_trade.storage:set_string("ah_data", minetest.serialize(ah))
        player:set_wielded_item(ItemStack(""))
        
        return true, "Item listed for " .. hours .. " hours!"
    end
})
