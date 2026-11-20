function calib_playback(mode, port, nPerClass, seconds)
%CALIB_PLAYBACK  Records public heart sounds through the real device.
%   Plays PhysioNet 2016 / CirCor 2022 recordings (normal AND abnormal)
%   through earphones whose earbud is held against the stethoscope
%   diaphragm, records them with the ESP32 and saves them, labelled, to
%   data/device_recordings/{normal,abnormal}. train_classifier then learns
%   what heart sounds look like after passing through OUR sensor.
%
%   calib_playback('list')           shows which recordings would be played
%   calib_playback('test')           plays one clip, reports the level
%   calib_playback('run')            20 normal + 20 abnormal, 15 s each (~12 min)
%   calib_playback('run', 'COM3', 25, 15)
%
%   Both classes go through the same earbud on purpose: the model must not
%   be able to tell normal from abnormal by "earbud vs chest".
%   Files are named <patient group>__pb_<record>.wav so that training keeps
%   each patient's original and device copy in the same test fold.
%   Already recorded clips are skipped, so an interrupted run can resume.
if nargin < 1, mode = 'test'; end
if nargin < 2, port = 'COM3'; end
if nargin < 3, nPerClass = 30; end
if nargin < 4, seconds = 15; end
here = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(here, 'core'), fullfile(here, 'scripts'));
cfg = st_config();
outBase = fullfile(fileparts(cfg.dataDir), 'device_recordings');

sel = local_select(cfg, nPerClass, seconds);
if strcmp(mode, 'list')
    for r = sel, fprintf('%-12s db %s  label %d  group %s\n', r.name, r.db, r.label, r.group); end
    fprintf('%d abnormal, %d normal, %d patients\n', sum([sel.label] == 1), sum([sel.label] == 0), ...
        numel(unique({sel.group})));
    return;
end
if strcmp(mode, 'test')
    sel = sel(find([sel.label] == 1 & [sel.db] == 'g', 1));   % CirCor: plays well through earbuds
    fprintf('TEST: playing %s (abnormal) for %d s\n', sel.name, seconds);
end

s = serialport(port, cfg.baud, 'Timeout', 1);
cleanup = onCleanup(@() delete(s));
pause(0.5); write(s, 'r', 'char'); pause(0.2);

fsPlay = 8000;
outId = -1;                                    % Windows default output
d = audiodevinfo;
k = find(contains({d.output.Name}, 'Headphone', 'IgnoreCase', true), 1);
if ~isempty(k)
    outId = d.output(k).ID;
    fprintf('audio output: %s\n', d.output(k).Name);
end
nOk = 0; nBad = 0;
for i = 1:numel(sel)
    r = sel(i);
    cls = 'normal'; if r.label == 1, cls = 'abnormal'; end
    out = fullfile(outBase, cls, sprintf('%s__pb_%s.wav', r.group, r.name));
    if strcmp(mode, 'run') && exist(out, 'file') == 2
        fprintf('[%2d/%d] %s already recorded, skipped\n', i, numel(sel), r.name);
        continue;
    end
    [x, fs] = st_read_audio(r.wav);
    x = x(round(fs) + 1:min(end, round(fs*(seconds + 1.5))));     % skip the first second
    x = x - mean(x);
    xSrc = x;                                       % what was played, for the content check
    a = sort(abs(x)); x = x / max(a(ceil(0.99*end)), eps);
    x = tanh(1.5*x) / tanh(1.5);                    % gentle compression: louder on average, no hard clipping
    t = (0:numel(x)-1).' / fs;
    y = interp1(t, x, (0:1/fsPlay:t(end)).', 'linear');
    player = audioplayer(y, fsPlay, 16, outId);
    [~, floorMv] = st_level(dev_capture(s, 1.5, cfg), cfg);         % room silence before the clip
    raw = dev_capture(s, seconds, cfg, @() play(player));
    stop(player);
    raw = raw(round(0.3*cfg.fsDevice) + 1:end);                    % playback start-up delay
    [state, p99, clip] = st_level(raw, cfg);
    % keep a clip only if it really carries the played heartbeats: a loud
    % clip can be pure handling or room noise (seen 2026-11-17)
    match = dev_match(raw, cfg.fsDevice, xSrc, fs, cfg);
    if strcmp(state, 'loud')
        verdict = 'loud';
    elseif match >= 0.4
        verdict = 'good';
    else
        verdict = 'nomatch';
    end
    fprintf('[%2d/%d] %-9s %-10s level %4.0f mV (silence %3.0f)  clip %.3f%%  match %.2f', i, numel(sel), ...
        cls, r.name, p99, floorMv, 100*clip, match);
    if strcmp(mode, 'test')
        fprintf('\n');
        local_advice(verdict);
        return;
    end
    if strcmp(verdict, 'good')
        if exist(fileparts(out), 'dir') ~= 7, mkdir(fileparts(out)); end
        audiowrite(out, max(-1, min(1, (raw - 2048)/2048)), cfg.fsDevice);
        nOk = nOk + 1; fprintf('  saved\n');
    else
        nBad = nBad + 1; fprintf('  NOT saved\n');
        if nBad >= 3 && nOk == 0
            fprintf('\nThree clips in a row failed (%s). Stopping.\n', verdict);
            local_advice(verdict);
            return;
        end
    end
end
fprintf('\nDone: %d saved, %d not saved. Next: run train_classifier.\n', nOk, nBad);
end

% -------------------------------------------------------------------------
function sel = local_select(cfg, nPerClass, seconds)
% Good-quality recordings long enough, at most one per patient, half from
% each dataset, fixed random choice (repeatable).
recs = ds_all_records(cfg);
s = load(fullfile(cfg.root, 'models', 'feature_table.mat'));
okNames = s.T.recordNames(s.T.quality == 1 & all(isfinite(s.T.X), 2));
recs = recs(ismember({recs.name}, okNames));
rng(7);
sel = recs([]);
for lab = [1 0]
    for isCc = [false true]
        m = find([recs.label] == lab & ([recs.db] == 'g') == isCc);
        m = m(randperm(numel(m)));
        want = ceil(nPerClass/2); if isCc, want = nPerClass - ceil(nPerClass/2); end
        got = {};
        for k = m
            if numel(got) >= want, break; end
            if any(strcmp(got, recs(k).group)), continue; end
            info = audioinfo(recs(k).wav);
            if info.Duration < seconds + 1.5, continue; end
            got{end+1} = recs(k).group; %#ok<AGROW>
            sel(end+1) = recs(k); %#ok<AGROW>
        end
    end
end
sel = sel(randperm(numel(sel)));      % mix normal and abnormal
end

function local_advice(state)
switch state
    case 'good', fprintf('GOOD: the device hears the played heartbeats. Run calib_playback(''run'').\n');
    case 'nomatch', fprintf(['The device does NOT hear the played heartbeats (only noise). Press the earbud''s\n' ...
            'speaker side flat onto the centre of the diaphragm (tape it), volume 100%%, diaphragm\n' ...
            'selected on the valve, nobody touching anything.\n']);
    case 'loud', fprintf('TOO LOUD (clipping). Turn the laptop volume down a little, or hold still.\n');
    otherwise,   fprintf('No data from the ESP32.\n');
end
end
