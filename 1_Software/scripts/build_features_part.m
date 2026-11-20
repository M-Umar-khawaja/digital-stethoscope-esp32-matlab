function build_features_part(augment, part, nParts)
%BUILD_FEATURES_PART  Features for one slice of all recordings.
%   build_features_part(augment, part, nParts)
%     augment : false = original recordings, true = one simulated-sensor
%               copy of each recording (st_augment, fixed seed per record)
%     part, nParts : process records part, part+nParts, ... so several
%               MATLAB/Octave sessions can share the work
%   Saves models/parts/feat_<orig|aug>_<part>.mat; merge_feature_tables
%   joins the slices. Run all slices via build_all_features.

cfg = st_config();
s = load(fullfile(cfg.root, 'models', 'seg_model.mat'));
segModel = s.segModel;
recs = ds_all_records(cfg);
idx = part:nParts:numel(recs);
X = NaN(numel(idx), 124); Q = NaN(numel(idx), 5); hr = NaN(numel(idx), 1);
t0 = tic;
for k = 1:numel(idx)
    i = idx(k);
    try
        [x, fs] = st_read_audio(recs(i).wav);
        if augment
            x = st_augment(x, fs, 100000 + i);
        end
        xa = st_preprocess(x, fs, cfg);
        seg = st_segment(xa, cfg, segModel);
        X(k, :) = st_features(xa, seg.cycles, cfg.fs);
        Q(k, :) = st_quality_features(xa, seg, cfg.fs);
        hr(k) = seg.hr;
    catch err
        fprintf('  %s failed: %s\n', recs(i).name, err.message);
    end
    if mod(k, 200) == 0
        fprintf('part %d: %d / %d (%.0f s)\n', part, k, numel(idx), toc(t0));
    end
end
outDir = fullfile(cfg.root, 'models', 'parts');
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end
tag = 'orig'; if augment, tag = 'aug'; end
save(fullfile(outDir, sprintf('feat_%s_%d.mat', tag, part)), 'idx', 'X', 'Q', 'hr', '-v7');
fprintf('part %d (%s) done: %d records in %.0f s\n', part, tag, numel(idx), toc(t0));
end
