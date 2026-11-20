function y = st_augment(x, fs, seed)
%ST_AUGMENT  Makes a recording sound as if a different sensor captured it.
%   y = st_augment(x, fs, seed)   (seed makes the result repeatable)
%   Used only for training, so the classifier learns heart sounds rather
%   than the colouring of one particular stethoscope. Each call draws:
%     - a bass cut at 15-40 Hz (chest-piece coupling, MAX4466 input capacitor)
%     - a treble roll-off at 400-1600 Hz (R1/C1 filter, diaphragm, tubing)
%     - two tone bumps or dips of up to +/-6 dB between 30 and 400 Hz
%     - 12-bit ADC quantisation at a random signal level plus ADC noise
%     - 50 Hz mains hum with harmonics, and background noise (15-35 dB SNR)
%   The heart-sound timing is untouched, so all labels stay valid.

if exist('rng', 'file') || exist('rng', 'builtin')
    rng(seed);
else
    rand('seed', seed); randn('seed', seed); %#ok<RAND>
end
x = double(x(:));
x = x - mean(x);
x = x / max(std(x), eps);
n = numel(x);
u = @(a, b) a + (b - a)*rand();
logu = @(a, b) exp(u(log(a), log(b)));

sos = [st_butter_sos(randi([1 2]), u(15, 40), fs, 'high'); ...
       st_butter_sos(1, min(u(400, 1600), 0.45*fs), fs, 'low')];
for k = 1:2
    sos = [sos; local_peak(logu(30, 400), u(-6, 6), u(0.7, 2), fs)]; %#ok<AGROW>
end
y = st_sosfilt(sos, x);

% background noise (slightly pink: white noise through a gentle low-pass)
nz = st_sosfilt(st_butter_sos(1, 200, fs, 'low'), randn(n, 1)) + 0.3*randn(n, 1);
snrDb = u(15, 35);
y = y + nz * (std(y) / std(nz)) * 10^(-snrDb/20);

% mains hum
t = (0:n-1).' / fs;
hum = zeros(n, 1);
for h = 1:3
    hum = hum + rand() / h * sin(2*pi*50*h*t + 2*pi*rand());
end
y = y + hum * std(y) * u(0, 0.2);

% ADC: random level (peak 150-1500 counts), rounding, ADC noise
peakCounts = u(150, 1500);
y = y / max(abs(y)) * peakCounts;
y = round(y + u(0.5, 3)*randn(n, 1)) + 2048;
y = min(max(y, 0), 4095);
end

function s = local_peak(f0, gainDb, Q, fs)
% RBJ audio-EQ-cookbook peaking filter
A = 10^(gainDb/40);
w0 = 2*pi*f0/fs;
al = sin(w0)/(2*Q);
b = [1 + al*A, -2*cos(w0), 1 - al*A];
a = [1 + al/A, -2*cos(w0), 1 - al/A];
s = [b/a(1), a/a(1)];
end
