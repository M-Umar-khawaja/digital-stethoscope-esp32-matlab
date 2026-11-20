function raw = dev_capture(s, seconds, cfg, startFcn)
%DEV_CAPTURE  Records raw ADC counts from an open ESP32 serialport.
%   raw = dev_capture(s, seconds, cfg)
%   raw = dev_capture(s, seconds, cfg, startFcn)   startFcn() is called
%   right after the input buffer is cleared (e.g. to start audio playback).
if nargin < 4, startFcn = []; end
flush(s);
if ~isempty(startFcn), startFcn(); end
need = round(seconds*cfg.fsDevice); raw = zeros(need, 1); n = 0; carry = '';
t = tic;
while n < need && toc(t) < seconds + 5
    pause(0.05);
    k = s.NumBytesAvailable;
    if k > 0
        [c, ~, carry] = st_serial_parse(carry, read(s, k, 'char'));
        m = min(numel(c), need - n);
        raw(n+1:n+m) = c(1:m); n = n + m;
    end
end
raw = raw(1:n);
end
