-- Initialize global table for cross-file access
eco_trade = {}
eco_trade.storage = minetest.get_mod_storage()

-- Get the path to this mod
local path = minetest.get_modpath("eco_trade")

-- Load the components
dofile(path .. "/api.lua")      -- Load pricing logic first
dofile(path .. "/auction.lua")  -- Load AH system
dofile(path .. "/commands.lua") -- Finally, register the commands

minetest.log("action", "[eco_trade] Mod loaded successfully!")
