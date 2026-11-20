function d = st_svm_decision(model, X)
%ST_SVM_DECISION  SVM decision values; positive means abnormal.
d = st_rbf_kernel(X, model.sv, model.gamma) * model.coef + model.b;
end
