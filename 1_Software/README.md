# Digital Stethoscope – MATLAB software

Software side of the FYP *Digital Stethoscope with Heart Sound Analysis*:
ESP32 + GY-MAX4466 → USB serial → MATLAB dashboard with live waveform,
live spectrogram, heart rate, 20 s recording, S1/S2 detection,
systole/diastole intervals, signal-quality check and a normal/abnormal
screening result (SVM trained on PhysioNet/CinC 2016 and CirCor 2022).

## 1. Start it

1. Install **MATLAB R2024b**. No toolboxes are needed: the filters, the
   segmentation and the SVM are implemented in this project.
2. Upload `firmware/stethoscope_esp32/stethoscope_esp32.ino` to the ESP32
   (see the hardware build sheet), and close the Arduino Serial Monitor.
3. In MATLAB, open this `software` folder and type:

   ```matlab
   run_stethoscope
   ```

4. Pick the ESP32's COM port and press **Connect**.
   *No hardware yet?* Pick **Simulated device**: it streams a real PhysioNet
   heart recording exactly like the ESP32 does.

   Use the **Cue** menu in the heart-rate tile during live acquisition.
   **Beat** plays one synthesized chime at the detected beat onset.
   **Lub-dub** adds a softer, higher tone when a second sound is detected.
   **Off** mutes the cue. Allow about three seconds for detector warm-up.
   The cue uses the computer's audio output and is separate from Play and
   the saved WAV data.

## 2. Using the dashboard

| Area | What it shows |
|---|---|
| Header | COM port, connection lamp, wiring check from the ESP32 (`OK` / `FAIL`) |
| Live heart sound | Last 5 s, filtered 20–500 Hz with the 50 Hz hum notched out, in mV |
| Live spectrogram | Same 5 s, 0–500 Hz. S1/S2 appear as bright vertical bands |
| Recording | The 20 s clip after analysis, S1 shaded blue and S2 pink (zoom with the mouse) |
| Heart rate | Live value (last 8 s) while placing the chest piece; the recording's value after analysis |
| Screening result | **Normal** (green), **Abnormal** (amber), or **Poor quality – retry** (cyan), with confidence |
| Intervals | S1→S2 (systole) and S2→S1 (diastole), median ± SD, number of cycles |
| Buttons | **Record 20 s** (press again to stop early), **Play**, **Save**, **Open file** |

**Workflow:** connect → press the chest piece firmly on bare skin (lower left
chest, apex) in a quiet room → wait until the heart rate shows a number →
**Record** → hold still for 20 s → result appears in about 1 s.

**Save** writes four files to `software/recordings/`:
- `_raw.wav`: 4 kHz, the original signal; open it again with **Open file**.
- `_filtered.wav`: 2 kHz, for listening.
- `_result.mat`: every number shown.
- `_screen.png`: a picture of the dashboard, for the report.

**Open file** analyses any WAV, for example PhysioNet recordings from
`data/physionet2016/training-*/`. This is handy for showing an abnormal
example in the viva.

## 3. How the analysis works

```
raw ADC (4 kHz) ─► resample to 2 kHz ─► 50/100/150/200/250 Hz notches
   ├─► 20–500 Hz band-pass  ─► display, playback, saved WAV
   └─► 25–400 Hz band-pass ─► spike removal ─► normalise
          ├─► heart rate + systole time  (autocorrelation of homomorphic envelope)
          ├─► 4 envelope features at 50 Hz ─► logistic-regression HSMM (Springer 2016)
          │       ─► S1 / systole / S2 / diastole for every sample
          ├─► quality check (5 features, logistic model) ─► "Poor quality" or continue
          └─► 124 features (Potes 2016: timing, band power, MFCC per state)
                  ─► RBF SVM (class-weighted) ─► Platt scaling ─► Normal/Abnormal + confidence
```

All filters are zero-phase Butterworth filters (designed by `st_butter_sos`, applied
forwards and backwards), so S1/S2 timing is not shifted. The live view uses
the same filters run causally, chunk by chunk.

## 4. Results

Training data: **6130 recordings** from two public datasets.
- **PhysioNet/CinC 2016:** 3240 recordings, adults and children, six databases recorded with different stethoscopes. "Abnormal" means a confirmed heart condition.
- **CirCor DigiScope 2022:** 2890 recordings from 816 children, 4 kHz like our ESP32. "Abnormal" means a murmur heard at that chest site.

Every recording also had one **simulated-sensor copy** in training (`st_augment`):
- a different bass cut and treble roll-off;
- tone bumps;
- an ESP32-style 12-bit ADC;
- mains hum and noise.

This teaches the model to ignore the microphone.

| Part | Result | How it was tested |
|---|---|---|
| S1/S2 detection | F1 91.6% | 236 hand-annotated recordings (both datasets) never used for training, 60 ms tolerance |
| Heart rate | mean error 4.1 bpm, within 5 bpm on 91% | same recordings vs. hand annotations |
| Normal/abnormal, all data | **sensitivity 82.4%, specificity 85.5%, balanced accuracy 84.0%** | 5-fold cross-validation, all recordings of one patient in one fold |
| – PhysioNet 2016 part | sensitivity 91.6%, specificity 83.8%, balanced 87.7% | same |
| – CirCor part (children, murmurs) | sensitivity 71.9%, specificity 87.7%, balanced 79.8% | same |
| Different microphone only (simulated) | balanced 81.8% (−2.1 points) | same patients, test clips through a simulated different sensor |
| **Own device (ESP32 + MAX4466)** | balanced 65.5% (Se 47%, Sp 84%); own heart called Normal in 83% | 42 device clips, threshold 0.80 chosen leave-one-person-out |
| Quality check | flags 40% of PhysioNet's "unusable" clips, accepts 95% of good ones | rule checks (clipping, too few beats, implausible heart rate) come first |
| Different dataset entirely | balanced 56–58% | train on one dataset/database, test on another |

Full numbers: `models/training_report.txt`.

**What this means for your device.** The different-microphone test is the
one that matches your situation: your device changes the sensor, not the
patients. With the simulated-sensor training, a new microphone costs about
2 points. Without it, the cost was 4.5 points
(`scripts/experiment_sensor_shift.m`).

The "different dataset" test scores much lower because the datasets differ
in more than the sensor:
- different patients (children vs adults);
- different meanings of "abnormal" (murmur vs diagnosis).

A model trained only on murmurs finds just 15% of PhysioNet's abnormal
cases, because many of them have no audible murmur. That is a limit of
what a heart sound can show, not of the microphone.

**Calibrate with your own device** to confirm and improve real-world accuracy:

1. **Earbud playback** (`calib_playback`): wired earphones in the laptop,
   one earbud pressed flat onto the diaphragm. `calib_playback('test')`
   checks the level, then `calib_playback('run')` plays 20 normal and 20
   abnormal public recordings (40 different patients) and records them
   with the ESP32 (about 12 minutes). Normal and abnormal go through the
   same earbud, so the model cannot learn "earbud = abnormal".
2. **Your own heart** (`calib_self`): 4 chest positions × 3 conditions
   (resting, breath held, after exercise), 15 s each, saved as normal.
3. Optional: more people with the dashboard's **Save**, copied into
   `data/device_recordings/normal/` or `.../abnormal/`. Name files
   `<person>__anything.wav` so one person's clips stay together.
4. Run `train_classifier` (about 5 minutes). Device recordings count 10×.
   The report then shows a separate "own device" score.

The **LEVEL** indicator above the live trace shows *Good*, *Too weak* or
*Too loud* from the last 2 s of raw signal: set the gain until it shows
Good with the chest piece in place, then record.

**Calibration done (2026-11-18):** 30 public recordings played through an
earbud onto the diaphragm (each checked to really carry the played
heartbeats; 16 noise-only clips were rejected) and 12 recordings of one
healthy heart (4 positions × rest / breath-hold / after exercise). The real
sensor makes hearts look more "abnormal" (public model: 67% on device copies
vs 83% on their originals), so ESP32 input uses its own decision threshold
(p ≥ 0.80, stored in the model). Device signal quality uses rule checks plus
a spikiness test (log kurtosis ≥ 1.25), because the PhysioNet-trained quality
model could not tell good device clips from noise. The public-only model is
kept in `models/steth_model_public_only.mat`.

State it this way in the viva: validated on two public datasets
(6130 recordings) with patient-grouped testing; screening aid, not a
diagnosis.

## 5. Folders

| Folder | Contents |
|---|---|
| `run_stethoscope.m` | Start here |
| `StethoscopeApp.m` | The dashboard |
| `core/` | All signal processing and machine learning (`st_*.m`), toolbox-free |
| `scripts/` | Dataset tools and training: `train_all.m` rebuilds every model (about 1 hour) |
| `models/` | `steth_model.mat` (used by the app), `training_report.txt` (accuracy figures) |
| `tests/` | `run_tests` runs every automatic check |
| `../data/physionet2016/`, `../data/circor/` | PhysioNet 2016 and CirCor 2022 training data and annotations |

## 6. Checks

```matlab
addpath core scripts tests
run_tests
```

This checks:
- The filters against MATLAB reference values.
- The SVM solver against a general quadratic-programming solver.
- The serial parser, using boot garbage, status lines and split lines.
- The live path against offline filtering.
- The full analysis, comparing a WAV against the same audio sent as ESP32 ADC counts, plus clipping, too-short and noise-only cases.

`test_dashboard` (or `test_dashboard('COM3')` with the ESP32) opens the
dashboard and presses the buttons itself: Connect, 20 s Record, Play, Save.

## 7. If something goes wrong

| Problem | Fix |
|---|---|
| COM port not listed | Data cable (not charge-only), CH340/CP210x driver, then the refresh button |
| "Could not open COMx" | Close Arduino Serial Monitor/Plotter, since only one program can use the port |
| "No data – check cable / firmware" | Re-upload the firmware; check the baud rate is 921600 in both |
| Wiring: FAIL | Message says which wire; see the build sheet |
| Heart rate stays "--" | Press harder, check the tube joint is airtight, turn the gain up, quiet room |
| Result "Poor quality" | The reason is shown; usually movement, talking, or the gain is too low or high |
| "Model missing" | `models/steth_model.mat` was deleted; run `scripts/train_all.m` |

*Screening aid only, not a diagnostic device.*
