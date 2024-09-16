# Medical Data Automation Tool

## Personal Initiative

This project was undertaken as a personal initiative, driven by my curiosity and passion for exploring the intersection of technology and healthcare. It has been in development for the past year, with a focus on automating data extraction and entry for medical records, improving efficiency and accuracy. This tool was developed and utilized to automate data extraction and entry for medical research, significantly increasing efficiency and accuracy in a controlled environment. 

## Disclaimer

Please note that this tool is not intended for public use. It is presented as a proof of concept, demonstrating the potential benefits of automation in medical data processing. Users should be aware that applying this tool in a clinical setting requires appropriate ethical approval and compliance with patient data privacy regulations. Proper authorization is necessary before using or modifying this tool in real-world environments, especially when handling sensitive patient data.

**Note:** While this tool was tested and used in compliance with research protocols, any further application must adhere to ethical guidelines and institutional review board (IRB) requirements, ensuring the confidentiality and security of patient information.


## Key Features
- Automates data extraction and entry
- Implements data validation and duplicate checking
- Provides a user interface for easy data visualization and management
- Utilizes hotkeys for quick actions

## Technical Highlights
- Developed using Lua programming language
- Leverages Hammerspoon for macOS automation, with interaction through JavaScript
- Implements complex data structures and algorithms
- Includes error handling and data integrity checks
- Core code is customizable for various research studies and needs

## Core Components

The `init.lua` script serves as the central configuration file for the tool. It sets up the environment, initializes variables, and manages the activation of different automation scripts (`barrets`, `polyps`, and `polypjson`). Key functionalities include:

- Activating and deactivating scripts through the menu bar
- Emergency stop functionality to terminate all running scripts
- Error logging to track issues during script execution
- Binding hotkeys for quick access to different scripts


## Impact
- Increases efficiency and accuracy in medical record processing for research purposes
- Reduces the risk of data entry errors

## User Interface
Below are some screenshots of the tool in action:

### Polyp UI
![Main Interface](medical_data_tool_interface.png)

### Polyp Counter UI
![Polyp Counter UI](polyp_counter.png)

### Barrett's UI
![Barrett's UI](BarrretsUI.png)
