# Digital Stethoscope: Project Specification

## 1. What this project is

A **digital stethoscope**. It replaces the listening part of a normal stethoscope with a small electronic microphone. The heart sound is sent to a laptop, where you can see it, hear it, measure the heart rate, and save it.

The main purpose is to **listen to and measure the heartbeat**, just like a normal stethoscope, but with a screen, a recording and numbers.

An **extra feature** was added: the software gives a simple screening result, *Normal* or *Abnormal*, with a confidence level. It is a helper only. It is **not a medical diagnosis**.

---

## 2. Main features (the core requirement)

| Feature | What it does |
|---|---|
| Live heart sound | Shows the heartbeat as a moving wave on the laptop, in real time |
| Live spectrogram | Shows which sound frequencies are present over time |
| Heart rate | Shows beats per minute, from the live sound and from recordings |
| Recording | Records 20 seconds of heart sound (press Record, then Stop or wait) |
| S1 / S2 marking | Marks the two heart sounds ("lub" and "dub") on the recording |
| Timing | Shows the time between the two sounds (systole and diastole) |
| Play and Save | Plays the recording through the laptop speakers and saves it as sound files, numbers and a picture |
| Open file | Opens and analyses any saved heart-sound file |
| Level meter | Shows *Good*, *Too weak* or *Too loud* while you place the chest piece, so you can adjust before recording |
| Connection check | Shows if the microphone wiring is correct |

## 3. Extra feature: screening (Normal / Abnormal)

- The software gives a **Normal** or **Abnormal** result with a confidence percentage.
- It was trained on **5,851 public heart-sound recordings** from two well-known medical datasets (PhysioNet 2016 and CirCor 2022).
- On those public recordings, it gets the right answer about **84 out of 100 times** (balanced accuracy 84%).
- On this device, with the real microphone, the result is **preliminary**: about **65%** on held-out test clips, because the microphone changes the sound. It was calibrated with 42 device clips, 12 of them from one healthy person.
- It also says **"Poor quality"** when the recording is too noisy, too short or clipped, and asks the user to try again.

## 4. Hardware (parts)

1. **Stethoscope chest piece and tube**: a normal stethoscope. The microphone sits at the end of the tube, in the diaphragm side.
2. **Microphone module (MAX4466)**: picks up the sound and amplifies it. A small screw on the board adjusts how loud it is.
3. **Small filter circuit**: one resistor (1 kΩ) and one capacitor (100 nF). It removes high-pitched noise before the signal reaches the board.
4. **ESP32 board**: a small, cheap microcontroller (about the size of a matchbox). It converts the sound into numbers, 4,000 times per second, and sends them to the laptop.
5. **USB cable**: connects the ESP32 to the laptop. It carries the data and the power.
6. **Laptop with MATLAB**: runs the dashboard.

**How the signal flows:**
Heart sound → tube → microphone → amplifier → filter → ESP32 → USB cable → laptop → dashboard (wave, heart rate, recording, result).

## 5. Software

- **Language and tool:** MATLAB, version R2024b.
- **Extra toolboxes:** none needed. The program runs on a standard MATLAB installation.
- **Main program:** a dashboard window with the wave, spectrogram, recording, heart rate, result and buttons.
- **Start:** open `START.m` and press Run.
- **Demo:** a "Simulated device" option plays a real heart sound, so the program can be tried without hardware.
- **Tests:** an automatic test suite (filters, classifier, serial data, live processing, analysis) and a dashboard test. All pass.

## 6. Results (plain summary)

| Test | Result |
|---|---|
| Finding the two heart sounds (S1 and S2) | Correct about 92% of the time (F1 91.6%) |
| Heart rate | Average error about 4 beats per minute |
| Normal / Abnormal on public recordings | About 84% balanced accuracy |
| Normal / Abnormal on this device (held-out) | About 65%, preliminary |
| Own heart at rest (calibration) | Called Normal in 83% of clips |
| Live check on a real person | Heart rate 77 beats per minute, result Normal (69% confidence) |

## 7. Limits and honest notes

- **This is not a medical device.** It is a screening aid and a learning project. It must not be used to decide on treatment.
- The Normal / Abnormal result on this device is **preliminary**. More real recordings from patients with known conditions would improve it.
- It needs a **quiet room**, **firm contact** on bare skin, and the person **keeping still**. Movement and talking make the result "Poor quality".
- It runs on **Windows** with **MATLAB R2024b**. The ESP32 may need a USB driver (CH340) the first time it is plugged in.
- Only **one program** can use the USB port at a time.

## 8. What is in the project package

```
Digital_Stethoscope_Project/
  START.m                      open and press Run
  README.txt                   simple step-by-step guide
  1_Software/                  MATLAB program and trained model
  2_Firmware_ESP32/            program for the ESP32 board (already loaded)
  3_Diagrams_and_Documents/    circuit and wiring sheet, block diagram,
                               proposal, software design, training report,
                               this specification
  4_Example_Heart_Sounds/      normal and abnormal examples to try
  data/                        small data files the program needs
```

## 9. How to run it (short)

1. Install MATLAB R2024b (no extra toolboxes needed).
2. Open `START.m` in MATLAB and press Run.
3. Choose **Simulated device** and press Connect, to try it without hardware.
4. With the real device: plug in the ESP32, choose its COM port, press Connect, place the chest piece, wait for LEVEL "Good", then press Record.

## 10. Possible future improvements

- More real patient recordings with the device, to improve the Normal / Abnormal result.
- A smaller, battery-powered version with a wireless connection instead of USB.
- A proper enclosure (case) for the electronics.
- A medical-grade review before any clinical use.

## 11. Status

- Hardware: built and working (wiring check passes, real heart sounds recorded).
- Software: complete, tested in MATLAB R2024b, including the real device.
- Package: complete and tested from a fresh MATLAB session.
