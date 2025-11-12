-- Phantom Chat Hub Client (Roblox Lua) 🌌
local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
local SoundService = game:GetService("SoundService") -- สำหรับแจ้งเตือนเสียง 🔥

-- ─── CONFIG ────────────────────────────── ⚙️
local DEBUG_MODE   = false -- Toggle debug mode (true = enabled, false = disabled)
local USE_DEFAULT_URL = true
local DEFAULT_URL     = "wss://03547fcf98d3.ngrok-free.app"

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

-- ─── ฟังก์ชัน log ────────────────────── 📜
local function log(txt)
    if DEBUG_MODE then
        print(txt)
    end
end

-- ─── สร้าง UI ใหม่กับ 2 แท็บ ────────── 🖼️✨
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
    chatTabBtn.Text = "💬 แชทสาธารณะ"
    chatTabBtn.Size = UDim2.new(0.5, 0, 1, 0)
    chatTabBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    chatTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    chatTabBtn.Font = Enum.Font.SourceSansBold
    chatTabBtn.TextSize = 18

    local settingsTabBtn = Instance.new("TextButton", tabBar)
    settingsTabBtn.Text = "⚙️ ตั้งค่า"
    settingsTabBtn.Size = UDim2.new(0.5, 0, 1, 0)
    settingsTabBtn.Position = UDim2.new(0.5, 0, 0, 0)
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
            settingsTabBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            chatOutputFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            chatInput.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
            chatBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 0)
            settingsScroll.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            if toggleButtonGui then
                local toggleButton = toggleButtonGui:FindFirstChildOfClass("TextButton")
                if toggleButton then
                    toggleButton.BackgroundColor3 = Color3.fromRGB(0, 120, 0)
                end
            end
        end
    end)

    -- โหมดเรนโบว์ 🌈 (ครอบคลุมทั้ง UI)
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
                settingsTabBtn.BackgroundColor3 = Color3.fromHSV(hue + 0.15, 0.7, 0.7)
                chatOutputFrame.BackgroundColor3 = Color3.fromHSV(hue + 0.2, 0.7, 0.7)
                chatInput.BackgroundColor3 = Color3.fromHSV(hue + 0.3, 0.7, 0.7)
                chatBtn.BackgroundColor3 = Color3.fromHSV(hue + 0.4, 0.7, 0.7)
                settingsScroll.BackgroundColor3 = Color3.fromHSV(hue + 0.2, 0.7, 0.7)
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
        settingsTabFrame.Visible = false
        chatTabBtn.BackgroundColor3 = settings.theme == "default" and Color3.fromRGB(60, 60, 60) or chatTabBtn.BackgroundColor3
        settingsTabBtn.BackgroundColor3 = settings.theme == "default" and Color3.fromRGB(40, 40, 40) or settingsTabBtn.BackgroundColor3
    end)

    settingsTabBtn.MouseButton1Click:Connect(function()
        chatTabFrame.Visible = false
        settingsTabFrame.Visible = true
        chatTabBtn.BackgroundColor3 = settings.theme == "default" and Color3.fromRGB(40, 40, 40) or chatTabBtn.BackgroundColor3
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
            if data.chat then  
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
        end)  
    end  
    if connection.OnError then  
        connection.OnError:Connect(function(err)  
            if DEBUG_MODE then log("⚠️ Error: " .. tostring(err)) end  
            connected = false  
            showNotification("⚠️ การเชื่อมต่อมีปัญหา!")  
        end)  
    end
end

-- ─── เริ่ม ───────────────────────────── 🚀
if USE_DEFAULT_URL then
    connectToHub(DEFAULT_URL)
end
