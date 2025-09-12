-- Phantom Chat Hub Client (Roblox Lua) 🌌
local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
local SoundService = game:GetService("SoundService") -- สำหรับแจ้งเตือนเสียง 🔥

-- ─── CONFIG ────────────────────────────── ⚙️
local DEBUG_MODE   = false -- Toggle debug mode (true = enabled, false = disabled)
local USE_DEFAULT_URL = true
local DEFAULT_URL     = "wss://11f2d4110382.ngrok-free.app"

local wsApi = WebSocket or WebSocketClient or (syn and syn.websocket)
if not wsApi then
    if DEBUG_MODE then
        warn("❌ Executor นี้ไม่รองรับ WebSocket! 🚫")
    end
    local noWsGui = Instance.new("ScreenGui", PlayerGui)
    noWsGui.Name = "NoWebSocketWarning"
    local noWsLabel = Instance.new("TextLabel", noWsGui)
    noWsLabel.Size = UDim2.new(0.4, 0, 0.2, 0)
    noWsLabel.Position = UDim2.new(0.3, 0, 0.4, 0)
    noWsLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    noWsLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
    noWsLabel.Text = "❌ Executor ไม่รองรับ WebSocket!"
    noWsLabel.Font = Enum.Font.SourceSansBold
    noWsLabel.TextSize = 20
    task.delay(5, function() noWsGui:Destroy() end)
    return
end

-- ป้องกันการรันซ้ำ (Duplicate-run guard) 🛡️
if PlayerGui:FindFirstChild("PhantomChatHub") then
    if DEBUG_MODE then
        warn("PhantomChatHub: UI already exists in PlayerGui — aborting duplicate execution.")
    end
    return
end
if (getgenv and getgenv().PhantomChatHubLoaded) or _G.PhantomChatHubLoaded then
    if DEBUG_MODE then
        warn("PhantomChatHub: already running (global flag) — aborting duplicate execution.")
    end
    return
end
if getgenv then getgenv().PhantomChatHubLoaded = true end
_G.PhantomChatHubLoaded = true

-- ─── VARIABLES ────────────────────────── 📦
local connection, connected = nil, false
local connectCooldown = false
local isAuthenticated = false
local sendCooldown = false
local hasAccessToTab3 = false -- สำหรับ check access tab 3
local requestCooldown = false -- Cooldown สำหรับ request list users

local chatGui = nil
local chatOutputFrame = nil
local chatList = nil
local toggleButtonGui = nil
local hasSentAuth = false
local settings = {
    uiScale = 1,
    notificationEnabled = true,
    theme = "default" -- default หรือ rainbow 🌈
}

local selectedTarget = nil -- ตัวแปรใหม่สำหรับเป้าหมายที่เลือกใน tab 3

-- ─── ฟังก์ชัน log ────────────────────── 📜
local function log(txt)
    if DEBUG_MODE then
        print(txt)
    end
end

-- ─── สร้าง UI ใหม่กับ 3 แท็บ ────────── 🖼️✨
local function createChatUI()
    if chatGui and chatGui.Parent then return chatGui end
    local existing = PlayerGui:FindFirstChild("PhantomChatHub")
    if existing then chatGui = existing return chatGui end

    chatGui = Instance.new("ScreenGui")  
    chatGui.Name = "PhantomChatHub"  
    chatGui.ResetOnSpawn = false  
    chatGui.Enabled = false  
    chatGui.Parent = PlayerGui  

    local chatFrame = Instance.new("Frame", chatGui)  
    chatFrame.Size            = UDim2.new(0.6 * settings.uiScale, 0, 0.7 * settings.uiScale, 0)  
    chatFrame.Position        = UDim2.new(0.2, 0, 0.15, 0)  
    chatFrame.BackgroundColor3= Color3.fromRGB(20, 20, 20)  
    chatFrame.Active          = true  
    chatFrame.Draggable       = true  

    local title = Instance.new("TextLabel", chatFrame)  
    title.Text              = "🌌 Phantom Chat Hub"  
    title.Size              = UDim2.new(1, 0, 0.1, 0)  
    title.BackgroundColor3  = Color3.fromRGB(30, 30, 30)  
    title.TextColor3        = Color3.fromRGB(0, 255, 0)  
    title.Font              = Enum.Font.SourceSansBold  
    title.TextSize          = 24  

    -- ─── ระบบแท็บ ────────────────────────── 📑
    local tabBar = Instance.new("Frame", chatFrame)
    tabBar.Size = UDim2.new(1, 0, 0.08, 0)
    tabBar.Position = UDim2.new(0, 0, 0.1, 0)
    tabBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)

    local chatTabBtn = Instance.new("TextButton", tabBar)
    chatTabBtn.Text = "💬 แชท"
    chatTabBtn.Size = UDim2.new(0.333, 0, 1, 0)
    chatTabBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    chatTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    chatTabBtn.Font = Enum.Font.SourceSansBold
    chatTabBtn.TextSize = 18

    local usersTabBtn = Instance.new("TextButton", tabBar)
    usersTabBtn.Text = "👥 ผู้ใช้"
    usersTabBtn.Size = UDim2.new(0.333, 0, 1, 0)
    usersTabBtn.Position = UDim2.new(0.333, 0, 0, 0)
    usersTabBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    usersTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    usersTabBtn.Font = Enum.Font.SourceSansBold
    usersTabBtn.TextSize = 18

    local settingsTabBtn = Instance.new("TextButton", tabBar)
    settingsTabBtn.Text = "⚙️ ตั้งค่า"
    settingsTabBtn.Size = UDim2.new(0.333, 0, 1, 0)
    settingsTabBtn.Position = UDim2.new(0.666, 0, 0, 0)
    settingsTabBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    settingsTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    settingsTabBtn.Font = Enum.Font.SourceSansBold
    settingsTabBtn.TextSize = 18

    -- แท็บ 1: แชทสาธารณะ 💬
    local chatTabFrame = Instance.new("Frame", chatFrame)
    chatTabFrame.Size = UDim2.new(1, 0, 0.82, 0)
    chatTabFrame.Position = UDim2.new(0, 0, 0.18, 0)
    chatTabFrame.BackgroundTransparency = 1
    chatTabFrame.Visible = true

    chatOutputFrame = Instance.new("ScrollingFrame", chatTabFrame)  
    chatOutputFrame.Name = "ChatScroll"  
    chatOutputFrame.Size             = UDim2.new(1, -20, 0.65, -10)  
    chatOutputFrame.Position         = UDim2.new(0, 10, 0, 5)  
    chatOutputFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)  
    chatOutputFrame.BorderSizePixel  = 0  
    chatOutputFrame.CanvasSize       = UDim2.new(0, 0, 0, 0)  
    chatOutputFrame.ScrollBarThickness = 8  
    chatOutputFrame.BackgroundTransparency = 0.1  
    pcall(function() chatOutputFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y end)  

    chatList = Instance.new("UIListLayout", chatOutputFrame)  
    chatList.SortOrder = Enum.SortOrder.LayoutOrder  
    chatList.Padding   = UDim.new(0, 6)  

    local chatInput = Instance.new("TextBox", chatTabFrame)  
    chatInput.Name = "ChatInput"  
    chatInput.PlaceholderText = "🗨️ พิมพ์ข้อความแชท..."  
    chatInput.Size            = UDim2.new(0.7, -10, 0.1, 0)  
    chatInput.Position        = UDim2.new(0, 10, 0.78, 5)  
    chatInput.BackgroundColor3= Color3.fromRGB(10, 10, 10)  
    chatInput.TextColor3      = Color3.fromRGB(0, 255, 255)  
    chatInput.Font            = Enum.Font.SourceSans  
    chatInput.TextSize        = 18  

    local chatBtn = Instance.new("TextButton", chatTabFrame)  
    chatBtn.Text          = "🗨️ ส่ง"  
    chatBtn.Size          = UDim2.new(0.3, -10, 0.1, 0)  
    chatBtn.Position      = UDim2.new(0.7, 0, 0.78, 5)  
    chatBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 0)  
    chatBtn.TextColor3    = Color3.fromRGB(255, 255, 255)  
    chatBtn.Font          = Enum.Font.SourceSansBold  
    chatBtn.TextSize      = 18  

    chatBtn.MouseButton1Click:Connect(function()  
        if sendCooldown then 
            if DEBUG_MODE then log("⏱️ โปรดรอซักครู่") end 
            return 
        end  
        if not connection or not connected then 
            if DEBUG_MODE then log("🔌 ยังไม่เชื่อมต่อ!") end 
            return 
        end  
        sendCooldown = true  
        task.delay(2, function() sendCooldown = false end)  

        local msg = chatInput.Text  
        if msg == "" then 
            if DEBUG_MODE then log("⚠️ กรอกข้อความแชท") end 
            return 
        end  

        connection:Send("chat " .. msg)  
        chatInput.Text = ""  
    end)  

    -- แท็บ 3: ผู้ใช้ออนไลน์ 👥 – แบ่งซ้าย (list ชื่อ) ขวา (ปุ่มคำสั่ง)
    local usersTabFrame = Instance.new("Frame", chatFrame)
    usersTabFrame.Size = UDim2.new(1, 0, 0.82, 0)
    usersTabFrame.Position = UDim2.new(0, 0, 0.18, 0)
    usersTabFrame.BackgroundTransparency = 1
    usersTabFrame.Visible = false

    -- ซ้าย: List ชื่อผู้ใช้ (กดเลือก)
    local leftFrame = Instance.new("Frame", usersTabFrame)
    leftFrame.Size = UDim2.new(0.5, -10, 1, -10)
    leftFrame.Position = UDim2.new(0, 10, 0, 5)
    leftFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    leftFrame.BorderSizePixel = 0

    local leftTitle = Instance.new("TextLabel", leftFrame)
    leftTitle.Text = "รายชื่อผู้ใช้ออนไลน์"
    leftTitle.Size = UDim2.new(1, 0, 0.05, 0)
    leftTitle.BackgroundTransparency = 1
    leftTitle.TextColor3 = Color3.fromRGB(0, 255, 0)
    leftTitle.Font = Enum.Font.SourceSansBold
    leftTitle.TextSize = 18

    local leftScroll = Instance.new("ScrollingFrame", leftFrame)
    leftScroll.Size = UDim2.new(1, 0, 0.95, 0)
    leftScroll.Position = UDim2.new(0, 0, 0.05, 0)
    leftScroll.BackgroundTransparency = 1
    leftScroll.ScrollBarThickness = 6
    leftScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    pcall(function() leftScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y end)

    local leftListLayout = Instance.new("UIListLayout", leftScroll)
    leftListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    leftListLayout.Padding = UDim.new(0, 5)

    -- ขวา: ปุ่มคำสั่งสำหรับเป้าหมายที่เลือก
    local rightFrame = Instance.new("Frame", usersTabFrame)
    rightFrame.Size = UDim2.new(0.5, -10, 1, -10)
    rightFrame.Position = UDim2.new(0.5, 0, 0, 5)
    rightFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    rightFrame.BorderSizePixel = 0

    local rightTitle = Instance.new("TextLabel", rightFrame)
    rightTitle.Text = "คำสั่งสำหรับเป้าหมาย"
    rightTitle.Size = UDim2.new(1, 0, 0.05, 0)
    rightTitle.BackgroundTransparency = 1
    rightTitle.TextColor3 = Color3.fromRGB(0, 255, 0)
    rightTitle.Font = Enum.Font.SourceSansBold
    rightTitle.TextSize = 18

    local selectedLabel = Instance.new("TextLabel", rightFrame)
    selectedLabel.Name = "SelectedLabel"
    selectedLabel.Text = "เลือกผู้ใช้ก่อน"
    selectedLabel.Size = UDim2.new(1, 0, 0.1, 0)
    selectedLabel.Position = UDim2.new(0, 0, 0.1, 0)
    selectedLabel.BackgroundTransparency = 1
    selectedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    selectedLabel.Font = Enum.Font.SourceSans
    selectedLabel.TextSize = 16

    local killBtn = Instance.new("TextButton", rightFrame)
    killBtn.Text = "💀 ฆ่า"
    killBtn.Size = UDim2.new(1, 0, 0.1, 0)
    killBtn.Position = UDim2.new(0, 0, 0.25, 0)
    killBtn.BackgroundColor3 = Color3.fromRGB(100, 0, 0)
    killBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    killBtn.Font = Enum.Font.SourceSansBold
    killBtn.TextSize = 18
    killBtn.MouseButton1Click:Connect(function()
        if selectedTarget and connection and connected then
            connection:Send(";ฆ่า " .. selectedTarget)
            if DEBUG_MODE then log("📤 ส่งคำสั่งฆ่า: " .. selectedTarget) end
        else
            showNotification("❌ เลือกเป้าหมายก่อน!")
        end
    end)

    local kickBtn = Instance.new("TextButton", rightFrame)
    kickBtn.Text = "🦵 แตะ"
    kickBtn.Size = UDim2.new(1, 0, 0.1, 0)
    kickBtn.Position = UDim2.new(0, 0, 0.4, 0)
    kickBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 0)
    kickBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    kickBtn.Font = Enum.Font.SourceSansBold
    kickBtn.TextSize = 18
    kickBtn.MouseButton1Click:Connect(function()
        if selectedTarget and connection and connected then
            connection:Send(";แตะ " .. selectedTarget)
            if DEBUG_MODE then log("📤 ส่งคำสั่งแตะ: " .. selectedTarget) end
        else
            showNotification("❌ เลือกเป้าหมายก่อน!")
        end
    end)

    local pullBtn = Instance.new("TextButton", rightFrame)
    pullBtn.Text = "🧲 ดึง"
    pullBtn.Size = UDim2.new(1, 0, 0.1, 0)
    pullBtn.Position = UDim2.new(0, 0, 0.55, 0)
    pullBtn.BackgroundColor3 = Color3.fromRGB(0, 100, 100)
    pullBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    pullBtn.Font = Enum.Font.SourceSansBold
    pullBtn.TextSize = 18
    pullBtn.MouseButton1Click:Connect(function()
        if selectedTarget and connection and connected then
            connection:Send(";ดึง pull " .. selectedTarget)
            if DEBUG_MODE then log("📤 ส่งคำสั่งดึง: " .. selectedTarget) end
        else
            showNotification("❌ เลือกเป้าหมายก่อน!")
        end
    end)

    local refreshUsersBtn = Instance.new("TextButton", usersTabFrame)
    refreshUsersBtn.Text = "🔄 รีเฟรชรายชื่อ"
    refreshUsersBtn.Size = UDim2.new(0.3, 0, 0.05, 0)
    refreshUsersBtn.Position = UDim2.new(0.35, 0, 0.93, 0)
    refreshUsersBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    refreshUsersBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    refreshUsersBtn.Font = Enum.Font.SourceSansBold
    refreshUsersBtn.TextSize = 16
    refreshUsersBtn.MouseButton1Click:Connect(function()
        if requestCooldown then return end
        requestCooldown = true
        task.delay(5, function() requestCooldown = false end)
        if connection and connected then
            connection:Send("!list_users")
            if DEBUG_MODE then log("📤 ขอรายชื่อผู้ใช้ออนไลน์ใหม่") end
        end
    end)

    -- แท็บ 2: ตั้งค่า ⚙️
    local settingsTabFrame = Instance.new("Frame", chatFrame)
    settingsTabFrame.Size = UDim2.new(1, 0, 0.82, 0)
    settingsTabFrame.Position = UDim2.new(0, 0, 0.18, 0)
    settingsTabFrame.BackgroundTransparency = 1
    settingsTabFrame.Visible = false

    local settingsScroll = Instance.new("ScrollingFrame", settingsTabFrame)
    settingsScroll.Size = UDim2.new(1, -20, 1, -10)
    settingsScroll.Position = UDim2.new(0, 10, 0, 5)
    settingsScroll.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    settingsScroll.BorderSizePixel = 0
    settingsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    settingsScroll.ScrollBarThickness = 8
    pcall(function() settingsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y end)

    local settingsList = Instance.new("UIListLayout", settingsScroll)
    settingsList.SortOrder = Enum.SortOrder.LayoutOrder
    settingsList.Padding = UDim.new(0, 10)

    -- ตั้งค่า UI Scale
    local uiScaleLabel = Instance.new("TextLabel", settingsScroll)
    uiScaleLabel.Size = UDim2.new(1, 0, 0, 30)
    uiScaleLabel.BackgroundTransparency = 1
    uiScaleLabel.Text = "📏 UI Scale: " .. settings.uiScale
    uiScaleLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
    uiScaleLabel.Font = Enum.Font.SourceSans
    uiScaleLabel.TextSize = 18

    local uiScaleBox = Instance.new("TextBox", uiScaleLabel)
    uiScaleBox.Size = UDim2.new(0.3, 0, 1, 0)
    uiScaleBox.Position = UDim2.new(0.7, 0, 0, 0)
    uiScaleBox.Text = tostring(settings.uiScale)
    uiScaleBox.FocusLost:Connect(function()
        local newScale = tonumber(uiScaleBox.Text)
        if newScale and newScale >= 0.8 and newScale <= 1.5 then
            settings.uiScale = newScale
            chatFrame.Size = UDim2.new(0.6 * newScale, 0, 0.7 * newScale, 0)
            uiScaleLabel.Text = "📏 UI Scale: " .. newScale
        else
            uiScaleBox.Text = tostring(settings.uiScale)
            if DEBUG_MODE then log("⚠️ UI Scale ต้องอยู่ระหว่าง 0.8-1.5") end
        end
    end)

    -- ตั้งค่า Notification Enabled
    local notifEnabledLabel = Instance.new("TextLabel", settingsScroll)
    notifEnabledLabel.Size = UDim2.new(1, 0, 0, 30)
    notifEnabledLabel.BackgroundTransparency = 1
    notifEnabledLabel.Text = "🔔 แจ้งเตือนข้อความใหม่: " .. (settings.notificationEnabled and "เปิด" or "ปิด")
    notifEnabledLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
    notifEnabledLabel.Font = Enum.Font.SourceSans
    notifEnabledLabel.TextSize = 18

    local notifEnabledToggle = Instance.new("TextButton", notifEnabledLabel)
    notifEnabledToggle.Size = UDim2.new(0.2, 0, 1, 0)
    notifEnabledToggle.Position = UDim2.new(0.8, 0, 0, 0)
    notifEnabledToggle.Text = "Toggle"
    notifEnabledToggle.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    notifEnabledToggle.MouseButton1Click:Connect(function()
        settings.notificationEnabled = not settings.notificationEnabled
        notifEnabledLabel.Text = "🔔 แจ้งเตือนข้อความใหม่: " .. (settings.notificationEnabled and "เปิด" or "ปิด")
    end)

    -- ตั้งค่า Theme
    local themeLabel = Instance.new("TextLabel", settingsScroll)
    themeLabel.Size = UDim2.new(1, 0, 0, 30)
    themeLabel.BackgroundTransparency = 1
    themeLabel.Text = "🎨 Theme: " .. (settings.theme == "default" and "สีเริ่มต้น" or "เรนโบว์")
    themeLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
    themeLabel.Font = Enum.Font.SourceSans
    themeLabel.TextSize = 18

    local themeToggle = Instance.new("TextButton", themeLabel)
    themeToggle.Size = UDim2.new(0.2, 0, 1, 0)
    themeToggle.Position = UDim2.new(0.8, 0, 0, 0)
    themeToggle.Text = "Toggle"
    themeToggle.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    themeToggle.MouseButton1Click:Connect(function()
        settings.theme = settings.theme == "default" and "rainbow" or "default"
        themeLabel.Text = "🎨 Theme: " .. (settings.theme == "default" and "สีเริ่มต้น" or "เรนโบว์")
        if settings.theme == "default" then
            chatFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
            title.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
            tabBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            chatTabBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
            usersTabBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            settingsTabBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            chatOutputFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            chatInput.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
            chatBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 0)
            leftFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
            rightFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
            settingsScroll.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            refreshUsersBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
            if toggleButtonGui then
                local toggleButton = toggleButtonGui:FindFirstChildOfClass("TextButton")
                if toggleButton then
                    toggleButton.BackgroundColor3 = Color3.fromRGB(0, 120, 0)
                end
            end
        end
    end)

    -- โหมดเรนโบว์ 🌈 (ครอบคลุมทั้ง UI รวม tab 3)
    local rainbowRunning = false
    local function updateRainbow()
        if rainbowRunning or settings.theme ~= "rainbow" then return end
        rainbowRunning = true
        task.spawn(function()
            while settings.theme == "rainbow" do
                local hue = (tick() % 5) / 5
                local color = Color3.fromHSV(hue, 0.7, 0.7)
                chatFrame.BackgroundColor3 = color
                title.BackgroundColor3 = Color3.fromHSV(hue + 0.05, 0.7, 0.7)
                tabBar.BackgroundColor3 = Color3.fromHSV(hue + 0.1, 0.7, 0.7)
                chatTabBtn.BackgroundColor3 = Color3.fromHSV(hue + 0.15, 0.7, 0.7)
                usersTabBtn.BackgroundColor3 = Color3.fromHSV(hue + 0.15, 0.7, 0.7)
                settingsTabBtn.BackgroundColor3 = Color3.fromHSV(hue + 0.15, 0.7, 0.7)
                chatOutputFrame.BackgroundColor3 = Color3.fromHSV(hue + 0.2, 0.7, 0.7)
                chatInput.BackgroundColor3 = Color3.fromHSV(hue + 0.3, 0.7, 0.7)
                chatBtn.BackgroundColor3 = Color3.fromHSV(hue + 0.4, 0.7, 0.7)
                leftFrame.BackgroundColor3 = Color3.fromHSV(hue + 0.2, 0.7, 0.7)
                rightFrame.BackgroundColor3 = Color3.fromHSV(hue + 0.2, 0.7, 0.7)
                settingsScroll.BackgroundColor3 = Color3.fromHSV(hue + 0.2, 0.7, 0.7)
                refreshUsersBtn.BackgroundColor3 = Color3.fromHSV(hue + 0.5, 0.7, 0.7)
                if toggleButtonGui then
                    local toggleButton = toggleButtonGui:FindFirstChildOfClass("TextButton")
                    if toggleButton then
                        toggleButton.BackgroundColor3 = Color3.fromHSV(hue + 0.5, 0.7, 0.7)
                    end
                end
                task.wait(0.1)
            end
            rainbowRunning = false
        end)
    end
    themeToggle.MouseButton1Click:Connect(updateRainbow)

    -- สลับแท็บ
    chatTabBtn.MouseButton1Click:Connect(function()
        chatTabFrame.Visible = true
        usersTabFrame.Visible = false
        settingsTabFrame.Visible = false
        chatTabBtn.BackgroundColor3 = settings.theme == "default" and Color3.fromRGB(60, 60, 60) or chatTabBtn.BackgroundColor3
        usersTabBtn.BackgroundColor3 = settings.theme == "default" and Color3.fromRGB(40, 40, 40) or usersTabBtn.BackgroundColor3
        settingsTabBtn.BackgroundColor3 = settings.theme == "default" and Color3.fromRGB(40, 40, 40) or settingsTabBtn.BackgroundColor3
    end)

    usersTabBtn.MouseButton1Click:Connect(function()
        chatTabFrame.Visible = false
        usersTabFrame.Visible = true
        settingsTabFrame.Visible = false
        chatTabBtn.BackgroundColor3 = settings.theme == "default" and Color3.fromRGB(40, 40, 40) or chatTabBtn.BackgroundColor3
        usersTabBtn.BackgroundColor3 = settings.theme == "default" and Color3.fromRGB(60, 60, 60) or usersTabBtn.BackgroundColor3
        settingsTabBtn.BackgroundColor3 = settings.theme == "default" and Color3.fromRGB(40, 40, 40) or settingsTabBtn.BackgroundColor3
        -- Auto check access และ request list เมื่อเปิด tab
        if connection and connected then
            connection:Send("!check_access")
            if DEBUG_MODE then log("📤 ขอตรวจสอบสิทธิ์ tab 3") end
        end
    end)

    settingsTabBtn.MouseButton1Click:Connect(function()
        chatTabFrame.Visible = false
        usersTabFrame.Visible = false
        settingsTabFrame.Visible = true
        chatTabBtn.BackgroundColor3 = settings.theme == "default" and Color3.fromRGB(40, 40, 40) or chatTabBtn.BackgroundColor3
        usersTabBtn.BackgroundColor3 = settings.theme == "default" and Color3.fromRGB(40, 40, 40) or usersTabBtn.BackgroundColor3
        settingsTabBtn.BackgroundColor3 = settings.theme == "default" and Color3.fromRGB(60, 60, 60) or settingsTabBtn.BackgroundColor3
    end)

    -- ปุ่ม toggle UI  
    if not toggleButtonGui or not toggleButtonGui.Parent then  
        toggleButtonGui = Instance.new("ScreenGui")  
        toggleButtonGui.Name = "ToggleChatButton"  
        toggleButtonGui.ResetOnSpawn = false  
        toggleButtonGui.Parent = PlayerGui  

        local toggleButton = Instance.new("TextButton", toggleButtonGui)  
        toggleButton.Size = UDim2.new(0, 50, 0, 50)  
        toggleButton.Position = UDim2.new(1, -60, 0, 10)  
        toggleButton.BackgroundColor3 = Color3.fromRGB(0, 120, 0)  
        toggleButton.Text = "💬"  
        toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)  
        toggleButton.Font = Enum.Font.SourceSansBold  
        toggleButton.TextSize = 20  
        toggleButton.BorderSizePixel = 0  

        Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0, 10)  

        toggleButton.MouseButton1Click:Connect(function()  
            chatGui.Enabled = not chatGui.Enabled  
            toggleButton.Text = chatGui.Enabled and "❌" or "💬"  
        end)  
    end  

    return chatGui
end

-- ─── ฟังก์ชันแสดง Notification ───────── 🔔
local lastNotifTime = 0
local function showNotification(text)
    if tick() - lastNotifTime < 3 then return end
    lastNotifTime = tick()

    local notifGui = Instance.new("ScreenGui")
    notifGui.Name = "PhantomNotification"
    notifGui.ResetOnSpawn = false
    notifGui.Parent = PlayerGui

    local notifFrame = Instance.new("Frame", notifGui)
    notifFrame.Size = UDim2.new(0.3, 0, 0.1, 0)
    notifFrame.Position = UDim2.new(0.35, 0, 0.05, 0)
    notifFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    notifFrame.BorderSizePixel = 0

    Instance.new("UICorner", notifFrame).CornerRadius = UDim.new(0, 8)

    local notifLabel = Instance.new("TextLabel", notifFrame)
    notifLabel.Size = UDim2.new(1, 0, 1, 0)
    notifLabel.BackgroundTransparency = 1
    notifLabel.Text = text
    notifLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
    notifLabel.Font = Enum.Font.SourceSansBold
    notifLabel.TextSize = 20
    notifLabel.TextWrapped = true

    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://9113391805"
    sound.Volume = 0.5
    sound.Parent = SoundService
    sound:Play()

    task.delay(3, function()
        sound:Destroy()
        notifGui:Destroy()
    end)
end

-- ─── ฟังก์ชันเพิ่มข้อความ chat ───────── 💬
local function addChatMessage(text)
    if not chatOutputFrame then return end
    local msgLabel = Instance.new("TextLabel")
    msgLabel.Size             = UDim2.new(1, -10, 0, 24)
    msgLabel.BackgroundTransparency = 1
    msgLabel.TextColor3       = Color3.fromRGB(0, 255, 0)
    msgLabel.Font             = Enum.Font.Code
    msgLabel.TextSize         = 16
    msgLabel.TextWrapped      = true
    msgLabel.TextXAlignment   = Enum.TextXAlignment.Left
    msgLabel.TextYAlignment   = Enum.TextYAlignment.Top
    msgLabel.Text             = tostring(text)
    msgLabel.Parent           = chatOutputFrame

    if not chatGui.Enabled and settings.notificationEnabled then
        showNotification("🔔 มีข้อความมาใหม่!")
    end

    local success, contentY = pcall(function() return chatList.AbsoluteContentSize.Y end)  
    if success and contentY then  
        pcall(function()  
            chatOutputFrame.CanvasSize = UDim2.new(0, 0, 0, contentY + 12)  
            chatOutputFrame.CanvasPosition = Vector2.new(0, math.max(0, contentY - chatOutputFrame.AbsoluteSize.Y))  
        end)  
    end
end

-- ─── ฟังก์ชันแสดง list users ใน tab 3 ── 📋
local function displayUserList(users)
    for _, child in ipairs(leftScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end

    for _, userData in ipairs(users) do
        local nameBtn = Instance.new("TextButton", leftScroll)
        nameBtn.Text = userData.name .. " (" .. userData.role .. ")"
        nameBtn.Size = UDim2.new(1, 0, 0, 30)
        nameBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        nameBtn.TextColor3 = Color3.fromRGB(0, 255, 0)
        nameBtn.Font = Enum.Font.SourceSans
        nameBtn.TextSize = 16
        nameBtn.TextWrapped = true
        nameBtn.MouseButton1Click:Connect(function()
            selectedTarget = userData.name
            selectedLabel.Text = "Selected: " .. selectedTarget
            if DEBUG_MODE then log("🎯 เลือกเป้าหมาย: " .. selectedTarget) end
        end)
    end

    local success, contentY = pcall(function() return leftListLayout.AbsoluteContentSize.Y end)
    if success and contentY then
        pcall(function()
            leftScroll.CanvasSize = UDim2.new(0, 0, 0, contentY + 12)
        end)
    end
end

-- ─── ฟังก์ชันส่งข้อความไป RBXGeneral (เช็ค) ── 📢
local function checkMessage()
    local success, result = pcall(function()
        local TextChatService = game:GetService("TextChatService")
        local channel = TextChatService:FindFirstChild("TextChannels") and TextChatService.TextChannels:FindFirstChild("RBXGeneral")
        if channel then
            channel:SendAsync("ผมใช้TOU HUB🎉")
            if DEBUG_MODE then log("📢 ส่งข้อความไป RBXGeneral สำเร็จ") end
        else
            warn("❌ ไม่พบแชนเนล RBXGeneral")
        end
    end)
    if not success and DEBUG_MODE then
        log("⚠️ CheckMessage Error: " .. tostring(result))
    end
end

-- ─── ฟังก์ชันวาปไปหาผู้ส่ง (ดึง) ────── 🚀
local function pullToSender(senderName)
    local success, result = pcall(function()
        local senderPlayer = Players:FindFirstChild(senderName)
        if not senderPlayer or not senderPlayer.Character then
            if DEBUG_MODE then log("❌ ไม่พบตัวละครของ " .. senderName) end
            showNotification("❌ ไม่พบตัวละครของ " .. senderName)
            return
        end

        local senderRoot = senderPlayer.Character:FindFirstChild("HumanoidRootPart")
        local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not senderRoot or not localRoot then
            if DEBUG_MODE then log("❌ HumanoidRootPart ไม่พบสำหรับ " .. senderName .. " หรือตัวคุณ") end
            showNotification("❌ ไม่สามารถวาปได้: ไม่พบตัวละคร")
            return
        end

        local offset = Vector3.new(3, 0, 0) -- วาปไปด้านหน้าผู้ส่ง 3 หน่วย
        localRoot.CFrame = senderRoot.CFrame * CFrame.new(offset)
        if DEBUG_MODE then log("🚀 วาปไปหา " .. senderName .. " สำเร็จ") end
        showNotification("🚀 วาปไปหา " .. senderName .. "!")
    end)
    if not success and DEBUG_MODE then
        log("⚠️ PullToSender Error: " .. tostring(result))
    end
end

-- ─── handleMessage ────────────────────── 📩
local function handleMessage(msg)
    if not msg then return end

    local success, result = pcall(function()
        if not hasSentAuth and msg:find("✅ คุณเชื่อมต่อเซิร์ฟเวอร์สำเร็จ!") then  
            local auth = {name=LocalPlayer.Name, userId=LocalPlayer.UserId}  
            connection:Send(HttpService:JSONEncode(auth))  
            hasSentAuth = true  
            if DEBUG_MODE then log("📤 ส่งชื่อ+ID ไปยังเซิร์ฟเวอร์") end  
            return  
        end  

        if not isAuthenticated and msg:find("🔑 ตั้งชื่อสำเร็จ") then  
            isAuthenticated = true  
            if chatGui then chatGui.Enabled = false end  
            if DEBUG_MODE then log(msg) end  
            return  
        end  

        local data = HttpService:JSONDecode(msg)  
        if type(data) == "table" then  
            if data.type == "access_check" then
                hasAccessToTab3 = data.granted
                if hasAccessToTab3 then
                    connection:Send("!list_users")
                    if DEBUG_MODE then log("✅ ได้สิทธิ์ tab 3 - ขอ list users") end
                else
                    showNotification("🚫 ไม่มีสิทธิ์เข้าถึง tab ผู้ใช้!")
                    if DEBUG_MODE then log("❌ ไม่มีสิทธิ์ tab 3: " .. (data.message or "No message")) end
                    -- สลับกลับแท็บแชทถ้า denied
                    chatTabFrame.Visible = true
                    usersTabFrame.Visible = false
                    settingsTabFrame.Visible = false
                    chatTabBtn.BackgroundColor3 = settings.theme == "default" and Color3.fromRGB(60, 60, 60) or chatTabBtn.BackgroundColor3
                    usersTabBtn.BackgroundColor3 = settings.theme == "default" and Color3.fromRGB(40, 40, 40) or usersTabBtn.BackgroundColor3
                    settingsTabBtn.BackgroundColor3 = settings.theme == "default" and Color3.fromRGB(40, 40, 40) or settingsTabBtn.BackgroundColor3
                end
                return
            elseif data.type == "user_list" then
                displayUserList(data.users)
                if DEBUG_MODE then log("📋 ได้ list users จาก server") end
                return
            elseif data.chat then  
                if tostring(data.chat):match("^.+:%s.+") then  
                    addChatMessage("🗨️ " .. tostring(data.chat))  
                else  
                    if DEBUG_MODE then log("ℹ️ System: " .. tostring(data.chat)) end  
                end  
            elseif data.error then  
                if DEBUG_MODE then log("❌ " .. tostring(data.error)) end  
            elseif data.command and data.target == LocalPlayer.Name then  
                if data.command == "kick" then  
                    if DEBUG_MODE then log("🦵 คุณถูก kick!") end  
                    LocalPlayer:Kick("คุณถูก kick โดย Phantom Hub")  
                elseif data.command == "kill" then  
                    if DEBUG_MODE then log("💀 คุณถูก kill!") end  
                    local char = LocalPlayer.Character  
                    if char then  
                        local hum = char:FindFirstChildOfClass("Humanoid")  
                        if hum then hum.Health = 0 end  
                    end  
                elseif data.command == "pull" then  
                    if data.sender then
                        if DEBUG_MODE then log("🚀 ได้รับคำสั่งดึงจาก " .. data.sender) end
                        pullToSender(data.sender)
                    else
                        if DEBUG_MODE then log("❌ คำสั่งดึงไม่มี sender") end
                    end
                elseif data.command == "check" then  
                    if DEBUG_MODE then log("📢 ได้รับคำสั่งเช็ค") end
                    checkMessage()
                end  
            end  
        else  
            if DEBUG_MODE then log("📄 " .. tostring(msg)) end  
        end
    end)

    if not success then
        if DEBUG_MODE then log("⚠️ HandleMessage Error: " .. tostring(result)) end
    end
end

-- ─── connect ─────────────────────────── 🔌
function connectToHub(url)
    if connection and connected then
        if DEBUG_MODE then log("🔌 Already connected") end
        return
    end
    if connectCooldown then return end
    connectCooldown = true
    task.delay(2, function() connectCooldown = false end)

    if DEBUG_MODE then log("🌐 กำลังเชื่อมต่อ: " .. tostring(url)) end  
    local success, sock = pcall(wsApi.connect, url)  
    if not success or not sock then  
        if DEBUG_MODE then log("❌ เชื่อมต่อไม่สำเร็จ!") end  
        showNotification("❌ การเชื่อมต่อล้มเหลว!")  
        return  
    end  

    connection, connected = sock, true  
    createChatUI() -- สร้าง UI เมื่อเชื่อมต่อสำเร็จ

    if connection.OnMessage then  
        connection.OnMessage:Connect(function(raw) pcall(handleMessage, raw) end)  
    else  
        task.spawn(function()  
            while connected do  
                local ok, msg = pcall(function() return connection:Recv() end)  
                if ok and msg then pcall(handleMessage, msg) end  
                task.wait(0.1)  
            end  
        end)  
    end  

    if connection.OnClose then  
        connection.OnClose:Connect(function(code, reason)  
            if DEBUG_MODE then log("🔌 การเชื่อมต่อถูกตัด: " .. tostring(reason)) end  
            connected = false  
            showNotification("🔌 การเชื่อมต่อถูกตัด!")  
            -- Cleanup UI and connection
            if chatGui then chatGui:Destroy() end
            if toggleButtonGui then toggleButtonGui:Destroy() end
            connection = nil
        end)  
    end  
    if connection.OnError then  
        connection.OnError:Connect(function(err)  
            if DEBUG_MODE then log("⚠️ Error: " .. tostring(err)) end  
            connected = false  
            showNotification("⚠️ การเชื่อมต่อมีปัญหา!")  
            -- Cleanup UI and connection
            if chatGui then chatGui:Destroy() end
            if toggleButtonGui then toggleButtonGui:Destroy() end
            connection = nil
        end)  
    end
end

-- ─── เริ่ม ───────────────────────────── 🚀
if USE_DEFAULT_URL then
    connectToHub(DEFAULT_URL)
end
