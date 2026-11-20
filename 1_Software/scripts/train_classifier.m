function model = train_classifier(opts)
%TRAIN_CLASSIFIER  Trains and tests the quality and normal/abnormal models.
%   model = train_classifier()            full training, saves the model
%   model = train_classifier(opts)        opts.augment (true), opts.save (true),
%                                         opts.Cgrid, opts.gammaScale, opts.tag
%   Data: PhysioNet/CinC 2016 (databases a-f) + CirCor 2022 (g), plus
%   optional own-device recordings (h) from data/device_recordings.
%   With opts.augment, every training recording also contributes one
%   simulated-sensor copy (st_augment); copies are only ever used for
%   training, always together with their original, and never for testing.
%
%   Tests reported (all grouped by patient, never leaking a patient):
%     - 5-fold cross-validation over everything (main figure)
%     - per-dataset breakdown of that cross-validation
%     - leave-one-database-out over the 7 databases (new-sensor test)
%     - cross-dataset: train on PhysioNet 2016 only -> test on CirCor,
%       and the reverse (hardest new-sensor test)
%   Saves models/steth_model.mat and models/training_report.txt.

if nargin < 1, opts = struct(); end
opts = local_default(opts, 'augment', true);
opts = local_default(opts, 'save', true);
opts = local_default(opts, 'Cgrid', [0.5 1 2]);
opts = local_default(opts, 'gammaScale', [0.5 1]);
opts = local_default(opts, 'tag', '');

cfg = st_config();
s = load(fullfile(cfg.root, 'models', 'feature_table.mat')); T = s.T;
s = load(fullfile(cfg.root, 'models', 'seg_model.mat')); segModel = s.segModel;
rep = {};
rep{end+1} = sprintf('Training report  %s  %s', datestr(now, 'yyyy-mm-dd HH:MM'), opts.tag);
rep{end+1} = sprintf('Recordings: %d PhysioNet 2016 + %d CirCor 2022; simulated-sensor copies: %s', ...
    sum(T.db ~= 'g'), sum(T.db == 'g'), local_onoff(opts.augment));

% ------------------------------------------------------------------ quality
% (only PhysioNet 2016 has usable/unusable labels)
okQ = all(isfinite(T.Q), 2) & T.db ~= 'g';
Q = T.Q(okQ, :);
poor = T.quality(okQ) == 0;
qMu = mean(Q, 1); qSd = std(Q, 0, 1); qSd(qSd < eps) = 1;
Qs = bsxfun(@rdivide, bsxfun(@minus, Q, qMu), qSd);
qf = local_folds(T.group(okQ), poor, 5);
pOut = zeros(size(poor));
for k = 1:5
    tr = qf ~= k; te = qf == k;
    w = st_logreg_fit(Qs(tr, :), poor(tr), 1e-2);
    pOut(te) = 1 ./ (1 + exp(-[ones(sum(te), 1), Qs(te, :)] * w));
end
thr = local_quantile(pOut(~poor), 0.95);
quality.mu = qMu; quality.sd = qSd; quality.w = st_logreg_fit(Qs, poor, 1e-2);
quality.threshold = thr;
quality.names = {'autocorr peak', 'cycles per 10 s', 'cycle variation', 'log kurtosis', 'S1+S2 energy share'};
rep{end+1} = '';
rep{end+1} = 'SIGNAL QUALITY CHECK (PhysioNet 2016 labels, 5-fold CV grouped by patient)';
rep{end+1} = sprintf('  poor recordings caught: %.1f%%   good recordings accepted: %.1f%%', ...
    100*mean(pOut(poor) >= thr), 100*mean(pOut(~poor) < thr));

% ---------------------------------------------------------- the data set
use = T.quality == 1 & all(isfinite(T.X), 2);
D.X = T.X(use, :);
D.Xa = T.Xaug(use, :);
D.y = 2*T.y(use) - 1;
D.g = T.group(use);
D.db = T.db(use);
[Xd, yd, gd] = local_device_recordings(cfg, segModel);
if ~isempty(yd)
    D.X = [D.X; Xd]; D.Xa = [D.Xa; NaN(size(Xd))]; D.y = [D.y; yd];
    D.g = [D.g; gd]; D.db = [D.db; repmat('h', numel(yd), 1)];
end
D.w = ones(size(D.y));
D.w(D.db == 'h') = 10;                        % own-device recordings count 10x
D.hasAug = opts.augment & all(isfinite(D.Xa), 2);
d = size(D.X, 2);
rep{end+1} = '';
rep{end+1} = sprintf('CLASSIFIER DATA: %d recordings (%d abnormal, %d normal), %d features', ...
    numel(D.y), sum(D.y > 0), sum(D.y < 0), d);
for db = unique(D.db).'
    m = D.db == db;
    rep{end+1} = sprintf('  %-22s %5d rec  %4d abnormal', local_dbname(db), sum(m), sum(D.y(m) > 0)); %#ok<AGROW>
end
if ~isempty(yd)
    rep{end+1} = '  own-device recordings are weighted 10x';
end

% -------------------------------------------------- settings by grouped CV
folds = local_folds(D.g, D.y > 0, 5);
best = struct('macc', -inf);
rep{end+1} = '';
rep{end+1} = '5-FOLD CROSS-VALIDATION, GROUPED BY PATIENT (settings search)';
for C = opts.Cgrid
    for gs = opts.gammaScale
        g = gs / d;
        dv = local_cv(D, folds, C, g);
        m = local_metrics(dv > 0, D.y > 0);
        line = sprintf('  C=%-4g gamma=%.2f/d  Se %.3f  Sp %.3f  MAcc %.3f', C, gs, m.se, m.sp, m.macc);
        fprintf('%s\n', line); rep{end+1} = line; %#ok<AGROW>
        if m.macc > best.macc
            best = m; best.C = C; best.gamma = g; best.dv = dv;
        end
    end
end
pw = ones(size(D.y)); pw(D.y > 0) = sum(D.y < 0) / sum(D.y > 0);
platt = st_logreg_fit(best.dv, D.y > 0, 1e-6, pw);
pOOF = 1 ./ (1 + exp(-(platt(1) + platt(2)*best.dv)));
best = local_merge(best, local_metrics(pOOF >= 0.5, D.y > 0));
rep{end+1} = '';
rep{end+1} = sprintf('BEST SETTINGS: C = %g, gamma = %.2f/d', best.C, best.gamma*d);
rep{end+1} = sprintf('  all data (rule p>=0.5): sensitivity %.1f%%  specificity %.1f%%  MAcc %.1f%%  accuracy %.1f%%', ...
    100*best.se, 100*best.sp, 100*best.macc, 100*best.acc);
rep{end+1} = sprintf('  confusion (rows true N/A, cols predicted N/A): [%d %d; %d %d]', best.tn, best.fp, best.fn, best.tp);
for set = {'abcdef', 'PhysioNet 2016'; 'g', 'CirCor 2022'; 'h', 'own device'}.'
    m = ismember(D.db, set{1});
    if ~any(m), continue; end
    mm = local_metrics(pOOF(m) >= 0.5, D.y(m) > 0);
    rep{end+1} = sprintf('    %-16s Se %.3f  Sp %.3f  MAcc %.3f  (%d rec)', set{2}, mm.se, mm.sp, mm.macc, sum(m)); %#ok<AGROW>
end

% ---------------------------------------- device decision threshold
% Our sensor shifts heart sounds towards "abnormal". For ESP32 input the
% probability threshold is re-chosen on the own-device recordings (out-of-
% fold scores). Honest estimate: leave-one-person-out, i.e. the threshold
% used for a person is chosen from the OTHER device recordings only.
devThr = 0.5;
mDev = D.db == 'h';
if sum(mDev) >= 10 && any(D.y(mDev) > 0) && any(D.y(mDev) < 0)
    pD = pOOF(mDev); yD = D.y(mDev) > 0; gD = D.g(mDev);
    devThr = local_best_thr(pD, yD);
    [ug, ~, gi] = unique(gD);
    predL = false(size(yD));
    for k = 1:numel(ug)
        te = gi == k;
        if all(yD(~te)) || ~any(yD(~te)), t = 0.5; else, t = local_best_thr(pD(~te), yD(~te)); end
        predL(te) = pD(te) >= t;
    end
    mm = local_metrics(predL, yD);
    rep{end+1} = sprintf('  own device, device threshold (leave-one-person-out): Se %.3f  Sp %.3f  MAcc %.3f', ...
        mm.se, mm.sp, mm.macc);
    self = strcmp(gD, 'self');
    if any(self)
        rep{end+1} = sprintf('    own heart (normal, %d clips) called normal: %.0f%%', sum(self), 100*mean(~predL(self)));
    end
    rep{end+1} = sprintf('  device threshold used by the app: p(abnormal) >= %.2f', devThr);
end

% ------------------------------------------------- new-sensor tests
rep{end+1} = '';
rep{end+1} = 'LEAVE-ONE-DATABASE-OUT (train on the others, test on the one left out)';
dbs = unique(D.db).';
dbFold = zeros(size(D.y));
for k = 1:numel(dbs), dbFold(D.db == dbs(k)) = k; end
dvL = local_cv(D, dbFold, best.C, best.gamma);
for k = 1:numel(dbs)
    te = dbFold == k;
    m = local_metrics(dvL(te) > 0, D.y(te) > 0);
    rep{end+1} = sprintf('  %-22s Se %.3f  Sp %.3f  MAcc %.3f', local_dbname(dbs(k)), m.se, m.sp, m.macc); %#ok<AGROW>
end
mL = local_metrics(dvL > 0, D.y > 0);
macL = mean(cellfun(@(k) local_metrics(dvL(dbFold == k) > 0, D.y(dbFold == k) > 0).macc, num2cell(1:numel(dbs))));
rep{end+1} = sprintf('  pooled: Se %.3f  Sp %.3f  MAcc %.3f   |  mean MAcc over databases %.3f', mL.se, mL.sp, mL.macc, macL);

rep{end+1} = '';
rep{end+1} = 'CROSS-DATASET (hardest new-sensor test)';
crossFold = 1 + double(D.db == 'g');            % 1 = PhysioNet 2016, 2 = CirCor
crossFold(D.db == 'h') = 3;
if any(D.db == 'g')
    dvX = local_cv(D, crossFold, best.C, best.gamma, [1 2]);
    m = local_metrics(dvX(crossFold == 2) > 0, D.y(crossFold == 2) > 0);
    rep{end+1} = sprintf('  train PhysioNet 2016 -> test CirCor:        Se %.3f  Sp %.3f  MAcc %.3f', m.se, m.sp, m.macc);
    m = local_metrics(dvX(crossFold == 1) > 0, D.y(crossFold == 1) > 0);
    rep{end+1} = sprintf('  train CirCor         -> test PhysioNet 2016: Se %.3f  Sp %.3f  MAcc %.3f', m.se, m.sp, m.macc);
end

% ------------------------------------------------------------ final model
[Xtr, ytr, wtr] = local_trainset(D, true(size(D.y)));
mu = mean(Xtr, 1); sd = std(Xtr, 0, 1); sd(sd < eps) = 1;
svm = st_svm_train(bsxfun(@rdivide, bsxfun(@minus, Xtr, mu), sd), ytr, best.C, best.gamma, [], wtr);
classifier.mu = mu; classifier.sd = sd; classifier.svm = svm;
classifier.platt = platt; classifier.names = T.names;
classifier.deviceThreshold = devThr;
classifier.cv = rmfield(best, 'dv');
classifier.lodo = mL;
rep{end+1} = '';
rep{end+1} = sprintf('FINAL MODEL: %d support vectors, trained on %d rows (%d recordings + copies)', ...
    svm.nSV, numel(ytr), numel(D.y));

model.seg = segModel;
model.quality = quality;
model.classifier = classifier;
model.created = datestr(now, 'yyyy-mm-dd HH:MM');
model.fs = cfg.fs;
fprintf('%s\n', rep{:});
if opts.save
    save(cfg.modelFile, 'model', '-v7');
    fid = fopen(fullfile(cfg.root, 'models', 'training_report.txt'), 'w');
    fprintf(fid, '%s\n', rep{:});
    fclose(fid);
end
end

% =========================================================================
function [X, y, w] = local_trainset(D, m)
% training rows: the chosen recordings plus their simulated-sensor copies
a = m & D.hasAug;
X = [D.X(m, :); D.Xa(a, :)];
y = [D.y(m); D.y(a)];
w = [D.w(m); D.w(a)];
end

function dv = local_cv(D, folds, C, gamma, testFolds)
dv = zeros(size(D.y));
if nargin < 5, testFolds = unique(folds).'; end
for k = testFolds
    te = folds == k;
    [Xtr, ytr, wtr] = local_trainset(D, ~te);
    mu = mean(Xtr, 1); sd = std(Xtr, 0, 1); sd(sd < eps) = 1;
    m = st_svm_train(bsxfun(@rdivide, bsxfun(@minus, Xtr, mu), sd), ytr, C, gamma, [], wtr);
    dv(te) = st_svm_decision(m, bsxfun(@rdivide, bsxfun(@minus, D.X(te, :), mu), sd));
end
end

function t = local_best_thr(p, y)
% threshold on p maximising balanced accuracy (ties: closest to 0.5)
cand = unique([0.5; p(:)]);
best = -inf; t = 0.5;
for c = cand.'
    m = local_metrics(p >= c, y);
    if m.macc > best + 1e-9 || (abs(m.macc - best) < 1e-9 && abs(c - 0.5) < abs(t - 0.5))
        best = m.macc; t = c;
    end
end
end

function m = local_metrics(pred, truth)
pred = logical(pred(:)); truth = logical(truth(:));
m.tp = sum(pred & truth); m.tn = sum(~pred & ~truth);
m.fp = sum(pred & ~truth); m.fn = sum(~pred & truth);
m.se = m.tp / max(m.tp + m.fn, 1);
m.sp = m.tn / max(m.tn + m.fp, 1);
m.macc = (m.se + m.sp) / 2;
m.acc = (m.tp + m.tn) / max(numel(truth), 1);
end

function folds = local_folds(groups, pos, K)
% Stratified, grouped folds: whole patients go to one fold, and each fold
% gets a similar share of abnormal recordings. Fixed order -> repeatable.
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
        [~, k] = min(fill);
        gFold(i) = k;
        fill(k) = fill(k) + gSize(i);
    end
end
folds = gFold(gi);
end

function q = local_quantile(v, p)
v = sort(v(:));
q = v(max(1, min(numel(v), ceil(p*numel(v)))));
end

function a = local_merge(a, b)
f = fieldnames(b);
for i = 1:numel(f), a.(f{i}) = b.(f{i}); end
end

function o = local_default(o, f, v)
if ~isfield(o, f), o.(f) = v; end
end

function s = local_onoff(b)
if b, s = 'on'; else, s = 'off'; end
end

function s = local_dbname(c)
switch c
    case 'g', s = 'CirCor 2022';
    case 'h', s = 'own device';
    otherwise, s = ['PhysioNet 2016-' c];
end
end

function [X, y, g] = local_device_recordings(cfg, segModel)
% WAV files recorded with our own device and sorted by known status into
% data/device_recordings/normal and .../abnormal (use the *_raw.wav files
% that the dashboard's Save button writes).
X = zeros(0, 124); y = zeros(0, 1); g = {};
base = fullfile(fileparts(cfg.dataDir), 'device_recordings');
cls = {'normal', -1; 'abnormal', 1};
for c = 1:2
    files = dir(fullfile(base, cls{c, 1}, '*.wav'));
    for i = 1:numel(files)
        try
            [x, fs] = st_read_audio(fullfile(files(i).folder, files(i).name));
            xa = st_preprocess(x, fs, cfg);
            seg = st_segment(xa, cfg, segModel);
            f = st_features(xa, seg.cycles, cfg.fs);
            if all(isfinite(f))
                X(end+1, :) = f; %#ok<AGROW>
                y(end+1, 1) = cls{c, 2}; %#ok<AGROW>
                % group = text before "__" (patient of a played-back record,
                % or "self"), so one person never sits in train and test
                k = strfind(files(i).name, '__');
                if isempty(k), grp = ['dev_' files(i).name]; else, grp = files(i).name(1:k(1)-1); end
                g{end+1, 1} = grp; %#ok<AGROW>
            end
        catch err
            fprintf('  skipped %s: %s\n', files(i).name, err.message);
        end
    end
end
end
