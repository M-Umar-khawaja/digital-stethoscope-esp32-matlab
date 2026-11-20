function recs = ds_circor_list(cfg)
%DS_CIRCOR_LIST  Index of the CirCor DigiScope 2022 recordings (PhysioNet).
%   recs = ds_circor_list(cfg) -> same fields as ds_list_records, plus group
%   Recordings are 4 kHz, from 4 chest sites, with expert murmur labels.
%   Label per recording (heart-sound screening target):
%     abnormal (1) : murmur Present AND audible at this recording's site
%     normal   (0) : murmur Absent
%     left out     : murmur Unknown, or Present but not audible at this site
%   Patients recorded in both CirCor campaigns ("Additional ID") share one
%   group, so they never appear in both a training and a test fold.

recs = struct('name', {}, 'db', {}, 'wav', {}, 'label', {}, 'quality', {}, 'ann', {}, 'group', {});
base = local_find_base(cfg);
if isempty(base), return; end
fid = fopen(fullfile(base, 'training_data.csv'), 'r');
txt = fread(fid, inf, '*char').';
fclose(fid);
lines = regexp(txt, '[\r\n]+', 'split');
hdr = strsplit(lines{1}, ',');
col = @(name) find(strcmpi(strtrim(hdr), name), 1);
cId = col('Patient ID'); cMur = col('Murmur'); cLoc = col('Murmur locations'); cAdd = col('Additional ID');
dataDir = fullfile(base, 'training_data');
for i = 2:numel(lines)
    p = strsplit(lines{i}, ',');
    if numel(p) < max([cId cMur cLoc cAdd]), continue; end
    pid = strtrim(p{cId});
    mur = strtrim(p{cMur});
    murLocs = strsplit(strtrim(p{cLoc}), '+');
    add = strtrim(p{cAdd});
    if strcmp(mur, 'Unknown'), continue; end
    grp = ['cc_' pid];
    if ~isempty(add) && ~strcmpi(add, 'nan')
        grp = ['cc_' num2str(min(str2double(pid), str2double(add)))];
    end
    files = dir(fullfile(dataDir, [pid '_*.wav']));
    for k = 1:numel(files)
        [~, stem] = fileparts(files(k).name);
        loc = regexp(stem, '^\d+_([A-Za-z]+)', 'tokens', 'once');
        loc = loc{1};
        if strcmp(mur, 'Present')
            if ~any(strcmp(murLocs, loc)), continue; end
            lab = 1;
        else
            lab = 0;
        end
        r.name = stem;
        r.db = 'g';
        r.wav = fullfile(dataDir, files(k).name);
        r.label = lab;
        r.quality = 1;
        r.ann = fullfile(dataDir, [stem '.tsv']);
        r.group = grp;
        recs(end+1) = r; %#ok<AGROW>
    end
end
end

function base = local_find_base(cfg)
base = '';
root = fullfile(fileparts(cfg.dataDir), 'circor');
% the CSV sits in data/circor itself, or one folder down if the PhysioNet
% zip was unpacked there instead
if exist(fullfile(root, 'training_data.csv'), 'file') == 2
    base = root;
    return;
end
d = dir(root);
for i = 1:numel(d)
    if d(i).isdir && d(i).name(1) ~= '.' && ...
            exist(fullfile(root, d(i).name, 'training_data.csv'), 'file') == 2
        base = fullfile(root, d(i).name);
        return;
    end
end
end
