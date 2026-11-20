function recs = ds_all_records(cfg)
%DS_ALL_RECORDS  Every labelled recording from both datasets, one list.
%   recs = ds_all_records(cfg)
%   db 'a'..'f' = PhysioNet/CinC 2016 databases, 'g' = CirCor 2022.
%   Each record has a patient group for leak-free cross-validation.
r16 = ds_list_records(cfg);
g = ds_groups(cfg, r16);
for i = 1:numel(r16), r16(i).group = g{i}; end
rcc = ds_circor_list(cfg);
recs = [r16, rcc];
end
