function test_live_pipeline()
%TEST_LIVE_PIPELINE  Simulated ESP32 stream -> parser -> live filter -> HR.
cfg = st_config();
recs = ds_list_records(cfg);
r = recs(strcmp({recs.name}, 'a0005'));
[x, fs] = st_read_audio(r.wav);
nDev = 12 * cfg.fsDevice;                         % 12 s of device data
text = [sprintf('ets Jul 29 2019\xff\xfe\n# Digital Stethoscope ESP32 firmware v1.1\n# OK  bias is correct\n'), ...
        st_device_sim(x, fs, 1, nDev, cfg)];
% insert a status line in the middle, as the firmware does after 'c'
cut = find(text == 10, 1, 'first') + 5000;
cut = cut + find(text(cut:end) == 10, 1) - 1;
text = [text(1:cut), sprintf('# CHECK  mean 1650 mV\n'), text(cut+1:end)];

L = st_live_init(cfg);
carry = ''; allCounts = []; status = {};
pos = 1; chunkSizes = [37 1200 813 2900 5 4096];   % uneven serial reads
k = 0;
while pos <= numel(text)
    k = k + 1;
    n = chunkSizes(mod(k - 1, numel(chunkSizes)) + 1);
    chunk = text(pos:min(end, pos + n - 1));
    pos = pos + n;
    [s, st, carry] = st_serial_parse(carry, chunk);
    status = [status; st]; %#ok<AGROW>
    allCounts = [allCounts; s]; %#ok<AGROW>
    L = st_live_push(L, s);
end
assert(numel(allCounts) == nDev, sprintf('lost samples: %d of %d', numel(allCounts), nDev));
assert(numel(status) == 3, 'status lines');
ref = st_device_sim(x, fs, 1, nDev, cfg);
assert(isequal(allCounts, sscanf(ref, '%d')), 'sample values changed');

% live buffer equals one-shot causal filtering + decimation
y = st_sosfilt(L.sos, allCounts * L.mvPerCount, st_sos_zi(L.sos) * allCounts(1) * L.mvPerCount);
y = y(1:2:end);
assert(max(abs(L.buf - y(end - L.nBuf + 1:end))) < 1e-9, 'live buffer mismatch');

% live heart rate vs offline analysis of the same audio
xd2 = y(end - 8*cfg.fs + 1:end);
[hrLive, ok] = st_live_hr(xd2, cfg);
xa = st_preprocess(x, fs, cfg);
hrOff = st_heart_rate(xa, cfg.fs, cfg);
fprintf('live HR %.1f bpm (ok=%d), offline HR %.1f bpm\n', hrLive, ok, hrOff);
assert(ok && abs(hrLive - hrOff) < 5, 'live heart rate');

[S, f, t] = st_spectrogram(L.buf, cfg.fs, cfg.specWin, cfg.specHop, cfg.specMaxHz);
assert(size(S, 1) == numel(f) && size(S, 2) == numel(t) && f(end) <= 500, 'spectrogram');
[tt, yy] = st_minmax_decimate(L.buf, cfg.fs, 1000);
assert(numel(tt) == numel(yy) && max(yy) == max(L.buf) && tt(end) <= 0, 'minmax');
fprintf('test_live_pipeline: all checks passed (%d samples, %d chunks)\n', nDev, k);
end
