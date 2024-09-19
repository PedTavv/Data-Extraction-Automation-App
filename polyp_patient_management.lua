local M = {}

M.NUM_PATIENTS = 200-1000
M.POLYP_COUNT_FILE_PATH = "~/polypcounts/polypcount.json"
M.patientData = {}
M.patientCount = {}
M.currentRecordID = nil
M.patientInfoWindow = nil
M.polypsHotkeys = {}
M.savedFrame = nil
M.tags = {}
M.shouldStop = false

for i = 1, M.NUM_PATIENTS do
    M.patientData[i] = {
        id = i,
        recordId = "",
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
            current.gender ~= "" and current.gender ~= "Select" and current.age ~=
            "" and current.total ~= "" and current.adenomatous ~= "" and
            current.serrated ~= "" then
            return true, i, i + 1
        end
    end
    return false
end

function M.checkForDuplicates()
    local recordIdSet = {}
    for i = 1, M.NUM_PATIENTS do
        local recordId = M.patientData[i].recordId
        if recordId and recordId ~= "" then
            if recordIdSet[recordId] then
                hs.notify.new({
                    title = "Duplicate Detected",
                    informativeText = "Duplicate record ID found: " .. recordId
                }):send()
                return true, recordId
            else
                recordIdSet[recordId] = true
            end
        end
    end
    return false
end

function M.updateAndStorePatientData(newData, source)
    local updated = false
    for patientIndex, data in pairs(newData) do
        if tonumber(patientIndex) and tonumber(patientIndex) >= 1 and
            tonumber(patientIndex) <= M.NUM_PATIENTS then
            for key, value in pairs(data) do
                if M.patientData[patientIndex][key] ~= value then
                    M.patientData[patientIndex][key] = value
                    updated = true
                end
            end
            M.patientData[patientIndex].lastUpdatedBy = source
            M.patientData[patientIndex].lastUpdatedTime = os.time()
        end
    end

    local isDuplicate, duplicateRecordId = M.checkForDuplicates()
    if isDuplicate then
        hs.notify.new({
            title = "Duplicate Detected",
            informativeText = "Duplicate record ID found: " .. duplicateRecordId ..
                ". Please correct the data."
        }):send()
    else
        local isConsecutive, firstIndex, secondIndex =
            M.checkForConsecutivePatients()
        if isConsecutive then
            local alertMessage = string.format(
                "Patients %d and %d have the same gender (%s), age (%s), total polyps (%s), adenomatous (%s), and serrated (%s) counts. Please review the data.",
                firstIndex, secondIndex,
                M.patientData[firstIndex].gender,
                M.patientData[firstIndex].age,
                M.patientData[firstIndex].total,
                M.patientData[firstIndex].adenomatous,
                M.patientData[firstIndex].serrated)

            hs.notify.new({
                title = "Consecutive Patient Data Alert",
                informativeText = alertMessage
            }):send()
        end

        if updated then M.updateUI(M.patientData) end
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

function M.savePatientData()
    local filePath = "~/patientdata.json"
    local file, err = io.open(filePath, "w")
    if not file then return end
    local jsonString = hs.json.encode(M.patientData)
    file:write(jsonString)
    file:close()
end

function M.loadPatientData()
    local filePath = "/users/ped/patientdata.json"
    local file, err = io.open(filePath, "r")
    if not file then return end
    local content = file:read("*all")
    file:close()
    local success, data = pcall(hs.json.decode, content)
    if not success then return end
    M.patientData = data
    M.updateUI(M.patientData)
end

function M.manualSavePatientData()
    M.savePatientData()
    hs.notify.new({
        title = "Patient Data",
        informativeText = "Patient data has been manually saved"
    }):send()
end

function M.handleWebviewMessage(message)
    local body = hs.json.decode(message.body)
    if body and type(body) == "table" then
        if body.action == "updatePatientData" then
            local index = tonumber(body.data.index)
            if index then
                M.updateSinglePatientData(index, body.data.patientData)
            end
        elseif body.action == "pastePolypCounts" then
            M.parsePolypCounts(body.data)
        elseif body.action == "manualSavePatientData" then
            M.manualSavePatientData()
        elseif body.action == "loadPatientData" then
            M.loadPatientData()
        elseif body.action == "runScriptForPatient" then
            M.runScriptForPatient(body.data)
        else
            print("Unknown action:", body.action)
        end
    else
        print("Invalid message body:", message.body)
    end
end

function M.updateSinglePatientData(index, patientData)
    index = tonumber(index)
    if M.patientData[index] then
        for key, value in pairs(patientData) do
            M.patientData[index][key] = value
        end
        M.updateAndStorePatientData({ [index] = M.patientData[index] }, "Manual")
    end
end

function M.parsePolypCounts(text)
    local lines = hs.fnutils.split(text, "\n")
    local updatedPatients = {}

    for i, line in ipairs(lines) do
        local patientNum, recordId, age, gender, serrated, adenomatous, total =
            line:match(
                "Patient (%d+) %- Record ID: ([^,]+), Age: ([^,]+), Gender: ([^,]+), Serrated: (%d+), Adenomatous: (%d+), Total: (%d+)")

        if patientNum then
            patientNum = tonumber(patientNum)
            if patientNum and patientNum >= 1 and patientNum <= M.NUM_PATIENTS then
                local updatedData = {
                    id = patientNum,
                    recordId = recordId ~= "N/A" and recordId or "",
                    age = age ~= "N/A" and age or "",
                    gender = gender ~= "N/A" and gender or "Select",
                    adenomatous = tonumber(adenomatous) or 0,
                    serrated = tonumber(serrated) or 0,
                    total = tonumber(total) or 0,
                    lastUpdatedBy = "Paste",
                    lastUpdatedTime = os.time()
                }

                updatedPatients[patientNum] = updatedData
            end
        end
    end

    if next(updatedPatients) then
        M.updateAndStorePatientData(updatedPatients, "Paste")
    end
end

function M.integratePolypCounts()
    M.clearExistingData()
    local filePath = "/Users/ped/polypcounts/polypcount.json"
    local file, err = io.open(filePath, "r")
    if not file then return end

    local jsonString = file:read("*all")
    file:close()

    local polypCounts, jsonErr = hs.json.decode(jsonString)
    if not polypCounts then return end

    if not polypCounts.allPatientsData then return end

    local updatedPatients = {}

    for i = 1, M.NUM_PATIENTS do
        local patientKey = "Patient " .. i
        local polypData = polypCounts.allPatientsData[patientKey]

        if polypData then
            local updatedData = {
                id = i,
                recordId = polypData.recordID ~= "N/A" and polypData.recordID or
                    "",
                age = polypData.age ~= "N/A" and polypData.age or "",
                gender = polypData.gender ~= "N/A" and polypData.gender or
                    "Select",
                adenomatous = polypData.adenomatous or 0,
                serrated = polypData.serrated or 0,
                total = polypData.total or 0,
                lastUpdatedBy = "F11",
                lastUpdatedTime = os.time()
            }

            for key, value in pairs(updatedData) do
                M.patientData[i][key] = value
            end

            table.insert(updatedPatients, updatedData)
        end
    end

    if #updatedPatients > 0 then
        M.updateAndStorePatientData(updatedPatients, "F11")
    end
end

function M.storePatientData(index, data, source)
    if not data then return end
    index = tonumber(index)
    if not index or index < 1 or index > M.NUM_PATIENTS then return end

    local updatedData = { M.patientData[index] }
    for field, value in pairs(data) do
        if field == "adenomatous" or field == "serrated" or field == "total" then
            updatedData[1][field] = tonumber(value) or updatedData[1][field] or
                0
        else
            updatedData[1][field] = value or updatedData[1][field] or ""
        end
    end

    M.updateAndStorePatientData(updatedData, source or "Manual")
end

function M.deletePatientData(index)
    if index and index >= 1 and index <= M.NUM_PATIENTS then
        M.patientData[index] = {
            id = index,
            recordId = "",
            age = "",
            gender = "Select",
            adenomatous = 0,
            serrated = 0,
            total = 0,
            tags = {}
        }
        M.patientCount[index] = false

        M.updateAndStorePatientData({ M.patientData[index] }, "Delete")
    end
end

function M.getHTMLContent()
    return [[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Patient Info</title>
    <script src="https://unpkg.com/react@17/umd/react.development.js"></script>
    <script src="https://unpkg.com/react-dom@17/umd/react-dom.development.js"></script>
    <script src="https://unpkg.com/babel-standalone@6/babel.min.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
        window.addEventListener('message', function(event) {
            try {
                window.webkit.messageHandlers.hammerspoonMessageHandler.postMessage(JSON.stringify(event.data));
            } catch(err) {
                console.error('Failed to send message to Hammerspoon:', err);
            }
        });
    </script>
    <style>
        body {
            font-family: Arial, sans-serif;
            background-color: #1e1e1e;
            color: #c5c6c7;
        }
        input, select, textarea {
            background-color: #282a36;
            color: #f8f8f2;
            border-color: #6272a4;
            padding: 0.5rem;
            font-size: 1.2rem;
        }
        input:focus, select:focus, textarea:focus {
            border-color: #50fa7b;
            outline: none;
        }
        button {
            background-color: #6272a4;
            color: #f8f8f2;
            padding: 0.5rem 1rem;
            font-size: 1rem;
            border: none;
            border-radius: 0.25rem;
            cursor: pointer;
        }
        button:hover {
            background-color: #50fa7b;
        }
        th {
            background-color: #44475a;
            padding: 0.5rem;
        }
        tr:nth-child(even) {
            background-color: #282a36;
        }
        tr:nth-child(odd) {
            background-color: #3b3f5c;
        }
        td {
            padding: 0.5rem;
        }
        .input-number {
            width: 100%;
            text-align: center;
            background-color: #282a36;
            color: #f8f8f2;
            border: 1px solid #6272a4;
            border-radius: 0.25rem;
        }
        .input-number:focus {
            border-color: #50fa7b;
        }
        .input-select {
            width: 100%;
            background-color: #282a36;
            color: #f8f8f2;
            border: 1px solid #6272a4;
            border-radius: 0.25rem;
        }
        .input-select:focus {
            border-color: #50fa7b;
        }
        .selected-row {
            background-color: #6272a4 !important;
            border: 2px solid #50fa7b !important;
        }
    </style>
</head>
<body>
    <div id="root"></div>
    <button onclick="sendTestMessage()" class="bg-[#458588] hover:bg-[#83a598] text-[#ebdbb2] font-bold py-2 px-4 rounded mt-4">
        Test Hammerspoon Message
    </button>
    <script type="text/babel">
        function sendTestMessage() {
            try {
                window.webkit.messageHandlers.hammerspoonMessageHandler.postMessage(JSON.stringify({
                    action: 'testMessage',
                    data: 'Hello from HTML'
                }));
            } catch (error) {
                console.error("Error sending test message:", error);
            }
        }

        function runScriptForSelectedPatient(patientIndex) {
            if (patientIndex !== null) {
                try {
                    window.webkit.messageHandlers.hammerspoonMessageHandler.postMessage(JSON.stringify({
                        action: 'runScriptForPatient',
                        data: patientIndex
                    }));
                } catch (error) {
                    console.error("Error sending run script message:", error);
                }
            }
        }

        function PatientInfoComponent() {
            const [patients, setPatients] = React.useState({});
            const [selectedPatientIndex, setSelectedPatientIndex] = React.useState(null);
            const [polypCountsInput, setPolypCountsInput] = React.useState('');
            const [filter, setFilter] = React.useState('');

            React.useEffect(() => {
                window.updatePatientData = function(newPatients) {
                    setPatients(prevPatients => {
                        const updatedPatients = {...prevPatients};
                        Object.keys(newPatients).forEach(index => {
                            updatedPatients[index] = {...updatedPatients[index], ...newPatients[index]};
                        });
                        return updatedPatients;
                    });
                };

                window.updateSinglePatient = function(index, patientData) {
                    setPatients(prevPatients => ({
                        ...prevPatients,
                        [index]: patientData
                    }));
                };
            }, []);

            const handleCellChange = (index, field, value) => {
                setPatients(prevPatients => {
                    const updatedPatients = {
                        ...prevPatients,
                        [index]: {
                            ...prevPatients[index],
                            [field]: value
                        }
                    };

                    try {
                        window.webkit.messageHandlers.hammerspoonMessageHandler.postMessage(JSON.stringify({
                            action: 'updatePatientData',
                            data: { index, patientData: updatedPatients[index] }
                        }));
                    } catch (error) {
                        console.error("Error sending cell change message:", error);
                    }

                    return updatedPatients;
                });
            };

            const handleDeletePatient = () => {
                if (selectedPatientIndex !== null) {
                    try {
                        window.webkit.messageHandlers.hammerspoonMessageHandler.postMessage(JSON.stringify({
                            action: 'deletePatient',
                            data: selectedPatientIndex
                        }));
                        setSelectedPatientIndex(null);
                        setPatients(prevPatients => {
                            const updatedPatients = { ...prevPatients };
                            delete updatedPatients[selectedPatientIndex];
                            return updatedPatients;
                        });
                    } catch (error) {
                        console.error("Error sending delete patient message:", error);
                    }
                } else {
                    alert('Please select a patient first');
                }
            };

            const handlePastePolypCounts = () => {
                try {
                    window.webkit.messageHandlers.hammerspoonMessageHandler.postMessage(JSON.stringify({
                        action: 'pastePolypCounts',
                        data: polypCountsInput
                    }));
                    setPolypCountsInput('');
                } catch (error) {
                    console.error("Error sending polyp counts:", error);
                }
            };

            const handleIntegratePolypCounts = () => {
                try {
                    window.webkit.messageHandlers.hammerspoonMessageHandler.postMessage(JSON.stringify({
                        action: 'integratePolypCounts'
                    }));
                } catch (error) {
                    console.error("Error sending integrate polyp counts:", error);
                }
            };

            const filteredPatients = React.useMemo(() => {
                return Object.entries(patients)
                    .filter(([_, patient]) =>
                        patient.recordId && patient.recordId.toString().includes(filter)
                    )
                    .sort(([a], [b]) => parseInt(a) - parseInt(b));
            }, [patients, filter]);

            return (
                <div className="flex flex-col h-screen bg-[#1e1e1e] text-[#c5c6c7]">
                    <div className="flex justify-center items-center bg-[#282a36] p-4">
                        <h2 className="text-4xl font-extrabold text-[#ffb86c]">Polyp Script</h2>
                    </div>
                    <div className="flex flex-1 overflow-hidden">
                        <div className="w-3/4 overflow-auto border-r border-[#6272a4]">
                            <div className="mb-4">
                                <input
                                    type="text"
                                    placeholder="Filter by Record ID"
                                    value={filter}
                                    onChange={(e) => setFilter(e.target.value)}
                                    className="w-full bg-[#282a36] text-[#f8f8f2] border border-[#6272a4] rounded p-2"
                                />
                            </div>
                            <table className="w-full">
                                <thead>
                                    <tr className="bg-[#44475a]">
                                        <th>Patient</th>
                                        <th>Record ID</th>
                                        <th>Age</th>
                                        <th>Gender</th>
                                        <th>Adenomatous</th>
                                        <th>Serrated</th>
                                        <th>Total</th>
                                        <th>Total Polyps</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {filteredPatients.map(([index, patient]) => (
                                        <tr
                                            key={index}
                                            className={`${selectedPatientIndex === parseInt(index) ? 'selected-row' : ''}`}
                                            onClick={() => setSelectedPatientIndex(parseInt(index))}
                                        >
                                            <td>P{index}</td>
                                            <td>
                                                <input
                                                    type="text"
                                                    value={patient.recordId || ''}
                                                    onChange={(e) => handleCellChange(index, 'recordId', e.target.value)}
                                                    placeholder="Enter record ID"
                                                    className="input-number"
                                                    id={`recordId-${index}`}
                                                />
                                            </td>
                                            <td>
                                                <input
                                                    type="text"
                                                    value={patient.age || ''}
                                                    onChange={(e) => {
                                                        const value = e.target.value.replace(/^0+/, ''); // Remove leading zeros
                                                        if (value === '' || (/^\d+$/.test(value) && parseInt(value) <= 120)) {
                                                            handleCellChange(index, 'age', value);
                                                        }
                                                    }}
                                                    placeholder="Enter age"
                                                    className="input-number"
                                                    id={`age-${index}`}
                                                />
                                            </td>
                                            <td>
                                                <select
                                                    value={patient.gender || 'Select'}
                                                    onChange={(e) => handleCellChange(index, 'gender', e.target.value)}
                                                    className="input-select"
                                                    id={`gender-${index}`}
                                                >
                                                    <option value="Select">Select</option>
                                                    <option value="Male">Male</option>
                                                    <option value="Female">Female</option>
                                                </select>
                                            </td>
                                            <td>
                                                <input
                                                    type="number"
                                                    value={patient.adenomatous || 0}
                                                    onChange={(e) => handleCellChange(index, 'adenomatous', e.target.value)}
                                                    className="input-number"
                                                    id={`adenomatous-${index}`}
                                                />
                                            </td>
                                            <td>
                                                <input
                                                    type="number"
                                                    value={patient.serrated || 0}
                                                    onChange={(e) => handleCellChange(index, 'serrated', e.target.value)}
                                                    className="input-number"
                                                    id={`serrated-${index}`}
                                                />
                                            </td>
                                            <td>
                                                <input
                                                    type="number"
                                                    value={patient.total || 0}
                                                    onChange={(e) => handleCellChange(index, 'total', e.target.value)}
                                                    className="input-number"
                                                    id={`total-${index}`}
                                                />
                                            </td>
                                            <td>
                                                {(parseInt(patient.adenomatous) || 0) + (parseInt(patient.serrated) || 0)}
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                        <div className="w-1/4 p-4 flex flex-col">
                            <div className="space-y-4 mb-4">
                                <button onClick={handleDeletePatient} className="w-full bg-[#cc241d] hover:bg-[#fb4934] text-[#f8f8f2] font-bold py-2 px-4 rounded">
                                    Delete Selected Patient
                                </button>
                                <button onClick={() => runScriptForSelectedPatient(selectedPatientIndex)} className="w-full bg-[#6272a4] hover:bg-[#50fa7b] text-[#f8f8f2] font-bold py-2 px-4 rounded">
                                    Run Script for Selected Patient
                                </button>
                                <button onClick={() => window.webkit.messageHandlers.hammerspoonMessageHandler.postMessage(JSON.stringify({action: 'manualSavePatientData'}))} className="w-full bg-[#98971a] hover:bg-[#b8bb26] text-[#f8f8f2] font-bold py-2 px-4 rounded">
                                    Save Patient Data
                                </button>
                                <button onClick={handlePastePolypCounts} className="w-full bg-[#d79921] hover:bg-[#fabd2f] text-[#f8f8f2] font-bold py-2 px-4 rounded">
                                    Update Polyp Counts
                                </button>
                                <button onClick={() => window.webkit.messageHandlers.hammerspoonMessageHandler.postMessage(JSON.stringify({action: 'loadPatientData'}))} className="w-full bg-[#b16286] hover:bg-[#d3869b] text-[#f8f8f2] font-bold py-2 px-4 rounded">
                                    Load Saved Patient Data
                                </button>
                                <button onClick={handleIntegratePolypCounts} className="w-full bg-[#689d6a] hover:bg-[#98971a] text-[#f8f8f2] font-bold py-2 px-4 rounded">
                                    Integrate Polyp Counts
                                </button>
                            </div>
                            <div className="flex-grow">
                                <textarea
                                    className="w-full h-full p-2 bg-[#282a36] text-[#f8f8f2] border border-[#6272a4] rounded"
                                    placeholder="Paste polyp counts here..."
                                    value={polypCountsInput}
                                    onChange={(e) => setPolypCountsInput(e.target.value)}
                                />
                            </div>
                        </div>
                    </div>
                </div>
            );
        }

        ReactDOM.render(<PatientInfoComponent />, document.getElementById('root'));
    </script>
</body>
</html>
    ]]
end

function M.createPatientInfoWindow()
    if not M.patientInfoWindow then
        local screen = hs.screen.primaryScreen()
        local screenFrame = screen:frame()
        local windowWidth = screenFrame.w * 0.8
        local windowHeight = screenFrame.h * 0.8
        local windowX = screenFrame.x + (screenFrame.w - windowWidth) / 2
        local windowY = screenFrame.y + (screenFrame.h - windowHeight) / 2

        -- Create the user content controller
        local contentController = hs.webview.usercontent.new(
            "hammerspoonMessageHandler")

        -- Set the callback for handling messages from the webview
        contentController:setCallback(function(message)
            print("Received message from webview:",
                hs.inspect(message, { depth = 2 }))
            M.handleWebviewMessage(message)
        end)

        -- Create the webview with the content controller
        M.patientInfoWindow = hs.webview.new({
            x = windowX,
            y = windowY,
            w = windowWidth,
            h = windowHeight
        }, { developerExtrasEnabled = true }, contentController):windowStyle({
            "closable", "titled", "resizable"
        }):allowTextEntry(true):level(hs.drawing.windowLevels.floating)

        -- Inject the script to set up message passing
        contentController:injectScript({
            source = [[
                window.webkit.messageHandlers.hammerspoonMessageHandler.postMessage = function(message) {
                    window.webkit.messageHandlers.hammerspoonMessageHandler.postMessage(JSON.stringify(message));
                };
            ]],
            injectionTime = "documentStart"
        })

        local html = M.getHTMLContent()
        M.patientInfoWindow:html(html)
    end

    if not M.patientInfoWindow:isVisible() then M.patientInfoWindow:show() end

    print("Patient info window created and shown")
end

function M.togglePatientInfoWindow()
    if M.patientInfoWindow then
        if M.patientInfoWindow:isVisible() then
            M.patientInfoWindow:hide()
        else
            M.patientInfoWindow:show()
            M.updateAndStorePatientData(M.patientData, "Toggle")
            M.patientInfoWindow:bringToFront(true)
            M.patientInfoWindow:hswindow():focus()
        end
    else
        M.createPatientInfoWindow()
        M.updateAndStorePatientData(M.patientData, "Toggle")
        M.patientInfoWindow:bringToFront(true)
        M.patientInfoWindow:hswindow():focus()
    end
end

function M.resetPatientData()
    for i = 1, M.NUM_PATIENTS do
        M.patientData[i] = {
            id = i,
            recordId = "",
            age = "",
            gender = "Select",
            adenomatous = 0,
            serrated = 0,
            total = 0,
            tags = {}
        }
        M.patientCount[i] = false
    end
    hs.notify.new({
        title = "Patient Data",
        informativeText = "Patient data has been reset"
    }):send()

    -- Update UI with reset data
    M.updateUI(M.patientData)

    -- Switch to tab 1 in Microsoft Edge and press Ctrl+F4
    local script = [[
        tell application "Microsoft Edge"
            activate
            -- Switch to tab 1
            set active tab index of front window to 1
            delay 0.5
            -- Press Ctrl+F4
            tell application "System Events" to key code 118 using control down
            delay 0.5
            -- Switch to tab 2
            set active tab index of front window to 2
            delay 0.5
            -- Press Ctrl+F4
            tell application "System Events" to key code 118 using control down
        end tell
    ]]
    hs.osascript.applescript(script)
end

function M.resetShouldStop() M.shouldStop = false end

M.updateUI(M.patientData)

function M.pressFKey(key)
    hs.eventtap.event.newKeyEvent(hs.keycodes.map[key], true):post()
    hs.eventtap.event.newKeyEvent(hs.keycodes.map[key], false):post()
end

function M.init()
    M.patientData = M.patientData or {}
    M.patientCount = M.patientCount or {}
    M.currentRecordID = nil
    M.polypsHotkeys = M.polypsHotkeys or {}
    M.tags = M.tags or {}

    M.bindHotkeys()
    M.createPatientInfoWindow() -- Create the window
    hs.notify.new({
        title = "Patient Data",
        informativeText = "Patient data has been initialized"
    }):send()

    print("Initialization complete")
end

function M.runAppleScriptF6()
    local script = [[
        tell application "Microsoft Edge"
            activate
            -- Switch to tab 1
            set active tab index of window 1 to 1
            delay 0.5
            -- Press Control+F7
            tell application "System Events" to key code 98 using control down
            delay 0.5
            -- Switch to tab 2
            set active tab index of window 1 to 2
            delay 0.5
            -- Press Control+F6
            tell application "System Events" to key code 97 using control down
            delay 0.5
        end tell
    ]]
    -- Execute the AppleScript and then run the F8 script
    hs.osascript.applescript(script)
    M.runAppleScriptF8()
end

function M.runAppleScriptF8()
    local script = [[
        tell application "Microsoft Edge"
            -- Switch to tab 1
            set active tab index of window 1 to 1
            activate
            delay 0.5

            -- Execute JavaScript in the active tab
            tell active tab of window 1 to execute javascript "
                (function() {
                    function triggerClick(element) {
                        if (element) {
                            element.scrollIntoView();
                            ['mouseover', 'mousedown', 'mouseup', 'click'].forEach(function(eventType) {
                                var event = new MouseEvent(eventType, {
                                    bubbles: true,
                                    cancelable: true,
                                    view: window
                                });
                                element.dispatchEvent(event);
                            });
                        }
                    }

                    var button1 = document.evaluate('/html/body/div[10]/div[2]/a[3]/span',
                        document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                    if (button1) {
                        triggerClick(button1);
                    }

                    var button2 = document.evaluate('/html/body/div[7]/div[3]/div[2]/div[1]/div[1]/a[2]',
                        document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                    if (button2) {
                        triggerClick(button2);
                    }

                    var searchButton = document.querySelector('#multiple-patient-manager > div.manager-side-area > div.top-actions > a.open-patient-search-dialog.search.side.manager-btn.hoverable');
                    if (searchButton) {
                        triggerClick(searchButton);
                    }
                })();
            "
            delay 0.25

            -- Switch to tab 2
            set active tab index of window 1 to 2
            delay 0.9

            -- Click the save next button
            tell active tab of window 1 to execute javascript "
                (function() {
                    var saveNextButton = document.querySelector('#submit-btn-savenextrecord > span');
                    if (saveNextButton) { saveNextButton.click(); }
                })();
            "
            delay 0.9

            -- Click the event grid image
            tell active tab of window 1 to execute javascript "
                (function() {
                    var eventGridImage = document.querySelector('#event_grid_table > tbody > tr > td:nth-child(2) > a > img');
                    if (eventGridImage) { eventGridImage.click(); }
                })();
            "
            delay 0.8

            -- Get the patient name
            tell active tab of window 1 to set patientName to execute javascript "
                (function() {
                    var input = document.querySelector('#name-tr > td:nth-child(2) > span > input');
                    return input ? input.value : '';
                })();
            "

            -- Copy patient name to clipboard
            do shell script "echo " & quoted form of patientName & " | pbcopy"

            -- Switch to the first tab
            set active tab index of window 1 to 1

            -- Paste the patient name into the search input and press space
            tell active tab of window 1 to execute javascript "
                (function() {
                    var input = document.querySelector('#patient-search-dialog > div:nth-child(1) > form > div:nth-child(1) > input');
                    if (input) {
                        input.value = " & quoted form of patientName & ";
                        input.focus();
                    }
                })();
            "
            -- Use AppleScript to simulate pressing the space bar
            tell application "System Events"
                keystroke space
            end tell
            -- Wait a moment for the space to be registered
            delay 0.1
            -- Click the search button
            tell active tab of window 1 to execute javascript "
                (function() {
                    var searchButton = document.querySelector('#patient-search-dialog > div:nth-child(1) > form > div:nth-child(2) > button');
                    if (searchButton) {
                        searchButton.click();
                    }
                })();
            "
        end tell
    ]]
    hs.osascript.applescript(script)
end

function M.runAppleScriptB(patientIndex)
    local totalPolyps = tonumber(M.patientData[patientIndex].total) or 0
    local optionToSelect = totalPolyps >= 10 and "2" or "3" -- "2" for Unverified, "3" for Complete

    local scriptB = [[
        tell application "Microsoft Edge"
            activate
            delay 0.44
            -- Set 'None' in dropdown
            tell active tab of window 1 to set result1 to execute javascript "
                var noneOption = document.evaluate('/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[8]/td[2]/span/span/select/option[2]',
                document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                if (noneOption) {
                    noneOption.selected = true;
                    noneOption.parentNode.dispatchEvent(new Event('change', { bubbles: true }));
                    'success';
                } else {
                    'failure';
                }"
            if result1 is "failure" then error "None option not found."
            delay 0.44
            -- Set 'Complete' or 'Unverified' in dropdown based on polyp count
            tell active tab of window 1 to set result2 to execute javascript "
                var totalPolyps = ]] .. totalPolyps .. [[;
                var optionToSelect = totalPolyps >= 10 ? 2 : 3;  // 2 for Unverified, 3 for Complete
                var option = document.evaluate('/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[10]/td[2]/span/span/select/option[' + optionToSelect + ']',
                document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                if (option) {
                    option.selected = true;
                    option.parentNode.dispatchEvent(new Event('change', { bubbles: true }));
                    'success: ' + (totalPolyps >= 10 ? 'Unverified' : 'Complete');
                } else {
                    'failure';
                }"
            if result2 is "failure" then error "Option not found."
            delay 0.44
            -- Save and exit form
            tell active tab of window 1 to set result3 to execute javascript "
                var saveButton = document.evaluate('/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[14]/td[2]/span/div/button[1]/span',
                document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                if (saveButton) {
                    saveButton.click();
                    'success';
                } else {
                    'failure';
                }"
            if result3 is "failure" then error "Save button not found."
            delay 0.7
        end tell
    ]]

    local ok, result = hs.osascript.applescript(scriptB)
    if not ok then
        print("Failed to run AppleScriptB: " .. tostring(result))
    else
        print("Successfully ran AppleScriptB. Selected option: " .. (totalPolyps >= 10 and "Unverified" or "Complete"))
    end
end

function M.waitForElementAndAct(xpath, action, maxRetries, timeout,
                                isRecordIDCheck, retry)
    maxRetries = maxRetries or 5
    timeout = timeout or 15 -- Default timeout in seconds
    local startTime = hs.timer.secondsSinceEpoch()

    if not xpath or type(xpath) ~= "string" then
        hs.notify.new({
            title = "Error",
            informativeText = "Invalid xpath provided to waitForElementAndAct"
        }):send()
        print("Error: Invalid xpath provided to waitForElementAndAct")
        return false
    end

    if not action or (type(action) ~= "string" and type(action) ~= "function") then
        hs.notify.new({
            title = "Error",
            informativeText = "Invalid action provided to waitForElementAndAct"
        }):send()
        print("Error: Invalid action provided to waitForElementAndAct")
        return false
    end

    for attempt = 1, maxRetries do
        if hs.timer.secondsSinceEpoch() - startTime > timeout then
            hs.notify.new({
                title = "Error",
                informativeText = "Timeout reached while waiting for element: " ..
                    xpath
            }):send()
            return false
        end

        if isRecordIDCheck then
            -- Use the verifyRecordID function for record ID checks
            local ok, result = M.verifyRecordID(action)
            if ok then
                return true
            elseif result == "mismatch" and retry then
                print("Record ID verification failed. Retrying...")
                return retry()
            else
                print("Record ID verification failed.")
                return false
            end
        else
            local script = string.format([[
                tell application "Microsoft Edge"
                    tell active tab of window 1
                        set elementFound to execute javascript "
                            var element = document.evaluate('%s', document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                            if (element && !element.disabled && element.offsetParent !== null) {
                                try {
                                    %s
                                    'success'
                                } catch (error) {
                                    'error: ' + error.message
                                }
                            } else {
                                'not found or not interactable'
                            }"
                        return elementFound
                    end tell
                end tell
            ]], xpath, action)

            local ok, result = hs.osascript.applescript(script)
            if ok then
                if result == "success" then
                    return true
                elseif type(result) == "string" and string.sub(result, 1, 6) ==
                    "error:" then
                    hs.notify.new({
                        title = "Error",
                        informativeText = "Action failed: " .. result
                    }):send()
                    return false
                end
            else
                print("AppleScript execution failed. Error:", result)
            end
        end

        hs.timer.usleep(1300000)
    end

    hs.notify.new({
        title = "Error",
        informativeText = "Failed to find or act on element after " ..
            maxRetries .. " attempts. XPath: " .. xpath
    }):send()
    return false
end

function M.waitForPageLoad(xpath, timeout)
    local startTime = hs.timer.secondsSinceEpoch()
    timeout = timeout or 15 -- Default timeout of 15 seconds

    while hs.timer.secondsSinceEpoch() - startTime < timeout do
        local script = string.format([[
            tell application "Microsoft Edge"
                tell active tab of window 1
                    set elementFound to execute javascript "
                        var element = document.evaluate('%s', document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                        element ? 'found' : 'not found'
                    "
                    return elementFound
                end tell
            end tell
        ]], xpath)

        local ok, result = hs.osascript.applescript(script)
        if ok and result == "found" then return true end
        hs.timer.usleep(500000) -- Wait 0.5 seconds before checking again
    end
    return false
end

function M.verifyRecordID(expectedID)
    local function refreshPage()
        local refreshScript = [[
            tell application "Microsoft Edge"
                tell active tab of window 1
                    execute javascript "location.reload();"
                end tell
            end tell
        ]]
        hs.osascript.applescript(refreshScript)
        hs.timer.usleep(2000000) -- Pause for 2.0 seconds
    end

    local function clickDashboard()
        local dashboardScript = [[
            tell application "Microsoft Edge"
                tell active tab of window 1
                    execute javascript "
                        var dashboardElement = document.evaluate('/html/body/div[12]/div/div[1]/div[2]/div[2]/div/div/div/div[1]/a/span', document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                        if (dashboardElement) {
                            dashboardElement.click();
                        }
                    "
                end tell
            end tell
        ]]
        hs.osascript.applescript(dashboardScript)
        hs.timer.usleep(1000000) -- Pause for 1.0 second
    end

    local function switchToTab(tabNumber)
        local switchTabScript = string.format([[
            tell application "Microsoft Edge"
                activate
                tell application "System Events"
                    keystroke "%d" using {command down}
                end tell
            end tell
        ]], tabNumber)
        hs.osascript.applescript(switchTabScript)
        hs.timer.usleep(1000000) -- Pause for 1.0 second
    end

    local function checkRecordID()
        local script = string.format([[
            tell application "Microsoft Edge"
                tell active tab of window 1
                    execute javascript "
                        var recordIDElement = document.evaluate('/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[1]/td/div/div/div/span/b', document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                        if (recordIDElement) {
                            var foundID = recordIDElement.textContent.trim();
                            if (foundID === '%s') {
                                'match:' + foundID;
                            } else {
                                'mismatch:' + foundID;
                            }
                        } else {
                            'not found';
                        }
                    "
                end tell
            end tell
        ]], expectedID)

        local ok, result = hs.osascript.applescript(script)
        return ok, result
    end

    for attempt = 1, 2 do -- Allow one retry
        local ok, result = checkRecordID()

        -- Debug logging
        print("Verification OK:", ok)
        print("Verification Result:", result)

        if ok then
            local status, foundID = result:match("(%w+):?(.*)")
            if status == "match" then
                print(string.format("Record ID matched: Expected %s, Found %s", expectedID, foundID))
                return true, foundID
            elseif status == "mismatch" then
                print(string.format("Record ID mismatch: Expected %s, Found %s", expectedID, foundID))
                if attempt == 1 then
                    print("Mismatch detected. Performing retry sequence...")
                    clickDashboard()
                    refreshPage()
                    switchToTab(2)
                    switchToTab(3)
                    hs.timer.usleep(1000000) -- Wait for 1 second before retry
                    -- Continue to next iteration for retry
                else
                    return false, "mismatch"
                end
            else
                print("Record ID element not found")
                return false, "not found"
            end
        else
            print("Verification failed")
            return false, "verification failed"
        end
    end

    return false, "retry failed"
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
            print("Processing patient data:",
                hs.inspect(patientData, { depth = 2 }))
            hs.notify.new({
                title = "Running Script",
                informativeText = string.format(
                    "Record ID: %s | Age: %s | Gender: %s | Total Polyps: %s | Adenomatous: %s | Serrated: %s",
                    patientData.recordId, patientData.age, patientData.gender,
                    patientData.total, patientData.adenomatous,
                    patientData.serrated)
            }):send()
            M.runAppleScriptX(index + 1)
        else
            print("No data found for patient index:", index)
        end
    else
        print("Invalid patient index:", index)
    end
end

function M.runAppleScriptX(index)
    M.resetShouldStop() -- Reset the flag at the start
    -- Initialize tracking variables
    local patientsProcessed = 0
    local successfulEntries = 0
    local errors = {}
    local highPolypsCount = 0

    local startIndex = index or 1
    local endIndex = index or M.NUM_PATIENTS

    -- Create a list of patient indices with data
    local patientsWithData = {}
    for i = startIndex, endIndex do
        if M.patientData[i] and M.patientData[i].recordId and M.patientData[i].recordId ~= "" then
            table.insert(patientsWithData, i)
        end
    end

    -- Switch to tab 3 before starting the process
    local switchToTab3Script = [[
        tell application "Microsoft Edge"
            activate
            tell application "System Events"
                keystroke "3" using {command down}
            end tell
        end tell
    ]]
    hs.osascript.applescript(switchToTab3Script)
    hs.timer.usleep(1000000) -- Wait 1 second after switching tabs

    for _, i in ipairs(patientsWithData) do
        if M.shouldStop then
            print("Script execution stopped by user")
            break
        end

        local data = M.patientData[i]
        print("Processing patient:", i)
        print("Patient data:", hs.inspect(data, { depth = 2 }))

        local function processPatient()
            if data.recordId and data.recordId ~= "" and data.age and data.age ~= "" and
                data.gender and data.gender ~= "Select" and data.adenomatous and
                data.serrated and data.total then
                patientsProcessed = patientsProcessed + 1

                -- Patient Entry Tracking Notification
                hs.notify.new({
                    title = "Patient Entry",
                    informativeText = string.format(
                        "Record ID: %s | Age: %s | Gender: %s | Total Polyps: %s | Adenomatous: %s | Serrated: %s",
                        data.recordId, data.age, data.gender, data.total,
                        data.adenomatous, data.serrated)
                }):send()

                -- Check for high polyp count
                if tonumber(data.total) >= 10 then
                    highPolypsCount = highPolypsCount + 1
                    hs.notify.new({
                        title = "High Polyp Count",
                        informativeText = "Record ID " .. data.recordId ..
                            " has 10 or more polyps (Total: " .. data.total .. ")"
                    }):send()
                end

                -- Wait for dashboard to appear before processing next patient
                if not M.waitForPageLoad(
                        "/html/body/div[12]/div/div[1]/div[2]/div[2]/div/div/div/div[1]/a/span",
                        15) then
                    table.insert(errors,
                        { patient = i, error = "Dashboard not found" })
                    hs.notify.new({
                        title = "Error",
                        informativeText = "Dashboard not found for patient " .. i ..
                            ". Stopping process."
                    }):send()
                    return false
                end

                local steps = {
                    {
                        name = "Click dashboard",
                        xpath = "/html/body/div[12]/div/div[1]/div[2]/div[2]/div/div/div/div[1]/a/span",
                        action = "element.click();",
                        waitForLoad = true
                    }, {
                    name = "Enter record ID",
                    xpath = "/html/body/div[12]/div/div[2]/div[4]/input",
                    action = string.format("element.value = '%s';",
                        data.recordId)
                }, {
                    name = "Click submit",
                    xpath = "/html/body/div[12]/div/div[2]/div[4]/div/button",
                    action = "element.click();",
                    waitForLoad = true
                }, {
                    name = "Click second button",
                    xpath = "/html/body/div[12]/div/div[2]/table[2]/tbody/tr[1]/td[2]/a/img",
                    action = "element.click();",
                    waitForLoad = true
                }, {
                    name = "Check record ID",
                    xpath = "/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[1]/td/div/div/div/span/b",
                    action = data.recordId, -- Pass the expected record ID
                    waitForLoad = true,
                    isRecordIDCheck = true,
                    retry = function()
                        -- This retry function will be called if there's a mismatch
                        return M.verifyRecordID(data.recordId)
                    end
                }, {
                    name = "Select gender",
                    action = string.format([[
                            tell application "Microsoft Edge"
                                tell active tab of window 1
                                    execute javascript "
                                        var genderSelect = document.evaluate('/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[3]/td[2]/span/span/select', document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                                        if (genderSelect) {
                                            var genderOption = Array.from(genderSelect.options).find(option => option.text === '%s');
                                            if (genderOption) {
                                                genderOption.selected = true;
                                                genderSelect.dispatchEvent(new Event('change', { bubbles: true }));
                                            } else {
                                                throw new Error('Gender option not found');
                                            }
                                        } else {
                                            throw new Error('Gender select not found');
                                        }"
                                end tell
                            end tell
                        ]], data.gender)
                }, {
                    name = "Enter age",
                    xpath = "/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[4]/td[2]/span/input",
                    action = string.format("element.value = '%s';", data.age)
                }, {
                    name = "Enter total polyps",
                    xpath = "/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[5]/td[2]/span/input",
                    action = string.format("element.value = '%s';", data.total)
                }, {
                    name = "Enter total serrated",
                    xpath = "/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[6]/td[2]/span/input",
                    action = string.format("element.value = '%s';",
                        data.serrated)
                }, {
                    name = "Enter total adenomatous",
                    xpath = "/html/body/div[12]/div/div[2]/form/div/table/tbody/tr[7]/td[2]/span/input",
                    action = string.format("element.value = '%s';",
                        data.adenomatous)
                }
                }
                local allStepsSuccessful = true
                for _, step in ipairs(steps) do
                    if M.shouldStop then
                        print("Script execution stopped by user")
                        break
                    end

                    hs.notify.new({
                        title = "Executing Step",
                        informativeText = "Patient " .. i .. ": " .. step.name
                    }):send()
                    if step.name == "Select gender" then
                        hs.timer.usleep(920000) -- Wait 0.92 seconds before selecting gender
                        local ok, result = hs.osascript.applescript(step.action)
                        if not ok then
                            table.insert(errors, {
                                patient = i,
                                error = "Failed to select gender: " ..
                                    (result or "unknown error")
                            })
                            allStepsSuccessful = false
                            break
                        end
                    else
                        if step.waitForLoad and
                            not M.waitForPageLoad(step.xpath, 15) then
                            table.insert(errors, {
                                patient = i,
                                error = "Page did not load in time for step: " ..
                                    step.name
                            })
                            hs.notify.new({
                                title = "Error",
                                informativeText = "Page did not load in time for step: " ..
                                    step.name .. " (Patient " .. i .. ")"
                            }):send()
                            allStepsSuccessful = false
                            break
                        end
                        if step.name == "Check record ID" then
                            local ok, result = M.waitForElementAndAct(step.xpath, step.action, 10, 15,
                                step.isRecordIDCheck, step.retry)
                            if not ok then
                                if result == "mismatch" then
                                    print("Record ID mismatch detected. Retrying the entire patient process.")
                                    return false -- Indicate that we need to retry the entire patient process
                                else
                                    hs.notify.new({
                                        title = "Error",
                                        informativeText =
                                            "Failed to verify Record ID for patient " .. i
                                    }):send()
                                    allStepsSuccessful = false
                                    break
                                end
                            end
                        else
                            if not M.waitForElementAndAct(step.xpath, step.action, 10, 15, step.isRecordIDCheck, step.retry) then
                                hs.notify.new({
                                    title = "Error",
                                    informativeText = "Failed to " .. step.name ..
                                        " for patient " .. i
                                }):send()
                                allStepsSuccessful = false
                                break
                            end
                        end
                    end
                    hs.timer.usleep(800000) -- Wait 0.8 seconds between steps
                end

                if allStepsSuccessful then
                    print("All steps successful for patient " .. i)
                    hs.timer.usleep(1000000 - 670000) -- 0.33 second delay between polyp count and AppleScriptB
                    -- Run AppleScriptB
                    M.runAppleScriptB(i)
                    successfulEntries = successfulEntries + 1
                    hs.timer.usleep(1500000 - 670000) -- 0.83 second delay between patients

                    -- Update UI for the processed patient
                    -- Remove non-serializable fields
                    local serializableData = {}
                    for key, value in pairs(M.patientData[i]) do
                        if type(value) ~= "function" and type(value) ~= "userdata" then
                            serializableData[key] = value
                        end
                    end

                    M.updateUI({ [i] = serializableData }) -- Use the cleaned data
                    return true                            -- Indicate successful processing
                else
                    print("Failed to process patient " .. i)
                    hs.notify.new({
                        title = "Error",
                        informativeText = "Failed to process patient " .. i
                    }):send()
                    return false -- Indicate that a retry might be needed
                end
            else
                print("Skipping patient due to incomplete data:",
                    hs.inspect(data, { depth = 2 }))
                hs.notify.new({
                    title = "Warning",
                    informativeText = "Skipping patient " .. i ..
                        " due to incomplete data"
                }):send()
            end
        end

        local patientProcessed = false
        local retryCount = 0
        repeat
            patientProcessed = processPatient()
            if patientProcessed then
                break -- Exit the loop if patient was processed successfully
            else
                retryCount = retryCount + 1
                if retryCount < 2 then
                    print("Retrying patient " .. i .. ". Attempt " .. (retryCount + 1))
                    hs.timer.usleep(2000000) -- Wait 2 seconds before retrying
                end
            end
        until patientProcessed or retryCount >= 2

        if not patientProcessed then
            print("Failed to process patient " .. i .. " after retries")
            hs.notify.new({ title = "Error", informativeText = "Failed to process patient " .. i .. " after retries" })
                :send()
        end
    end

    -- Final notification with summary
    local summaryText = string.format(
        "Processed %d patients. Successful entries: %d. Errors: %d. High polyp count: %d",
        patientsProcessed, successfulEntries, #errors,
        highPolypsCount)

    -- Send summary notification
    hs.notify.new({ title = "Process Complete", informativeText = summaryText }):send()

    -- High polyp counts notification
    if highPolypsCount > 0 then
        local highPolypRecords = {}
        for i = 1, M.NUM_PATIENTS do
            local data = M.patientData[i]
            if data.recordId and data.recordId ~= "" and tonumber(data.total) > 10 then
                table.insert(highPolypRecords, data.recordId)
            end
        end
        local highPolypText = string.format("High polyp counts (>10) found in %d records:\n%s",
            highPolypsCount, table.concat(highPolypRecords, ", "))
        hs.notify.new({ title = "High Polyp Counts", informativeText = highPolypText }):send()
    end

    -- Detailed Hammerspoon console log summary
    print("========== Process Summary ==========")
    print(string.format("Total patients processed: %d", patientsProcessed))
    print(string.format("Successful entries: %d", successfulEntries))
    print(string.format("Errors encountered: %d", #errors))
    print(string.format("Patients with high polyp count (>10): %d", highPolypsCount))

    -- High polyp counts details
    if highPolypsCount > 0 then
        local highPolypRecords = {}
        for i = 1, M.NUM_PATIENTS do
            local data = M.patientData[i]
            if data.recordId and data.recordId ~= "" and tonumber(data.total) > 10 then
                table.insert(highPolypRecords, data.recordId)
            end
        end
        print("Record IDs with high polyp counts (>10): " .. table.concat(highPolypRecords, ", "))
    end

    -- Add this line to prevent restarting
    M.shouldStop = true
end

function M.bindHotkeys()
    if #M.polypsHotkeys == 0 then -- Ensure hotkeys are not bound multiple times
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

function M.unbindHotkeys()
    for _, hotkey in ipairs(M.polypsHotkeys) do hotkey:delete() end
    M.polypsHotkeys = {}
end

-- Cleanup function to unbind hotkeys and close the patient info window
function M.cleanup()
    M.unbindHotkeys()
    if M.patientInfoWindow then
        M.patientInfoWindow:delete()
        M.patientInfoWindow = nil
    end
    hs.notify.new({
        title = "Polyp Script",
        informativeText = "Cleaned up successfully"
    }):send()
end

function M.processClipboardData()
    local clipboardContent = hs.pasteboard.getContents()
    if clipboardContent then
        print("Clipboard content:", clipboardContent)
        M.parsePolypCounts(clipboardContent)
    else
        print("Clipboard is empty")
        hs.notify.new({ title = "Error", informativeText = "Clipboard is empty" }):send()
    end
end

return M
