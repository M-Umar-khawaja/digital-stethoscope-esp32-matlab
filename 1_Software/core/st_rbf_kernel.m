function K = st_rbf_kernel(A, B, gamma)
%ST_RBF_KERNEL  Gaussian kernel matrix exp(-gamma*||a_i - b_j||^2).
sa = sum(A.^2, 2);
sb = sum(B.^2, 2).';
D2 = max(bsxfun(@plus, sa, sb) - 2*(A*B.'), 0);
K = exp(-gamma * D2);
end
