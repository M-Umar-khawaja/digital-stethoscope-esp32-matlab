function T = merge_feature_tables()
%MERGE_FEATURE_TABLES  Joins the slices from build_features_part.
%   T = merge_feature_tables() -> models/feature_table.mat with
%     X, Q, hr       original recordings (rows = ds_all_records order)
%     Xaug, Qaug     one simulated-sensor copy of each recording
%     y, quality, db, group, recordNames, names
cfg = st_config();
recs = ds_all_records(cfg);
N = numel(recs);
[~, names] = st_features(zeros(100, 1), zeros(0, 5), cfg.fs);
T.X = NaN(N, 124); T.Q = NaN(N, 5); T.hr = NaN(N, 1);
T.Xaug = NaN(N, 124); T.Qaug = NaN(N, 5);
d = dir(fullfile(cfg.root, 'models', 'parts', 'feat_*.mat'));
for i = 1:numel(d)
    s = load(fullfile(d(i).folder, d(i).name));
    if strncmp(d(i).name, 'feat_aug', 8)
        T.Xaug(s.idx, :) = s.X; T.Qaug(s.idx, :) = s.Q;
    else
        T.X(s.idx, :) = s.X; T.Q(s.idx, :) = s.Q; T.hr(s.idx) = s.hr;
    end
end
T.names = names;
T.y = [recs.label].';
T.quality = [recs.quality].';
T.db = [recs.db].';
T.group = {recs.group}.';
T.recordNames = {recs.name}.';
save(fullfile(cfg.root, 'models', 'feature_table.mat'), 'T', '-v7');
fprintf('merged: %d records, %d with original features, %d with augmented features\n', ...
    N, sum(all(isfinite(T.X), 2)), sum(all(isfinite(T.Xaug), 2)));
end
