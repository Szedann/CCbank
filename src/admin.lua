local bank = require("atmBankApi")
bank.setCryptoLoggingEnabled(false)
local prompt = false -- set to true when terminal should prompt user

local function registerClient(input)
    if (bank.isConnected()) then
        local args = {}
        for i in string.gmatch(input, "([^" .. "," .. "]+)") do
            table.insert(args, i)
        end

        if (#args ~= 2) then
            print("Wrong number of arguments, expect 2.")
            prompt = true
            return
        end
        -- prepare data
        local id = args[1]
        local type = args[2]

        bank.request("setup", { id = id, type = type },
            function(response)
                if (response.status == "success") then
                    print("Registered client " .. id .. " as type: " .. type)
                else
                    print("Failed to register client " .. id .. " as type: " .. type)
                    print(response.message)
                end
                -- prompt user for another registration
                prompt = true;
            end
        )
    else
        print("Failed to register client " .. id .. " as type: " .. type)
        -- prompt user for another registration
        -- once connection established
        prompt = true;
    end
end

local function promptUser()
    if (prompt) then
        prompt = false
        print("Input <id,type> to register:")
        print("Example: 1,atm")
        local input = io.stdin:read()
        registerClient(input)
    end
end

local function onEvent(event)
    -- call api listners first
    local handled = bank.onEvent(event)

    -- if event wasn't handled, try and handle it
    if (not handled) then
        promptUser()
    end
    return handled
end

-- setup screen
local w, h = term.getSize()
term.setBackgroundColor(colors.red)
term.setCursorPos(1, 1)
term.clearLine()
print("Admin Terminal")
term.setBackgroundColor(colors.black)
local window = window.create(term.current(), 1, 2, w, h - 1)
term.redirect(window)

local function registerATMCallback(status)
    if (status == "updates") then
        print("Updating...")
    elseif (status == "unknown") then
        print("Card not Registered. Please contact support.")
    elseif (status == "success") then
        prompt = true;
        promptUser()
    end
end

local function onDisconnect()
    -- reboot to try reconnect
    os.reboot()
    --[[term.clear()
    term.setCursorPos(1, 1)
    print("Disconnected... Trying to reconnect...")
    bank.onStart()
    bank.registerATM({
        "atmBankApi.lua",
        "bankApi.lua",
        "userRegister.lua"
    }, registerATMCallback)]]
end

local function main()
    -- run any start methods for the APIs
    print("Connecting to Server...")
    bank.onStart()
    bank.registerATM({
        "atmBankApi.lua",
        "bankApi.lua",
        "admin.lua"
    }, registerATMCallback)
end

-- intialize, passing main and this onEvent function as the entry listener
bank.initialize(main, onEvent, onDisconnect)
