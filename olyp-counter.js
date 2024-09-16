(function () {
    "use strict";

    const MAX_PATIENTS = 200;
    const serratedPolyps = [
        "traditional serrated adenoma", "sessile serrated adenoma", "sessile serrated polyp",
        "sessile serrated polyps", "sessile serrated lesion", "sessile serrated lesions",
        "sessile serrated adenomas", "sessile serrated lesion/polyp",
        "sessile serrated lesion \\(sessile serrated polyp\\)",
        "sessile serrated lesion \\(sessile serrated adenoma\\)",
        "Traditional[\\s\\S]*?Serrated[\\s\\S]*?Adenoma",
    ];

    const adenomatousPolyps = [
        "tubular adenoma", "tubular adenomas", "tubulovillous adenoma", "tubular adenomata",
        "villous adenoma", "tubulovillous adenoma \\(ta\\)", "villotubular adenoma",
        "tubular adenomatous", "tubular adenoma \\(s\\)", "tubular adenoma\\(s\\)", "tubular adenomas",
    ];

    let currentPatient = 1;
    let allPatientsData = initializePatientsData();

    function initializePatientsData() {
        const patients = {};
        for (let i = 1; i <= MAX_PATIENTS; i++) {
            patients[`Patient ${i}`] = {
                serrated: 0,
                adenomatous: 0,
                total: 0
            };
        }
        return patients;
    }

    function normalizeText(text) {
        return text.replace(/-\s*\n\s*/g, "")
                   .replace(/\s+/g, " ")
                   .replace(/[^\x20-\x7E]/g, "")
                   .toLowerCase()
                   .trim();
    }

    function createFloatingPanel() {
        if (document.getElementById("polyp-counter-panel")) return;

        const panel = document.createElement("div");
        panel.id = "polyp-counter-panel";
        panel.style.cssText = `
            position: fixed;
            bottom: 2%;
            left: 1px;
            width: 123px;  /* Further reduced width */
            padding: 4px;  /* Further reduced padding */
            background-color: white;
            border: 1px solid #d1d1d1;
            border-radius: 4px;  /* Further reduced border radius */
            z-index: 10000;
            font-family: Arial, sans-serif;
            font-size: 10px;  /* Further reduced font size */
            color: #333;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        `;

        const title = document.createElement("h2");
        title.textContent = "Polyp Counter";
        title.style.cssText = `
            text-align: center;
            margin-bottom: 4px;  /* Further reduced margin */
            color: #4a4a4a;
            font-size: 11px;  /* Further reduced font size */
        `;
        panel.appendChild(title);

        const patientNumberDiv = document.createElement("div");
        patientNumberDiv.id = "patient-number";
        patientNumberDiv.style.cssText = `
            text-align: center;
            margin-bottom: 6px;
            font-weight: bold;
        `;
        panel.appendChild(patientNumberDiv);

        const patientDetails = createPatientDetails();
        panel.appendChild(patientDetails);

        const navigationDiv = document.createElement("div");
        navigationDiv.style.cssText = `
            display: flex;
            justify-content: space-between;
            margin-top: 4px;  /* Further reduced margin */
        `;

        const prevButton = document.createElement("button");
        prevButton.textContent = "← Prev";
        prevButton.style.cssText = `
            font-size: 10px;  /* Reduced button font size */
            padding: 2px 4px;  /* Reduced button padding */
        `;
        prevButton.onclick = moveToPreviousPatient;

        const nextButton = document.createElement("button");
        nextButton.textContent = "Next →";
        nextButton.style.cssText = `
            font-size: 10px;  /* Reduced button font size */
            padding: 2px 4px;  /* Reduced button padding */
        `;
        nextButton.onclick = moveToNextPatient;

        navigationDiv.appendChild(prevButton);
        navigationDiv.appendChild(nextButton);

        panel.appendChild(navigationDiv);

        document.body.appendChild(panel);
        updatePatientDetails(currentPatient);
    }

    function createPatientDetails() {
        const patientDetails = document.createElement("div");
        patientDetails.id = "current-patient-details";
        patientDetails.style.cssText = `
            background-color: #f8f8f8;
            border-radius: 3px;
            padding: 4px;  /* Further reduced padding */
        `;

        const totalCount = createPolypDetail("Total:", `total-count`, "#2c3e50");
        const serratedCount = createPolypDetail("Serrated:", `serrated-count`, "#c0392b");
        const adenomatousCount = createPolypDetail("Adenomatous:", `adenomatous-count`, "#27ae60");

        patientDetails.appendChild(totalCount);
        patientDetails.appendChild(serratedCount);
        patientDetails.appendChild(adenomatousCount);

        return patientDetails;
    }

    function createPolypDetail(label, id, color) {
        const detail = document.createElement("div");
        detail.style.cssText = `
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 2px;  /* Further reduced margin */
            font-size: 10px;  /* Further reduced font size */
        `;

        const labelText = document.createElement("span");
        labelText.textContent = label;
        labelText.style.fontWeight = "normal";
        detail.appendChild(labelText);

        const countSpan = document.createElement("span");
        countSpan.id = id;
        countSpan.style.cssText = `
            font-weight: bold;
            color: ${color};
            font-size: 11px;  /* Further reduced font size */
            min-width: 16px;  /* Further reduced min-width */
            text-align: right;
        `;
        countSpan.textContent = "0";
        detail.appendChild(countSpan);

        return detail;
    }

    function updatePatientDetails(patientIndex) {
        const patientData = allPatientsData[`Patient ${patientIndex}`];
        document.getElementById("patient-number").textContent = `Patient ${patientIndex}`;
        document.getElementById(`serrated-count`).textContent = patientData.serrated;
        document.getElementById(`adenomatous-count`).textContent = patientData.adenomatous;
        document.getElementById(`total-count`).textContent = patientData.total;
    }

    function saveAllData() {
        // Your save logic here, if needed
    }

    function updateFloatingPanel() {
        updatePatientDetails(currentPatient);
    }

    function countMatches(doc, patterns) {
        let count = 0;
        const regex = new RegExp(patterns.map((p, i) => `(?<p${i}>${p.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})`).join('|'), 'gi');
        
        let match;
        while ((match = regex.exec(doc.text())) !== null) {
            count += 1;
        }

        return count;
    }

    function countPolyps(patient) {
        const text = document.body.innerText;
        const normalizedText = normalizeText(text);
        const doc = nlp(normalizedText);

        const serratedCount = countMatches(doc, serratedPolyps);
        const adenomatousCount = countMatches(doc, adenomatousPolyps);

        const patientData = allPatientsData[`Patient ${patient}`];

        patientData.serrated += serratedCount;
        patientData.adenomatous += adenomatousCount;
        patientData.total += serratedCount + adenomatousCount;

        saveAllData();
        updateFloatingPanel();
    }

    function incrementPolypCount(type, patient) {
        const patientData = allPatientsData[`Patient ${patient}`];

        if (type === "adenomatous") {
            patientData.adenomatous += 1;
            patientData.total += 1;
        } else if (type === "serrated") {
            patientData.serrated += 1;
            patientData.total += 1;
        }

        saveAllData();
        updateFloatingPanel();
    }

    function resetCounts(patient) {
        const patientData = allPatientsData[`Patient ${patient}`];
        patientData.serrated = 0;
        patientData.adenomatous = 0;
        patientData.total = 0;

        saveAllData();
        updateFloatingPanel();
    }

    function resetAllCounts() {
        allPatientsData = initializePatientsData();
        saveAllData();
        currentPatient = 1;
        updateFloatingPanel();
    }

    function handleValueChange(name, old_value, new_value, remote) {
        if (name === 'currentPatient') {
            currentPatient = new_value;
            updatePatientDetails(new_value);
        } else if (name === 'allPatientsData') {
            allPatientsData = new_value;
            updatePatientDetails(currentPatient);
        }
    }

    createFloatingPanel();
    updateFloatingPanel();

    function updateCurrentPatient(patient) {
        currentPatient = patient;
        updatePatientDetails(patient);
    }

    function moveToNextPatient() {
        currentPatient = currentPatient < MAX_PATIENTS ? currentPatient + 1 : 1;
        updateCurrentPatient(currentPatient);
    }

    function moveToPreviousPatient() {
        currentPatient = currentPatient > 1 ? currentPatient - 1 : MAX_PATIENTS;
        updateCurrentPatient(currentPatient);
    }

    document.addEventListener("keydown", (event) => {
        switch (event.key) {
            case "F12":
                if (event.shiftKey) {
                    moveToPreviousPatient();
                } else {
                    moveToNextPatient();
                }
                break;
            case "F1":
                incrementPolypCount("adenomatous", currentPatient);
                break;
            case "F2":
                incrementPolypCount("serrated", currentPatient);
                break;
            case "F3":
                countPolyps(currentPatient);
                break;
            case "F4":
                if (event.ctrlKey) {
                    resetAllCounts();
                    updateCurrentPatient(1); // Explicitly update to Patient 1
                } else {
                    resetCounts(currentPatient);
                }
                break;
            default:
                // Add any additional shortcut handlers here
        }
    });

    window.addEventListener("load", updateFloatingPanel);
    document.addEventListener("visibilitychange", () => {
        if (!document.hidden) {
            updateFloatingPanel();
        }
    });
})();
