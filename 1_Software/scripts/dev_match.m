function [c, lagSec] = dev_match(xDev, fsDev, xSrc, fsSrc, cfg)
%DEV_MATCH  How well a device recording reproduces the played source.
%   [c, lagSec] = dev_match(xDev, fsDev, xSrc, fsSrc, cfg)
%   Correlation (0..1) of the heart-sound envelopes at 50 Hz, best over
%   lags of -0.5..+1.5 s (playback delay). A copy that really carries the
%   heartbeats scores about 0.6-0.9; noise or a lost earbud scores < 0.3.
ed = local_env(xDev, fsDev, cfg);
es = local_env(xSrc, fsSrc, cfg);
fe = 50;
best = -1; lagSec = NaN;
for L = round(-0.5*fe):round(1.5*fe)            % device lags behind the source by L
    if L >= 0, a = ed(1+L:end); b = es; else, a = ed; b = es(1-L:end); end
    n = min(numel(a), numel(b));
    if n < 5*fe, continue; end
    a = a(1:n) - mean(a(1:n)); b = b(1:n) - mean(b(1:n));
    r = (a.' * b) / max(norm(a)*norm(b), eps);
    if r > best, best = r; lagSec = L/fe; end
end
c = max(best, 0);
end

function e = local_env(x, fs, cfg)
xa = st_preprocess(x, fs, cfg);
e = st_homomorphic_env(xa(:), cfg.fs, 8);
e = e(1:round(cfg.fs/50):end);
e = e(:);
end
