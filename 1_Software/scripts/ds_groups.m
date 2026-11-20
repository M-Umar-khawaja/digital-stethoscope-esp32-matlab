function g = ds_groups(cfg, recs)
%DS_GROUPS  Patient group for each recording, used to split train/test.
%   g = ds_groups(cfg, recs) -> cell array of group names
%   Recordings from one patient must all be in the same cross-validation
%   fold, otherwise test scores are too optimistic. Patient identity is
%   known for training-b (Subject ID column) and training-a (original name
%   'C45S1' = patient C45). Elsewhere each recording is its own group.

g = {recs.name};
file = fullfile(cfg.dataDir, 'annotations', 'Online Appendix_training set.csv');
fid = fopen(file, 'r');
if fid < 0, return; end
txt = fread(fid, inf, '*char').';
fclose(fid);
lines = regexp(txt, '[\r\n]+', 'split');
map = struct();
for i = 2:numel(lines)
    p = strsplit(lines{i}, ',');
    if numel(p) < 15, continue; end
    name = strtrim(p{1});
    db = strtrim(p{2});
    orig = strtrim(p{3});
    sid = strtrim(p{15});
    if strcmp(db, 'training-b') && ~isempty(sid)
        map.(name) = ['b_' sid];
    elseif strcmp(db, 'training-a')
        tok = regexp(orig, '^([A-Za-z]+\d+)S', 'tokens', 'once');
        if ~isempty(tok), map.(name) = ['a_' tok{1}]; end
    end
end
for i = 1:numel(recs)
    if isfield(map, recs(i).name), g{i} = map.(recs(i).name); end
end
end
