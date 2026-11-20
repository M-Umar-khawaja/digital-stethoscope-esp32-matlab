function test_core_dsp()
%TEST_CORE_DSP  Checks the toolbox-free filters against known values.

% 1) butter(2, 0.5) reference from MATLAB: b=[0.2929 0.5858 0.2929], a=[1 0 0.1716]
sos = st_butter_sos(2, 500, 2000, 'low');
b = sos(1, 1:3); a = sos(1, 4:6);
assert(max(abs(b - [0.292893 0.585786 0.292893])) < 1e-5, 'butter low b');
assert(max(abs(a - [1 0 0.171573])) < 1e-5, 'butter low a');

% 2) magnitude is -3.01 dB at the band edges and ~0 dB in the middle
fs = 2000;
sos = st_butter_sos(4, [25 400], fs, 'bandpass');
assert(size(sos, 1) == 4, 'bandpass sections');
H = local_resp(sos, [25 100 400 900], fs);
assert(abs(20*log10(H(1)) + 3.0103) < 0.01, 'bp low edge');
assert(abs(20*log10(H(3)) + 3.0103) < 0.01, 'bp high edge');
assert(abs(20*log10(H(2))) < 0.2, 'bp passband');
assert(20*log10(H(4)) < -25, 'bp stopband');

for t = {'high', 'stop'}
    if strcmp(t{1}, 'high'), fc = 30; else, fc = [45 55]; end
    s2 = st_butter_sos(3, fc, fs, t{1});
    Hh = local_resp(s2, [fc(1), 900], fs);
    assert(abs(20*log10(Hh(1)) + 3.0103) < 0.01, ['edge ' t{1}]);
    assert(abs(20*log10(Hh(2))) < 0.1, ['pass ' t{1}]);
end

% 3) notch: deep at 50 Hz, flat at 100 Hz
sn = st_notch_sos(50, fs, 30);
Hn = local_resp(sn, [50 100], fs);
assert(20*log10(Hn(1)) < -60 && abs(20*log10(Hn(2))) < 0.1, 'notch');

% 4) zero-phase: a filtered in-band sine keeps its phase
t = (0:1/fs:2).';
x = sin(2*pi*60*t);
y = st_sosfiltfilt(sos, x);
mid = 500:3500;
assert(max(abs(y(mid) - x(mid))) < 0.02, 'filtfilt zero phase');

% 5) live filter in chunks equals one-shot filtering
[y1] = st_sosfilt(sos, x);
zi = []; y2 = [];
for k = 1:400:numel(x)
    seg = x(k:min(k+399, end));
    [yy, zi] = st_sosfilt(sos, seg, zi);
    y2 = [y2; yy]; %#ok<AGROW>
end
assert(max(abs(y1 - y2)) < 1e-12, 'chunked filtering');

% 6) resample 4000 -> 2000 keeps a 100 Hz tone and removes 1500 Hz
t4 = (0:1/4000:1).';
x4 = sin(2*pi*100*t4) + sin(2*pi*1500*t4);
y4 = st_resample(x4, 4000, 2000);
ref = sin(2*pi*100*(0:numel(y4)-1).'/2000);
assert(max(abs(y4(200:end-200) - ref(200:end-200))) < 0.02, 'resample');

% 7) Hilbert envelope of a pure tone is ~1
e = abs(st_hilbert(sin(2*pi*50*t)));
assert(max(abs(e(200:end-200) - 1)) < 0.01, 'hilbert');

% 8) serial parser: partial lines, status lines, boot garbage
[s1, st1, c] = st_serial_parse('', sprintf('ets Jun  8 2016\xff\n# OK  bias\r\n2048\n20'));
assert(isequal(s1, 2048) && numel(st1) == 1 && strcmp(c, '20'), 'parse 1');
[s2, ~, c] = st_serial_parse(c, sprintf('49\n0\n4095\n5000\n'));
assert(isequal(s2(:).', [2049 0 4095]) && isempty(c), 'parse 2');
fprintf('test_core_dsp: all 8 checks passed\n');
end

function H = local_resp(sos, f, fs)
z = exp(1i*2*pi*f(:)/fs);
H = ones(size(z));
for k = 1:size(sos, 1)
    H = H .* polyval(sos(k, 1:3), z) ./ polyval(sos(k, 4:6), z);
    % polyval on [b0 b1 b2] evaluates b0 z^2 + b1 z + b2: same ratio as z^-k form
end
H = abs(H);
end
