function model = st_svm_train(X, y, C, gamma, classWeight, sampleWeight)
%ST_SVM_TRAIN  Support vector machine with an RBF kernel (SMO solver).
%   model = st_svm_train(X, y, C, gamma, classWeight)
%     X           : n-by-d standardised features
%     y           : n-by-1 labels, +1 abnormal / -1 normal
%     C           : box constraint (penalty for errors)
%     gamma       : RBF width, K(a,b) = exp(-gamma*||a-b||^2)
%     classWeight : [w_neg w_pos], multiplies C per class so the rarer
%                   abnormal class is not ignored (default balanced)
%     sampleWeight: optional n-by-1 extra weight per recording
%   Solver: SMO with second-order working-set selection (Fan, Chen & Lin,
%   JMLR 2005), the method inside LIBSVM and MATLAB fitcsvm. Toolbox-free.
%   Decision value: f(x) = sum_i alpha_i y_i K(x_i, x) + b ; f > 0 -> abnormal.

y = double(y(:));
n = numel(y);
if nargin < 5 || isempty(classWeight)
    classWeight = [n/(2*sum(y < 0)), n/(2*sum(y > 0))];
end
Ci = C * ones(n, 1);
Ci(y < 0) = C * classWeight(1);
Ci(y > 0) = C * classWeight(2);
if nargin >= 6 && ~isempty(sampleWeight)
    Ci = Ci .* sampleWeight(:);       % per-recording weights (e.g. per database)
end

% kernel in single precision, built in blocks: about 4x less memory than a
% double n-by-n matrix plus a separate Q matrix (n = 10000 -> 400 MB).
K = zeros(n, n, 'single');
blk = 1000;
for r0 = 1:blk:n
    r = r0:min(n, r0 + blk - 1);
    K(:, r) = single(st_rbf_kernel(X, X(r, :), gamma));
end
QD = ones(n, 1);                                % RBF: K(i,i) = 1
alpha = zeros(n, 1);
G = -ones(n, 1);                                % gradient of 0.5a'Qa - e'a
tau = 1e-12;
tol = 1e-3;
maxIter = max(10000, 100*n);
for iter = 1:maxIter
    % --- select i: max violating in "up" set
    up = (y > 0 & alpha < Ci) | (y < 0 & alpha > 0);
    lo = (y > 0 & alpha > 0) | (y < 0 & alpha < Ci);
    vUp = -y .* G;
    vUp(~up) = -inf;
    [Gmax, i] = max(vUp);
    vLo = -y .* G;
    vLo(~lo) = inf;
    Gmin = min(vLo);
    if Gmax - Gmin < tol, break; end
    % --- select j: second-order gain
    b = Gmax + y .* G;                           % = Gmax - (-y.*G)
    Qi = y(i) * y .* double(K(:, i));          % column i of Q = (y*y').*K
    a = QD(i) + QD - 2*y(i)*y.*Qi;
    a(a <= 0) = tau;
    gain = -(b.^2) ./ a;
    gain(~lo | b <= 0) = inf;
    [~, j] = min(gain);
    % --- two-variable update (LIBSVM)
    aOldI = alpha(i); aOldJ = alpha(j);
    if y(i) ~= y(j)
        quad = max(QD(i) + QD(j) + 2*Qi(j), tau);
        delta = (-G(i) - G(j)) / quad;
        diff = alpha(i) - alpha(j);
        alpha(i) = alpha(i) + delta; alpha(j) = alpha(j) + delta;
        if diff > 0
            if alpha(j) < 0, alpha(j) = 0; alpha(i) = diff; end
        else
            if alpha(i) < 0, alpha(i) = 0; alpha(j) = -diff; end
        end
        if diff > Ci(i) - Ci(j)
            if alpha(i) > Ci(i), alpha(i) = Ci(i); alpha(j) = Ci(i) - diff; end
        else
            if alpha(j) > Ci(j), alpha(j) = Ci(j); alpha(i) = Ci(j) + diff; end
        end
    else
        quad = max(QD(i) + QD(j) - 2*Qi(j), tau);
        delta = (G(i) - G(j)) / quad;
        sm = alpha(i) + alpha(j);
        alpha(i) = alpha(i) - delta; alpha(j) = alpha(j) + delta;
        if sm > Ci(i)
            if alpha(i) > Ci(i), alpha(i) = Ci(i); alpha(j) = sm - Ci(i); end
        else
            if alpha(j) < 0, alpha(j) = 0; alpha(i) = sm; end
        end
        if sm > Ci(j)
            if alpha(j) > Ci(j), alpha(j) = Ci(j); alpha(i) = sm - Ci(j); end
        else
            if alpha(i) < 0, alpha(i) = 0; alpha(j) = sm; end
        end
    end
    dI = alpha(i) - aOldI; dJ = alpha(j) - aOldJ;
    Qj = y(j) * y .* double(K(:, j));
    G = G + Qi*dI + Qj*dJ;
end

% bias: average over free support vectors (LIBSVM rule)
free = alpha > 1e-8 & alpha < Ci - 1e-8;
yG = y .* G;
if any(free)
    rho = mean(yG(free));
else
    upB = (y > 0 & alpha < Ci) | (y < 0 & alpha > 0);
    loB = (y > 0 & alpha > 0) | (y < 0 & alpha < Ci);
    rho = (max(yG(loB)) + min(yG(upB))) / 2;     % midpoint of feasible range
    if isempty(rho) || ~isfinite(rho), rho = 0; end
end
sv = alpha > 1e-8;
model.sv = X(sv, :);
model.coef = alpha(sv) .* y(sv);
model.b = -rho;
model.gamma = gamma;
model.C = C;
model.classWeight = classWeight;
model.iterations = iter;
model.nSV = sum(sv);
end
