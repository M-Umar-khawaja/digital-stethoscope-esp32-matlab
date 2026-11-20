function recs = ds_list_records(cfg)
%DS_LIST_RECORDS  Index of the PhysioNet 2016 training recordings.
%   recs = ds_list_records(cfg)  ->  struct array with fields
%     name, db ('a'..'f'), wav (path), label (1 abnormal / 0 normal),
%     quality (1 good / 0 unusable), ann (hand-corrected state file)
%   Labels come from each database's REFERENCE.csv (3240 recordings).
%   Quality comes from annotations/updated/.../REFERENCE_withSQI.csv; the
%   87 training-e recordings missing from that file count as good quality.

recs = struct('name', {}, 'db', {}, 'wav', {}, 'label', {}, 'quality', {}, 'ann', {});
for db = 'abcdef'
    dbDir = fullfile(cfg.dataDir, ['training-' db]);
    ref = local_read(fullfile(dbDir, 'REFERENCE.csv'));
    sqi = local_read(fullfile(cfg.dataDir, 'annotations', 'updated', ...
        ['training-' db], 'REFERENCE_withSQI.csv'));
    for i = 1:numel(ref.names)
        r.name = ref.names{i};
        r.db = db;
        r.wav = fullfile(dbDir, [r.name '.wav']);
        r.label = double(ref.c2(i) == 1);
        k = find(strcmp(sqi.names, r.name), 1);
        if isempty(k) || isnan(sqi.c3(k)), r.quality = 1; else, r.quality = sqi.c3(k); end
        r.ann = fullfile(cfg.dataDir, 'annotations', 'hand_corrected', ...
            ['training-' db '_StateAns'], [r.name '_StateAns.mat']);
        recs(end+1) = r; %#ok<AGROW>
    end
end
end

function t = local_read(file)
t.names = {}; t.c2 = []; t.c3 = [];
fid = fopen(file, 'r');
if fid < 0, return; end
txt = fread(fid, inf, '*char').';
fclose(fid);
lines = regexp(txt, '[\r\n]+', 'split');
for i = 1:numel(lines)
    p = strtrim(strsplit(lines{i}, ','));
    if isempty(p{1}), continue; end
    t.names{end+1, 1} = p{1};
    v = NaN(1, 2);
    for c = 2:min(3, numel(p)), v(c-1) = str2double(p{c}); end
    t.c2(end+1, 1) = v(1);
    t.c3(end+1, 1) = v(2);
end
end
