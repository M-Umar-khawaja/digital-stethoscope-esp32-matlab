function calib_self(port, seconds)
%CALIB_SELF  Guided recordings of your own (normal) heart with the device.
%   Run in the MATLAB Command Window:   calib_self      (or calib_self('COM3', 15))
%   4 chest positions x 3 conditions = 12 clips of 15 s. A beep starts and
%   ends each clip. Clips with a good level are saved to
%   data/device_recordings/normal as self__<position>_<condition>_<time>.wav
%   (all with the group "self", so training keeps them in one test fold).
%   Press Enter to record, s + Enter to skip a step, q + Enter to quit.
if nargin < 1, port = 'COM3'; end
if nargin < 2, seconds = 15; end
here = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(here, 'core'), fullfile(here, 'scripts'));
cfg = st_config();
outDir = fullfile(fileparts(cfg.dataDir), 'device_recordings', 'normal');
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end

pos = {'apex',   'APEX: left chest, 5th rib space, just below the left nipple'
       'llsb',   'LOWER LEFT of the breastbone, 4th rib space'
       'pulm',   'UPPER LEFT of the breastbone, 2nd rib space'
       'aortic', 'UPPER RIGHT of the breastbone, 2nd rib space'};
cond = {'rest',   'Breathe slowly and gently through your nose.'
        'hold',   'At the beep: breathe out, then hold your breath as long as is comfortable, then breathe gently.'
        'active', 'First do 20 squats or climb stairs for 1 minute (faster heart), then sit down.'};

s = serialport(port, cfg.baud, 'Timeout', 1);
cleanup = onCleanup(@() delete(s));
pause(0.5); write(s, 'r', 'char'); pause(0.2);
fprintf(['\nOWN-HEART CALIBRATION: %d clips of %d s.\n' ...
    'Diaphragm side selected, bare skin, hold the chest piece by its stem, tube hanging free,\n' ...
    'do not touch the board or wires, no talking.\n'], size(pos, 1)*size(cond, 1), seconds);
nSaved = 0;
for c = 1:size(cond, 1)
    for p = 1:size(pos, 1)
        fprintf('\n--- %s\n    %s\n', pos{p, 2}, cond{c, 2});
        while true
            a = lower(strtrim(input('    Place the chest piece, then press Enter (s = skip, q = quit): ', 's')));
            if strcmp(a, 'q'), fprintf('Stopped. %d clips saved.\n', nSaved); return; end
            if strcmp(a, 's'), break; end
            % let the hand settle after pressing Enter, then check the level
            % for 2 s (a few clipped spikes allowed here; the clip itself
            % must still pass the analysis clipping limit)
            fprintf('    hands still...\n'); pause(2);
            pre = dev_capture(s, 2, cfg);
            cPre = cfg; cPre.levelMaxClip = cfg.sqiMaxClip;
            [state, p99] = st_level(pre, cPre);
            fprintf('    level %s (%d mV)', upper(state), round(p99));
            if ~strcmp(state, 'good')
                fprintf(' - %s Try again.\n', local_tip(state));
                continue;
            end
            fprintf(' - recording %d s, hold still...\n', seconds);
            beep; raw = dev_capture(s, seconds, cfg); beep;
            [state, p99, clip] = st_level(raw, cPre);
            if ~strcmp(state, 'good')
                fprintf('    clip level %s (%d mV, clipping %.2f%%) - %s Try again.\n', ...
                    upper(state), round(p99), 100*clip, local_tip(state));
                continue;
            end
            % content check: a loud clip can be pure handling noise
            [~, xd] = st_preprocess(raw, cfg.fsDevice, cfg);
            [hr, okHr] = st_live_hr(xd(:), cfg);
            if ~okHr
                fprintf('    no clear heart rhythm in this clip (noise?) - press firmly, hold still. Try again.\n');
                continue;
            end
            fprintf('    heart rate %.0f bpm\n', hr);
            name = sprintf('self__%s_%s_%s.wav', pos{p, 1}, cond{c, 1}, datestr(now, 'yyyymmdd_HHMMSS'));
            audiowrite(fullfile(outDir, name), max(-1, min(1, (raw - 2048)/2048)), cfg.fsDevice);
            nSaved = nSaved + 1;
            fprintf('    saved %s\n', name);
            break;
        end
    end
end
fprintf('\nDone: %d clips saved to %s\n', nSaved, outDir);
end

function t = local_tip(state)
switch state
    case 'weak', t = 'Press firmer, centre the chest piece.';
    case 'loud', t = 'Hold still; if it keeps happening, lower the gain a little.';
    otherwise,   t = 'No data from the ESP32.';
end
end
