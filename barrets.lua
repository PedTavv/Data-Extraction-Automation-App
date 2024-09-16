-- Constants
local M = {}

-- Initialize all necessary tables and variables
M.patientData = {}
M.patientCount = {}
M.currentPatientIndex = 1
M.currentRecordID = nil
M.patientInfoWindow = nil
M.barretsHotkeys = {}

M.dynamicSleep = function(attempt)
    local baseDelay = 0.1
    local maxDelay = 2
    local delay = math.min(baseDelay * (2 ^ (attempt - 1)), maxDelay)
    hs.timer.usleep(delay * 100000)
end

M.notifyError = function(message)
    hs.notify.new({ title = "Error", informativeText = message }):send()
end

M.notifySuccess = function(title, message)
    hs.notify.new({ title = title, informativeText = message }):send()
end

-- Core functions
M.init = function()
    M.bindHotkeys()
    M.updatePatientInfoWindow()
    hs.notify.new({ title = "Script", informativeText = "Initialized successfully" }):send()
end

M.deleteCurrentPatientData = function()
    if M.currentPatientIndex > 1 then
        local index = M.currentPatientIndex - 1
        M.patientData[index] = {}
        M.patientCount[index] = false
        hs.notify.new({
            title = "Patient Data",
            informativeText = "Data deleted for patient " .. tostring(index)
        }):send()
        M.updatePatientDataInWindow()
    else
        hs.notify.new({
            title = "Patient Data",
            informativeText = "No patient data to delete."
        }):send()
    end
end

M.resetPatientData = function()
    M.patientData = {}
    M.patientCount = {}
    M.currentPatientIndex = 1
    hs.notify.new({ title = "Patient Data", informativeText = "Patient data has been reset" }):send()
    M.updatePatientDataInWindow()
end

M.updatePatientDataInWindow = function()
    local patients = {}
    for i, patient in ipairs(M.patientData) do
        if patient and patient.id then
            table.insert(patients, {
                id = patient.id,
                hotkey = patient.hotkey
            })
        end
    end
    if M.patientInfoWindow then
        M.patientInfoWindow:evaluateJavaScript(
            string.format("updatePatientData(%s);", hs.json.encode(patients))
        )
    end
end

M.updatePatientInfoWindow = function()
    if not M.patientInfoWindow then
        M.screen = hs.screen.primaryScreen()
        if not M.screen then
            hs.notify.new({ title = "Error", informativeText = "No primary screen detected" }):send()
            return
        end
        M.screenFrame = M.screen:frame()
        M.windowWidth = 450
        M.windowHeight = 600
        M.windowX = M.screenFrame.x + M.screenFrame.w - M.windowWidth - 10
        M.windowY = M.screenFrame.y + 10

        M.userContent = hs.webview.usercontent.new("hammerspoon")
        M.userContent:setCallback(function(message)
            M.handleWebviewMessage(message.body)
        end)

        M.patientInfoWindow = hs.webview.new(
            { x = M.windowX, y = M.windowY, w = M.windowWidth, h = M.windowHeight },
            { developerExtrasEnabled = true },
            M.userContent
        )
        M.patientInfoWindow:windowStyle({ "utility", "closable", "miniaturizable", "titled" })
        M.patientInfoWindow:level(hs.drawing.windowLevels.floating)
        M.patientInfoWindow:allowGestures(true)
        M.patientInfoWindow:windowTitle("Script")
        M.patientInfoWindow:bringToFront(true)
        M.patientInfoWindow:show()
        M.patientInfoWindow:windowCallback(function(win, event, data)
            if event == "focusChange" and data then
                win:hswindow():focus()
            end
        end)
    end
    M.updatePatientDataInWindow()

    local htmlContent = [[
    <!DOCTYPE html>
    <html>
    <head>
        <style>
            body {
                font-family: 'Inter', 'Helvetica Neue', Arial, sans-serif;
                font-size: 14px;
                margin: 0;
                padding: 20px;
                background-color: rgb(40, 40, 40);
                color: rgb(235, 219, 178);
                overflow: hidden;
            }
            h2 {
                color: rgb(251, 73, 52);
                text-align: center;
                margin-bottom: 20px;
                font-size: 28px;
                font-weight: bold;
            }
            .table-container {
                max-height: 500px;
                overflow-y: auto;
                border: 2px solid rgb(60, 56, 54);
                border-radius: 8px;
                box-shadow: 0 0 10px rgba(130, 170, 255, 0.3);
            }
            table {
                width: 100%;
                border-collapse: separate;
                border-spacing: 0;
                background-color: rgb(60, 56, 54);
            }
            th, td {
                padding: 10px 12px;
                text-align: left;
                border-bottom: 1px solid rgb(80, 73, 69);
            }
            th {
                position: sticky;
                top: 0;
                background-color: rgb(69, 133, 136);
                color: rgb(40, 40, 40);
                font-weight: bold;
                text-transform: uppercase;
                font-size: 14px;
                letter-spacing: 1px;
                z-index: 10;
            }
            td {
                font-size: 14px;
            }
            tr:nth-child(even) { background-color: rgb(50, 48, 47); }
            tr:hover { background-color: rgb(80, 73, 69); cursor: pointer; }
            tr.selected { 
                background-color: rgb(104, 157, 106); 
                box-shadow: 0 0 0 2px rgb(130, 170, 255) inset;
            }
            button {
                display: inline-block;
                margin: 5px 2px;
                padding: 8px 16px;
                background-color: rgb(215, 153, 33);
                color: rgb(40, 40, 40);
                border: none;
                border-radius: 5px;
                cursor: pointer;
                transition: background-color 0.3s ease, transform 0.1s ease;
                font-size: 14px;
                font-weight: bold;
            }
            button:hover {
                background-color: rgb(250, 189, 47);
                transform: translateY(-2px);
            }
            button:active {
                transform: translateY(0);
            }
            .button-container {
                text-align: center;
                margin-top: 20px;
            }
            .input-container {
                text-align: center;
                margin: 10px 0;
            }
            input {
                padding: 10px;
                font-size: 14px;
                border: 2px solid rgb(60, 56, 54);
                border-radius: 5px;
                width: 60%;
                margin-right: 10px;
            }
            select {
                padding: 5px;
                font-size: 14px;
                border: 2px solid rgb(60, 56, 54);
                border-radius: 5px;
                background-color: rgb(80, 73, 69);
                color: rgb(235, 219, 178);
            }
            ::-webkit-scrollbar {
                width: 10px;
            }
            ::-webkit-scrollbar-track {
                background: rgb(60, 56, 54);
            }
            ::-webkit-scrollbar-thumb {
                background: rgb(69, 133, 136);
                border-radius: 5px;
            }
            ::-webkit-scrollbar-thumb:hover {
                background: rgb(130, 170, 255);
            }
        </style>
    </head>
    <body>
        <h2>Script</h2>
        <div class="table-container">
            <table id="patientTable">
                <thead>
                    <tr>
                        <th>Patient</th>
                        <th>Record ID</th>
                        <th>Hotkey</th>
                    </tr>
                </thead>
                <tbody>
                    <!-- Table body will be populated by JavaScript -->
                </tbody>
            </table>
        </div>
        <div class="button-container">
            <button onclick="deleteSelectedPatient()">Delete Selected Patient</button>
        </div>
        <script>
            window.updatePatientData = function(patients) {
                var tableBody = document.querySelector('#patientTable tbody');
                tableBody.innerHTML = '';
                patients.forEach(function(patient, index) {
                    var row = tableBody.insertRow();
                    row.insertCell(0).textContent = 'P' + (index + 1);
                    row.insertCell(1).textContent = patient.id || '--';
                    
                    var hotkeyCell = row.insertCell(2);
                    var select = document.createElement('select');
                    ['--', 'F1', 'F2', 'F3'].forEach(function(key) {
                        var option = document.createElement('option');
                        option.value = key;
                        option.text = key;
                        if (patient.hotkey === key) {
                            option.selected = true;
                        }
                        select.appendChild(option);
                    });
                    select.onchange = function() {
                        window.hammerspoon.sendMessage('updateHotkey', {
                            patientIndex: index + 1,
                            hotkey: select.value
                        });
                    };
                    hotkeyCell.appendChild(select);

                    row.onclick = function() {
                        window.selectedPatientIndex = index + 1;
                        window.hammerspoon.sendMessage('selectPatient', index + 1);
                        highlightSelectedRow(this);
                    };
                });
            }

            function highlightSelectedRow(row) {
                var rows = document.querySelectorAll('#patientTable tbody tr');
                rows.forEach(function(r) {
                    r.classList.remove('selected');
                });
                row.classList.add('selected');
            }

            function deleteSelectedPatient() {
                if (window.selectedPatientIndex !== undefined) {
                    window.webkit.messageHandlers.hammerspoon.postMessage({
                        action: 'deletePatient',
                        patientIndex: window.selectedPatientIndex
                    });
                }
            }

            window.hammerspoon = {
                sendMessage: function(action, data) {
                    var message = { action: action };
                    if (typeof data === 'object') {
                        message = { ...message, ...data };
                    } else {
                        message.patientIndex = data;
                    }
                    window.webkit.messageHandlers.hammerspoon.postMessage(message);
                }
            };
        </script>
    </body>
    </html>
    ]]
    M.patientInfoWindow:html(htmlContent)
end
M.updatePatientDataInWindow()

M.handleWebviewMessage = function(message)
    local action = message.action
    local patientIndex = message.patientIndex

    if action == "selectPatient" then
        M.currentPatientIndex = patientIndex
    elseif action == "deletePatient" then
        M.patientData[patientIndex] = {}
        M.patientCount[patientIndex] = false
        M.updatePatientDataInWindow()
    elseif action == "updateHotkey" then
        local hotkey = message.hotkey
        if M.patientData[patientIndex] then
            M.patientData[patientIndex].hotkey = hotkey
            M.updatePatientDataInWindow()
        end
    end
end

M.togglePatientInfoWindow = function()
    if M.patientInfoWindow then
        if M.patientInfoWindow:isVisible() then
            M.patientInfoWindow:hide()
        else
            M.patientInfoWindow:show()
            M.patientInfoWindow:bringToFront(true)
        end
    else
        M.updatePatientInfoWindow()
    end
end

function M.storePatientData(index, data)
    M.patientData[index] = data
    M.patientCount[index] = true
    M.updatePatientDataInWindow()
end

M.waitForElementAndAct = function(xpath, action, options)
    -- Ensure options is a table
    if type(options) ~= "table" then
        options = {}
    end

    options.maxAttempts = options.maxAttempts or 10
    options.useDynamicSleep = options.useDynamicSleep ~= false
    local cssSelector = options.cssSelector or nil

    local function createScript(selector, isXPath)
        if isXPath then
            return string.format([[
                (function() {
                    let element = document.evaluate('%s', document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                    if (element && !element.disabled && element.offsetParent !== null) {
                        try {
                            %s
                            return 'success';
                        } catch (e) {
                            console.error('Action failed:', e);
                            return 'error';
                        }
                    }
                    return 'not found';
                })();
            ]], selector, action)
        else
            return string.format([[
                (function() {
                    let element = document.querySelector('%s');
                    if (element && !element.disabled && element.offsetParent !== null) {
                        try {
                            %s
                            return 'success';
                        } catch (e) {
                            console.error('Action failed:', e);
                            return 'error';
                        }
                    }
                    return 'not found';
                })();
            ]], selector, action)
        end
    end

    for attempt = 1, options.maxAttempts do
        local script = createScript(xpath, true)
        local ok, result = hs.osascript.applescript([[
            tell application "Microsoft Edge"
                tell active tab of window 1
                    set result to execute javascript "]] .. script .. [["
                    return result
                end tell
            end tell
        ]])

        if ok and result == 'success' then
            hs.notify.new({
                title = "Action Success",
                informativeText = "Successfully executed action for XPath: " .. xpath
            }):send()
            return true
        elseif result == 'error' then
            hs.notify.new({
                title = "Action Failed",
                informativeText = "Action failed for XPath: " .. xpath .. " at attempt: " .. attempt
            }):send()
        elseif result == 'not found' and cssSelector then
            script = createScript(cssSelector, false)
            ok, result = hs.osascript.applescript([[
                tell application "Microsoft Edge"
                    tell active tab of window 1
                        set result to execute javascript "]] .. script .. [["
                        return result
                    end tell
                end tell
            ]])

            if ok and result == 'success' then
                hs.notify.new({
                    title = "Action Success",
                    informativeText = "Successfully executed action for CSS selector: " .. cssSelector
                }):send()
                return true
            elseif result == 'error' then
                hs.notify.new({
                    title = "Action Failed",
                    informativeText = "Action failed for CSS selector: " .. cssSelector .. " at attempt: " .. attempt
                }):send()
            end
        end

        if options.useDynamicSleep then
            M.dynamicSleep(attempt)
        else
            hs.timer.usleep(100000)
        end
    end

    hs.notify.new({
        title = "Action Failed",
        informativeText = "Element not found or action not successful after " .. options.maxAttempts .. " attempts for XPath: " .. xpath .. (cssSelector and " or CSS selector: " .. cssSelector or "")
    }):send()
    return false
end

function M.waitForPageLoad(xpath, cssSelector, maxWaitTime)
    maxWaitTime = maxWaitTime or 15
    local startTime = hs.timer.secondsSinceEpoch()
    
    while (hs.timer.secondsSinceEpoch() - startTime) < maxWaitTime do
        local script = string.format([[
            tell application "Microsoft Edge"
                tell active tab of window 1
                    set pageLoaded to execute javascript "
                        (function() {
                            if (document.readyState !== 'complete') return false;
                            var element = document.evaluate('%s', document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                            if (element !== null) return true;
                            if ('%s') {
                                element = document.querySelector('%s');
                                return element !== null;
                            }
                            return false;
                        })()
                    "
                    return pageLoaded
                end tell
            end tell
        ]], xpath, cssSelector or "", cssSelector or "")
        
        local ok, result = hs.osascript.applescript(script)
        if ok and result then
            hs.timer.usleep(500000)
            return true
        end
        
        hs.timer.usleep(500000)
    end
    
    return false
end

M.extractInputValue = function(xpath)
    local script = string.format([[
        (function() {
            var element = document.evaluate("%s", document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
            return element ? element.value.trim() : '';
        })();
    ]], xpath)
    local ok, result = hs.osascript.javascript(script)
    if ok then
        return result
    else
        return nil
    end
end

M.switchToTab = function(tabIndex)
    hs.osascript.applescript(string.format([[
        tell application "Microsoft Edge"
            activate
            set active tab index of window 1 to %d
        end tell
    ]], tabIndex))
end

M.runAppleScriptF1 = function()
    if M.currentPatientIndex > 1 then
        M.switchToTab(3)
        hs.timer.usleep(1000000)

        if not M.waitForPageLoad("/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[5]/td[2]/span/div[2]/input", 15) then
            M.notifyError("F1: Page did not load")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[5]/td[2]/span/div[2]/input", "element.click();", { maxAttempts = 10, useDynamicSleep = true }) then
            M.notifyError("F1: Failed to click first 'No'")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[7]/td[2]/span/div[2]/input", "element.click();", { maxAttempts = 10, useDynamicSleep = true }) then
            M.notifyError("F1: Failed to click second 'No'")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[9]/td[2]/span/span/select",
                [[
                var options = element.options;
                for (var i = 0; i < options.length; i++) {
                    if (options[i].text.toLowerCase() === 'complete') {
                        element.selectedIndex = i;
                        var event = new Event('change', { bubbles: true });
                        element.dispatchEvent(event);
                        break;
                    }
                }
                if (element.selectedIndex === -1) {
                    alert('Failed to select Complete');
                }
                ]], { maxAttempts = 10, useDynamicSleep = true }) then
            M.notifyError("F1: Failed to select 'Complete' from dropdown menu")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[10]/td[2]/span/div/button[1]/span", "element.click();", { maxAttempts = 10, useDynamicSleep = true }) then
            M.notifyError("F1: Failed to click 'Save and Exit Record'")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForPageLoad("/html/body/div[12]/div/div[1]/div[2]/div[2]/div/div/div/div[1]/a/span", 15) then
            M.notifyError("F1: 'Record Status Dashboard' did not appear")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForElementAndAct("/html/body/div[12]/div/div[1]/div[2]/div[2]/div/div/div/div[1]/a/span", "element.click();", { maxAttempts = 10, useDynamicSleep = true }) then
            M.notifyError("F1: Failed to click 'Record Status Dashboard'")
            return false
        end
        hs.timer.usleep(1000000)

        return true
    else
        M.notifyError("No patient data to run F1 script.")
        return false
    end
end

M.runAppleScriptF2 = function()
    if M.currentPatientIndex > 1 then
        M.switchToTab(3)
        hs.timer.usleep(1000000)

        if not M.waitForPageLoad("/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[5]/td[2]/span/div[1]/input", 15) then
            M.notifyError("F2: Page did not load")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[5]/td[2]/span/div[1]/input", "element.click();", { maxAttempts = 10, useDynamicSleep = true }) then
            M.notifyError("F2: Failed to click first 'Yes'")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[6]/td[2]/span/div[1]/input", "element.click();", { maxAttempts = 10, useDynamicSleep = true }) then
            M.notifyError("F2: Failed to click second 'Yes'")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[7]/td[2]/span/div[1]/input", "element.click();", { maxAttempts = 10, useDynamicSleep = true }) then
            M.notifyError("F2: Failed to click third 'Yes'")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[9]/td[2]/span/span/select",
                [[
                var options = element.options;
                for (var i = 0; i < options.length; i++) {
                    if (options[i].text.toLowerCase() === 'complete') {
                        element.selectedIndex = i;
                        var event = new Event('change', { bubbles: true });
                        element.dispatchEvent(event);
                        break;
                    }
                }
                if (element.selectedIndex === -1) {
                    alert('Failed to select Complete');
                }
                ]], { maxAttempts = 10, useDynamicSleep = true }) then
            M.notifyError("F2: Failed to select 'Complete' from dropdown menu")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[10]/td[2]/span/div/button[1]/span", "element.click();", { maxAttempts = 10, useDynamicSleep = true }) then
            M.notifyError("F2: Failed to click 'Save and Exit Record'")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForPageLoad("/html/body/div[12]/div/div[2]/table[2]/tbody/tr[2]/td[2]/a/img", 15) then
            M.notifyError("F2: Page did not load after saving")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/table[2]/tbody/tr[2]/td[2]/a/img", "element.click();", { maxAttempts = 10, useDynamicSleep = true }) then
            M.notifyError("F2: Failed to click the image link")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForPageLoad("/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[53]/td[2]/span/div/button[1]", 15) then
            M.notifyError("F2: Page did not load after clicking image")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[53]/td[2]/span/div/button[1]", "element.click();", { maxAttempts = 10, useDynamicSleep = true }) then
            M.notifyError("F2: Failed to click 'Save and Exit' (second time)")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForPageLoad("/html/body/div[14]/div[3]/div/button[1]", 15) then
            M.notifyError("F2: 'Ignore' button did not appear")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForElementAndAct("/html/body/div[14]/div[3]/div/button[1]", "element.click();", { maxAttempts = 10, useDynamicSleep = true }) then
            M.notifyError("F2: Failed to click 'Ignore'")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForPageLoad("/html/body/div[12]/div/div[1]/div[2]/div[2]/div/div/div/div[1]/a/span", 15) then
            M.notifyError("F2: 'Record Status Dashboard' did not appear")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForElementAndAct("/html/body/div[12]/div/div[1]/div[2]/div[2]/div/div/div/div[1]/a/span", "element.click();", { maxAttempts = 10, useDynamicSleep = true }) then
            M.notifyError("F2: Failed to click 'Record Status Dashboard'")
            return false
        end
        hs.timer.usleep(1000000)

        return true
    else
        M.notifyError("No patient data to run F2 script.")
        return false
    end
end

M.runAppleScriptF6 = function()
    M.switchToTab(2)
    hs.timer.usleep(1000000)

    if not M.waitForPageLoad("/html/body/div[12]/div/div[2]/table[2]/tbody/tr/td[2]/a", 15) then
        M.notifyError("F6: Page did not load")
        return false
    end
    hs.timer.usleep(1000000)

    if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/table[2]/tbody/tr/td[2]/a/img", "element.click();", { maxAttempts = 10 }) then
        if not M.waitForElementAndAct("#event_grid_table > tbody > tr > td.nowrap > a > img", "element.click();", { maxAttempts = 10 }) then 
            M.notifyError("F6: Failed to click status button")
            return false
        end
    end
    hs.timer.usleep(1000000)

    local extractRecordIDScript = [[
        tell application "Microsoft Edge"
            tell active tab of window 1
                set recordID to execute javascript "
                    (function() {
                        var recordIDElement = document.evaluate('/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[2]/td[2]/span', document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                        return recordIDElement ? recordIDElement.textContent.trim().replace(/[^0-9]/g, '') : null;
                    })();
                "
                if recordID is null then
                    log "Record ID is null"
                    return null
                else
                    log "Record ID: " & recordID
                    return recordID
                end if
            end tell
        end tell
    ]]
    
    local ok, recordID = hs.osascript.applescript(extractRecordIDScript)
    if not ok or not recordID then
        M.notifyError("F6: Failed to extract record ID")
        return false
    end

    local data = { 
        id = recordID,
        hotkey = nil
    }
    M.patientData[M.currentPatientIndex] = data
    M.patientCount[M.currentPatientIndex] = true
    M.currentPatientIndex = M.currentPatientIndex + 1
    M.updatePatientDataInWindow()

    M.notifySuccess("F6: Patient data extracted and stored", "Record ID: " .. recordID)

    return true
end

M.runAppleScriptF3 = function()
    if M.currentPatientIndex > 1 then
        M.switchToTab(3)
        hs.timer.usleep(500000)

        M.waitForElementAndAct(
            "/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[5]/td[2]/span/div[1]/input",
            "element.click();", 
            { maxAttempts = 10, useDynamicSleep = true }
        )
        hs.timer.usleep(500000)

        M.waitForElementAndAct(
            "/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[6]/td[2]/span/div[1]/input",
            "element.click();", 
            { maxAttempts = 10, useDynamicSleep = true }
        )
        hs.timer.usleep(500000)

        M.waitForElementAndAct(
            "/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[7]/td[2]/span/div[2]/input",
            "element.click();", 
            { maxAttempts = 10, useDynamicSleep = true }
        )
        hs.timer.usleep(500000)

        if not M.waitForElementAndAct(
            "/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[9]/td[2]/span/span/select",
            [[
            var options = element.options;
            for (var i = 0; i < options.length; i++) {
                if (options[i].text.toLowerCase() === 'complete') {
                    element.selectedIndex = i;
                    var event = new Event('change', { bubbles: true });
                    element.dispatchEvent(event);
                    break;
                }
            }
            if (element.selectedIndex === -1) {
                alert('Failed to select Complete');
            }
            ]], 
            { maxAttempts = 10, useDynamicSleep = true }
        ) then
            M.notifyError("F1: Failed to select 'Complete' from dropdown menu")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForElementAndAct(
            "/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[10]/td[2]/span/div/button[1]/span", 
            "element.click();", 
            { maxAttempts = 10, useDynamicSleep = true }
        ) then
            M.notifyError("F1: Failed to click 'Save and Exit Record'")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForPageLoad(
            "/html/body/div[12]/div/div[1]/div[2]/div[2]/div/div/div/div[1]/a/span", 
            15
        ) then
            M.notifyError("F1: 'Record Status Dashboard' did not appear")
            return false
        end
        hs.timer.usleep(1000000)

        if not M.waitForElementAndAct(
            "/html/body/div[12]/div/div[1]/div[2]/div[2]/div/div/div/div[1]/a/span", 
            "element.click();", 
            { maxAttempts = 10, useDynamicSleep = true }
        ) then
            M.notifyError("F1: Failed to click 'Record Status Dashboard'")
            return false
        end
        hs.timer.usleep(1000000)

        return true
    else
        M.notifyError("No patient data to run F1 script.")
        return false
    end
end

M.runAppleScriptF7 = function()
    for i, patient in ipairs(M.patientData) do
        if M.patientCount[i] and patient and patient.id then
            M.currentRecordID = patient.id
            
            M.switchToTab(3)
            hs.timer.usleep(1000000)

            if not M.waitForPageLoad("/html/body/div[12]/div/div[2]/div[4]/input", 15) then
                M.notifyError("F7: Page did not load for patient " .. i)
                goto continue
            end

            if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/div[4]/input",
                    string.format("element.value = '%s';", M.currentRecordID), { maxAttempts = 10, useDynamicSleep = true }) then
                M.notifyError("F7: Failed to enter record ID for patient " .. i)
                goto continue
            end
            hs.timer.usleep(1000000)

            if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/div[4]/div/button", "element.click();", { maxAttempts = 10, useDynamicSleep = true }) then
                M.notifyError("F7: Failed to click 'Create' for patient " .. i)
                goto continue
            end
            hs.timer.usleep(600000)

            if not M.waitForPageLoad("/html/body/div[12]/div/div[2]/table[2]/tbody/tr[1]/td[2]/a/img", 15) then
                M.notifyError("F7: Page did not load after clicking 'Create' for patient " .. i)
                goto continue
            end

            if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/table[2]/tbody/tr[1]/td[2]/a/img", "element.click();", { maxAttempts = 10, useDynamicSleep = true }) then
                M.notifyError("F7: Failed to click final button for patient " .. i)
                goto continue
            end
            hs.timer.usleep(600000)

            local scriptToRun
            if patient.hotkey == "F1" then
                scriptToRun = M.runAppleScriptF1
            elseif patient.hotkey == "F2" then
                scriptToRun = M.runAppleScriptF2
            elseif patient.hotkey == "F3" then
                scriptToRun = M.runAppleScriptF3
            else
                M.notifyError("F7: Invalid hotkey for patient " .. i)
                goto continue
            end
            
            if not scriptToRun() then
                M.notifyError("F7: Failed to run " .. patient.hotkey .. " for patient " .. i)
                goto continue
            end
            
            M.notifySuccess("F7: Success", "Processed patient " .. i .. " successfully")
            M.currentRecordID = nil

            hs.timer.usleep(1000000)
            
            if i % 3 == 0 then
                hs.osascript.applescript([[
                    tell application "Microsoft Edge"
                        reload active tab of window 1
                    end tell
                ]])
                if not M.waitForPageLoad("/html/body/div[12]/div/div[2]/div[4]/input", 15) then
                    M.notifyError("F7: Page did not reload properly after processing 3 patients")
                    goto continue
                end
                hs.timer.usleep(5000000)
            end
        end
        ::continue::
    end
    
    M.patientData = {}
    M.patientCount = {}
    M.currentPatientIndex = 1
    M.currentRecordID = nil
    M.updatePatientDataInWindow()
    
    M.notifySuccess("F7: Completion", "All patients have been processed and data has been reset")
end

M.runAppleScriptF8 = function()
    if M.currentPatientIndex <= 1 then
        M.notifyError("F8: No current patient. Please run F6 first.")
        return false
    end

    local currentPatient = M.patientData[M.currentPatientIndex - 1]
    if not currentPatient then
        M.notifyError("F8: No patient data found. Please run F6 first.")
        return false
    end

    local recordID = currentPatient.id
    if not recordID then
        M.notifyError("F8: No record ID found. Please run F6 first.")
        return false
    end

    M.switchToTab(2)
    hs.timer.usleep(1000000)

    if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[6]/td[2]/span/input", "element.value = 'PT';", { maxAttempts = 10, useDynamicSleep = true }) then
        M.notifyError("F8: Failed to insert PT initials")
        return false
    end
    hs.timer.usleep(600000)

    if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[8]/td[2]/span/span/select",
            [[
            var options = element.options;
            for (var i = 0; i < options.length; i++) {
                if (options[i].text === 'Complete') {
                    element.selectedIndex = i;
                    var event = new Event('change', { bubbles: true });
                    element.dispatchEvent(event);
                    break;
                }
            }
            ]], { maxAttempts = 10, useDynamicSleep = true }) then
        M.notifyError("F8: Failed to select 'Complete' from dropdown menu")
        return false
    end
    hs.timer.usleep(600000)

    if not M.waitForElementAndAct("/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[9]/td[2]/span/div/div/button[1]/span", "element.click();", { maxAttempts = 10, useDynamicSleep = true }) then
        M.notifyError("F8: Failed to click 'Save and Next Record'")
        return false
    end
    hs.timer.usleep(600000)

    M.switchToTab(1)
    hs.timer.usleep(300000)

    hs.osascript.applescript([[
        tell application "Microsoft Edge"
            tell active tab of window 1
                execute javascript "
                    var button1 = document.evaluate('/html/body/div[10]/div[2]/a[3]/span', 
                    document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                    if (button1) { button1.click(); }"
            end tell
        end tell
    ]])
    hs.timer.usleep(300000)

    hs.osascript.applescript([[
        tell application "Microsoft Edge"
            tell active tab of window 1
                execute javascript "
                    var button2 = document.evaluate('/html/body/div[7]/div[3]/div[2]/div[1]/div[1]/a[2]', 
                    document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                    if (button2) { button2.click(); }"
            end tell
        end tell
    ]])
    hs.timer.usleep(300000)

    hs.osascript.applescript([[
        tell application "Microsoft Edge"
            tell active tab of window 1
                execute javascript "
                    function triggerClick(element) {
                        if (element) {
                            element.scrollIntoView();
                            
                            var events = ['mouseover', 'mousedown', 'mouseup', 'click'];
                            events.forEach(function(eventType) {
                                var event = new MouseEvent(eventType, {
                                    bubbles: true,
                                    cancelable: true,
                                    view: window
                                });
                                element.dispatchEvent(event);
                            });
                        }
                    }"
            end tell
        end tell
    ]])
    hs.timer.usleep(300000)

    hs.osascript.applescript([[
        tell application "Microsoft Edge"
            tell active tab of window 1
                execute javascript "
                    var searchIconParent = document.querySelector('#multiple-patient-manager > div.manager-side-area > div.top-actions > a.open-patient-search-dialog.search.side.manager-btn.hoverable');
                    if (searchIconParent) { 
                        triggerClick(searchIconParent);
                    }"
            end tell
        end tell
    ]])
    hs.timer.usleep(300000)

    return true
end

M.bindHotkeys = function()
    if #M.barretsHotkeys == 0 then
        table.insert(M.barretsHotkeys, hs.hotkey.bind({}, "F6", function() M.runAppleScriptF6() end))
        table.insert(M.barretsHotkeys, hs.hotkey.bind({}, "F8", function() M.runAppleScriptF8() end))
        table.insert(M.barretsHotkeys, hs.hotkey.bind({}, "F3", function() M.runAppleScriptF3() end))
        table.insert(M.barretsHotkeys, hs.hotkey.bind({}, "F1", function() M.runAppleScriptF1() end))
        table.insert(M.barretsHotkeys, hs.hotkey.bind({}, "F2", function() M.runAppleScriptF2() end))
        table.insert(M.barretsHotkeys, hs.hotkey.bind({}, "F4", function() M.togglePatientInfoWindow() end))
        table.insert(M.barretsHotkeys, hs.hotkey.bind({}, "F7", function() M.runAppleScriptF7() end))
        table.insert(M.barretsHotkeys, hs.hotkey.bind({}, "F5", function() M.deleteCurrentPatientData() end))
    end
end

M.unbindHotkeys = function()
    for _, hotkey in ipairs(M.barretsHotkeys) do
        hotkey:delete()
    end
    M.barretsHotkeys = {}
end

M.cleanup = function()
    M.unbindHotkeys()
    if M.patientInfoWindow then
        M.patientInfoWindow:delete()
        M.patientInfoWindow = nil
    end
    hs.notify.new({ title = "Script", informativeText = "Cleaned up successfully" }):send()
end

return {
    bindHotkeys = M.bindHotkeys,
    unbindHotkeys = M.unbindHotkeys,
    init = M.init,
    cleanup = M.cleanup,
}
