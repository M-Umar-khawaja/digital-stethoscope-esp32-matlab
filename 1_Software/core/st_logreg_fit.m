function w = st_logreg_fit(X, y, lambda, sw)
%ST_LOGREG_FIT  Binary logistic regression by Newton's method (IRLS).
%   w = st_logreg_fit(X, y, lambda, sw)
%     X : n-by-d features, y : n-by-1 labels in {0,1}
%     sw: optional n-by-1 sample weights (e.g. to balance the classes)
%     w : (d+1)-by-1 weights, intercept first
%   P(y=1|x) = 1/(1+exp(-[1 x]*w)). lambda is a small ridge penalty for
%   numerical stability (default 1e-4). Replaces mnrfit, so no Statistics
%   Toolbox is needed.

if nargin < 3, lambda = 1e-4; end
A = [ones(size(X, 1), 1), X];
y = double(y(:));
if nargin < 4 || isempty(sw), sw = ones(size(y)); end
sw = sw(:) / mean(sw);
w = zeros(size(A, 2), 1);
R = lambda * eye(size(A, 2));
R(1, 1) = 0;                                    % do not penalise the intercept
for it = 1:50
    z = A*w;
    p = 1 ./ (1 + exp(-z));
    s = max(p .* (1 - p), 1e-9) .* sw;
    g = A.' * (sw .* (p - y)) + R*w;
    H = A.' * bsxfun(@times, A, s) + R;
    step = H \ g;
    w = w - step;
    if max(abs(step)) < 1e-8, break; end
end
end
