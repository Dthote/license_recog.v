# FPGA-Based License Plate Recognition

## Project Overview
This project explores automatic vehicle license plate recognition using **Verilog HDL and Python**, targeting the Digilent Arty A7 FPGA development board.

Python prepares the input image and generates hexadecimal pixel data, while Verilog implements the FPGA-side image-processing and character-recognition logic. The project is inspired by the FPGA4Student license plate recognition design.

## Problem Statement
Automatic License Plate Recognition (ALPR) identifies alphanumeric characters from vehicle registration plates. This project explores how image preprocessing and hardware-based processing can be combined to implement an FPGA-oriented recognition system.

## Key Features
- Python-based image preprocessing.
- Conversion of grayscale pixel data into hexadecimal memory files.
- FPGA memory initialization for stored-image processing.
- Verilog-based image processing and character-recognition architecture.
- FPGA LED output for character codes or recognition status.
- Potential UART integration for displaying complete results on a computer.

## Technologies Used
- **Verilog HDL** — FPGA hardware design.
- **Python** — Image preprocessing and memory-file generation.
- **OpenCV** — Image processing, where used.
- **NumPy** — Pixel-data manipulation, where used.
- **Xilinx Vivado** — Simulation, synthesis, implementation, and bitstream generation.
- **Digilent Arty A7-35T** — FPGA development board.
- **Git and GitHub** — Version control and project hosting.

## System Architecture

```text
Input Plate Image
       |
       v
Python Image Preprocessing
       |
       v
Hexadecimal Pixel File (.mem)
       |
       v
FPGA Memory (BRAM)
       |
       v
Verilog Image Processing
       |
       v
Character Recognition Logic
       |
       v
Character Codes / Status
       |
       v
FPGA LEDs or UART-to-PC Output
```

### Component Interaction
1. **Python:** Loads and preprocesses the input image, then converts pixel values into hexadecimal data.
2. **Memory file:** Stores the prepared pixel values in a format suitable for FPGA memory initialization.
3. **FPGA memory:** Supplies stored image pixels to the Verilog processing logic.
4. **Verilog modules:** Process the image and generate character codes using the implemented recognition algorithm.
5. **Output interface:** LEDs can represent binary character codes or status. UART can transfer readable recognition results to a PC if the communication interface is implemented.

## Setup and Usage

### Prerequisites
- Windows or Linux computer.
- Python 3.
- Xilinx Vivado with Artix-7 device support.
- Digilent Arty A7-35T board for hardware testing.
- Required Python libraries for the implemented preprocessing scripts.

### 1. Clone the Repository

```bash
git clone <YOUR_REPOSITORY_URL>
cd license_recog
```

Replace the placeholder with your actual GitHub repository URL.

### 2. Install Python Dependencies

If a `requirements.txt` file is provided:

```bash
python -m venv .venv
```

On Windows:

```powershell
.venv\Scripts\activate
pip install -r requirements.txt
```

### 3. Prepare the Input Image
Place a test license plate image in the configured input directory and run the Python preprocessing script.

Example command, if the script uses these arguments:

```bash
python preprocess_image.py --input data/plate.png
```

Adjust the filename and arguments to match the actual script.

### 4. Generate FPGA Memory Data
Convert the preprocessed image into a hexadecimal memory initialization file, such as `plate.mem`. Ensure its pixel dimensions and data format match the Verilog memory configuration.

### 5. Run the FPGA Design
1. Open the Vivado project.
2. Add the Verilog source files and the Arty A7 constraints file.
3. Ensure the memory initialization file is included and accessible.
4. Run behavioral simulation.
5. Run synthesis and implementation.
6. Generate the bitstream and program the FPGA board.

### 6. View the Output
Observe the configured LED output on the FPGA board. If UART transmission and the Python serial receiver are implemented, connect to the configured serial port to display the complete recognized registration string.

## Known Limitations
- The design targets stored images; live-camera processing requires additional hardware and data-transfer logic.
- Recognition accuracy depends on the implemented character-recognition algorithm.
- Input dimensions and pixel formats must match the FPGA memory configuration.
- Arbitrary image orientation is not guaranteed unless rotation handling is implemented.
- LEDs represent binary codes or status rather than displaying complete text.
- PC-based output requires a functioning UART interface if it is not already integrated.

## Future Improvements
- Add or improve UART-based result display.
- Improve character segmentation and recognition accuracy.
- Support rotated and skewed plate images.
- Evaluate performance using a larger test-image dataset.
- Optimize FPGA resource utilization and processing latency.
- Explore real-time camera input.

## Reference
FPGA4Student — [License Plate Recognition using Verilog and MATLAB](https://www.fpga4student.com/2016/11/plate-license-recognition-verilogmatlab.html)

The reference design uses a Xilinx Spartan-6 platform. Adaptation to the Arty A7 requires appropriate changes and verification.

## Project Status
**Status: In Progress**

The project focuses on integrating Python-based image preparation with Verilog-based FPGA processing. Features should be marked complete only after their implementation and testing have been verified.
