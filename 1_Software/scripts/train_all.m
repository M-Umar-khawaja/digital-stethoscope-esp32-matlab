function train_all()
%TRAIN_ALL  Rebuilds every trained model from the public datasets.
%   Only needed if you change the processing; the trained models are
%   already included in models/. Takes several hours in one MATLAB session.
%   Steps: segmentation model -> segmentation test -> features for all
%   6130 recordings and their simulated-sensor copies -> quality and
%   normal/abnormal classifiers with patient-grouped testing ->
%   models/steth_model.mat + models/training_report.txt
%   (To recalibrate with your own device recordings only, just run
%   train_classifier: it uses the saved feature table, about 5 minutes.)

here = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(here, 'core'), fullfile(here, 'scripts'));
cfg = st_config();
if exist(fullfile(cfg.dataDir, 'training-a'), 'dir') ~= 7
    error(['PhysioNet 2016 data not found in %s.\nDownload training.zip and annotations.zip from ' ...
        'https://physionet.org/content/challenge-2016/1.0.0/ and unzip them there.'], cfg.dataDir);
end
if isempty(ds_circor_list(cfg))
    warning(['CirCor 2022 data not found in data/circor (training_data.csv + training_data/). ' ...
        'Training continues with PhysioNet 2016 only. Download: ' ...
        'https://physionet.org/content/circor-heart-sound/1.0.3/']);
end
train_segmentation_model(60);
evaluate_segmentation(40);
build_all_features();
train_classifier();
end
