function build_all_features()
%BUILD_ALL_FEATURES  Features for every recording, original and augmented.
%   Runs build_features_part over all recordings of PhysioNet 2016 and
%   CirCor 2022 (about 2-3 hours in one MATLAB session), then merges the
%   results into models/feature_table.mat. Only needed after changing the
%   processing; the finished table is already included.
%   (To use several sessions in parallel: build_features_part(aug, k, N).)
outDir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'models', 'parts');
if exist(outDir, 'dir') == 7
    delete(fullfile(outDir, 'feat_*.mat'));
end
build_features_part(false, 1, 1);
build_features_part(true, 1, 1);
merge_feature_tables();
end
