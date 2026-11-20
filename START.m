%% DIGITAL STETHOSCOPE - START HERE
%  Press the green "Run" button above (or press F5).
%  The dashboard window opens. See README.txt for the next steps.

clc;
projectFolder = fileparts(mfilename('fullpath'));
softwareFolder = fullfile(projectFolder, '1_Software');
cd(softwareFolder);
addpath(fullfile(softwareFolder, 'core'), fullfile(softwareFolder, 'scripts'), ...
        fullfile(softwareFolder, 'tests'));

fprintf('Digital Stethoscope\n');
fprintf('MATLAB version: %s\n', version('-release'));
if isMATLABReleaseOlderThan('R2021a')
    error('This project needs MATLAB R2021a or newer (made for R2024b).');
end
if exist(fullfile(softwareFolder, 'models', 'steth_model.mat'), 'file') ~= 2
    error('The file 1_Software/models/steth_model.mat is missing. Copy the project folder again.');
end
ports = serialportlist("available");
if isempty(ports)
    fprintf(['No ESP32 found. That is OK: choose "Simulated device" in the Port list\n' ...
             'to see a demo, or plug in the ESP32 and press the refresh button.\n']);
else
    fprintf('Serial ports found: %s  (the ESP32 is usually the only one)\n', strjoin(ports, ', '));
end
fprintf('Opening the dashboard...\n');
run_stethoscope;
