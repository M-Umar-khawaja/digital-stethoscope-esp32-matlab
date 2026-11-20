function test_dashboard(port)
%TEST_DASHBOARD  Drives the real dashboard like a user (MATLAB only).
%   test_dashboard()          uses "Simulated device"
%   test_dashboard('COM3')    uses the ESP32
%   Connect -> live view for 10 s -> Record 20 s -> result -> Play -> Save.
if nargin < 1, port = 'Simulated device'; end
here = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(here, 'core'), fullfile(here, 'scripts'));
old = findall(groot, 'Type', 'figure', 'Name', 'Digital Stethoscope - Heart Sound Analysis');
delete(old);
app = StethoscopeApp(); %#ok<NASGU>
fig = findall(groot, 'Type', 'figure', 'Name', 'Digital Stethoscope - Heart Sound Analysis');
assert(isscalar(fig), 'dashboard window not found');
scr = get(groot, 'ScreenSize'); p = fig.Position;
fprintf('screen %dx%d, window [%d %d %d %d]\n', scr(3), scr(4), p);
assert(p(1) >= 1 && p(1) + p(3) - 1 <= scr(3) && p(2) >= 1 && p(2) + p(4) + 30 <= scr(4), ...
    'window does not fit on the screen');
dd = findall(fig, 'Tag', 'StethoscopePort');
fprintf('ports offered: %s\n', strjoin(dd.Items, ', '));
assert(any(strcmp(dd.Items, port)), 'port %s not offered', port);
dd.Value = port;
btn = @(txt) byText(fig, 'uibutton', txt);
press = @(b) b.ButtonPushedFcn(b, []);

press(btn('^Connect$'));
waitFor(10);
fprintf('connection : %s\n', labelText(fig, '^(Connected|No data|Connection)'));
fprintf('wiring     : %s\n', labelText(fig, '^Wiring'));
fprintf('live HR    : %s (%s)\n', hrText(fig), labelText(fig, '^live'));
fprintf('level      : %s\n', labelText(fig, '^LEVEL'));

press(btn('Record'));
waitFor(23);
res = findall(fig, 'Type', 'uilabel', 'FontSize', 23);
fprintf('result     : %s | %s\n', res.Text, labelText(fig, '^(Confidence|Not classified)'));
fprintf('heart rate : %s bpm (%s)\n', hrText(fig), labelText(fig, '^from recording'));
sys = findall(fig, 'Type', 'uilabel', 'FontSize', 19);
fprintf('intervals  : %s\n', strjoin(fliplr({sys.Text}), '  /  '));
assert(~strcmp(res.Text, 'No result yet'), 'recording was not analysed');

pb = btn('Play$'); assert(strcmp(pb.Enable, 'on'), 'Play disabled');
press(pb); pause(1.5); press(btn('Stop$')); pause(0.3);
press(btn('^Save$')); pause(1);
cfg = st_config();
d = dir(fullfile(cfg.saveDir, 'steth_*_screen.png'));
[~, k] = max([d.datenum]);
fprintf('saved      : %s\n', fullfile(d(k).folder, d(k).name));
delete(findall(groot, 'Type', 'figure', 'Name', 'Saved'));
press(btn('^Disconnect$')); pause(0.5);
fig.CloseRequestFcn(fig, []);
fprintf('test_dashboard (%s): passed\n', port);
end

function waitFor(sec)
t = tic;
while toc(t) < sec, pause(0.1); end
end

function s = hrText(fig)
h = findall(fig, 'Type', 'uilabel', 'FontSize', 58); s = h.Text;
end

function h = byText(fig, type, pat)
h = findall(fig, 'Type', type);
h = h(~cellfun(@isempty, regexp({h.Text}, pat, 'once')));
assert(~isempty(h), 'no %s matching "%s"', type, pat);
h = h(1);
end

function s = labelText(fig, pat)
h = findall(fig, 'Type', 'uilabel');
h = h(~cellfun(@isempty, regexp({h.Text}, pat, 'once')));
if isempty(h), s = '(none)'; else, s = strjoin({h.Text}, ' | '); end
end
