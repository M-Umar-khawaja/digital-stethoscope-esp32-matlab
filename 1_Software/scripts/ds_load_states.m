function st = ds_load_states(annFile, n)
%DS_LOAD_STATES  Hand-corrected state labels for one PhysioNet recording.
%   st = ds_load_states(annFile, n)  ->  n-by-1 state per 2 kHz sample
%     1=S1 2=systole 3=S2 4=diastole, 0 = not labelled
%   The annotation lists the sample where each state starts.

st = zeros(n, 1);
if exist(annFile, 'file') ~= 2, return; end
[~, ~, ext] = fileparts(annFile);
if strcmpi(ext, '.tsv')
    % CirCor: "start_s <tab> end_s <tab> state" (0 = not annotated), 2 kHz here
    fid = fopen(annFile, 'r');
    A = fscanf(fid, '%f', [3 inf]).';
    fclose(fid);
    for i = 1:size(A, 1)
        s0 = max(1, round(A(i, 1)*2000) + 1);
        s1 = min(n, round(A(i, 2)*2000));
        if s1 >= s0, st(s0:s1) = A(i, 3); end
    end
    return;
end
s = load(annFile);
a = s.state_ans;
starts = zeros(size(a, 1), 1);
lab = zeros(size(a, 1), 1);
for i = 1:size(a, 1)
    starts(i) = double(a{i, 1});
    nm = a{i, 2};
    if iscell(nm), nm = nm{1}; end
    switch lower(strtrim(nm))
        case 's1',       lab(i) = 1;
        case 'systole',  lab(i) = 2;
        case 's2',       lab(i) = 3;
        case 'diastole', lab(i) = 4;
        otherwise,       lab(i) = 0;   % noise / unknown sections
    end
end
for i = 1:numel(starts)
    s0 = max(1, starts(i));
    if i < numel(starts), s1 = min(n, starts(i+1) - 1); else, s1 = n; end
    if s1 >= s0, st(s0:s1) = lab(i); end
end
end
