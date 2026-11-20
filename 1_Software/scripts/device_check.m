function R = device_check(port, seconds)
%DEVICE_CHECK  Wiring check + one recording from the real ESP32, with numbers.
%   R = device_check('COM3', 20)
%   Prints the firmware wiring check, the signal level (how much of the ADC
%   range is used, clipping), then analyses the clip exactly like the
%   dashboard. Saves the raw WAV and a picture to software/recordings.
if nargin < 1, port = 'COM3'; end
if nargin < 2, seconds = 20; end
here = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(here, 'core'));
cfg = st_config();
s = serialport(port, cfg.baud, 'Timeout', 1);
cleanup = onCleanup(@() delete(s));
pause(0.5); flush(s);
write(s, 'c', 'char'); pause(1.6);
[~, st] = st_serial_parse('', read(s, s.NumBytesAvailable, 'char'));
fprintf('%s\n', st{startsWith(st, {'# CHECK', '# OK', '# FAIL', '# WARN', '# GAIN'})});
write(s, 'r', 'char'); flush(s);
fprintf('recording %d s ...\n', seconds);
need = seconds*cfg.fsDevice; raw = zeros(need, 1); n = 0; carry = '';
t = tic;
while n < need && toc(t) < seconds + 5
    pause(0.05);
    k = s.NumBytesAvailable;
    if k > 0
        [c, ~, carry] = st_serial_parse(carry, read(s, k, 'char'));
        m = min(numel(c), need - n); raw(n+1:n+m) = c(1:m); n = n + m;
    end
end
raw = raw(1:n);
fprintf('got %d samples (%.1f s)\n', n, n/cfg.fsDevice);
mv = raw*3300/4095;
fprintf('ADC: mean %.0f mV, p-p %.0f mV, 1st-99th pct %.0f..%.0f mV, clipped %.3f%%\n', ...
    mean(mv), max(mv) - min(mv), prctile(mv, 1), prctile(mv, 99), 100*mean(raw <= 5 | raw >= 4090));
s1 = load(cfg.modelFile);
R = st_analyze(raw, cfg.fsDevice, s1.model, cfg, true);
fprintf('status %s | %s %.0f%% | HR %.1f | sys %.0f dia %.0f ms | cycles %d | %s\n', ...
    R.status, R.label, 100*R.confidence, R.hr, R.sysMs, R.diaMs, R.nCycles, R.reason);
if exist(cfg.saveDir, 'dir') ~= 7, mkdir(cfg.saveDir); end
base = fullfile(cfg.saveDir, ['device_' datestr(now, 'yyyymmdd_HHMMSS')]);
audiowrite([base '_raw.wav'], max(-1, min(1, (raw - 2048)/2048)), cfg.fsDevice);
f = figure('Visible', 'off', 'Position', [0 0 1400 700]);
tr = (0:n-1)/cfg.fsDevice;
subplot(3, 1, 1); plot(tr, mv); ylabel('raw mV'); title('Raw ADC input'); xlim([0 tr(end)]);
if ~isempty(R.xd)
    td = (0:numel(R.xd)-1)/R.fs;
    subplot(3, 1, 2); plot(td, R.xd); hold on;
    plot(td, 0.9*(R.states == 1), 'b'); plot(td, 0.9*(R.states == 3), 'm');
    ylabel('filtered'); title('Filtered 20-500 Hz, S1 blue / S2 magenta'); xlim([0 td(end)]);
    subplot(3, 1, 3); i0 = find(td >= min(4, td(end)/2), 1);
    w = i0:min(numel(td), i0 + 3*R.fs); plot(td(w), R.xd(w)); hold on;
    plot(td(w), 0.9*(R.states(w) == 1), 'b'); plot(td(w), 0.9*(R.states(w) == 3), 'm');
    xlabel('seconds'); title('3 s zoom'); xlim(td(w([1 end])));
end
exportgraphics(f, [base '_check.png']); close(f);
fprintf('saved %s_raw.wav and _check.png\n', base);
end
