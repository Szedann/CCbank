local bank = require("atmBankApi")
local monitor = peripheral.find("monitor") or error("No monitor attached", 0)
local cardDrive = peripheral.wrap("right")
local interfaceStorage = peripheral.wrap("front")
local internalStorage = peripheral.wrap("back")
bank.setLoggingEnabled(true)

local interfaceStorageMoney = {
    total = 0,
    detail = {}
}
local internalStorageMoney = {
    total = 0,
    detail = {}
}

local currentUser = nil

local function countCoins(tab, amount)
    if ((tab.total or 0) < amount) then
        if (bank.getLoggingEnabled()) then print("Not enough money (" .. tab.total .. " < " .. amount .. ")") end
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

    table.sort(tab.detail, function(a, b) return bank.coins[a.coin].rate > bank.coins[b.coin].rate end)
    for _, data in pairs(tab.detail) do
        local coin = bank.coins[data.coin]
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
    return result
end

local function checkInterfaceStorage()
    local total = 0
    for slot, item in pairs(interfaceStorage.list()) do
        for key, coin in pairs(bank.coins) do
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
        for key, coin in pairs(bank.coins) do
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
local screen = "insert" -- insert, info, withdraw, deposit, transfer, balance(main)
local skipInfo = true   -- true if user can continue from current info screen
monitor.setTextScale(0.5)
local w, h = monitor.getSize()

-- call to update UI state
local function updateUI()
    if screen == "info" then
        if (bank.getLoggingEnabled()) then print("Info: " .. DisplayedMessage) end
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
    elseif screen == "main" then
        checkInterfaceStorage()
        monitor.clear()
        monitor.setCursorPos(1, 1)
        monitor.write(currentUser.name)
        monitor.setCursorPos(1, 2)
        monitor.write("Bal: " .. math.floor(currentUser.balance * 100) / 100 .. "C")
        monitor.setCursorPos(1, 4)
        monitor.write("deposit " .. math.floor(interfaceStorageMoney.total * 100) / 100 .. "C")
        monitor.setCursorPos(1, 5)
        monitor.write("withdraw")
    elseif screen == "insert" then
        monitor.clear()
        monitor.setCursorPos(1, 1)
        monitor.write("Insert card")
    end
end

-- Function to display a message on the monitor
local function displayMessage(message, skip)
    if (skip == nil) then skip = true end -- skip defaults to true if not passed

    if (bank.getLoggingEnabled()) then print("displaying message: " .. message) end
    screen = "info"
    skipInfo = skip
    DisplayedMessage = message or "Unknown error"
    updateUI()
end

local function updateUser()
    local UUID = bank.getUUID(cardDrive)
    if (bank.getLoggingEnabled()) then print(UUID) end
    displayMessage("Reading Card. Please Wait...", false)
    bank.getUser(UUID,
        function(response)
            currentUser = response
            if not currentUser then
                displayMessage("Invalid card. Please remove card and insert a valid card.", false)
            else
                screen = "main"
            end
            updateUI()
        end
    )
end

local function deposit(amount)
    if (bank.getLoggingEnabled()) then print("Depositing " .. amount .. "C into " .. currentUser.name .. "'s account") end
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
        if (bank.getLoggingEnabled()) then print("Not enough coins to make up " .. amount .. "C") end
        displayMessage("Not enough money in interface storage")
        return
    end
    print(textutils.serialise(currentUser))
    displayMessage("Please wait...", false)

    local totalDeposited = 0
    for slot, value in pairs(coinSlots) do
        local movedAmount = interfaceStorage.pushItems("back", slot, value.count)
        totalDeposited = totalDeposited + movedAmount * bank.coins[value.coin].rate
    end
    print(totalDeposited)
    if (totalDeposited ~= amount) then
        checkInternalStorage()

        if (bank.getLoggingEnabled()) then
            print("Failed to deposit " ..
                amount .. "C into " .. currentUser.name .. "'s account")
        end
        displayMessage("Unable to move coins, internal storage may be full")
        local slots = countCoins(internalStorageMoney, totalDeposited)
        for slot, value in pairs(slots) do
            interfaceStorage.pullItems("back", slot, value.count)
        end
        return
    end
    bank.request("deposit", { amount = amount, cardID = currentUser.cardID },
        function(response)
            if (response.status == "success") then
                -- update user balance locally
                currentUser.balance = currentUser.balance + amount
                if (bank.getLoggingEnabled()) then
                    print("Deposited " ..
                        amount .. "C into " .. currentUser.name .. "'s account")
                end
                displayMessage("Deposited " .. amount .. "C")
            else
                displayMessage("Failed to deposit " .. amount .. "C")
                if (bank.getLoggingEnabled()) then
                    print("Failed to deposit " ..
                        amount .. "C into " .. currentUser.name .. "'s account")
                end
            end
        end
    )
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
                if (value == bank.coins[coin.coin]) then
                    tab.detail[slot] = coin
                    tab.total = tab.total + coin.count * bank.coins[coin.coin].rate
                end
            end
        end
    else
        tab = internalStorageMoney
    end
    local coinSlots = countCoins(tab, amount)
    if (coinSlots == 0) then
        if (bank.getLoggingEnabled()) then print("Not enough money in internal storage") end
        bank.alertServer("Not enough money in internal storage")
        displayMessage("Not enough money in internal storage")
        return
    end
    print(textutils.serialise(coinSlots))
    displayMessage("Please wait...", false)
    bank.request("withdraw", { amount = amount, cardID = currentUser.cardID },
        function(response)
            print(textutils.serialise(response))
            if (response.status == "success") then
                -- update user balance locally
                currentUser.balance = currentUser.balance - amount
                for slot, value in pairs(coinSlots) do
                    internalStorage.pushItems("front", slot, value.count)
                end
                displayMessage("Withdrew " .. amount .. "C")
                if (bank.getLoggingEnabled()) then
                    print("Withdrew " ..
                        amount .. "C from " .. currentUser.name .. "'s account")
                end
            else
                displayMessage("Failed to withdraw " .. amount .. "C")
                if (bank.getLoggingEnabled()) then
                    print("Failed to withdraw " ..
                        amount .. "C from " .. currentUser.name .. "'s account")
                end
            end
        end
    )
end

-- Event driven handler for listening to events
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
    monitor.write("Withdraw")
    monitor.setCursorPos(1, 2)
    local letter = "C"
    if withdrawCoinType then
        letter = withdrawCoinType.letter
    end
    monitor.write("Amount: " .. withdrawAmountString .. letter)
    if withdrawCoinType then
        monitor.setCursorPos(1, 3)
        monitor.setTextColor(colors.lightGray)
        monitor.write("= " .. math.floor(tonumber(withdrawAmountString) * withdrawCoinType.rate * 100) / 100 .. "C")
        monitor.setTextColor(colors.white)
    end
    local iteration = 0
    for index, coin in pairs(bank.coins) do
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
    monitor.write("Accept   Cancel")
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
end

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
    for coin, data in pairs(bank.coins) do
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
            withdrawCoinType = bank.coins[coin]
        end
    end
    if (y == 10) then
        if (x < 8) then
            local actualAmount = tonumber(withdrawAmountString)
            if withdrawCoinType then
                actualAmount = actualAmount * withdrawCoinType.rate
            end
            if (withdrawCoinType) then
                withdraw(actualAmount, { withdrawCoinType })
            else
                withdraw(actualAmount)
            end
            withdrawAmountString = "0"
            withdrawCoinType = nil
        else
            screen = "main"
            withdrawAmountString = "0"
            withdrawCoinType = nil
        end
    end
    if (screen == "withdraw") then
        withdrawScreen()
    end
end

local function onEvent(event)
    -- if there was a change to the total in the interface
    if (checkInterfaceStorage()) then
        -- update the UI
        updateUI()
    end
    -- call api listners first
    local handled = bank.onEvent(event)

    -- if event wasn't handled, try and handle it
    if (not handled) then
        if event[1] == "disk" then
            handled = true
            updateUser()
        elseif event[1] == "disk_eject" then
            handled = true
            currentUser = nil
            screen = "insert"
            updateUI()
        elseif event[1] == "monitor_touch" then
            if (bank.getLoggingEnabled()) then print("Touch: " .. screen) end
            if screen == "info" and skipInfo then
                handled = true
                -- go back to the main menu only if the user can skip this info
                screen = "main"
            elseif screen == "main" then
                handled = true
                local x, y = event[3], event[4]
                if (bank.getLoggingEnabled()) then print(x, y) end
                if y == 4 then
                    ---- remove this
                    print("depositing " .. interfaceStorageMoney.total)
                    deposit(interfaceStorageMoney.total)
                elseif y == 5 then
                    screen = "withdraw"
                    withdrawScreen()
                    withdrawAmountString = "0"
                end
            elseif screen == "withdraw" then
                handled = true
                local x, y = event[3], event[4]
                handleWithdrawTouch(x, y)
            end
            updateUI()
        end
    end
    return handled
end

local function main()
    -- run any start methods for the APIs
    bank.onStart()
    -- initalize UI
    monitor.setTextScale(0.5)
    updateUI()
    bank.registerATM()
end

-- intialize, passing main and this onEvent function as the entry listener
bank.initialize(main, onEvent)
