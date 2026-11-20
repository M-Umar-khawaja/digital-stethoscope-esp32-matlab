classdef StethoscopeApp < handle
%STETHOSCOPEAPP  Digital stethoscope dashboard (MATLAB R2024b or newer).
%   app = StethoscopeApp();      or run  run_stethoscope
%
%   Live:      connect to the ESP32, see the filtered heart sound, its
%              spectrogram and the heart rate while placing the chest piece.
%   Record:    capture 20 s, then the clip is analysed: S1/S2 marked, heart
%              rate, systole/diastole intervals, signal quality, and the
%              normal/abnormal screening result with its confidence.
%   Play/Save/Open: listen to the clip, save it (WAV + results + picture),
%              or analyse any WAV file (e.g. PhysioNet recordings).
%   "Simulated device" in the port list streams a PhysioNet recording as if
%   it came from the ESP32, to test everything without hardware.

    properties (Access = private)
        cfg; model; modelOk = false
        % ui
        fig; ddPort; btnRefresh; btnConnect; lampConn; lblConn; lampWire; lblWire
        axLive; lnLive; lblLevel; axSpec; imSpec; axClip; lnClip; pS1; pS2; lgClip
        lblHr; lblHrUnit; lblHrSrc; ddCue
        pnlResult; stripe; lblIcon; lblResult; lblConf; axConf; patConf; lblReason
        lblSys; lblDia; lblCycles
        btnRecord; axProg; patProg; lblProg; btnPlay; btnSave; btnOpen
        lblFooter
        % live data
        sp = []; tmr = []; carry = ''; live; lastDataTime = 0; lastHrTime = 0
        hrLive = NaN; specMax = -inf; yLim = 50; tickCount = 0
        levelBuf = []; lastLevelTime = 0
        beatState; cuePlayers = cell(1, 2)
        sim = struct('active', false, 'x', [], 'fs', 0, 'pos', 1, 't0', 0, 'sent', 0)
        % recording / result
        recording = false; recBuf = []; recN = 0; recTarget = 0
        result = []; resultName = ''; rawForSave = []; rawFs = 0
        player = []
        C   % colour palette
    end

    methods
        function app = StethoscopeApp()
            app.cfg = st_config();
            app.C = StethoscopeApp.palette();
            app.loadModel();
            app.buildUi();
            app.live = st_live_init(app.cfg);
            app.refreshPorts();
            app.setResultEmpty();
            app.updateButtons();
            app.tmr = timer('ExecutionMode', 'fixedSpacing', 'BusyMode', 'drop', ...
                'Period', app.cfg.timerPeriod, 'TimerFcn', @(~, ~) app.onTick(), ...
                'Name', 'StethoscopeTimer');
            if ~app.modelOk
                uialert(app.fig, ['Trained model not found (models/steth_model.mat). ' ...
                    'Live view works; run scripts/train_all.m to enable analysis.'], ...
                    'Model missing', 'Icon', 'warning');
            end
        end

        function delete(app)
            app.cleanup();
        end
    end

    % =====================================================================
    methods (Access = private)

        % ------------------------------------------------------------- setup
        function loadModel(app)
            if exist(app.cfg.modelFile, 'file') == 2
                s = load(app.cfg.modelFile);
                app.model = s.model;
                app.modelOk = true;
            end
        end

        function buildUi(app)
            C = app.C;
            % medium window: about 90% of the screen, at most 1320 x 740,
            % centred, leaving room for the taskbar and title bar
            scr = get(groot, 'ScreenSize');
            w = round(min(1320, max(960, 0.90*scr(3))));
            h = round(min(740, max(540, 0.86*scr(4) - 30)));
            pos = [scr(1) + round((scr(3) - w)/2), scr(2) + max(50, round((scr(4) - h)/2) + 10), w, h];
            app.fig = uifigure('Name', 'Digital Stethoscope - Heart Sound Analysis', ...
                'Color', C.bg, 'Position', pos, ...
                'CloseRequestFcn', @(~, ~) app.onClose());
            if ~isMATLABReleaseOlderThan('R2025a')
                app.fig.Theme = 'dark';   % R2025a+: dark dialogs too
            end
            root = uigridlayout(app.fig, [3 1], 'RowHeight', {42, '1x', 50}, ...
                'Padding', [10 8 10 8], 'RowSpacing', 8, 'BackgroundColor', C.bg);

            % ---- header
            hdr = uigridlayout(root, [1 10], 'ColumnWidth', {'fit', '1x', 'fit', 150, 36, 120, 16, 200, 16, 220}, ...
                'Padding', [4 0 4 0], 'ColumnSpacing', 8, 'BackgroundColor', C.bg);
            uilabel(hdr, 'Text', 'Digital Stethoscope', 'FontSize', 18, 'FontWeight', 'bold', 'FontColor', C.text);
            uilabel(hdr, 'Text', '', 'FontSize', 12, 'FontColor', C.text2);
            uilabel(hdr, 'Text', 'Port', 'FontSize', 12, 'FontColor', C.text2, 'HorizontalAlignment', 'right');
            app.ddPort = uidropdown(hdr, 'Tag', 'StethoscopePort', 'Items', {'(none)'}, 'FontSize', 12, ...
                'BackgroundColor', C.panel, 'FontColor', C.text);
            app.btnRefresh = uibutton(hdr, 'Text', char(8635), 'FontSize', 16, 'Tooltip', 'Refresh port list', ...
                'BackgroundColor', C.panel, 'FontColor', C.text, 'ButtonPushedFcn', @(~, ~) app.refreshPorts());
            app.btnConnect = uibutton(hdr, 'Text', 'Connect', 'FontSize', 13, 'FontWeight', 'bold', ...
                'BackgroundColor', C.accent, 'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) app.onConnect());
            app.lampConn = uilamp(hdr, 'Color', C.neutral);
            app.lblConn = uilabel(hdr, 'Text', 'Not connected', 'FontSize', 12, 'FontColor', C.text2);
            app.lampWire = uilamp(hdr, 'Color', C.neutral);
            app.lblWire = uilabel(hdr, 'Text', 'Wiring: not checked', 'FontSize', 12, 'FontColor', C.text2);

            % ---- body
            body = uigridlayout(root, [1 2], 'ColumnWidth', {'1x', 300}, 'Padding', 0, ...
                'ColumnSpacing', 8, 'BackgroundColor', C.bg);
            left = uigridlayout(body, [3 1], 'RowHeight', {'1x', '0.8x', '1.15x'}, 'Padding', 0, ...
                'RowSpacing', 8, 'BackgroundColor', C.bg);
            [app.axLive, app.lblLevel] = app.makeAxes(left, 'LIVE HEART SOUND  (filtered 20-500 Hz)', 'mV', false);
            app.axSpec = app.makeAxes(left, 'LIVE SPECTROGRAM', 'Hz', false);
            app.axClip = app.makeAxes(left, 'RECORDING  ·  S1 / S2 marked', 'norm.', true);

            nLive = 2*1200;
            app.lnLive = line(app.axLive, linspace(-app.cfg.liveSeconds, 0, nLive), zeros(1, nLive), ...
                'Color', C.trace, 'LineWidth', 1.1, 'HitTest', 'off', 'PickableParts', 'none');
            app.axLive.XLim = [-app.cfg.liveSeconds 0];
            app.axLive.YLim = [-app.yLim app.yLim];
            app.axLive.XGrid = 'off'; app.axLive.YGrid = 'off';
            app.axLive.XLabel.String = 'seconds';

            [S, f, t] = st_spectrogram(zeros(app.cfg.liveSpecSeconds*app.cfg.fs, 1), app.cfg.fs, ...
                app.cfg.specWin, app.cfg.specHop, app.cfg.specMaxHz);
            app.imSpec = image(app.axSpec, 'XData', t - app.cfg.liveSpecSeconds, 'YData', f, ...
                'CData', S*0 - 200, 'CDataMapping', 'scaled', 'HitTest', 'off', 'PickableParts', 'none');
            app.axSpec.YDir = 'normal';
            app.axSpec.XLim = [-app.cfg.liveSpecSeconds 0];
            app.axSpec.YLim = [0 app.cfg.specMaxHz];
            app.axSpec.CLim = [-60 0];
            colormap(app.axSpec, StethoscopeApp.specMap());
            app.axSpec.XLabel.String = 'seconds';
            app.axSpec.XGrid = 'off'; app.axSpec.YGrid = 'off';

            app.pS1 = patch(app.axClip, NaN, NaN, C.s1, 'FaceAlpha', 0.28, 'EdgeColor', 'none', ...
                'DisplayName', 'S1', 'HitTest', 'off');
            app.pS2 = patch(app.axClip, NaN, NaN, C.s2, 'FaceAlpha', 0.28, 'EdgeColor', 'none', ...
                'DisplayName', 'S2', 'HitTest', 'off');
            app.lnClip = line(app.axClip, NaN, NaN, 'Color', C.trace, 'LineWidth', 0.9, 'HitTest', 'off');
            app.lgClip = legend(app.axClip, [app.pS1 app.pS2], {'S1', 'S2'}, 'Location', 'northeast', ...
                'Orientation', 'horizontal', 'TextColor', C.text, 'Color', C.panel, 'EdgeColor', C.border, ...
                'FontSize', 11);
            app.axClip.XLabel.String = 'seconds';
            app.axClip.YLim = [-1 1];
            app.axClip.XLim = [0 app.cfg.recordSeconds];

            right = uigridlayout(body, [3 1], 'RowHeight', {136, '1x', 128}, 'Padding', 0, ...
                'RowSpacing', 8, 'BackgroundColor', C.bg);
            % heart-rate tile
            hrP = app.makeTile(right);
            g = uigridlayout(hrP, [3 2], 'RowHeight', {24, '1x', 16}, 'ColumnWidth', {'1x', 118}, ...
                'Padding', [14 6 14 6], 'RowSpacing', 0, 'BackgroundColor', C.panel);
            l = uilabel(g, 'Text', 'HEART RATE', 'FontSize', 12, 'FontWeight', 'bold', 'FontColor', C.text2);
            l.Layout.Row = 1; l.Layout.Column = 1;
            app.ddCue = uidropdown(g, 'Items', {'Cue: Beat', 'Cue: Lub-dub', 'Cue: Off'}, ...
                'ItemsData', {'Beat', 'Lub-dub', 'Off'}, 'Value', app.cfg.soundDefault, ...
                'BackgroundColor', C.panel, 'FontColor', C.text, 'FontSize', 11, ...
                'Tooltip', 'Synthesized live heartbeat cue', ...
                'ValueChangedFcn', @(~, ~) app.stopCue());
            app.ddCue.Layout.Row = 1; app.ddCue.Layout.Column = 2;
            app.lblHr = uilabel(g, 'Text', '--', 'FontSize', 58, 'FontWeight', 'bold', 'FontName', 'Consolas', ...
                'FontColor', C.trace, 'HorizontalAlignment', 'left');
            app.lblHr.Layout.Row = 2; app.lblHr.Layout.Column = 1;
            app.lblHrUnit = uilabel(g, 'Text', 'bpm', 'FontSize', 18, 'FontColor', C.text2, ...
                'VerticalAlignment', 'bottom');
            app.lblHrUnit.Layout.Row = 2; app.lblHrUnit.Layout.Column = 2;
            app.lblHrSrc = uilabel(g, 'Text', 'waiting for signal', 'FontSize', 11, 'FontColor', C.text2);
            app.lblHrSrc.Layout.Row = 3; app.lblHrSrc.Layout.Column = [1 2];

            % result tile
            app.pnlResult = app.makeTile(right);
            g = uigridlayout(app.pnlResult, [1 2], 'ColumnWidth', {5, '1x'}, 'Padding', 0, ...
                'ColumnSpacing', 0, 'BackgroundColor', C.panel);
            app.stripe = uipanel(g, 'BackgroundColor', C.neutral, 'BorderType', 'none');
            gr = uigridlayout(g, [6 2], 'RowHeight', {18, 38, 20, 8, '1x', 'fit'}, ...
                'ColumnWidth', {34, '1x'}, 'Padding', [12 8 12 8], 'RowSpacing', 5, 'BackgroundColor', C.panel);
            l = uilabel(gr, 'Text', 'SCREENING RESULT', 'FontSize', 12, 'FontWeight', 'bold', 'FontColor', C.text2);
            l.Layout.Row = 1; l.Layout.Column = [1 2];
            app.lblIcon = uilabel(gr, 'Text', '', 'FontSize', 26, 'FontWeight', 'bold', 'FontColor', C.text2);
            app.lblIcon.Layout.Row = 2; app.lblIcon.Layout.Column = 1;
            app.lblResult = uilabel(gr, 'Text', '', 'FontSize', 23, 'FontWeight', 'bold', 'FontColor', C.text, ...
                'WordWrap', 'on');
            app.lblResult.Layout.Row = 2; app.lblResult.Layout.Column = 2;
            app.lblConf = uilabel(gr, 'Text', '', 'FontSize', 14, 'FontColor', C.text);
            app.lblConf.Layout.Row = 3; app.lblConf.Layout.Column = [1 2];
            [app.axConf, app.patConf] = app.makeBar(gr, C.neutral);
            app.axConf.Layout.Row = 4; app.axConf.Layout.Column = [1 2];
            app.lblReason = uilabel(gr, 'Text', '', 'FontSize', 12, 'FontColor', C.text, ...
                'WordWrap', 'on', 'VerticalAlignment', 'top');
            app.lblReason.Layout.Row = 5; app.lblReason.Layout.Column = [1 2];
            app.lblFooter = uilabel(gr, 'Text', '', 'FontSize', 11, 'FontColor', C.text2);
            app.lblFooter.Layout.Row = 6; app.lblFooter.Layout.Column = [1 2];

            % intervals tile
            ip = app.makeTile(right);
            g = uigridlayout(ip, [4 2], 'RowHeight', {18, '1x', '1x', 16}, 'ColumnWidth', {'1x', 'fit'}, ...
                'Padding', [14 6 14 6], 'RowSpacing', 2, 'BackgroundColor', C.panel);
            l = uilabel(g, 'Text', 'INTERVALS (median ± SD)', 'FontSize', 12, 'FontWeight', 'bold', 'FontColor', C.text2);
            l.Layout.Row = 1; l.Layout.Column = [1 2];
            uilabel(g, 'Text', ['S1' char(8594) 'S2  systole'], 'FontSize', 12, 'FontColor', C.text2);
            app.lblSys = uilabel(g, 'Text', '--', 'FontSize', 19, 'FontWeight', 'bold', 'FontName', 'Consolas', ...
                'FontColor', C.text, 'HorizontalAlignment', 'right');
            uilabel(g, 'Text', ['S2' char(8594) 'S1  diastole'], 'FontSize', 12, 'FontColor', C.text2);
            app.lblDia = uilabel(g, 'Text', '--', 'FontSize', 19, 'FontWeight', 'bold', 'FontName', 'Consolas', ...
                'FontColor', C.text, 'HorizontalAlignment', 'right');
            app.lblCycles = uilabel(g, 'Text', '', 'FontSize', 11, 'FontColor', C.text2);
            app.lblCycles.Layout.Row = 4; app.lblCycles.Layout.Column = [1 2];

            % ---- action bar
            bar = uigridlayout(root, [1 6], 'ColumnWidth', {150, '1x', 110, 100, 100, 110}, ...
                'Padding', [0 4 0 4], 'ColumnSpacing', 10, 'BackgroundColor', C.bg);
            app.btnRecord = uibutton(bar, 'Text', [char(9679) '  Record ' num2str(app.cfg.recordSeconds) ' s'], ...
                'FontSize', 14, 'FontWeight', 'bold', 'BackgroundColor', C.accent, 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~, ~) app.onRecord());
            barHolder = uigridlayout(bar, [3 1], 'RowHeight', {'1x', 10, '1x'}, 'Padding', 0, ...
                'RowSpacing', 0, 'BackgroundColor', C.bg);
            uilabel(barHolder, 'Text', '');
            [app.axProg, app.patProg] = app.makeBar(barHolder, C.accent);
            app.lblProg = uilabel(bar, 'Text', '', 'FontSize', 13, 'FontName', 'Consolas', 'FontColor', C.text);
            app.btnPlay = uibutton(bar, 'Text', [char(9654) '  Play'], 'FontSize', 13, ...
                'BackgroundColor', C.panel, 'FontColor', C.text, 'ButtonPushedFcn', @(~, ~) app.onPlay());
            app.btnSave = uibutton(bar, 'Text', 'Save', 'FontSize', 13, ...
                'BackgroundColor', C.panel, 'FontColor', C.text, 'ButtonPushedFcn', @(~, ~) app.onSave());
            app.btnOpen = uibutton(bar, 'Text', 'Open file', 'FontSize', 13, ...
                'BackgroundColor', C.panel, 'FontColor', C.text, 'ButtonPushedFcn', @(~, ~) app.onOpen());
        end

        function [ax, side] = makeAxes(app, parent, titleText, yUnit, interactive)
            % side: right-aligned label in the title row (used for the level meter)
            C = app.C;
            p = uipanel(parent, 'BackgroundColor', C.panel, 'BorderType', 'line', 'HighlightColor', C.border);
            g = uigridlayout(p, [2 2], 'RowHeight', {18, '1x'}, 'ColumnWidth', {'1x', 'fit'}, ...
                'Padding', [10 6 10 4], 'RowSpacing', 0, 'BackgroundColor', C.panel);
            uilabel(g, 'Text', titleText, 'FontSize', 11, 'FontWeight', 'bold', 'FontColor', C.text2);
            side = uilabel(g, 'Text', '', 'FontSize', 11, 'FontWeight', 'bold', 'FontColor', C.text2, ...
                'HorizontalAlignment', 'right');
            ax = uiaxes(g,'Color', C.plot, 'XColor', C.text2, 'YColor', C.text2, 'GridColor', C.grid, ...
                'GridAlpha', 1, 'FontSize', 10, 'Box', 'on', 'BackgroundColor', C.panel, ...
                'XGrid', 'on', 'YGrid', 'on', 'TickDir', 'out');
            ax.Layout.Row = 2; ax.Layout.Column = [1 2];
            ax.YLabel.String = yUnit;
            ax.YLabel.Color = C.text2;
            ax.XLabel.Color = C.text2;
            if ~interactive
                ax.Toolbar.Visible = 'off';
                disableDefaultInteractivity(ax);
            end
        end

        function [g, fillPanel] = makeBar(app, parent, colour)
            % Thin horizontal bar: a 2-column grid whose column weights are
            % the filled and empty fractions (see setBar).
            g = uigridlayout(parent, [1 2], 'ColumnWidth', {'0.0001x', '1x'}, 'Padding', 0, ...
                'ColumnSpacing', 0, 'BackgroundColor', app.C.track);
            fillPanel = uipanel(g, 'BackgroundColor', colour, 'BorderType', 'none');
            uipanel(g, 'BackgroundColor', app.C.track, 'BorderType', 'none');
        end

        function setBar(~, g, frac)
            frac = min(max(frac, 0.0001), 1);
            g.ColumnWidth = {sprintf('%.4fx', frac), sprintf('%.4fx', max(1 - frac, 0.0001))};
        end

        function p = makeTile(app, parent)
            p = uipanel(parent, 'BackgroundColor', app.C.panel, 'BorderType', 'line', ...
                'HighlightColor', app.C.border);
        end

        % ------------------------------------------------------- connection
        function refreshPorts(app)
            items = {};
            try
                items = cellstr(serialportlist("available"));
            catch
            end
            items = [items(:).', {'Simulated device'}];
            app.ddPort.Items = items;
            app.ddPort.Value = items{1};
        end

        function onConnect(app)
            if app.isConnected()
                app.disconnect('Not connected', app.C.neutral);
                return;
            end
            port = app.ddPort.Value;
            app.setConn(app.C.abnormal, ['Connecting ' port char(8230)]);
            app.btnConnect.Enable = 'off';
            drawnow;
            try
                if strcmp(port, 'Simulated device')
                    app.startSimulation();
                else
                    app.sp = serialport(port, app.cfg.baud, 'Timeout', 1);
                    pause(0.3);                    % ESP32 may reset when the port opens
                    flush(app.sp);
                    write(app.sp, 'r', 'char');    % make sure raw 4 kHz streaming is on
                    pause(0.05);
                    write(app.sp, 'c', 'char');    % ask for the wiring check
                end
                app.carry = '';
                app.live = st_live_init(app.cfg);
                app.beatState = st_beat_init(app.cfg);
                app.lastDataTime = tic;
                app.lastHrTime = tic;
                app.levelBuf = []; app.lastLevelTime = tic;
                app.specMax = -inf;
                app.setConn(app.C.normal, ['Connected ' char(183) ' ' port]);
                app.setWire(app.C.neutral, 'Wiring: checking...');
                app.btnConnect.Text = 'Disconnect';
                app.btnConnect.BackgroundColor = app.C.border;
                start(app.tmr);
            catch err
                app.sp = [];
                app.sim.active = false;
                app.setConn(app.C.fail, 'Connection failed');
                uialert(app.fig, sprintf(['Could not open %s.\n\n%s\n\nCheck the USB cable (data, not charge-only), ' ...
                    'close Arduino Serial Monitor/Plotter, and press Refresh.'], port, err.message), 'Connection');
            end
            app.btnConnect.Enable = 'on';
            app.updateButtons();
        end

        function startSimulation(app)
            recs = dir(fullfile(app.cfg.dataDir, 'training-a', 'a0001.wav'));
            if isempty(recs)
                recs = dir(fullfile(app.cfg.dataDir, 'training-*', '*.wav'));
            end
            if isempty(recs)
                error('No PhysioNet WAV files found in %s', app.cfg.dataDir);
            end
            [x, fs] = st_read_audio(fullfile(recs(1).folder, recs(1).name));
            app.sim = struct('active', true, 'x', x, 'fs', fs, 'pos', 1, 't0', tic, 'sent', 0);
            app.carry = '';
        end

        function disconnect(app, msg, colour)
            if app.recording, app.stopRecording(false); end
            try, stop(app.tmr); catch, end
            app.stopCue();
            if ~isempty(app.sp)
                try, write(app.sp, 's', 'char'); catch, end
                try, delete(app.sp); catch, end
            end
            app.sp = [];
            app.sim.active = false;
            app.setConn(colour, msg);
            app.setWire(app.C.neutral, 'Wiring: not checked');
            app.lblLevel.Text = '';
            app.btnConnect.Text = 'Connect';
            app.btnConnect.BackgroundColor = app.C.accent;
            if ~strcmp(app.lblHrSrc.Text, 'from recording')   % keep a recording's result
                app.lblHr.Text = '--';
                app.lblHrSrc.Text = 'not connected';
            end
            app.updateButtons();
        end

        function tf = isConnected(app)
            tf = ~isempty(app.sp) || app.sim.active;
        end

        % --------------------------------------------------------- the loop
        function onTick(app)
            try
                chunk = app.readChunk();
                if isempty(chunk)
                    if toc(app.lastDataTime) > 2.5
                        app.setConn(app.C.fail, 'No data - check cable / firmware');
                    end
                    return;
                end
                app.lastDataTime = tic;
                [counts, status, app.carry] = st_serial_parse(app.carry, chunk);
                for i = 1:numel(status), app.handleStatus(status{i}); end
                if isempty(counts), return; end
                if app.recording
                    n = min(numel(counts), app.recTarget - app.recN);
                    app.recBuf(app.recN + 1:app.recN + n) = counts(1:n);
                    app.recN = app.recN + n;
                    frac = app.recN / app.recTarget;
                    app.setBar(app.axProg, frac);
                    app.lblProg.Text = sprintf('%4.1f / %d s', app.recN/app.cfg.fsDevice, app.cfg.recordSeconds);
                end
                [app.live, filtered] = st_live_push(app.live, counts);
                [app.beatState, events] = st_beat_push(app.beatState, filtered, app.cfg);
                app.playCue(events);
                nLev = app.cfg.levelSeconds*app.cfg.fsDevice;
                app.levelBuf = [app.levelBuf; counts(:)];
                if numel(app.levelBuf) > nLev, app.levelBuf = app.levelBuf(end - nLev + 1:end); end
                if toc(app.lastLevelTime) >= 0.5
                    app.lastLevelTime = tic;
                    app.updateLevel();
                end
                app.drawLive();
                if toc(app.lastHrTime) >= app.cfg.hrUpdateSec
                    app.lastHrTime = tic;
                    app.updateLiveHr();
                end
                if app.recording && app.recN >= app.recTarget
                    app.stopRecording(true);
                end
                drawnow limitrate;
            catch err
                app.disconnect('Connection lost', app.C.fail);
                uialert(app.fig, sprintf('The connection stopped:\n%s', err.message), 'Connection');
            end
        end

        function chunk = readChunk(app)
            chunk = '';
            if app.sim.active
                due = round(toc(app.sim.t0) * app.cfg.fsDevice) - app.sim.sent;
                due = min(due, app.cfg.fsDevice);       % at most 1 s per tick
                if due > 0
                    chunk = st_device_sim(app.sim.x, app.sim.fs, app.sim.pos, due, app.cfg);
                    app.sim.pos = app.sim.pos + due;
                    app.sim.sent = app.sim.sent + due;
                    if app.sim.sent == due      % first chunk: pretend wiring check passed
                        chunk = [sprintf('# OK     bias is correct (simulated device).\n'), chunk];
                    end
                end
                return;
            end
            n = app.sp.NumBytesAvailable;
            if n > 0
                chunk = read(app.sp, n, 'char');
            end
        end

        function handleStatus(app, s)
            C = app.C;
            if startsWith(s, '# OK')
                app.setWire(C.normal, 'Wiring: OK');
            elseif startsWith(s, '# FAIL')
                app.setWire(C.fail, ['Wiring: FAIL ' char(8211) ' see message']);
                app.lblWire.Tooltip = s;
                uialert(app.fig, strtrim(s(7:end)), 'Wiring check failed');
            elseif startsWith(s, '# WARN')
                app.setWire(C.abnormal, 'Wiring: check bias');
                app.lblWire.Tooltip = s;
            elseif contains(s, 'clipping')
                app.lblWire.Tooltip = 'Signal clipping: turn the gain screw down a little';
            end
            app.updateButtons();
        end

        function drawLive(app)
            buf = app.live.buf;
            nL = round(app.cfg.liveSeconds*app.cfg.fs);
            [t, y] = st_minmax_decimate(buf(end - min(nL, numel(buf)) + 1:end), app.cfg.fs, 1200);
            app.lnLive.XData = t;
            app.lnLive.YData = y;
            % slowly adapting vertical scale (no jumping every frame)
            pk = max(abs(buf(end - min(end, app.cfg.fs) + 1:end)));
            target = max(5, 1.25*pk);
            if target > app.yLim
                app.yLim = target;
            else
                app.yLim = 0.995*app.yLim + 0.005*target;
            end
            app.axLive.YLim = [-app.yLim app.yLim];
            app.tickCount = app.tickCount + 1;
            if mod(app.tickCount, 2) == 0           % spectrogram at 10 frames/s
                nS = app.cfg.liveSpecSeconds*app.cfg.fs;
                [S, ~, ts] = st_spectrogram(buf(end - min(nS, numel(buf)) + 1:end), app.cfg.fs, ...
                    app.cfg.specWin, app.cfg.specHop, app.cfg.specMaxHz);
                mx = max(S(:));
                if mx > app.specMax, app.specMax = mx; else, app.specMax = 0.98*app.specMax + 0.02*mx; end
                app.imSpec.CData = S;
                app.imSpec.XData = ts - app.cfg.liveSpecSeconds;
                app.axSpec.CLim = [app.specMax - app.cfg.specRangeDb, app.specMax];
            end
        end

        function updateLevel(app)
            [state, p99] = st_level(app.levelBuf, app.cfg);
            C = app.C;
            switch state
                case 'good', txt = 'Good'; col = C.normal;
                case 'weak', txt = 'Too weak - press firmer / raise gain'; col = C.abnormal;
                case 'loud', txt = 'Too loud - lower gain / hold still'; col = C.fail;
                otherwise,   txt = ''; col = C.text2;
            end
            if isempty(txt)
                app.lblLevel.Text = '';
            else
                app.lblLevel.Text = sprintf('LEVEL  %s %s  (%d mV)', char(9679), txt, round(p99));
            end
            app.lblLevel.FontColor = col;
        end

        function updateLiveHr(app)
            if app.recording || ~strcmp(app.lblHrSrc.Text, 'from recording') || isempty(app.result)
                nW = round(app.cfg.hrWindowSec*app.cfg.fs);
                buf = app.live.buf;
                if app.live.total < nW*app.live.decim
                    app.lblHrSrc.Text = 'live  ·  measuring...';
                    return;
                end
                x = buf(end - min(nW, numel(buf)) + 1:end);
                [hr, ok] = st_live_hr(x, app.cfg);
                if ok
                    app.hrLive = hr;
                    app.lblHr.Text = sprintf('%d', round(hr));
                    app.lblHrSrc.Text = sprintf('live  ·  last %d s', app.cfg.hrWindowSec);
                else
                    app.lblHr.Text = '--';
                    app.lblHrSrc.Text = 'live  ·  no clear rhythm';
                end
            end
        end

        % -------------------------------------------------------- recording
        function onRecord(app)
            if app.recording
                app.stopRecording(app.recN >= app.cfg.minSeconds*app.cfg.fsDevice);
                return;
            end
            app.stopPlayback();
            app.recTarget = app.cfg.recordSeconds * app.cfg.fsDevice;
            app.recBuf = zeros(app.recTarget, 1);
            app.recN = 0;
            app.recording = true;
            app.btnRecord.Text = [char(9632) '  Stop'];
            app.btnRecord.BackgroundColor = app.C.fail;
            app.setBar(app.axProg, 0);
            app.lblHrSrc.Text = 'live  ·  recording';
            app.updateButtons();
        end

        function stopRecording(app, analyse)
            app.recording = false;
            app.btnRecord.Text = [char(9679) '  Record ' num2str(app.cfg.recordSeconds) ' s'];
            app.btnRecord.BackgroundColor = app.C.accent;
            if analyse && app.recN > 0
                raw = app.recBuf(1:app.recN);
                app.lblProg.Text = 'analysing...';
                drawnow;
                % simulated device plays a hospital recording: no device calibration
                app.analyse(raw, app.cfg.fsDevice, ~app.sim.active, ['Recording ' datestr(now, 'HH:MM:SS')]);
                app.lblProg.Text = sprintf('%.1f s recorded', app.recN/app.cfg.fsDevice);
            else
                app.setBar(app.axProg, 0);
                app.lblProg.Text = '';
            end
            app.updateButtons();
        end

        % --------------------------------------------------------- analysis
        function analyse(app, raw, fs, isAdc, name)
            if ~app.modelOk
                uialert(app.fig, 'No trained model. Run scripts/train_all.m first.', 'Model missing');
                return;
            end
            R = st_analyze(raw, fs, app.model, app.cfg, isAdc);
            app.result = R;
            app.resultName = name;
            app.rawForSave = raw;
            app.rawFs = fs;
            app.showResult(R);
        end

        function showResult(app, R)
            C = app.C;
            % recording plot with S1/S2 shading
            if ~isempty(R.xd)
                t = (0:numel(R.xd)-1) / R.fs;
                app.lnClip.XData = t; app.lnClip.YData = R.xd;
                app.axClip.XLim = [0 max(t(end), 1)];
                app.axClip.YLim = [-1 1];
                [xs, ys] = StethoscopeApp.stateBoxes(R.states, 1, R.fs);
                set(app.pS1, 'XData', xs, 'YData', ys);
                [xs, ys] = StethoscopeApp.stateBoxes(R.states, 3, R.fs);
                set(app.pS2, 'XData', xs, 'YData', ys);
            end
            okQ = strcmp(R.status, 'ok');   % numbers from a poor clip are not shown
            % heart rate
            if okQ && ~isnan(R.hr)
                app.lblHr.Text = sprintf('%d', round(R.hr));
                app.lblHrSrc.Text = 'from recording';
            elseif ~okQ
                app.lblHr.Text = '--';
                app.lblHrSrc.Text = 'recording: poor quality';
            end
            % intervals
            if okQ && ~isnan(R.sysMs)
                app.lblSys.Text = sprintf('%d ± %d ms', round(R.sysMs), round(R.sysSdMs));
                app.lblDia.Text = sprintf('%d ± %d ms', round(R.diaMs), round(R.diaSdMs));
                app.lblCycles.Text = sprintf('n = %d cycles  ·  %.0f s clip', R.nCycles, R.durationSec);
            else
                app.lblSys.Text = '--'; app.lblDia.Text = '--';
                app.lblCycles.Text = sprintf('%.0f s clip', R.durationSec);
            end
            % result
            switch R.status
                case 'ok'
                    conf = round(100*R.confidence);
                    if conf >= 80, band = 'High'; elseif conf >= 60, band = 'Moderate'; else, band = 'Low'; end
                    if strcmp(R.label, 'Normal')
                        col = C.normal; icon = char(10003); txt = 'Normal';
                        reason = 'Heart sounds look normal.';
                    else
                        col = C.abnormal; icon = '!'; txt = 'Abnormal';
                        reason = 'Possible murmur or abnormal sound. Refer for clinical examination.';
                    end
                    app.setResult(col, icon, txt, sprintf('Confidence %d%%  (%s)', conf, band), ...
                        R.confidence, reason);
                otherwise
                    app.setResult(C.poor, char(8635), 'Poor quality', 'Not classified - please retry', ...
                        0, R.reason);
            end
            app.lblFooter.Text = app.resultName;
            app.updateButtons();
        end

        function setResult(app, col, icon, txt, confTxt, frac, reason)
            app.stripe.BackgroundColor = col;
            app.lblIcon.Text = icon; app.lblIcon.FontColor = col;
            app.lblResult.Text = txt; app.lblResult.FontColor = col;
            app.lblConf.Text = confTxt;
            app.setBar(app.axConf, frac);
            app.patConf.BackgroundColor = col;
            app.lblReason.Text = reason;
        end

        function setResultEmpty(app)
            app.setResult(app.C.neutral, '', 'No result yet', '', 0, ...
                'Connect, place the chest piece, then press Record. Or open a WAV file.');
        end

        % ----------------------------------------------------- play / save
        function playCue(app, events)
            mode = app.ddCue.Value;
            if isempty(events) || strcmp(mode, 'Off'), return; end
            if ~isempty(app.player) && isplaying(app.player), return; end
            if strcmp(mode, 'Beat'), events = events(events(:, 2) == 1, :); end
            % Discard stale events when the serial buffer arrives in a burst.
            if isempty(events) || app.beatState.n - events(end, 1) > 0.15 * app.cfg.fs
                return;
            end
            kind = events(end, 2);
            try
                if any(cellfun(@(p) ~isempty(p) && isplaying(p), app.cuePlayers)), return; end
                if isempty(app.cuePlayers{kind})
                    [tone, fs] = st_beat_tone(kind, app.cfg);
                    app.cuePlayers{kind} = audioplayer(tone, fs);
                end
                play(app.cuePlayers{kind});
            catch err
                app.stopCue();
                app.cuePlayers = cell(1, 2);
                app.ddCue.Value = 'Off';
                app.ddCue.Tooltip = 'Audio output unavailable. Select a cue mode to retry.';
                warning('StethoscopeApp:CueAudio', '%s', err.message);
            end
        end

        function stopCue(app)
            for k = 1:numel(app.cuePlayers)
                if ~isempty(app.cuePlayers{k})
                    try, stop(app.cuePlayers{k}); catch, end
                end
            end
        end

        function onPlay(app)
            if ~isempty(app.player) && isplaying(app.player)
                app.stopPlayback();
                return;
            end
            if isempty(app.result) || isempty(app.result.xd), return; end
            app.stopCue();
            fsPlay = 8000;                          % every sound card supports 8 kHz
            x = app.result.xd(:);
            t = (0:numel(x)-1).' / app.result.fs;
            tq = (0:1/fsPlay:t(end)).';
            y = 0.95 * interp1(t, x, tq, 'linear');
            app.player = audioplayer(y, fsPlay);
            app.player.StopFcn = @(~, ~) app.onPlayStopped();
            play(app.player);
            app.btnPlay.Text = [char(9632) '  Stop'];
        end

        function onPlayStopped(app)
            if isvalid(app.btnPlay), app.btnPlay.Text = [char(9654) '  Play']; end
        end

        function stopPlayback(app)
            if ~isempty(app.player)
                try, stop(app.player); catch, end
            end
            app.onPlayStopped();
        end

        function onSave(app)
            if isempty(app.result), return; end
            if exist(app.cfg.saveDir, 'dir') ~= 7, mkdir(app.cfg.saveDir); end
            base = fullfile(app.cfg.saveDir, ['steth_' datestr(now, 'yyyymmdd_HHMMSS')]);
            R = app.result;
            raw = app.rawForSave(:);
            if app.rawFs == app.cfg.fsDevice
                rawWav = (raw - 2048) / 2048;           % ADC counts -> -1..1
            else
                rawWav = raw / max(abs(raw) + eps);
            end
            audiowrite([base '_raw.wav'], max(-1, min(1, rawWav)), app.rawFs);
            audiowrite([base '_filtered.wav'], R.xd, R.fs);
            result = rmfield(R, {'xa', 'xd', 'states'}); %#ok<NASGU>
            source = app.resultName; %#ok<NASGU>
            save([base '_result.mat'], 'result', 'source');
            try
                exportapp(app.fig, [base '_screen.png']);
            catch
            end
            app.lblProg.Text = 'saved';
            uialert(app.fig, sprintf('Saved to\n%s\n\n_raw.wav (re-openable), _filtered.wav (listening),\n_result.mat, _screen.png', ...
                app.cfg.saveDir), 'Saved', 'Icon', 'success');
        end

        function onOpen(app)
            [f, p] = uigetfile({'*.wav', 'WAV recordings (*.wav)'}, 'Open a heart-sound recording');
            figure(app.fig);
            if isequal(f, 0), return; end
            try
                [x, fs] = st_read_audio(fullfile(p, f));
                if fs < app.cfg.fs
                    error('Sample rate %d Hz is too low; at least %d Hz is needed.', fs, app.cfg.fs);
                end
                app.stopPlayback();
                isDev = endsWith(lower(f), '_raw.wav') && fs == app.cfg.fsDevice;
                if isDev                        % saved from our ESP32: back to ADC counts
                    x = round(x*2048 + 2048);
                end
                app.analyse(x, fs, isDev, f);
            catch err
                uialert(app.fig, err.message, 'Cannot open file');
            end
        end

        % ------------------------------------------------------------ misc
        function updateButtons(app)
            conn = app.isConnected();
            app.btnRecord.Enable = matlab.lang.OnOffSwitchState(conn && app.modelOk && ...
                ~strcmp(app.lblWire.Text(1:min(end, 12)), 'Wiring: FAIL'));
            if app.recording, app.btnRecord.Enable = 'on'; end
            hasClip = ~isempty(app.result) && ~isempty(app.result.xd);
            app.btnPlay.Enable = matlab.lang.OnOffSwitchState(hasClip && ~app.recording);
            app.btnSave.Enable = matlab.lang.OnOffSwitchState(hasClip && ~app.recording);
            app.btnOpen.Enable = matlab.lang.OnOffSwitchState(~app.recording);
            app.ddPort.Enable = matlab.lang.OnOffSwitchState(~conn);
            app.btnRefresh.Enable = matlab.lang.OnOffSwitchState(~conn);
        end

        function setConn(app, col, txt)
            app.lampConn.Color = col; app.lblConn.Text = txt;
        end

        function setWire(app, col, txt)
            app.lampWire.Color = col; app.lblWire.Text = txt;
        end

        function onClose(app)
            app.cleanup();
            delete(app.fig);
        end

        function cleanup(app)
            try, stop(app.tmr); delete(app.tmr); catch, end
            app.stopCue();
            if ~isempty(app.sp)
                try, write(app.sp, 's', 'char'); catch, end
                try, delete(app.sp); catch, end
            end
            app.sp = [];
            if ~isempty(app.player)
                try, stop(app.player); catch, end
            end
        end
    end

    % =====================================================================
    methods (Static)
        function C = palette()
            h = @(s) sscanf(s(2:end), '%2x', [1 3]) / 255;
            C.bg = h('#0B0F14');      C.panel = h('#151B23');   C.border = h('#26303B');
            C.plot = h('#0E141A');    C.grid = h('#2A3440');    C.track = h('#222B35');
            C.text = h('#E6EDF3');    C.text2 = h('#8B98A5');   C.accent = h('#2563EB');
            C.trace = h('#4ADE80');   C.s1 = h('#60A5FA');      C.s2 = h('#F472B6');
            C.normal = h('#3FB950');  C.abnormal = h('#F0B429'); C.poor = h('#39C5CF');
            C.fail = h('#F85149');    C.neutral = h('#6E7681');
        end

        function M = specMap()
            h = @(s) sscanf(s(2:end), '%2x', [1 3]) / 255;
            stops = [h('#0B0F14'); h('#12324A'); h('#1F7A8C'); h('#4ADE80'); h('#F0FFF4')];
            x = linspace(0, 1, size(stops, 1));
            xi = linspace(0, 1, 256).';
            M = [interp1(x, stops(:, 1), xi), interp1(x, stops(:, 2), xi), interp1(x, stops(:, 3), xi)];
        end

        function [xs, ys] = stateBoxes(states, which, fs)
            % Rectangles (one per S1 or S2 sound) for a single patch object.
            m = states(:) == which;
            d = diff([0; m; 0]);
            on = find(d == 1); off = find(d == -1) - 1;
            t0 = (on - 1).' / fs; t1 = (off - 1).' / fs;
            xs = [t0; t1; t1; t0];
            ys = repmat([-1; -1; 1; 1], 1, numel(on));
            if isempty(on), xs = NaN; ys = NaN; end
        end
    end
end
