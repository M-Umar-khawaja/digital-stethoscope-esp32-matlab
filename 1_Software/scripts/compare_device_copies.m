function compare_device_copies()
%COMPARE_DEVICE_COPIES  Original public recording vs its copy recorded
%   through our device (earbud playback): does the model give the same
%   answer? Uses the public-only model (models/steth_model_public_only.mat
%   if present). Shows where the sensor changes the result.
cfg = st_config();
f = fullfile(cfg.root, 'models', 'steth_model_public_only.mat');
if exist(f, 'file') ~= 2, f = cfg.modelFile; end
s = load(f); model = s.model;
recs = ds_all_records(cfg); names = {recs.name};
base = fullfile(fileparts(cfg.dataDir), 'device_recordings');
c = cfg; c.sqiMaxClip = 1;
fprintf('%-9s %-10s | original: pAbn  pPoor  HR | device: pAbn  pPoor  HR  cyc | corr env\n', 'class', 'record');
res = [];
for cls = {'normal', 'abnormal'}
    d = dir(fullfile(base, cls{1}, '*__pb_*.wav'));
    for i = 1:numel(d)
        nm = regexprep(d(i).name, '^.*__pb_|\.wav$', '');
        r = recs(strcmp(names, nm));
        [x0, fs0] = st_read_audio(r.wav);
        x0 = x0(round(fs0) + 1:min(end, round(fs0*16.5)));
        R0 = st_analyze(x0, fs0, model, c, false);
        [x1, fs1] = st_read_audio(fullfile(d(i).folder, d(i).name));
        R1 = st_analyze(x1, fs1, model, c, false);
        p0 = local_p(R0, model); p1 = local_p(R1, model);
        fprintf('%-9s %-10s |          %.2f   %.2f  %3.0f |        %.2f   %.2f  %3.0f  %3d\n', ...
            cls{1}, nm, p0, R0.pPoor, R0.hr, p1, R1.pPoor, R1.hr, R1.nCycles);
        res(end+1, :) = [strcmp(cls{1}, 'abnormal'), p0, p1, R0.pPoor, R1.pPoor, abs(R0.hr - R1.hr) < 5]; %#ok<AGROW>
    end
end
y = res(:, 1) == 1;
acc = @(p) mean([mean(p(y) >= 0.5), mean(p(~y) < 0.5)]);
fprintf('\nbalanced accuracy  original %.2f   device copy %.2f   (n = %d)\n', acc(res(:, 2)), acc(res(:, 3)), numel(y));
fprintf('same answer on both: %.0f%%   HR within 5 bpm: %.0f%%\n', 100*mean((res(:, 2) >= 0.5) == (res(:, 3) >= 0.5)), 100*mean(res(:, 6)));
fprintf('quality model rejects: original %.0f%%  device %.0f%%  (threshold %.2f)\n', ...
    100*mean(res(:, 4) >= model.quality.threshold), 100*mean(res(:, 5) >= model.quality.threshold), model.quality.threshold);
fprintf('mean pAbn  normal: original %.2f device %.2f | abnormal: original %.2f device %.2f\n', ...
    mean(res(~y, 2)), mean(res(~y, 3)), mean(res(y, 2)), mean(res(y, 3)));
end

function p = local_p(R, model)
% probability of abnormal even when the quality gate said "poor"
if ~isnan(R.probAbn), p = R.probAbn; return; end
p = NaN;
if isempty(R.features)
    seg = st_segment(R.xa, st_config(), model.seg);
    f = st_features(R.xa, seg.cycles, R.fs);
else
    f = R.features;
end
cl = model.classifier;
dv = st_svm_decision(cl.svm, (f - cl.mu) ./ cl.sd);
p = 1 / (1 + exp(-(cl.platt(1) + cl.platt(2)*dv)));
end
