function run_tests()
%RUN_TESTS  Runs every automatic check of the software (about 1 minute).
%   In MATLAB:  cd software; addpath core scripts tests; run_tests
here = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(here, 'core'), fullfile(here, 'scripts'), fullfile(here, 'tests'));
test_core_dsp();
test_svm();
test_live_pipeline();
test_analysis();
fprintf('\nALL TESTS PASSED\n');
end
