local M = {}

M.NUM_PATIENTS = 200
M.POLYP_COUNT_FILE_PATH = "/path/to/extraction.json"
M.patientData = {}
M.patientCount = {}
M.currentRecordID = nil
M.polypsHotkeys = {}
M.tags = {}
M.shouldStop = false

for i = 1, M.NUM_PATIENTS do
    M.patientData[i] = {
        id = i,
        recordId = "", -- placeholder record ID
        age = "",
        gender = "Select",
        adenomatous = 0,
        serrated = 0,
        total = 0,
        tags = {}
    }
    M.patientCount[i] = false
end

function M.checkForConsecutivePatients()
    for i = 1, M.NUM_PATIENTS - 1 do
        local current = M.patientData[i]
        local next = M.patientData[i + 1]
        if current.gender == next.gender and current.age == next.age and
            current.total == next.total and current.adenomatous ==
            next.adenomatous and current.serrated == next.serrated and
            current.gender ~= "" and current.gender ~= "Select" and current.age ~= ""
            and current.total ~= "" and current.adenomatous ~= "" and
            current.serrated ~= "" then
            return true, i, i + 1
        end
    end
    return false
end

function M.checkForDuplicates()
    for i = 1, M.NUM_PATIENTS do
        local recordId = M.patientData[i].recordId
        if recordId and recordId ~= "" then
            if M.patientData[i].recordId in {M.patientData[i + 1].recordId, M.patientData[i - 1].recordId} then
                hs.notify.new({
                    title = "Duplicate Detected",
                    informativeText = "Duplicate record ID found: ".. recordId
                }):send()
                return true, recordId
            else
                hs.notify.new({
                    title = "Alert",
                    informativeText = "New patient added to database: ".. recordId
                }):send()
            end
        end
    end
    return false
end

function M.updateAndStorePatientData(newData, source)
    if not newData then return end
    for i, data in pairs(newData) do
        local index = tonumber(i)
        if index and index >= 1 and index <= M.NUM_PATIENTS then
            for field, value in pairs(data) do
                if M.patientData[index][field] then
                    if field == "adenomatous" or field == "serrated" or field == "total" then
                        M.patientData[index][field] = tonumber(value) or M.patientData[index][field] or 0
                    else
                        M.patientData[index][field] = value or M.patientData[index][field] or ""
                    end
                end
            end
            M.patientData[index].lastUpdatedBy = source
            M.patientData[index].lastUpdatedTime = os.time()
        end
    end

    local isDuplicate, duplicateRecordId = M.checkForDuplicates()
    if isDuplicate then
        hs.notify.new({
            title = "Duplicate Detected",
            informativeText = "Duplicate record ID found: ".. duplicateRecordId..
                ". Please correct the data."
        }):send()
    else
        for index, patient in pairs(newData) do
            table.insert(M.patientCount, index)
        end
        M.updateUI(M.patientData)
    end
end

function M.updateUI(data)
    if M.patientInfoWindow then
        local jsonData = hs.json.encode(data)
        M.patientInfoWindow:evaluateJavaScript(string.format([[
            (function() {
                var data = %s;
                if (Object.keys(data).length === 1) {
                    var patientIndex = Object.keys(data)[0];
                    window.updateSinglePatient(patientIndex, data[patientIndex]);
                } else {
                    window.updatePatientData(data);
                }
            })();
        ]], jsonData))
    else
        print("Patient info window not available. Creating it now.")
        M.createPatientInfoWindow()
        -- Retry updating UI after a short delay
        hs.timer.doAfter(0.5, function() M.updateUI(data) end)
    end
end

function M.runScriptForPatient(index)
    if M.shouldStop then
        print("Script execution stopped")
        return
    end

    print("Running script for patient index:", index)
    if index and index >= 0 and index < M.NUM_PATIENTS then
        local patientData = M.patientData[index + 1]
        if patientData then
            print("Processing patient data:", hs.inspect(patientData, { depth = 2 }))
            hs.notify.new({
                title = "Running Script",
                informativeText = "Record ID: ".. patientData.recordId.. " | Age: "..
                    patientData.age.. " | Gender: ".. patientData.gender.. " | Total Polyps: "..
                    patientData.total.. " | Adenomatous: "..
                    patientData.adenomatous.. " | Serrated: "..
                    patientData.serrated
            }):send()
            M.runAppleScriptX(index + 1)
        else
            print("No data found for patient index:", index)
        end
    else
        print("Invalid patient index:", index)
    end
end

function M.parsePolypCounts(text)
    local lines = hs.fnutils.split(text, "\n")
    for i, line in ipairs(lines) do
        local patientNum, recordId, age, gender, serrated, adenomatous, total =
            line:match(
                "Patient (%d+) %- Record ID: ([^,]+), Age: ([^,]+), Gender: ([^,]+), Serrated: (%d+), Adenomatous: (%d+), Total: (%d+)")

        if patientNum then
            patientNum = tonumber(patientNum)
            if patientNum and patientNum >= 1 and patientNum <= M.NUM_PATIENTS then
                local data = M.patientData[patientNum]
                if data then
                    local existingData = data.total
                    data.recordId = recordId ~= "N/A" and recordId or ""
                    data.age = age ~= "N/A" and age or ""
                    data.gender = gender ~= "N/A" and gender or "Select"
                    data.serrated = tonumber(serrated) or data.serrated or 0
                    data.adenomatous = tonumber(adenomatous) or data.adenomatous or 0
                    data.total = tonumber(total) or data.total or 0
                    M.updateAndStorePatientData({ [patientNum] = data })
                end
            end
        end
    end
end

function M.bindHotkeys()
    if #M.polypsHotkeys == 0 then
        table.insert(M.polypsHotkeys, hs.hotkey
           .bind({}, "F6", function() M.runAppleScriptF6() end))
        table.insert(M.polypsHotkeys, hs.hotkey
           .bind({}, "F7", function() M.runAppleScriptX() end))
        table.insert(M.polypsHotkeys, hs.hotkey
           .bind({}, "F8", function() M.runAppleScriptF8() end))
        table.insert(M.polypsHotkeys, hs.hotkey
           .bind({}, "F13", function() M.resetPatientData() end))
        table.insert(M.polypsHotkeys, hs.hotkey
           .bind({}, "F9",
                function() M.deleteCurrentPatientData() end))
        table.insert(M.polypsHotkeys, hs.hotkey
           .bind({}, "F11",
                function() M.integratePolypCounts() end))
        table.insert(M.polypsHotkeys, hs.hotkey
           .bind({}, "F5",
                function() M.togglePatientInfoWindow() end))
        table.insert(M.polypsHotkeys, hs.hotkey
           .bind({ "ctrl" }, "f5",
                function() M.processClipboardData() end))
    end
end
