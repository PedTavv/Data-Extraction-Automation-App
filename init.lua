-- Clear Console and Enable Dark Mode
hs.console.clearConsole()
hs.console.darkMode(true)

-- Install IPC CLI for Hammerspoon (if not already installed)
require('hs.ipc')
hs.ipc.cliInstall()

-- Set up Luarocks paths (if needed)
local home = os.getenv("HOME")
package.path = home .. "/.luarocks/share/lua/5.4/?.lua;" .. package.path
package.cpath = home .. "/.luarocks/lib/lua/5.4/?.so;" .. package.cpath

-- Initialize variables
local loadedScripts = {}
local activeScript = nil
local menuBar = hs.menubar.new()
local scriptCoroutine = nil

-- Define M table
local M = {}

-- Error Logging Function
local function logError(errorMessage)
    local logFile = io.open(home .. "/.hammerspoon/error.log", "a")
    if logFile then
        logFile:write(os.date("%Y-%m-%d %H:%M:%S") .. " ERROR: " .. errorMessage .. "\n")
        logFile:close()
    else
        print("Failed to open log file.")
    end
end

-- Forward declarations for functions
local loadScript, updateMenuBar

-- Activate Script Function
local function activateScript(scriptName)
    if activeScript == scriptName then return end

    if activeScript then
        if loadedScripts[activeScript] and loadedScripts[activeScript].cleanup then
            local ok, err = pcall(loadedScripts[activeScript].cleanup)
            if not ok then
                logError("Error during cleanup of script: " .. tostring(err))
                print("Error during cleanup of script: " .. tostring(err))
                hs.notify.new({
                    title = "Hammerspoon",
                    informativeText = "Error during cleanup of script: " .. activeScript,
                    autoWithdraw = true,
                    withdrawAfter = 5
                }):send()
            end
        end
        loadedScripts[activeScript] = nil
        scriptCoroutine = nil
    end

    if scriptName == "barrets" or scriptName == "polyps" or scriptName == "polypjson" then
        local ok, err = pcall(loadScript, scriptName)
        if not ok then
            logError("Error loading script: " .. tostring(err))
            print("Error loading script: " .. tostring(err))
            hs.notify.new({
                title = "Hammerspoon",
                informativeText = "Error loading script: " .. scriptName,
                autoWithdraw = true,
                withdrawAfter = 5
            }):send()
            return
        end
        activeScript = scriptName
    elseif scriptName == nil then
        activeScript = nil
    else
        logError("Unknown script: " .. tostring(scriptName))
        print("Unknown script: " .. tostring(scriptName))
    end

    updateMenuBar()
end

-- Update Menubar Function
function updateMenuBar()
    local menuItems = {}

    if activeScript then
        table.insert(menuItems,
            {
                title = activeScript .. " (Active)",
                fn = function() activateScript(nil) end
            })
    else
        table.insert(menuItems, { title = "No Active Script" })
    end

    table.insert(menuItems, { title = "-" })

    if activeScript ~= "barrets" then
        table.insert(menuItems, {
            title = "Activate Barrets",
            fn = function() activateScript("barrets") end
        })
    end

    if activeScript ~= "polyps" then
        table.insert(menuItems, {
            title = "Activate Polyps",
            fn = function() activateScript("polyps") end
        })
    end

    if activeScript ~= "polypjson" then
        table.insert(menuItems, {
            title = "Activate Polyp JSON",
            fn = function() activateScript("polypjson") end
        })
    end
    table.insert(menuItems, { title = "-" })
    table.insert(menuItems, {
        title = "Emergency Stop",
        fn = function() emergencyStopAllScripts() end
    })

    menuBar:setMenu(menuItems)
    local title = activeScript and string.upper(activeScript) or "NO SCRIPT"
    if activeScript == "barrets" then
        title = "🟢 " .. title
    elseif activeScript == "polyps" then
        title = "🔴 " .. title
    end
    menuBar:setTitle(title)
end

-- Load Script Function
function loadScript(scriptName)
    local scriptPath = home .. "/.hammerspoon/" .. scriptName .. ".lua"
    local ok, script = pcall(dofile, scriptPath)
    if not ok then
        logError("Error loading script: " .. tostring(script))
        print("Error loading script: " .. tostring(script))
        hs.notify.new({
            title = "Hammerspoon",
            informativeText = "Error loading script: " .. scriptName,
            autoWithdraw = true,
            withdrawAfter = 5
        }):send()
        return
    end

    print("Script loaded successfully: " .. scriptName)

    if type(script) == "table" and type(script.init) == "function" then
        local initOk, initError = pcall(script.init)
        if not initOk then
            logError("Error initializing script: " .. tostring(initError))
            print("Error initializing script: " .. tostring(initError))
            hs.notify.new({
                title = "Hammerspoon",
                informativeText = "Error initializing script: " .. scriptName,
                autoWithdraw = true,
                withdrawAfter = 5
            }):send()
        else
            print("Script initialized successfully: " .. scriptName)
        end
    else
        print("No init function found for: " .. scriptName)
    end

    loadedScripts[scriptName] = script
end

-- Emergency Stop Function
function emergencyStopAllScripts()
    -- Set the shouldStop flag for all loaded scripts
    for scriptName, scriptModule in pairs(loadedScripts) do
        if scriptModule.shouldStop ~= nil then
            scriptModule.shouldStop = true
        end
        if scriptModule.cleanup then
            local ok, err = pcall(scriptModule.cleanup)
            if not ok then
                print("Error during cleanup of script " .. scriptName .. ": " .. tostring(err))
            end
        end
    end

    -- Force terminate any running AppleScripts
    hs.osascript.applescript([[
        tell application "System Events"
            -- Kill all processes named "osascript" (this is the process running AppleScripts)
            set osascriptProcesses to (every process whose name is "osascript")
            repeat with aProcess in osascriptProcesses
                try
                    do shell script "kill -9 " & (unix id of aProcess)
                end try
            end repeat
        end tell
    ]])

    -- Reset environment
    activeScript = nil
    scriptCoroutine = nil
    loadedScripts = {}

    -- Notify the user and update the menu bar
    print("Emergency stop: All scripts terminated")
    hs.notify.new({
        title = "Hammerspoon",
        informativeText = "Emergency stop: All scripts terminated",
        autoWithdraw = true,
        withdrawAfter = 3
    }):send()

    updateMenuBar()
end

-- Show Welcome Notification
local function showWelcomeNotification()
    hs.notify.new({
        title = "Hammerspoon",
        informativeText = "We are ready for action",
        autoWithdraw = true,
        withdrawAfter = 5
    }):send()
end

-- Bind Hotkeys
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "B", function() activateScript("barrets") end)
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "P", function() activateScript("polyps") end)
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "J", function() activateScript("polypjson") end)
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "R", hs.reload)
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "S", function() emergencyStopAllScripts() end)

-- Initialize Hammerspoon
showWelcomeNotification()
updateMenuBar()
