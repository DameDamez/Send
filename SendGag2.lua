if not game:IsLoaded() then game.Loaded:Wait() end
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Auto Gift (Standalone)",
    SubTitle = "FB : Nattawat",
    TabWidth = 140,
    Size = UDim2.fromOffset(480, 380),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Gifting", Icon = "gift" })
}

local targetUsername = ""
local category = "Seeds"
local items = {"Gold"}
local amount = 999999
local isLooping = false
local isGifting = false

Tabs.Main:AddInput("TargetUser", {
    Title = "Target Username",
    Default = "",
    Placeholder = "Enter exact username (e.g. benze_423)",
    Numeric = false,
    Finished = false,
    Callback = function(Value)
        targetUsername = Value
    end
})

local categoryData = {
    Seeds = {"Gold", "Rainbow", "Dragon's Breath"},
    Fruits = {},
    Gears = {"Rusty Watering Can", "Common Watering Can"}
}

-- ฟังก์ชันค้นหา Category ที่แท้จริงจากโฟลเดอร์ในเกม
local function getRealCategoryFromAssets(itemName, defaultCategory)
    local ok, Assets = pcall(function() return game:GetService("ReplicatedStorage"):WaitForChild("Assets", 3) end)
    if ok and Assets then
        for _, obj in ipairs(Assets:GetChildren()) do
            if obj:IsA("Folder") then
                if obj:FindFirstChild(itemName) then
                    return obj.Name -- คืนค่าชื่อโฟลเดอร์ (เช่น Sprinklers, Props, Mushrooms)
                end
            end
        end
    end
    return defaultCategory
end

local CategoryDropdown = Tabs.Main:AddDropdown("GiftCategory", {
    Title = "Category",
    Values = {"Seeds", "Fruits", "Gears"},
    Multi = false,
    Default = 1,
    Callback = function(Value)
        category = Value
        local opts = Fluent.Options
        if opts and opts.GiftItems then
            local itemsList = categoryData[Value] or {}
            opts.GiftItems:SetValues(itemsList)
            opts.GiftItems:SetValue({}) -- เคลียร์ของเก่าที่เลือกไว้ทิ้ง
        end
    end
})

local ItemsDropdown = Tabs.Main:AddDropdown("GiftItems", {
    Title = "Items to Send",
    Description = "Select what you want to send",
    Values = categoryData.Seeds,
    Multi = true,
    Default = {"Gold"},
    Callback = function(Value)
        items = {}
        for k, v in pairs(Value) do
            -- แก้บัค UI Library ที่มักจะคืนค่ามาทั้ง Array และ Dictionary ปนกัน
            if type(k) == "string" and v == true then
                table.insert(items, k)
            elseif type(k) == "number" and type(v) == "string" then
                -- เผื่อในกรณีที่มันคืนค่ามาเป็น Array ล้วนๆ
                if not table.find(items, v) then
                    table.insert(items, v)
                end
            end
        end
    end
})

task.spawn(function()
    pcall(function()
        if not game:IsLoaded() then game.Loaded:Wait() end
        local SM = game:GetService("ReplicatedStorage"):WaitForChild("SharedModules", 5)
        if not SM then return end
        
        -- Load Seeds
        local seedData = SM:WaitForChild("SeedData", 5)
        if seedData then
            for _, v in pairs(require(seedData)) do
                if v.SeedName then 
                    local fName = string.gsub(v.SeedName, " Seed", "")
                    if not table.find(categoryData.Seeds, fName) then
                        table.insert(categoryData.Seeds, fName)
                    end
                end
            end
            table.sort(categoryData.Seeds)
        end
        
        -- Load Fruits
        local fruitData = SM:WaitForChild("FruitData", 5)
        if fruitData then
            for _, v in pairs(require(fruitData)) do
                if v.FruitName then
                    if not table.find(categoryData.Fruits, v.FruitName) then
                        table.insert(categoryData.Fruits, v.FruitName)
                    end
                end
            end
            table.sort(categoryData.Fruits)
        end
        
        -- Load Gears and map them
        local gearData = SM:WaitForChild("GearShopData", 5)
        if gearData then
            for _, v in pairs(require(gearData).Data) do
                if v.ItemName then
                    if not table.find(categoryData.Gears, v.ItemName) then
                        table.insert(categoryData.Gears, v.ItemName)
                    end
                end
            end
            table.sort(categoryData.Gears)
        end
        
        -- อัปเดต Dropdown หลังจากโหลดเสร็จ
        if categoryData[category] then
            ItemsDropdown:SetValues(categoryData[category])
        end
    end)
end)

Tabs.Main:AddInput("AmountLimit", {
    Title = "Amount Limit",
    Description = "Leave blank to send all items in backpack",
    Default = "",
    Numeric = true,
    Finished = false,
    Callback = function(Value)
        amount = tonumber(Value) or 999999
    end
})

local function performGift()
    local ok, Networking = pcall(function()
        return require(game:GetService("ReplicatedStorage"):WaitForChild("SharedModules"):WaitForChild("Networking"))
    end)
    local SendBatch = ok and Networking and Networking.Mailbox and Networking.Mailbox.SendBatch
    
    if not SendBatch then
        Fluent:Notify({Title="Error", Content="Networking module not ready!", Duration=3})
        return false
    end

    if targetUsername == "" then
        Fluent:Notify({Title="Error", Content="Please enter target username", Duration=3})
        return false
    end
    
    local targetId
    pcall(function()
        targetId = game.Players:GetUserIdFromNameAsync(targetUsername)
    end)
    
    if not targetId then
        Fluent:Notify({Title="Error", Content="Player not found!", Duration=3})
        return false
    end
    
    if #items == 0 then
        Fluent:Notify({Title="Error", Content="Please select at least 1 item", Duration=3})
        return false
    end
    
    local batch = {}
    local totalCount = 0
    local backpack = game:GetService("Players").LocalPlayer:FindFirstChild("Backpack")
    local character = game:GetService("Players").LocalPlayer.Character
    
    for _, itemName in ipairs(items) do
        local finalCount = 0
        local tool = nil
        
        if backpack then tool = backpack:FindFirstChild(itemName) end
        if not tool and character then tool = character:FindFirstChild(itemName) end -- เช็คในตัวเผื่อถือของอยู่
        
        if tool then
            local realCount = tool:GetAttribute("Count")
            if realCount and type(realCount) == "number" then
                finalCount = math.min(amount, realCount)
            else
                -- นับจำนวนชิ้นที่มีจริงๆ ทั้งในกระเป๋าและที่ถืออยู่
                local countInstances = 0
                if backpack then
                    for _, c in pairs(backpack:GetChildren()) do
                        if c.Name == itemName then countInstances = countInstances + 1 end
                    end
                end
                if character then
                    for _, c in pairs(character:GetChildren()) do
                        if c.Name == itemName then countInstances = countInstances + 1 end
                    end
                end
                finalCount = math.min(amount, countInstances)
                if finalCount <= 0 then finalCount = 1 end
            end
        else
            -- หาไม่เจอในกระเป๋า (อาจเพราะชื่อโมเดลไม่ตรงกับชื่อเรียก) ให้บังคับส่งไปเลยตามจำนวนที่ขอ
            if amount == 999999 then
                finalCount = 1 -- กันเหนียว
            else
                finalCount = amount
            end
        end
        if finalCount > 0 then
            local actualCategory = category
            if category == "Gears" then
                -- หาหมวดหมู่ที่แท้จริงจากโฟลเดอร์ Assets ในเกม (แม่นยำ 100%)
                actualCategory = getRealCategoryFromAssets(itemName, "Gears")
                
                -- Fallback สำรองเผื่อหาไม่เจอจริงๆ
                if actualCategory == "Gears" then
                    local lowerName = itemName:lower()
                    if string.find(lowerName, "sprinkler") then
                        actualCategory = "Sprinklers"
                    elseif string.find(lowerName, "watering can") then
                        actualCategory = "WateringCans"
                    elseif string.find(lowerName, "build") or string.find(lowerName, "hammer") then
                        actualCategory = "Builders"
                    end
                end
            end
            
            table.insert(batch, {
                Category = actualCategory,
                ItemKey = itemName,
                Count = finalCount
            })
            totalCount = totalCount + finalCount
        end
    end
    
    if #batch > 0 then
        -- 🔴 เพิ่มระบบ LOG ดูว่ายิงอะไรไปบ้าง
        warn("📦 [AUTO GIFT LOG] กำลังส่งคำสั่ง (Payload):")
        for i, data in ipairs(batch) do
            warn(string.format("   [%d] Category: '%s' | ItemKey: '%s' | Count: %s", i, tostring(data.Category), tostring(data.ItemKey), tostring(data.Count)))
        end
        
        pcall(function()
            SendBatch:Fire(targetId, batch, "")
        end)
        Fluent:Notify({Title="Sent Request", Content="Sent " .. totalCount .. " items! Check F9 Log", Duration=4})
        return true
    else
        return true -- return true so loop continues waiting for items
    end
end

Tabs.Main:AddButton({
    Title = "Send Once",
    Description = "Send selected items one time manually",
    Callback = function()
        if isGifting then return end
        isGifting = true
        task.spawn(function()
            performGift()
            isGifting = false
        end)
    end
})

local LoopToggle = Tabs.Main:AddToggle("AutoLoop", {Title = "Enable Auto Loop", Default = false })

LoopToggle:OnChanged(function()
    isLooping = LoopToggle.Value
    if isLooping then
        Fluent:Notify({Title="Loop Started", Content="Will send items every 1.5s", Duration=3})
        task.spawn(function()
            while isLooping do
                isGifting = true
                local success = performGift()
                if not success then
                    LoopToggle:SetValue(false)
                    break
                end
                task.wait(1.5)
            end
            isGifting = false
        end)
    else
        Fluent:Notify({Title="Loop Stopped", Content="Auto Gift Loop Stopped", Duration=3})
    end
end)

Window:SelectTab(1)
Fluent:Notify({
    Title = "Loaded",
    Content = "Standalone Auto Gift is ready!",
    Duration = 3
})
