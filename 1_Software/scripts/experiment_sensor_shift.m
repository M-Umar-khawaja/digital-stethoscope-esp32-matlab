function experiment_sensor_shift()
%EXPERIMENT_SENSOR_SHIFT  How much does a different microphone alone hurt?
%   Same patients and labels; the test recordings are played through a
%   simulated different sensor (st_augment: other bass cut, treble roll-off,
%   tone bumps, ADC level, hum, noise). Patient-grouped 5-fold CV.
%   Compares a model trained on original recordings only (A) with one
%   that also saw simulated-sensor copies of the TRAINING patients (B).
%   Test patients' copies are never used for training.
cfg = st_config();
s = load(fullfile(cfg.root, 'models', 'feature_table.mat')); T = s.T;
use = T.quality == 1 & all(isfinite(T.X), 2) & all(isfinite(T.Xaug), 2);
X = T.X(use, :); Xa = T.Xaug(use, :); y = 2*T.y(use) - 1; g = T.group(use);
d = size(X, 2); C = 1; gamma = 1/d;
folds = local_folds(g, y > 0, 5);
for useAug = [false true]
    dvO = zeros(size(y)); dvA = zeros(size(y));
    for k = 1:5
        tr = folds ~= k; te = folds == k;
        Xtr = X(tr, :); ytr = y(tr);
        if useAug, Xtr = [Xtr; Xa(tr, :)]; ytr = [ytr; y(tr)]; end %#ok<AGROW>
        mu = mean(Xtr, 1); sd = std(Xtr, 0, 1); sd(sd < eps) = 1;
        m = st_svm_train(bsxfun(@rdivide, bsxfun(@minus, Xtr, mu), sd), ytr, C, gamma);
        dvO(te) = st_svm_decision(m, bsxfun(@rdivide, bsxfun(@minus, X(te, :), mu), sd));
        dvA(te) = st_svm_decision(m, bsxfun(@rdivide, bsxfun(@minus, Xa(te, :), mu), sd));
    end
    if useAug, nm = 'B (trained with copies)'; else, nm = 'A (originals only)     '; end
    mo = local_m(dvO, y); ma = local_m(dvA, y);
    fprintf('%s  same sensor: Se %.3f Sp %.3f MAcc %.3f | new sensor: Se %.3f Sp %.3f MAcc %.3f\n', ...
        nm, mo, ma);
end
end

function m = local_m(dv, y)
se = mean(dv(y > 0) > 0); sp = mean(dv(y < 0) <= 0);
m = [se sp (se + sp)/2];
end

function folds = local_folds(groups, pos, K)
[ug, ~, gi] = unique(groups);
gPos = accumarray(gi, double(pos(:)), [], @max);
gSize = accumarray(gi, 1);
gFold = zeros(numel(ug), 1);
for cls = [1 0]
    idx = find(gPos == cls);
    [~, o] = sort(gSize(idx), 'descend');
    idx = idx(o);
    fill = zeros(K, 1);
    for i = idx.'
        [~, k] = min(fill); gFold(i) = k; fill(k) = fill(k) + gSize(i);
    end
end
folds = gFold(gi);
end
