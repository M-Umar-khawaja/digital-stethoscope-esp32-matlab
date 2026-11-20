function [f, names] = st_features(xa, cycles, fs)
%ST_FEATURES  124 features describing one heart-sound recording.
%   [f, names] = st_features(xa, cycles, fs)
%     xa     : analysis signal from st_preprocess (2 kHz, unit SD)
%     cycles : C-by-5 cycle boundaries from st_cycles (needs C >= 2)
%     f      : 1-by-124 feature row (NaN row if there are too few cycles)
%   Feature set of Potes et al. (2016), winner of the PhysioNet/CinC 2016
%   challenge, computed per heart state (S1, systole, S2, diastole):
%     36 time-domain : mean/SD of 5 durations, 3 duration ratios,
%                      2 amplitude ratios, and per-state skewness/kurtosis
%     36 band powers : median log power in 9 bands per state
%     52 MFCCs       : median of 13 MFCCs per state

names = local_names();
f = NaN(1, numel(names));
C = size(cycles, 1);
if C < 2, return; end
xa = xa(:);

S1 = cycles(:, 1); SY = cycles(:, 2); S2 = cycles(:, 3); DI = cycles(:, 4); NX = cycles(:, 5);
dS1 = (SY - S1) / fs;  dSy = (S2 - SY) / fs;  dS2 = (DI - S2) / fs;
dDi = (NX - DI) / fs;  RR = (NX - S1) / fs;
rSysRR = dSy ./ RR;  rDiaRR = dDi ./ RR;  rSysDia = dSy ./ dDi;

bands = [25 45; 45 65; 65 85; 85 105; 105 125; 125 150; 150 200; 200 300; 300 400];
nB = size(bands, 1);
nfft = 2048;
fr = (0:nfft/2).' * fs / nfft;
Bmask = false(numel(fr), nB);
for b = 1:nB, Bmask(:, b) = fr >= bands(b, 1) & fr < bands(b, 2); end
melFB = local_melbank(20, 25, 450, fr);
dctM = cos(pi/20 * (0:12).' * ((1:20) - 0.5));        % DCT-II, 13 coefficients

meanAbs = zeros(C, 4); sk = zeros(C, 4); ku = zeros(C, 4);
bp = zeros(C, 4, nB); mf = zeros(C, 4, 13);
for c = 1:C
    edges = [S1(c), SY(c), S2(c), DI(c), NX(c)];
    for s = 1:4
        seg = xa(edges(s):max(edges(s), edges(s+1) - 1));
        meanAbs(c, s) = mean(abs(seg));
        [sk(c, s), ku(c, s)] = local_moments(seg);
        n = numel(seg);
        w = 0.54 - 0.46*cos(2*pi*(0:n-1).'/max(n-1, 1));
        P = abs(fft(seg .* w, nfft)).^2;
        P = P(1:nfft/2 + 1) / max(sum(w.^2), eps);
        for b = 1:nB
            bp(c, s, b) = log10(mean(P(Bmask(:, b))) + 1e-12);
        end
        mf(c, s, :) = dctM * log(melFB * P + 1e-12);
    end
end
ampSysS1 = meanAbs(:, 2) ./ max(meanAbs(:, 1), eps);
ampDiaS2 = meanAbs(:, 4) ./ max(meanAbs(:, 3), eps);

td = [mean(RR) std(RR) mean(dS1) std(dS1) mean(dSy) std(dSy) ...
      mean(dS2) std(dS2) mean(dDi) std(dDi) ...
      mean(rSysRR) std(rSysRR) mean(rDiaRR) std(rDiaRR) mean(rSysDia) std(rSysDia) ...
      mean(ampSysS1) std(ampSysS1) mean(ampDiaS2) std(ampDiaS2)];
mom = [];
for s = 1:4
    mom = [mom, mean(sk(:, s)) std(sk(:, s)) mean(ku(:, s)) std(ku(:, s))]; %#ok<AGROW>
end
bpF = reshape(median(bp, 1), 1, []);                 % state varies fastest
mfF = reshape(median(mf, 1), 1, []);
f = [td, mom, bpF, mfF];
f(~isfinite(f)) = 0;
end

% -------------------------------------------------------------------------
function [s, k] = local_moments(x)
x = x - mean(x);
m2 = mean(x.^2);
if m2 < eps, s = 0; k = 3; return; end
s = mean(x.^3) / m2^1.5;
k = mean(x.^4) / m2^2;
end

function H = local_melbank(nF, fLo, fHi, fr)
mel = @(f) 2595*log10(1 + f/700);
imel = @(m) 700*(10.^(m/2595) - 1);
pts = imel(linspace(mel(fLo), mel(fHi), nF + 2));
H = zeros(nF, numel(fr));
for i = 1:nF
    lo = pts(i); ce = pts(i+1); hi = pts(i+2);
    up = (fr - lo) / (ce - lo);
    dn = (hi - fr) / (hi - ce);
    H(i, :) = max(0, min(up, dn)).';
end
end

function names = local_names()
stN = {'S1', 'Sys', 'S2', 'Dia'};
names = {'m_RR','sd_RR','m_S1','sd_S1','m_Sys','sd_Sys','m_S2','sd_S2','m_Dia','sd_Dia', ...
    'm_SysRR','sd_SysRR','m_DiaRR','sd_DiaRR','m_SysDia','sd_SysDia', ...
    'm_AmpSysS1','sd_AmpSysS1','m_AmpDiaS2','sd_AmpDiaS2'};
for s = 1:4
    names = [names, {['m_skew_' stN{s}], ['sd_skew_' stN{s}], ['m_kurt_' stN{s}], ['sd_kurt_' stN{s}]}]; %#ok<AGROW>
end
bn = {'25_45','45_65','65_85','85_105','105_125','125_150','150_200','200_300','300_400'};
for b = 1:9
    for s = 1:4
        names{end+1} = ['bp' bn{b} '_' stN{s}]; %#ok<AGROW>
    end
end
for k = 1:13
    for s = 1:4
        names{end+1} = sprintf('mfcc%d_%s', k - 1, stN{s}); %#ok<AGROW>
    end
end
end
