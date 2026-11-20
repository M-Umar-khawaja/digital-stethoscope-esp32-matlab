function app = run_stethoscope()
%RUN_STETHOSCOPE  Starts the digital stethoscope dashboard.
%   Open MATLAB, go to this folder, and type:   run_stethoscope
%
%   Needs MATLAB R2024b (works on R2021a or newer). No toolboxes are needed:
%   all filters, the segmentation and the SVM are implemented in this
%   project. The trained model is in models/steth_model.mat.

here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, 'core'), fullfile(here, 'scripts'));
if isMATLABReleaseOlderThan('R2021a')
    warning('This app was written for MATLAB R2024b; R2021a or newer is required.');
end
cfg = st_config();
if exist(cfg.modelFile, 'file') ~= 2
    warning(['models/steth_model.mat not found. The live view works, but analysis ' ...
        'needs the model: run scripts/train_all.m (about 1 hour).']);
end
app = StethoscopeApp();
if nargout == 0, clear app; end
end
