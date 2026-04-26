-- eco_trade/commands.lua

-- Helper Function: Check physical balance
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

-- Helper Function: Pay physical Minegeld
local function pay_physical(player, amount)
    local inv = player:get_inventory()
    local count_10 = math.floor(amount / 10)
    local leftover = amount % 10
    
    local s10 = ItemStack("currency:minegeld_10 " .. count_10)
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
        if stack:is_empty() then return false, "Hold something first!" end
        
        local unit_price = eco_trade.get_current_price(stack:get_name())
        if not unit_price then return false, "Server doesn't buy this item!" end
        
        local total = unit_price * stack:get_count()
        local fs = "size[6,4]background[0,0;6,4;eco_bg.png;true]" ..
                   "label[1,1;Sell " .. stack:get_count() .. "x " .. stack:get_name() .. "?]" ..
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
        if stack:is_empty() then return false, "Hold an item to list it!" end

        local s_bid, b_now, inc, hrs = param:match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
        if not s_bid then return false, "Usage: /ah_list <start_bid> <buy_now> <inc> <hours>" end

        local ah = minetest.deserialize(eco_trade.storage:get_string("ah_data")) or {}
        ah[os.time() .. "_" .. name] = {
            itemstring = stack:to_string(),
            seller = name,
            price = tonumber(s_bid),
            buy_now = tonumber(b_now),
            increment = tonumber(inc),
            end_time = os.time() + (tonumber(hrs) * 3600),
            last_bidder = nil
        }
        eco_trade.storage:set_string("ah_data", minetest.serialize(ah))
        player:set_wielded_item(ItemStack(""))
        return true, "Listed successfully!"
    end
})

-- 4. Formspec Handling
minetest.register_on_player_receive_fields(function(player, formname, fields)
    local name = player:get_player_name()

    -- SELL CONFIRMATION
    if formname == "eco_trade:sell_confirm" and fields.confirm_sell then
        local stack = player:get_wielded_item()
        local price = eco_trade.get_current_price(stack:get_name())
        if price then
            pay_physical(player, price * stack:get_count())
            eco_trade.record_sale(stack:get_name(), stack:get_count())
            player:set_wielded_item(ItemStack(""))
            minetest.chat_send_player(name, "Sold!")
        end
    end

    -- MAIN AH GRID
    if formname == "eco_trade:ah_main" then
        if fields.next_page or fields.prev_page then
            eco_trade.show_ah(name, tonumber(fields.next_page or fields.prev_page))
        end

        -- RECLAIM SYSTEM (Items and Money)
        if fields.claim_items then
            local storage_key = "expired:" .. name
            local unclaimed = minetest.deserialize(eco_trade.storage:get_string(storage_key)) or {}
            if #unclaimed == 0 then minetest.chat_send_player(name, "Nothing to reclaim!") return end
            
            local inv = player:get_inventory()
            for i, data in ipairs(unclaimed) do
                if data:sub(1,6) == "MONEY:" then
                    local amt = tonumber(data:sub(7))
                    pay_physical(player, amt)
                    unclaimed[i] = nil
                else
                    local stack = ItemStack(data)
                    if inv:room_for_item("main", stack) then
                        inv:add_item("main", stack)
                        unclaimed[i] = nil
                    end
                end
            end
            -- Clean up the table
            local new_list = {}
            for _, v in pairs(unclaimed) do table.insert(new_list, v) end
            eco_trade.storage:set_string(storage_key, minetest.serialize(new_list))
            minetest.chat_send_player(name, "Check your inventory for reclaimed items/money!")
        end

        -- SELECTING AN ITEM
        for field, _ in pairs(fields) do
            if field:sub(1,7) == "select_" then
                local id = field:sub(8)
                local ah = minetest.deserialize(eco_trade.storage:get_string("ah_data")) or {}
                if ah[id].seller == name then
                    minetest.chat_send_player(name, "You own this item! Wait for the auction to end.")
                else
                    eco_trade.show_bid_window(name, id)
                end
            end
        end
    end

    -- BIDDING POPUP LOGIC
    if formname:sub(1,19) == "eco_trade:bid_popup" then
        local id = formname:sub(21)
        local ah = minetest.deserialize(eco_trade.storage:get_string("ah_data")) or {}
        local entry = ah[id]
        if not entry then return end

        if fields.place_bid then
            local amt = tonumber(fields.bid_amount)
            if not amt or amt <= 0 then
                minetest.chat_send_player(name, "Incorrect value! Use numbers only.")
                return
            end
            if amt < (entry.price + entry.increment) then
                minetest.chat_send_player(name, "Bid must be at least " .. (entry.price + entry.increment) .. "¢")
                return
            end
            
            entry.price = amt
            entry.last_bidder = name
            eco_trade.storage:set_string("ah_data", minetest.serialize(ah))
            minetest.chat_send_all("[AH] " .. name .. " is now the top bidder for " .. entry.itemstring)
            eco_trade.show_ah(name)
        end

        if fields.buy_now then
            local bal = get_physical_balance(player)
            if bal < entry.buy_now then
                minetest.chat_send_player(name, "You can't afford the Buy Now price!")
                return
            end
            
            -- Take Money from Buyer
            player:get_inventory():remove_item("main", ItemStack("currency:minegeld_1 " .. entry.buy_now))
            -- Give Item to Buyer
            player:get_inventory():add_item("main", ItemStack(entry.itemstring))
            
            -- Send money to Seller's Reclaim bin
            local s_key = "expired:" .. entry.seller
            local s_storage = minetest.deserialize(eco_trade.storage:get_string(s_key)) or {}
            table.insert(s_storage, "MONEY:" .. entry.buy_now)
            eco_trade.storage:set_string(s_key, minetest.serialize(s_storage))
            
            ah[id] = nil
            eco_trade.storage:set_string("ah_data", minetest.serialize(ah))
            minetest.chat_send_player(name, "Item purchased!")
            eco_trade.show_ah(name)
        end
    end
end)
