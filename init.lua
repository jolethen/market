local storage = minetest.get_mod_storage()
local eco = {}

-- Load Prices from TXT
eco.prices = {}
local function load_prices()
    local path = minetest.get_modpath("eco_trade") .. "/prices.txt"
    local file = io.open(path, "r")
    if file then
        for line in file:lines() do
            local name, price = line:match("([^,]+),([^,]+)")
            if name and price then eco.prices[name] = tonumber(price) end
        end
        file:close()
    end
end
load_prices()

-- Helper: Get Dynamic Price
local function get_price(item_name)
    local base = eco.prices[item_name]
    if not base then return nil end
    local sold = storage:get_int("vol:" .. item_name)
    local drops = math.floor(sold / 640)
    return math.max(1, base - drops)
end

-- --- AUCTION HOUSE LOGIC ---

-- Expiry loop (Every 2 hours)
local function check_expiry()
    local ah = minetest.deserialize(storage:get_string("ah_data")) or {}
    local now = os.time()
    local changed = false
    for id, entry in pairs(ah) do
        if now - entry.time > 259200 then -- 72 Hours
            -- Logic to send to player's "collection" could go here
            ah[id] = nil
            changed = true
        end
    end
    if changed then storage:set_string("ah_data", minetest.serialize(ah)) end
    minetest.after(7200, check_expiry)
end
minetest.after(7200, check_expiry)

-- --- FORMSPECS ---

local function show_ah(player_name)
    local ah = minetest.deserialize(storage:get_string("ah_data")) or {}
    local form = "size[10,8]background[0,0;10,8;eco_bg.png;true]" ..
                 "label[3.5,0;=== SERVER AUCTION HOUSE ===]"
    
    local x, y = 0.5, 1
    for id, entry in pairs(ah) do
        local item = ItemStack(entry.itemstring)
        form = form .. ("item_image_button[%f,%f;1,1;%s;bid_%s;]"):format(x, y, entry.itemstring, id)
        form = form .. ("label[%f,%f;%s¢]"):format(x, y + 1, entry.price)
        
        x = x + 1.2
        if x > 8.5 then x = 0.5 y = y + 1.5 end
    end
    minetest.show_formspec(player_name, "eco_trade:ah_main", form)
end

-- --- COMMANDS ---

minetest.register_chatcommand("sell", {
    func = function(name)
        local player = minetest.get_player_by_name(name)
        local stack = player:get_wielded_item()
        local item_name = stack:get_name()
        local p = get_price(item_name)
        
        if not p then return false, "Server doesn't buy this!" end
        
        local total = p * stack:get_count()
        local fs = "size[5,3]background[0,0;5,3;eco_bg.png;true]" ..
                   "label[0.5,0.5;Sell " .. stack:get_count() .. "x for " .. total .. "¢?]" ..
                   "button_exit[0.5,2;2,1;confirm_sell;Confirm]" ..
                   "button_exit[2.5,2;2,1;cancel;Cancel]"
        minetest.show_formspec(name, "eco_trade:sell_confirm", fs)
    end
})

minetest.register_chatcommand("ah", {
    func = function(name) show_ah(name) return true end
})

-- --- HANDLERS ---

minetest.register_on_player_receive_fields(function(player, formname, fields)
    local name = player:get_player_name()
    
    if formname == "eco_trade:sell_confirm" and fields.confirm_sell then
        local stack = player:get_wielded_item()
        local item_name = stack:get_name()
        local payout = get_price(item_name) * stack:get_count()
        
        -- Update stats & give money
        storage:set_int("vol:" .. item_name, storage:get_int("vol:" .. item_name) + stack:get_count())
        -- Add your economy mod call here, e.g., currency.add(name, payout)
        
        player:set_wielded_item(ItemStack(""))
        minetest.chat_send_player(name, "Sold for " .. payout .. "¢!")
    end
    
    -- Add auction bidding logic here for fields starting with "bid_"
end)
