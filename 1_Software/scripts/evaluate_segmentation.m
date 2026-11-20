function res = evaluate_segmentation(nPerDb, override)
%EVALUATE_SEGMENTATION  How well S1 and S2 are found on unseen recordings.
%   res = evaluate_segmentation(nPerDb)   default 40 test recordings per database
%   Uses odd-indexed good-quality recordings (never used for training).
%   A heart sound counts as found when the centre of a detected S1 (or S2)
%   is within 60 ms of the centre of a hand-marked one (Springer 2016).
%   Also compares our heart rate with the rate from the hand annotations.

if nargin < 1, nPerDb = 40; end
cfg = st_config();
if nargin >= 2
    f = fieldnames(override);
    for i = 1:numel(f), cfg.(f{i}) = override.(f{i}); end
end
s = load(fullfile(cfg.root, 'models', 'seg_model.mat'));
segModel = s.segModel;
recs = ds_all_records(cfg);
tol = round(0.060 * cfg.fs);
TP = 0; FP = 0; FN = 0; hrErr = []; tSeg = 0; n = 0;
for db = 'abcdefg'
    idx = find([recs.db] == db & [recs.quality] == 1);
    idx = idx(1:2:end);
    idx = idx(1:min(nPerDb, numel(idx)));
    for k = idx
        r = recs(k);
        if exist(r.ann, 'file') ~= 2, continue; end
        [x, fs] = st_read_audio(r.wav);
        xa = st_preprocess(x, fs, cfg);
        t0 = tic;
        seg = st_segment(xa, cfg, segModel);
        tSeg = tSeg + toc(t0);
        n = n + 1;
        ref = ds_load_states(r.ann, numel(xa));
        lab = find(ref > 0);
        if isempty(lab) || isempty(seg.states), continue; end
        span = lab(1):lab(end);                      % only the annotated part
        for state = [1 3]
            cr = local_centres(ref(span) == state);
            cd = local_centres(seg.states(span) == state);
            used = false(size(cr));
            for c = cd.'
                [dmin, j] = min(abs(cr - c));
                if ~isempty(dmin) && dmin <= tol && ~used(j)
                    TP = TP + 1; used(j) = true;
                else
                    FP = FP + 1;
                end
            end
            FN = FN + sum(~used);
        end
        c1 = local_centres(ref(span) == 1);
        if numel(c1) > 2
            hrRef = 60 / (median(diff(c1)) / cfg.fs);
            hrErr(end+1) = seg.hr - hrRef; %#ok<AGROW>
        end
    end
    fprintf('database %s: %d recordings tested so far\n', db, n);
end
res.sensitivity = TP / max(TP + FN, 1);
res.ppv = TP / max(TP + FP, 1);
res.F1 = 2*res.sensitivity*res.ppv / max(res.sensitivity + res.ppv, eps);
res.hrMAE = mean(abs(hrErr));
res.hrWithin5 = mean(abs(hrErr) <= 5);
res.nRecordings = n;
res.secondsPerRecording = tSeg / max(n, 1);
fprintf('S1/S2 detection: sensitivity %.1f%%  PPV %.1f%%  F1 %.1f%%\n', ...
    100*res.sensitivity, 100*res.ppv, 100*res.F1);
fprintf('Heart rate: mean abs error %.1f bpm, within 5 bpm in %.1f%% of recordings\n', ...
    res.hrMAE, 100*res.hrWithin5);
fprintf('Segmentation time: %.2f s per recording\n', res.secondsPerRecording);
end

function c = local_centres(mask)
mask = mask(:);
d = diff([0; mask; 0]);
on = find(d == 1);
off = find(d == -1) - 1;
c = round((on + off) / 2);
end
