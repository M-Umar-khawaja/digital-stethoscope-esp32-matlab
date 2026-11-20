function test_svm()
%TEST_SVM  Checks the SMO solver against a general QP solver and on data.
rand('seed', 1); randn('seed', 1); %#ok<RAND>
% 1) XOR-like data that needs the RBF kernel
n = 80;
X = randn(n, 2);
y = sign(X(:, 1) .* X(:, 2)); y(y == 0) = 1;
C = 2; gamma = 0.7; cw = [1 1.5];
m = st_svm_train(X, y, C, gamma, cw);
Ci = C*ones(n, 1); Ci(y < 0) = C*cw(1); Ci(y > 0) = C*cw(2);
alphaSmo = zeros(n, 1);
[~, loc] = ismember(m.sv, X, 'rows');
alphaSmo(loc) = m.coef .* y(loc);
Q = (y*y.') .* st_rbf_kernel(X, X, gamma);
objSmo = 0.5*alphaSmo.'*Q*alphaSmo - sum(alphaSmo);
if exist('qp', 'file') || exist('qp', 'builtin')
    a0 = zeros(n, 1);
    alphaQp = qp(a0, Q, -ones(n, 1), y.', 0, zeros(n, 1), Ci);
    objQp = 0.5*alphaQp.'*Q*alphaQp - sum(alphaQp);
    fprintf('dual objective: SMO %.6f  QP %.6f\n', objSmo, objQp);
    assert(abs(objSmo - objQp) < 1e-3*max(1, abs(objQp)), 'SMO does not reach the QP optimum');
end
assert(abs(sum(alphaSmo .* y)) < 1e-8, 'equality constraint');
assert(all(alphaSmo >= -1e-10 & alphaSmo <= Ci + 1e-10), 'box constraint');
acc = mean(sign(st_svm_decision(m, X)) == y);
fprintf('training accuracy on XOR data: %.1f%%\n', 100*acc);
assert(acc > 0.9, 'XOR accuracy');

% 2) generalises: separate test set from the same distribution
Xt = randn(400, 2); yt = sign(Xt(:, 1) .* Xt(:, 2));
acct = mean(sign(st_svm_decision(m, Xt)) == yt);
fprintf('test accuracy on XOR data: %.1f%%\n', 100*acct);
assert(acct > 0.85, 'XOR test accuracy');
fprintf('test_svm: all checks passed\n');
end
