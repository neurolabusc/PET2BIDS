function structout = flattenstruct(structin)

% routine that take a structure with nested subfileds
% and output all fields in a flat structure
%
% FORMAT structout = flattendcm(filein)
%
% INPUT  structin is a structure with nested fields
% OUTPUT structout is a flat sructure with all the dcm fields
%                  fields that are flattened is empty [] and their
%                  subfileds start with the 1st letter of the parent 
%
% Cyril Pernet Novembre 2021
% ----------------------------------------------
% Copyright Open NeuroPET team

rootfields = fieldnames(structin); % root fieldnames
for f=1:length(rootfields)
    extractfrom = structin.(rootfields{f});
    if ~isstruct(extractfrom)
        structout.(rootfields{f}) = extractfrom;
    else
        done        = 0;
        fieldindex  = 1;
        while done == 0
            if isfield(extractfrom,'Item_1') % a struct of struct
                subfields   = fieldnames(extractfrom.Item_1);
                if ~isstruct(extractfrom.Item_1.(subfields{fieldindex}))
                    structout.(rootfields{f}) = [];
                    structout.([rootfields{f}(1) '_' subfields{fieldindex}]) = extractfrom.Item_1.(subfields{fieldindex});
                    fieldindex  = fieldindex  + 1;
                    if fieldindex == length(subfields)+1
                        done = 1;
                    end
                else
                    disp('deep recursion')
                    tmp = extractfrom.Item_1.(subfields{fieldindex});
                    if isfield(tmp,'Item_1') % because we can have empty struct
                        extractfrom = flattenstruct(extractfrom.Item_1.(subfields{fieldindex}).Item_1);
                    else
                        fieldindex  = fieldindex  + 1;
                        if fieldindex == length(subfields)+1
                            done = 1;
                        end
                    end
                end
                            
            else % just a struct
                subfields   = fieldnames(extractfrom);
                for s=1:length(subfields)
                   structout.(rootfields{f}) = [];
                   structout.([rootfields{f}(1) '_' subfields{s}]) = extractfrom.(subfields{s});
                end
                done = 1;
            end
        end
    end
end


