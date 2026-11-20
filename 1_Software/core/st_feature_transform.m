function F = st_feature_transform(F)
%ST_FEATURE_TRANSFORM  Removes the microphone's own colouring from features.
%   F = st_feature_transform(F)   rows = recordings, 124 columns (st_features)
%   Every sensor (PhysioNet's stethoscopes, our MAX4466) has its own
%   frequency response. It multiplies the spectrum of all four heart states
%   equally, i.e. it ADDS the same amount to every state's log band power
%   and MFCC. Subtracting the average over the four states removes it
%   (cepstral mean normalisation), while what differs between states, such
%   as a murmur raising systolic energy relative to S1/S2, is kept.
%   Columns 37-72: 9 bands x 4 states; 73-124: 13 MFCCs x 4 states
%   (state index changes fastest).

n = size(F, 1);
B = reshape(F(:, 37:72).', 4, 9*n);
B = bsxfun(@minus, B, mean(B, 1));
F(:, 37:72) = reshape(B, 36, n).';
M = reshape(F(:, 73:124).', 4, 13*n);
M = bsxfun(@minus, M, mean(M, 1));
F(:, 73:124) = reshape(M, 52, n).';
end
