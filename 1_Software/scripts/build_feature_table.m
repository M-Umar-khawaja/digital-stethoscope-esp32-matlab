function T = build_feature_table()
%BUILD_FEATURE_TABLE  Runs the full pipeline on all 3240 PhysioNet recordings.
%   T = build_feature_table()  ->  saves models/feature_table.mat with
%     X (3240-by-124 features), Q (quality features), y (1 abnormal),
%     quality (PhysioNet label), db, group (patient where known), names
%   Takes about 45-60 minutes in MATLAB/Octave. Run once.

cfg = st_config();
s = load(fullfile(cfg.root, 'models', 'seg_model.mat'));
segModel = s.segModel;
recs = ds_list_records(cfg);
groups = ds_groups(cfg, recs);
N = numel(recs);
[~, names] = st_features(zeros(100, 1), zeros(0, 5), cfg.fs);
X = NaN(N, numel(names));
Q = NaN(N, 5);
hr = NaN(N, 1);
t0 = tic;
for i = 1:N
    try
        [x, fs] = st_read_audio(recs(i).wav);
        xa = st_preprocess(x, fs, cfg);
        seg = st_segment(xa, cfg, segModel);
        X(i, :) = st_features(xa, seg.cycles, cfg.fs);
        Q(i, :) = st_quality_features(xa, seg, cfg.fs);
        hr(i) = seg.hr;
    catch err
        fprintf('  %s failed: %s\n', recs(i).name, err.message);
    end
    if mod(i, 100) == 0 || i == N
        fprintf('%d / %d recordings (%.0f s)\n', i, N, toc(t0));
    end
end
T.X = X; T.Q = Q; T.hr = hr; T.names = names;
T.y = [recs.label].';
T.quality = [recs.quality].';
T.db = [recs.db].';
T.group = groups(:);
T.recordNames = {recs.name}.';
save(fullfile(cfg.root, 'models', 'feature_table.mat'), 'T', '-v7');
fprintf('feature table saved\n');
end
