function R = st_analyze(x, fsIn, model, cfg, isAdc)
%ST_ANALYZE  Complete analysis of one recording (used by the dashboard).
%   R = st_analyze(x, fsIn, model, cfg, isAdc)
%     x     : raw recording (ESP32 ADC counts, or WAV samples)
%     fsIn  : its sample rate (4000 from the ESP32, 2000 for PhysioNet)
%     model : struct loaded from models/steth_model.mat
%     isAdc : true for ESP32 data (enables the clipping check)
%   R fields:
%     status    'ok' | 'poor' | 'short'
%     label     'Normal' | 'Abnormal' | 'Poor quality'
%     probAbn   probability of abnormal (0..1), NaN when not classified
%     confidence probability of the shown label (0..1)
%     reason    plain-language reason for a poor-quality result
%     hr, hrSd  heart rate and its beat-to-beat SD (bpm)
%     sysMs, sysSdMs, diaMs, diaSdMs   S1->S2 and S2->S1 intervals (ms)
%     nCycles   complete heart cycles found
%     xd, xa, fs  display and analysis signals at 2 kHz
%     states    S1/systole/S2/diastole per sample
%     s1, s2    sample index of the centre of every S1 and S2
%     features  1-by-124 feature row, quality 1-by-5, pPoor quality score

if nargin < 5, isAdc = false; end
R = local_empty();
x = double(x(:));
R.durationSec = numel(x) / fsIn;
if R.durationSec < cfg.minSeconds
    R.status = 'short'; R.label = 'Poor quality';
    R.reason = sprintf('Recording too short (%.1f s). Record at least %d s.', R.durationSec, cfg.minSeconds);
    return;
end
clipFrac = 0;
if isAdc
    clipFrac = mean(x <= cfg.clipLow | x >= cfg.clipHigh);
end

[xa, xd] = st_preprocess(x, fsIn, cfg);
R.xa = xa; R.xd = xd; R.fs = cfg.fs;
seg = st_segment(xa, cfg, model.seg);
R.states = seg.states;
R.nCycles = size(seg.cycles, 1);

% ---- intervals from the detected cycles
if R.nCycles >= 2
    c = seg.cycles;
    RR = (c(:, 5) - c(:, 1)) / cfg.fs;
    sys = (c(:, 3) - c(:, 1)) / cfg.fs;          % start S1 -> start S2
    dia = (c(:, 5) - c(:, 3)) / cfg.fs;          % start S2 -> next S1
    R.hr = 60 / median(RR);
    R.hrSd = std(60 ./ RR);
    R.sysMs = 1000*median(sys); R.sysSdMs = 1000*std(sys);
    R.diaMs = 1000*median(dia); R.diaSdMs = 1000*std(dia);
    R.s1 = round((c(:, 1) + c(:, 2)) / 2);
    R.s2 = round((c(:, 3) + c(:, 4)) / 2);
elseif ~isnan(seg.hr)
    R.hr = seg.hr;
end

% ---- signal quality
q = st_quality_features(xa, seg, cfg.fs);
R.quality = q;
qm = model.quality;
R.pPoor = 1 / (1 + exp(-[1, (q - qm.mu) ./ qm.sd] * qm.w));
reason = '';
if clipFrac > cfg.sqiMaxClip
    reason = 'Signal is clipping. Turn the gain screw down a little.';
elseif R.nCycles < cfg.sqiMinCycles
    reason = 'Too few clear heartbeats. Press the chest piece firmly and hold still.';
elseif isnan(R.hr) || R.hr < cfg.sqiMinHR || R.hr > cfg.sqiMaxHR
    reason = 'Heart rate could not be measured reliably. Reposition and retry.';
elseif (~isAdc || cfg.deviceQualityModel) && R.pPoor >= qm.threshold
    reason = 'Too much noise or weak heart sounds. Quiet room, firm contact, retry.';
elseif isAdc && ~cfg.deviceQualityModel && q(4) < cfg.deviceMinLogKurt   % q(4) = log kurtosis
    reason = 'Too much noise or weak heart sounds. Quiet room, firm contact, retry.';
end
if ~isempty(reason)
    R.status = 'poor'; R.label = 'Poor quality'; R.reason = reason;
    return;
end

% ---- normal / abnormal
f = st_features(xa, seg.cycles, cfg.fs);
R.features = f;
cl = model.classifier;
fs_ = (f - cl.mu) ./ cl.sd;
dv = st_svm_decision(cl.svm, fs_);
R.decision = dv;
R.probAbn = 1 / (1 + exp(-(cl.platt(1) + cl.platt(2)*dv)));
R.status = 'ok';
thr = 0.5;
if isAdc && isfield(cl, 'deviceThreshold'), thr = cl.deviceThreshold; end   % own-sensor calibration
R.threshold = thr;
% confidence: distance from the threshold, mapped back to 0.5..1
if R.probAbn >= thr
    R.label = 'Abnormal';
    R.confidence = 0.5 + 0.5*(R.probAbn - thr) / max(1 - thr, eps);
else
    R.label = 'Normal';
    R.confidence = 0.5 + 0.5*(thr - R.probAbn) / max(thr, eps);
end
end

function R = local_empty()
R = struct('status', '', 'label', '', 'probAbn', NaN, 'confidence', NaN, ...
    'reason', '', 'hr', NaN, 'hrSd', NaN, 'sysMs', NaN, 'sysSdMs', NaN, ...
    'diaMs', NaN, 'diaSdMs', NaN, 'nCycles', 0, 'xd', [], 'xa', [], 'fs', NaN, ...
    'states', [], 's1', [], 's2', [], 'features', [], 'quality', [], ...
    'pPoor', NaN, 'decision', NaN, 'durationSec', 0, 'threshold', 0.5);
end
