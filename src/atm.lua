local bank = require("atmBankApi")
local modem = peripheral.find("modem") or error("No modem attached", 0)
local monitor = peripheral.find("monitor") or error("No monitor attached", 0)
local cardDrive = peripheral.wrap("right")
local interfaceStorage = peripheral.wrap("front")
local internalStorage = peripheral.wrap("back")
local opMode = false

local responsePort = 531 + os.getComputerID()

bank.initialize(responsePort)

local coins = {
    spurs = {
        nbt = "d3adddbc586c8a708b5e213b206b7687",
        rate = 1 / 64
    },
    bevels = {
        nbt = "c9f52ce05acf3715bf592eea6edbc450",
        rate = 1 / 8
    },
    sprockets = {
        nbt = "25a3275f9ecdc11c78648e61e95376b0",
        rate = 1 / 4
    },
    cogs = {
        nbt = "2442f28a7aec5cf7b09d2c2756caa1a4",
        rate = 1
    },
    crowns = {
        nbt = "77b458f3adececb55e27a47b4ecb714b",
        rate = 8
    },
    suns = {
        nbt = "9eabd6c6d7c587c1694fb86d4182cd62",
        rate = 64
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

local currentUser = nil
local DisplayedMessage = "Unknown error"
local screen = "insert" -- insert, info, withdraw, deposit, transfer, balance

-- Function to display a message on the monitor

local function displayMessage(message)
    print("displaying message: " .. message)
    screen = "info"
    DisplayedMessage = message or "Unknown error"
end

local function updateUser()
    local UUID = bank.getUUID(cardDrive)
    print(UUID)
    currentUser = bank.getUser(UUID)
end

modem.open(responsePort)

local function countCoins(tab, amount)
    if ((tab.total or 0) < amount) then
        print("Not enough money (" .. tab.total .. " < " .. amount .. ")")
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

    table.sort(tab.detail, function(a, b) return coins[a.coin].rate > coins[b.coin].rate end)
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
    return result
end

local charset = {}
do -- [0-9a-zA-Z]
    for c = 48, 57 do table.insert(charset, string.char(c)) end
    for c = 65, 90 do table.insert(charset, string.char(c)) end
    for c = 97, 122 do table.insert(charset, string.char(c)) end
end

local function checkInterfaceStorage()
    interfaceStorageMoney.total = 0
    for slot, item in pairs(interfaceStorage.list()) do
        for key, coin in pairs(coins) do
            if (item.nbt == coin.nbt) then
                interfaceStorageMoney.detail[slot] = {
                    coin = key,
                    count = item.count,
                }
                interfaceStorageMoney.total = interfaceStorageMoney.total + item.count * coin.rate
            end
        end
    end
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

local function deposit(amount)
    print("Depositing " .. amount .. "C into " .. currentUser.name .. "'s account")
    checkInterfaceStorage()
    if interfaceStorageMoney.total < amount then
        print("Not enough money in interface storage")
        displayMessage("Not enough money in interface storage")
        return false
    end
    local coinSlots = countCoins(interfaceStorageMoney, amount)
    if coinSlots == 0 then
        print("Not enough coins to make up " .. amount .. "C")
        displayMessage("Not enough money in interface storage")
        return false
    end
    local response = bank.request("deposit", { name = currentUser.name, amount = amount, cardID = currentUser.cardID })
    if response.status == "success" then
        print("Deposited " .. amount .. "C into " .. currentUser.name .. "'s account")
        displayMessage("Deposited " .. amount .. "C")
        for slot, value in pairs(coinSlots) do
            interfaceStorage.pushItems("back", slot, value.count)
        end
        return true
    else
        displayMessage("Failed to deposit " .. amount .. "C")
        print("Failed to deposit " .. amount .. "C into " .. currentUser.name .. "'s account")
        return false
    end
end

local function withdraw(amount)
    checkInternalStorage()
    local coinSlots = countCoins(internalStorageMoney, amount)
    if (coinSlots == 0) then
        print("Not enough money in internal storage")
        bank.alertServer("Not enough money in internal storage")
        displayMessage("Not enough money in internal storage")
        return false
    end
    local response = bank.request("withdraw", { name = currentUser.name, amount = amount, cardID = currentUser.cardID })
    if response.status == "success" then
        for slot, value in pairs(coinSlots) do
            internalStorage.pushItems("front", slot, value.count)
        end
        displayMessage("Withdrew " .. amount .. "C")
        print("Withdrew " .. amount .. "C from " .. currentUser.name .. "'s account")
    else
        displayMessage("Failed to withdraw " .. amount .. "C")
        print("Failed to withdraw " .. amount .. "C from " .. currentUser.name .. "'s account")
    end
end

-- Main loop to listen for incoming requests

monitor.setTextScale(0.5)
local w, h = monitor.getSize()
local withdrawAmountString = ""

while true do
    checkInterfaceStorage()
    local e = { os.pullEvent() }
    if e[1] == "modem_message" then
        bank.handleModemRequest(e)
    elseif e[1] == "disk" then
        screen = "main"
    elseif e[1] == "disk_eject" then
        currentUser = nil
        screen = "insert"
    elseif e[1] == "monitor_touch" then
        print("Touch: " .. screen)
        if screen == "info" then
            screen = "main"
        end
        if screen == "main" then
            local x, y = e[3], e[4]
            print(x, y)
            if y == 4 then
                deposit(interfaceStorageMoney.total)
            elseif y == 5 then
                screen = "withdraw"
                monitor.clear()
                monitor.setCursorPos(1, 1)
                monitor.write("Withdraw")
                monitor.setCursorPos(1, 2)
                monitor.write("Amount:")
                monitor.setCursorPos(1, 3)
                monitor.write((tonumber(withdrawAmountString) or 0) .. "C")
                monitor.setCursorPos(1, 5)
                monitor.write("Confirm")
                monitor.setBackgroundColor(colors.gray)
                monitor.setCursorPos(4, 7)
                monitor.write(" 1 2 3 ")
                monitor.setCursorPos(4, 8)
                monitor.write(" 4 5 6 ")
                monitor.setCursorPos(4, 9)
                monitor.write(" 7 8 9 ")
                monitor.setCursorPos(4, 10)
                monitor.write(" 0 < x ")
                monitor.setBackgroundColor(colors.black)
            end
        elseif screen == "withdraw" then
            local x, y = e[3], e[4]

            if y == 5 then
                withdraw(tonumber(withdrawAmountString))
                withdrawAmountString = "0"
            end
            print(x, y)
            if y == 7 then
                if x == 5 then
                    withdrawAmountString = withdrawAmountString .. "1"
                elseif x == 7 then
                    withdrawAmountString = withdrawAmountString .. "2"
                elseif x == 9 then
                    withdrawAmountString = withdrawAmountString .. "3"
                end
            elseif y == 8 then
                if x == 5 then
                    withdrawAmountString = withdrawAmountString .. "4"
                elseif x == 7 then
                    withdrawAmountString = withdrawAmountString .. "5"
                elseif x == 9 then
                    withdrawAmountString = withdrawAmountString .. "6"
                end
            elseif y == 9 then
                if x == 5 then
                    withdrawAmountString = withdrawAmountString .. "7"
                elseif x == 7 then
                    withdrawAmountString = withdrawAmountString .. "8"
                elseif x == 9 then
                    withdrawAmountString = withdrawAmountString .. "9"
                end
            elseif y == 10 then
                if x == 5 then
                    withdrawAmountString = withdrawAmountString .. "0"
                elseif x == 7 then
                    withdrawAmountString = withdrawAmountString:sub(1, -2)
                elseif x == 9 then
                    withdrawAmountString = ""
                end
            end
            monitor.setCursorPos(1, 3)
            monitor.clearLine()
            monitor.write((tonumber(withdrawAmountString) or 0) .. "C")
        end
    end
    if screen == "info" then
        print("Info: " .. DisplayedMessage)
        monitor.clear()
        local wrappedErrorMessageLines = require "cc.strings".wrap(DisplayedMessage, w)
        for i, line in ipairs(wrappedErrorMessageLines) do
            monitor.setCursorPos(1, i)
            monitor.write(line)
        end
        monitor.setCursorPos(1, h)
        monitor.write("Continue")
    elseif screen == "main" then
        checkInterfaceStorage()
        updateUser()
        if not currentUser then
            screen = "invalid"
        else
            monitor.clear()
            monitor.setCursorPos(1, 1)
            monitor.write(currentUser.name)
            monitor.setCursorPos(1, 2)
            monitor.write("Bal: " .. math.floor(currentUser.balance * 100) / 100 .. "C")
            monitor.setCursorPos(1, 4)
            monitor.write("deposit " .. math.floor(interfaceStorageMoney.total * 100) / 100 .. "C")
            monitor.setCursorPos(1, 5)
            monitor.write("withdraw")
        end
    end
    if screen == "invalid" then
        monitor.clear()
        monitor.setCursorPos(1, 1)
        monitor.write("Invalid card.\nPlease remove card and insert a valid card.")
    end
    if screen == "insert" then
        monitor.clear()
        monitor.setCursorPos(1, 1)
        monitor.write("Insert card")
    end
end
