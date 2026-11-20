function test_analysis()
%TEST_ANALYSIS  End-to-end checks of st_analyze with the trained model.
cfg = st_config();
s = load(cfg.modelFile); model = s.model;
recs = ds_list_records(cfg);
pick = @(nm) recs(strcmp({recs.name}, nm));

% 1) same recording through the WAV path (2 kHz) and the device path
%    (ESP32 ADC counts at 4 kHz, via the serial text format) agrees
r = pick('a0005');
[x, fs] = st_read_audio(r.wav);
R1 = st_analyze(x, fs, model, cfg, false);
dev = st_device_sim(x, fs, 1, floor(numel(x)/fs*cfg.fsDevice) - 10, cfg);
[counts, ~, ~] = st_serial_parse('', dev);
R2 = st_analyze(counts, cfg.fsDevice, model, cfg, true);
fprintf('a0005 (label %d): WAV %s %.0f%% hr %.1f | device %s %.0f%% hr %.1f\n', r.label, ...
    R1.label, 100*R1.confidence, R1.hr, R2.label, 100*R2.confidence, R2.hr);
assert(strcmp(R1.label, R2.label), 'device path changes the result');
assert(abs(R1.hr - R2.hr) < 3, 'device path changes the heart rate');
assert(numel(R1.s1) == R1.nCycles && R1.sysMs > 150 && R1.sysMs < 500, 'intervals');

% 2) a few normal and abnormal recordings give sensible output
names = {'a0001', 'a0007', 'b0001', 'e00001', 'f0001'};
for i = 1:numel(names)
    r = pick(names{i});
    [x, fs] = st_read_audio(r.wav);
    R = st_analyze(x, fs, model, cfg, false);
    fprintf('%-7s label %d -> %-12s conf %5.1f%%  hr %5.1f  sys %4.0f ms  dia %4.0f ms  cycles %d\n', ...
        r.name, r.label, R.label, 100*R.confidence, R.hr, R.sysMs, R.diaMs, R.nCycles);
    assert(any(strcmp(R.status, {'ok', 'poor'})), 'status');
end

% 3) clipping ADC data is reported as poor quality with the gain advice
xc = min(max(2048 + 4*(counts - 2048), 0), 4095);   % gain 4x too high
Rc = st_analyze(xc, cfg.fsDevice, model, cfg, true);
assert(strcmp(Rc.status, 'poor') && ~isempty(strfind(Rc.reason, 'clipping')), 'clipping');

% 4) too-short recording
Rs = st_analyze(counts(1:3*cfg.fsDevice), cfg.fsDevice, model, cfg, true);
assert(strcmp(Rs.status, 'short'), 'short clip');

% 5) pure noise (no heart) is not classified
randn('seed', 3); %#ok<RAND>
Rn = st_analyze(2048 + 20*randn(20*cfg.fsDevice, 1), cfg.fsDevice, model, cfg, true);
fprintf('noise only -> %s (%s)\n', Rn.label, Rn.reason);
assert(strcmp(Rn.status, 'poor'), 'noise should be poor quality');
fprintf('test_analysis: all checks passed\n');
end
