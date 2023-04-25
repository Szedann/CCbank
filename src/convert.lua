local monitor = peripheral.find("monitor") or error("No monitor attached", 0)
local interfaceStorage = peripheral.wrap("front")
local internalStorage = peripheral.wrap("back")
local logging = true

local coins = {
    spurs = {
        nbt = "d3adddbc586c8a708b5e213b206b7687",
        rate = 1 / 64,
        letter = "S"
    },
    bevels = {
        nbt = "c9f52ce05acf3715bf592eea6edbc450",
        rate = 1 / 8,
        letter = "V"
    },
    sprockets = {
        nbt = "25a3275f9ecdc11c78648e61e95376b0",
        rate = 1 / 4,
        letter = "K"
    },
    cogs = {
        nbt = "2442f28a7aec5cf7b09d2c2756caa1a4",
        rate = 1,
        letter = "C"
    },
    crowns = {
        nbt = "77b458f3adececb55e27a47b4ecb714b",
        rate = 8,
        letter = "R"
    },
    suns = {
        nbt = "9eabd6c6d7c587c1694fb86d4182cd62",
        rate = 64,
        letter = "U"
    }
}

local interfaceStorageMoney = {
    total = 0,
    detail = {}
}
local internalStorageMoney = {
    total = 0,
    detail = {}
}


local function countCoins(tab, amount)
    if ((tab.total or 0) < amount) then
        if (logging) then print("Not enough money (" .. tab.total .. " < " .. amount .. ")") end
        return 0
    end
    if (tab.total == amount) then
        return tab.detail
    end

    local result = {}
    local total = 0

    for slot, data in pairs(tab.detail) do
        data.slot = slot
    end
    print(textutils.serialize(tab.detail))
    table.sort(tab.detail, function(a, b)
        if not b or not a then return true end
        return coins[a.coin].rate > coins[b.coin].rate
    end
    )

    for _, data in pairs(tab.detail) do
        local coin = coins[data.coin]
        local count = math.floor((amount - total) / coin.rate)
        if (count > data.count) then
            count = data.count
        end
        if (count > 0) then
            result[data.slot] = {
                coin = data.coin,
                count = count,
            }
            total = total + count * coin.rate
        end
        if (total == amount) then
            break
        end
    end
    if total ~= amount then
        if (logging) then print("Not enough money (" .. total .. " < " .. amount .. ")") end
        return 0
    end
    return result
end

local function checkInterfaceStorage()
    local total = 0
    for slot, item in pairs(interfaceStorage.list()) do
        for key, coin in pairs(coins) do
            if (item.nbt == coin.nbt) then
                interfaceStorageMoney.detail[slot] = {
                    coin = key,
                    count = item.count,
                }
                total = total + item.count * coin.rate
            end
        end
    end

    local changed = interfaceStorageMoney.total ~= total
    if (changed) then
        interfaceStorageMoney.total = total
    end
    return changed
end

local function checkInternalStorage()
    internalStorageMoney.total = 0
    for slot, item in pairs(internalStorage.list()) do
        for key, coin in pairs(coins) do
            if (item.nbt == coin.nbt) then
                internalStorageMoney.detail[slot] = {
                    coin = key,
                    count = item.count,
                }
                internalStorageMoney.total = internalStorageMoney.total + item.count * coin.rate
            end
        end
    end
end

-- screen variables
local DisplayedMessage = "Unknown error"
local screen = "withdraw" -- insert, info, withdraw, deposit, transfer, balance(main)
local skipInfo = true     -- true if user can continue from current info screen
monitor.setTextScale(0.5)
local w, h = monitor.getSize()

local withdrawAmountString = "0"
local withdrawCoinType = nil
--[[
Spurs
beVels
sprocKets
Cogs
cRowns
sUns]]
local function withdrawScreen()
    if (string.len(withdrawAmountString) == 0) then
        withdrawAmountString = "0"
    end
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor.write("Convert")

    local letter = "C"
    if withdrawCoinType then
        letter = withdrawCoinType.letter
    end
    monitor.write(" " .. interfaceStorageMoney.total .. "C")
    monitor.setCursorPos(1, 2)
    monitor.write("Amount: " .. withdrawAmountString .. letter)
    if withdrawCoinType then
        monitor.setCursorPos(1, 3)
        monitor.setTextColor(colors.lightGray)
        monitor.write("= " .. math.floor(tonumber(withdrawAmountString) * withdrawCoinType.rate * 100) / 100 .. "C")
        monitor.setTextColor(colors.white)
    end
    local iteration = 0
    for index, coin in pairs(coins) do
        monitor.setCursorPos(3 + iteration, 4)
        iteration = iteration + 2
        if coin == withdrawCoinType then
            monitor.setTextColor(colors.black)
            monitor.setBackgroundColor(colors.white)
        else
            monitor.setBackgroundColor(colors.black)
        end
        monitor.write(coin.letter)
        monitor.setTextColor(colors.white)
        monitor.setBackgroundColor(colors.black)
    end
    monitor.setCursorPos(5, 5)
    monitor.setBackgroundColor(colors.lightGray)
    monitor.setTextColor(colors.black)
    monitor.write(" 1 2 3 ")
    monitor.setCursorPos(5, 6)
    monitor.write(" 4 5 6 ")
    monitor.setCursorPos(5, 7)
    monitor.write(" 7 8 9 ")
    monitor.setCursorPos(5, 8)
    monitor.write(" 0 < x ")
    monitor.setCursorPos(1, 10)
    monitor.setBackgroundColor(colors.white)
    monitor.write("Accept")
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
end

-- call to update UI state
local function updateUI()
    if screen == "info" then
        if (logging) then print("Info: " .. DisplayedMessage) end
        monitor.clear()
        local wrappedErrorMessageLines = require "cc.strings".wrap(DisplayedMessage, w)
        for i, line in ipairs(wrappedErrorMessageLines) do
            monitor.setCursorPos(1, i)
            monitor.write(line)
        end
        -- allow going to the main menu only if user can skip this info
        if skipInfo then
            monitor.setCursorPos(1, h)
            monitor.write("Continue")
        end
    elseif screen == "withdraw" then
        checkInterfaceStorage()
        withdrawScreen()
    elseif screen == "insert" then
        monitor.clear()
        monitor.setCursorPos(1, 1)
        monitor.write("Insert card")
    end
end

-- Function to display a message on the monitor
local function displayMessage(message, skip)
    if (skip == nil) then skip = true end -- skip defaults to true if not passed

    if (logging) then print("displaying message: " .. message) end
    screen = "info"
    skipInfo = skip
    DisplayedMessage = message or "Unknown error"
    updateUI()
end


local function deposit(amount)
    if (logging) then print("Accepting " .. amount .. "C") end
    checkInterfaceStorage()
    -- redundant as countCoins achieves this with extra validation
    --[[if interfaceStorageMoney.total < amount then
        if (bank.logging) then print("Not enough money in interface storage")
        displayMessage("Not enough money in interface storage") end
        return false
    end]]
    --

    local coinSlots = countCoins(interfaceStorageMoney, amount)
    if coinSlots == 0 then
        if (logging) then print("Not enough coins to make up " .. amount .. "C") end
        displayMessage("Not enough money in interface storage")
        return
    end
    displayMessage("Please wait...", false)

    local totalDeposited = 0
    for slot, value in pairs(coinSlots) do
        local movedAmount = interfaceStorage.pushItems("back", slot, value.count)
        totalDeposited = totalDeposited + movedAmount * coins[value.coin].rate
    end
    print(totalDeposited)
    if (totalDeposited ~= amount) then
        checkInternalStorage()

        if (logging) then
            print("Failed to accept " ..
                amount .. "C")
        end
        displayMessage("Unable to move coins, internal storage may be full")
        local slots = countCoins(internalStorageMoney, totalDeposited)
        for slot, value in pairs(slots) do
            interfaceStorage.pullItems("back", slot, value.count)
        end
        return false
    end
    if (logging) then print("Accepted " .. amount .. "C") end
    return true
end


local function withdraw(amount, coinTypes)
    checkInternalStorage()
    local tab = {
        total = 0,
        detail = {}
    }
    if (coinTypes) then
        for slot, coin in pairs(internalStorageMoney.detail) do
            for index, value in ipairs(coinTypes) do
                if (value == coins[coin.coin]) then
                    tab.detail[slot] = coin
                    tab.total = tab.total + coin.count * coins[coin.coin].rate
                end
            end
        end
    else
        tab = internalStorageMoney
    end
    local coinSlots = countCoins(tab, amount)
    if (coinSlots == 0) then
        if (logging) then print("Not enough money in internal storage") end
        displayMessage("Not enough money in internal storage")
        return false
    end
    print(textutils.serialise(coinSlots))

    displayMessage("Please wait...", false)
    for slot, value in pairs(coinSlots) do
        internalStorage.pushItems("front", slot, value.count)
    end
    if (logging) then
        print("Converted " ..
            amount .. "C")
    end
    return true
end

-- Event driven handler for listening to events
local function handleWithdrawTouch(x, y)
    local optionGrid = {}
    optionGrid[5] = {}
    optionGrid[5][6] = "num_1"
    optionGrid[5][8] = "num_2"
    optionGrid[5][10] = "num_3"
    optionGrid[6] = {}
    optionGrid[6][6] = "num_4"
    optionGrid[6][8] = "num_5"
    optionGrid[6][10] = "num_6"
    optionGrid[7] = {}
    optionGrid[7][6] = "num_7"
    optionGrid[7][8] = "num_8"
    optionGrid[7][10] = "num_9"
    optionGrid[8] = {}
    optionGrid[8][6] = "num_0"
    optionGrid[8][8] = "backspace"
    optionGrid[8][10] = "clear"

    local iteration = 0
    optionGrid[4] = {}
    for coin, data in pairs(coins) do
        optionGrid[4][3 + iteration] = "coin_" .. coin
        iteration = iteration + 2
    end

    local optionY = optionGrid[y]
    if (optionY) then
        option = optionY[x]
        if (not option) then
            return
        end
        if (string.sub(option, 1, 4) == "num_") then
            local num = string.sub(option, 5)
            if (withdrawAmountString == "0") then
                withdrawAmountString = num
            else
                withdrawAmountString = withdrawAmountString .. num
            end
        elseif option == "backspace" then
            withdrawAmountString = string.sub(withdrawAmountString, 1, string.len(withdrawAmountString) - 1) or "0"
        elseif option == "clear" then
            withdrawAmountString = "0"
        elseif (string.sub(option, 1, 5) == "coin_") then
            local coin = string.sub(option, 6)
            print("coin: " .. coin)
            withdrawCoinType = coins[coin]
        end
    end
    if (y == 10) then
        if (x < 8) then
            local actualAmount = tonumber(withdrawAmountString)
            if withdrawCoinType then
                actualAmount = actualAmount * withdrawCoinType.rate
            end
            if (interfaceStorageMoney.total < actualAmount) then
                displayMessage("Conversion amount requested greater than total provided. Please put in more money.")
                withdrawAmountString = "0"
                withdrawCoinType = nil
                return
            end
            if (deposit(interfaceStorageMoney.total)) then
                if (withdrawCoinType) then
                    if (withdraw(interfaceStorageMoney.total - actualAmount) and
                        withdraw(actualAmount, { withdrawCoinType })) then
                        displayMessage("Converted " ..
                        actualAmount ..
                        "C" .. " With " .. interfaceStorageMoney.total - actualAmount .. "C changed to the highest coin.")
                    end
                else
                    if (withdraw(actualAmount)) then
                        displayMessage("Converted " .. actualAmount .. "C")
                    end
                end
            end

            withdrawAmountString = "0"
            withdrawCoinType = nil
        end
    end
    if (screen == "withdraw") then
        withdrawScreen()
    end
end

local function eventloop()
    while (true) do
        local event = { os.pullEventRaw() }

        -- if there was a change to the total in the interface
        if (checkInterfaceStorage()) then
            -- update the UI
            updateUI()
        end

        if event[1] == "monitor_touch" then
            if (logging) then print("Touch: " .. screen) end
            if screen == "info" and skipInfo then
                -- go back to the main menu only if the user can skip this info
                screen = "withdraw"
            elseif screen == "withdraw" then
                local x, y = event[3], event[4]
                handleWithdrawTouch(x, y)
            end
            updateUI()
        elseif event[1] == "terminate" then
            error("terminated", 1)
        end
    end
end

-- initalize UI
monitor.setTextScale(0.5)
displayMessage("Loading...", false)
screen = "withdraw"
updateUI()
eventloop()
