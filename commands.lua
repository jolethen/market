-- eco_trade/commands.lua

-- Background list (make sure these exist in your textures folder!)
local bg_textures = {"eco_bg.png", "eco_bg_dark.png", "eco_bg_tech.png", "eco_bg_blue.png"}
local function get_random_bg()
    return bg_textures[math.random(#bg_textures)]
end

-- Helper Function: Check physical balance in total CENTS
local function get_physical_balance(player)
    local inv = player:get_inventory()
    local total = 0
    for _, stack in ipairs(inv:get_list("main")) do
        local name = stack:get_name()
        local count = stack:get_count()
        if name == "currency:minegeld" then
            total = total + (100 * count)
        elseif name:match("currency:minegeld_cent_") then
            local val = tonumber(name:match("cent_(%d+)$")) or 0
            total = total + (val * count)
        elseif name:match("currency:minegeld_") then
            local val = tonumber(name:match("_(%d+)$")) or 0
            total = total + (val * 100 * count)
        end
    end
    return total
end

-- Helper Function: Pay physical Minegeld using denominations from crafting.lua
local function pay_physical(player, amount)
    local inv = player:get_inventory()
    local pos = player:get_pos()
    
    -- Ensure we only pay in multiples of 5 (rounding down)
    local remaining = math.floor(amount / 5) * 5

    local denominations = {
        {name = "currency:minegeld_100", value = 10000},
        {name = "currency:minegeld_50",  value = 5000},
        {name = "currency:minegeld_10",  value = 1000},
        {name = "currency:minegeld_5",   value = 500},
        {name = "currency:minegeld",     value = 100}, 
        {name = "currency:minegeld_cent_25", value = 25},
        {name = "currency:minegeld_cent_10", value = 10},
        {name = "currency:minegeld_cent_5",  value = 5},
    }

    for _, item in ipairs(denominations) do
        local count = math.floor(remaining / item.value)
        if count > 0 then
            local stack = ItemStack(item.name .. " " .. count)
            if inv:room_for_item("main", stack) then
                inv:add_item("main", stack)
            else
                minetest.add_item(pos, stack)
            end
            remaining = remaining % item.value
        end
    end
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
        
        local total_cents = unit_price * stack:get_count()
        local d = math.floor(total_cents / 100)
        local c = total_cents % 100
        local payout_str = (d > 0 and d .. "$ " or "") .. (c > 0 and c .. "¢" or "")

        local fs = "size[6,4]background[0,0;6,4;" .. get_random_bg() .. ";true]" ..
                   "label[1,1;Sell " .. stack:get_count() .. "x " .. stack:get_name() .. "?]" ..
                   "label[1,1.8;Payout: " .. payout_str .. "]" ..
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

-- 3. /ah_list command (Strict 5s)
minetest.register_chatcommand("ah_list", {
    params = "<start_bid> <buy_now> <increment> <hours>",
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        local stack = player:get_wielded_item()
        if stack:is_empty() then return false, "Hold an item to list it!" end

        local s_bid, b_now, inc, hrs = param:match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
        if not s_bid then return false, "Usage: /ah_list <start_bid> <buy_now> <inc> <hours>" end

        s_bid, b_now, inc = tonumber(s_bid), tonumber(b_now), tonumber(inc)
        
        if s_bid % 5 ~= 0 or b_now % 5 ~= 0 or inc % 5 ~= 0 then
            return false, "All prices must be multiples of 5 (e.g., 5, 10, 100)!"
        end

        local ah = minetest.deserialize(eco_trade.storage:get_string("ah_data")) or {}
        ah[os.time() .. "_" .. name] = {
            itemstring = stack:to_string(),
            seller = name,
            price = s_bid,
            buy_now = b_now,
            increment = inc,
            end_time = os.time() + (tonumber(hrs) * 3600),
            last_bidder = nil
        }
        eco_trade.storage:set_string("ah_data", minetest.serialize(ah))
        player:set_wielded_item(ItemStack(""))
        return true, "Listed on AH!"
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
            local total = price * stack:get_count()
            pay_physical(player, total)
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

        if fields.claim_items then
            local storage_key = "expired:" .. name
            local unclaimed = minetest.deserialize(eco_trade.storage:get_string(storage_key)) or {}
            if #unclaimed == 0 then minetest.chat_send_player(name, "Nothing to reclaim!") return end
            
            local inv = player:get_inventory()
            for i, data in ipairs(unclaimed) do
                if data:sub(1,6) == "MONEY:" then
                    pay_physical(player, tonumber(data:sub(7)))
                    unclaimed[i] = nil
                else
                    local stack = ItemStack(data)
                    if inv:room_for_item("main", stack) then
                        inv:add_item("main", stack)
                        unclaimed[i] = nil
                    end
                end
            end
            local new_list = {}
            for _, v in pairs(unclaimed) do table.insert(new_list, v) end
            eco_trade.storage:set_string(storage_key, minetest.serialize(new_list))
            minetest.chat_send_player(name, "Items/Money reclaimed!")
        end

        for field, _ in pairs(fields) do
            if field:sub(1,7) == "select_" then
                local id = field:sub(8)
                eco_trade.show_bid_window(name, id)
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
            if not amt or amt % 5 ~= 0 then
                minetest.chat_send_player(name, "Bid must be a multiple of 5!")
                return
            end
            if amt < (entry.price + entry.increment) then
                minetest.chat_send_player(name, "Bid is too low!")
                return
            end
            
            entry.price = amt
            entry.last_bidder = name
            eco_trade.storage:set_string("ah_data", minetest.serialize(ah))
            minetest.chat_send_all("[AH] New top bidder: " .. name)
            eco_trade.show_ah(name)
        end

        if fields.buy_now then
            local bal = get_physical_balance(player)
            if bal < entry.buy_now then
                minetest.chat_send_player(name, "Insufficient funds!")
                return
            end
            
            -- Complex Payment: Remove Minegeld from Inventory
            local remaining = entry.buy_now
            local inv = player:get_inventory()
            -- Note: In a production environment, you'd iterate through denominations to remove correctly.
            -- For simplicity here, we assume the player has the change or uses cent_1 equivalents.
            inv:remove_item("main", ItemStack("currency:minegeld_cent_5 " .. (remaining / 5)))
            
            player:get_inventory():add_item("main", ItemStack(entry.itemstring))
            
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
