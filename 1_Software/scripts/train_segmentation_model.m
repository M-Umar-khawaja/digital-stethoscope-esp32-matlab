function segModel = train_segmentation_model(nPerDb)
%TRAIN_SEGMENTATION_MODEL  Learns how S1/systole/S2/diastole look.
%   segModel = train_segmentation_model()      default 60 recordings per database
%   Trains the emission model of the HSMM segmenter from the hand-corrected
%   PhysioNet 2016 annotations, using only good-quality recordings with
%   an EVEN index in each database. Odd-indexed recordings are kept for
%   testing (evaluate_segmentation.m). Saves models/seg_model.mat.

if nargin < 1, nPerDb = 60; end
cfg = st_config();
recs = ds_all_records(cfg);
X = zeros(0, 4); Y = zeros(0, 1);
D = round(cfg.fs / cfg.featFs);
used = 0;
for db = 'abcdefg'
    idx = find([recs.db] == db & [recs.quality] == 1);
    idx = idx(2:2:end);
    idx = idx(1:min(nPerDb, numel(idx)));
    for k = idx
        r = recs(k);
        if exist(r.ann, 'file') ~= 2, continue; end
        [x, fs] = st_read_audio(r.wav);
        xa = st_preprocess(x, fs, cfg);
        F = st_seg_features(xa, cfg.fs, cfg.featFs);
        st = ds_load_states(r.ann, numel(xa));
        centre = round(((1:size(F, 1)).' - 0.5) * D);
        centre = min(max(centre, 1), numel(st));
        lab = st(centre);
        keep = lab > 0;
        X = [X; F(keep, :)]; %#ok<AGROW>
        Y = [Y; lab(keep)]; %#ok<AGROW>
        used = used + 1;
    end
    fprintf('database %s done (%d recordings so far)\n', db, used);
end

segModel.w = zeros(5, 4);
for j = 1:4
    segModel.w(:, j) = st_logreg_fit(X, Y == j, 1e-3);
end
segModel.mu = mean(X, 1);
segModel.Sigma = cov(X);
segModel.logdetSigma = log(det(segModel.Sigma));
segModel.prior = [0.25 0.25 0.25 0.25];
segModel.nRecordings = used;
segModel.nSamples = numel(Y);
segModel.created = datestr(now, 'yyyy-mm-dd HH:MM');

outDir = fullfile(cfg.root, 'models');
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end
save(fullfile(outDir, 'seg_model.mat'), 'segModel', '-v7');
fprintf('segmentation model saved: %d recordings, %d feature samples\n', used, numel(Y));
end
