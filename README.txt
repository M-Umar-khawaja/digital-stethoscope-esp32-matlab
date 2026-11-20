=====================================================================
  DIGITAL STETHOSCOPE WITH HEART SOUND ANALYSIS  -  HOW TO RUN
=====================================================================

WHAT YOU NEED
  - MATLAB R2024b (no extra toolboxes are needed)
  - The stethoscope hardware (ESP32 board with microphone), USB cable
    The ESP32 already has its program loaded. Nothing to install on it.

---------------------------------------------------------------------
STEP 1  Open the project
---------------------------------------------------------------------
  1. Copy this whole folder to your computer (for example to Desktop).
  2. Open MATLAB.
  3. In MATLAB: HOME tab -> Open -> choose  START.m  in this folder.
  4. Press the green  Run  button (or press F5).
     -> The "Digital Stethoscope" window opens.

     (If MATLAB asks "Change Folder" or "Add to Path", click
      "Change Folder".)

---------------------------------------------------------------------
STEP 2  Try it without hardware (demo)
---------------------------------------------------------------------
  1. In the window, top: Port  ->  choose  "Simulated device".
  2. Click  Connect.  You see a real heart sound moving live.
     After about three seconds, Cue: Beat plays a synthesized chime
     when the software detects a beat. Use the Cue menu in the heart
     rate tile for Lub-dub or Off. Play still plays the recorded clip.
  3. Click  Record 20 s.  Wait 20 seconds.
  4. The result appears on the right: heart rate, Normal / Abnormal,
     and S1 (blue) / S2 (pink) marked on the recording.
  5. Click  Disconnect  when done.

---------------------------------------------------------------------
STEP 3  Use the real stethoscope
---------------------------------------------------------------------
  1. Plug the ESP32 into the laptop with the USB cable.
  2. In the window: Port -> click the refresh button (circle arrow),
     then choose the COM port (for example COM3).  Click  Connect.
     "Wiring: OK" should turn green.
  3. Turn the round chest piece so the big flat side (diaphragm) is
     active (it clicks).
  4. Press the chest piece firmly on bare skin, left chest, just below
     the nipple. Quiet room, no talking, keep your hand still.
  5. Wait until  LEVEL  (above the live wave) says  Good  and a heart
     rate number appears.
  6. Click  Record 20 s  and hold still for 20 seconds.
  7. Read the result. Click  Play  to listen,  Save  to keep it.

  LEVEL says "Too loud":  hold still; if it stays, turn the small
                           screw on the microphone board a little.
  LEVEL says "Too weak":  press the chest piece more firmly.
  Result "Poor quality":  the reason is shown; try again.

---------------------------------------------------------------------
STEP 4  Analyse a saved sound file
---------------------------------------------------------------------
  Click  Open file  and choose a file from  4_Example_Heart_Sounds
  (Normal_1, Abnormal_1, ...). The result appears in about 1 second.

---------------------------------------------------------------------
WHAT IS IN THIS FOLDER
---------------------------------------------------------------------
  START.m                    <- open this and press Run
  README.txt                 <- this file
  1_Software                 MATLAB program (do not rename or move files)
  2_Firmware_ESP32           ESP32 program (already loaded on the board)
  3_Diagrams_and_Documents   circuit, wiring, block diagram, proposal,
                             software design and results
  4_Example_Heart_Sounds     normal and abnormal heart sounds to open
  data                       files the program needs (do not delete)

  Saved recordings go to  1_Software/recordings.

---------------------------------------------------------------------
PROBLEMS?
---------------------------------------------------------------------
  No COM port in the list   Use a USB DATA cable (not charge-only).
                            Windows may need the "CH340" USB driver.
                            Then click the refresh button.
  "Could not open COM..."   Close Arduino IDE / Serial Monitor.
  Wiring: FAIL              Check the 3 microphone wires (see
                            3_Diagrams_and_Documents/Circuit_and_Wiring...).
  Nothing happens on Run    Make sure the file you ran is START.m in
                            this folder.

  Screening aid only - not a medical diagnosis.
=====================================================================
