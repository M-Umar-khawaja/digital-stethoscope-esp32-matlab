function experiment_robustness()
%EXPERIMENT_ROBUSTNESS  Compares feature/weighting options on new-sensor data.
%   For each option: 5-fold patient-grouped CV and leave-one-database-out
%   (LODO, the best stand-in for a new microphone such as the MAX4466).
cfg = st_config();
s = load(fullfile(cfg.root, 'models', 'feature_table.mat')); T = s.T;
use = T.quality == 1 & all(isfinite(T.X), 2);
X0 = T.X(use, :); y = 2*T.y(use) - 1; dbs = T.db(use); grp = T.group(use);
d = size(X0, 2);
folds = local_folds(grp, y > 0, 5);
dbFold = double(dbs) - double('a') + 1;
% weight so every database's abnormal and normal sets count equally
w = zeros(size(y));
for k = 1:6
    for c = [-1 1]
        m = dbFold == k & y == c;
        if any(m), w(m) = 1 / sum(m); end
    end
end
w = w / mean(w);
opts = {'baseline', 'channel-normalised', 'channel-normalised + database weights'};
for o = 1:3
    X = X0;
    if o >= 2, X = st_feature_transform(X); end
    sw = []; if o == 3, sw = w; end
    for g = [0.5 1] / d
        for C = [0.25 1]
            cv = local_cv(X, y, folds, C, g, sw);
            lo = local_cv(X, y, dbFold, C, g, sw);
            mc = local_m(cv, y); ml = local_m(lo, y);
            fprintf('%-40s C=%-4g g=%.2f/d | CV Se %.3f Sp %.3f MAcc %.3f | LODO Se %.3f Sp %.3f MAcc %.3f\n', ...
                opts{o}, C, g*d, mc(1), mc(2), mc(3), ml(1), ml(2), ml(3));
        end
    end
end
end

function dv = local_cv(X, y, folds, C, gamma, sw)
dv = zeros(size(y));
for k = unique(folds).'
    tr = folds ~= k; te = folds == k;
    mu = mean(X(tr, :), 1); sd = std(X(tr, :), 0, 1); sd(sd < eps) = 1;
    Xtr = bsxfun(@rdivide, bsxfun(@minus, X(tr, :), mu), sd);
    Xte = bsxfun(@rdivide, bsxfun(@minus, X(te, :), mu), sd);
    if isempty(sw), m = st_svm_train(Xtr, y(tr), C, gamma);
    else, m = st_svm_train(Xtr, y(tr), C, gamma, [1 1], sw(tr)); end
    dv(te) = st_svm_decision(m, Xte);
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
