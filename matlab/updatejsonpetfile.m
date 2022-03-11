function status = updatejsonpetfile(varargin)

% generic function that updates PET json file with missing PET-BIDS
% information, if only the jsonfile is provided, it only checks if valid
%
% FORMAT status = updatejsonpetfile(jsonfilename,newfields,dcminfo)
%
% INPUT - jsonfilename: jspon file to check or update update
%       optional
%       - newfields: a structure with the newfields to go into the json file
%       - dcminfo:   a dcmfile or the dicominfo structure from a representative
%                    dicom file- This information is used to also update the json
%                    file, and if a comflict exists, it returns warning messages,
%                    assumnimg the newfield provided is correct (i.e. as a user you
%                    know better than default dicom, presumably)
%
% OUTPUT status returns the state of the updating (includes warning messages
%               returned if any)
%
% jsonfilename = fullfile(pwd,'DBS_Gris_13_FullCT_DBS_Az_2mm_PRR_AC_Images_20151109090448_48.json')
% metadata = get_SiemensBiograph_metadata('TimeZero','ScanStart','tracer','AZ10416936','Radionuclide','C11', ...
%                        'ModeOfAdministration','bolus','Radioactivity', 605.3220,'InjectedMass', 1.5934,'MolarActivity', 107.66)
% dcminfo = dicominfo('DBSGRIS13.PT.PETMR_NRU.48.13.2015.11.11.14.03.16.226.61519201.dcm')
% status = updatejsonpetfile(jsonfilename,metadata,dcminfo)
%
% Cyril Pernet Nov 2021
% ----------------------------------------------
% Copyright Open NeuroPET team

status = struct('state',[],'messages',{''});

%% check data in
jsonfilename = varargin{1};
if nargin >= 2
    newfields = varargin{2};
    if iscell(newfields)
        newfields = cell2mat(newfields);
    end
    
    if nargin == 3
        dcminfo = varargin{3};
    end
end

% current file metadata
if isstruct(jsonfilename)
    filemetadata = jsonfilename;
else
    if exist(jsonfilename,'file')
        filemetadata = jsondecode(fileread(jsonfilename));
    else
        error('looking for %s, but the file is missing',jsonfilename)
    end
end

% expected metadata from the BIDS specification
current    = which('updatejsonpetfile.m');
root       = current(1:strfind(current,'converter')+length('converter'));
jsontoload = fullfile(root,['metadata' filesep 'PET_metadata.json']);
if exist(jsontoload,'file')
    petmetadata = jsondecode(fileread(jsontoload));
else
    error('looking for %s, but the file is missing',jsontoload)
end

%% check metadata and update them
if nargin == 1
    % -------------- only check ---------------
    for m=length(petmetadata.mandatory):-1:1
        test(m) = isfield(filemetadata,petmetadata.mandatory{m});
    end
    
    if sum(test)~=length(petmetadata.mandatory)
        status.state    = 0;
        missing         = find(test==0);
        for m=1:length(missing)
            status.messages{m} = sprintf('missing mandatory field %s',petmetadata.mandatory{missing(m)});
            warning(status.messages{m})
        end
    else
        status.state    = 1;
    end
    
else % -------------- update ---------------
       
    %% run the update
       
    addfields = fields(newfields);
    for f=1:length(addfields)
        filemetadata.(addfields{f}) = newfields.(addfields{f});
    end
   
    if isfield(filemetadata,'TimeZero')
        if strcmpi(filemetadata.TimeZero,'ScanStart') || isempty(filemetadata.TimeZero)
            filemetadata.TimeZero   = filemetadata.AcquisitionTime;
            filemetadata            = rmfield(filemetadata,'AcquisitionTime');
            filemetadata.ScanStart  = 0;     
            
            if ~isfield(filemetadata,'InjectionStart')
                filemetadata.InjectionStart = 0;
            end
        end
    else
        warning('TimeZero is not defined, which is not compliant with PET BIDS')
    end
  
    % recheck those fields, assume 0 is not specified
    if ~isfield(filemetadata,'ScanStart')
        filemetadata.ScanStart     = 0;
    end
    
    if ~isfield(filemetadata,'InjectionStart')
        filemetadata.InjectionStart = 0;
    end
    
    % -------------------------------------------------------------------
    %         dcm2nixx extracted data to update with BIDS name if needed  
    % -------------------------------------------------------------------
    
    % check Unit(s) (depends on dcm2nixx version)
    if isfield(filemetadata,'Unit')
        filemetadata.Units = filemetadata.Unit;
        filemetadata       = rmfield(filemetadata,'Unit');
        if strcmpi(filemetadata.Units,'BQML')
            filemetadata.Units = 'Bq/mL';
        end
    end
    
    % run some heuristic - from names we know
    if isfield(filemetadata,'ReconstructionMethod')
        if isfield(filemetadata.ReconMethodName) % if already there remove dcm2niix info
            filemetadata                 = rmfield(filemetadata,'ReconstructionMethod');
        else % try to fill in info
            filemetadata.ReconMethodName = filemetadata.ReconstructionMethod;
            filemetadata                 = rmfield(filemetadata,'ReconstructionMethod');
            iterations                   = regexp(filemetadata.ReconMethodName,'\d\di','Match');
            if isempty(iterations)
                iterations               = regexp(filemetadata.ReconMethodName,'\di','Match');
            end
            subsets                      = regexp(filemetadata.ReconMethodName,'\d\ds','Match');
            if isempty(subsets)
                subsets                  = regexp(filemetadata.ReconMethodName,'\ds','Match');
            end
            
            if ~isempty(iterations) && ~isempty(subsets)
                index1 = strfind(filemetadata.ReconMethodName,iterations);
                index2 = index1 + length(cell2mat(iterations))-1;
                filemetadata.ReconMethodName(index1:index2) = [];
                index1 = strfind(filemetadata.ReconMethodName,subsets);
                index2 = index1 + length(cell2mat(subsets ))-1;
                filemetadata.ReconMethodName(index1:index2) = [];
                filemetadata.ReconMethodParameterLabels     = ["subsets","iterations"];
                filemetadata.ReconMethodParameterUnits      = ["none","none"];
                filemetadata.ReconMethodParameterValues     = [str2double(subsets{1}(1:end-1)),str2double(iterations{1}(1:end-1))];
            end
        end
    end
    
    if isfield(filemetadata,'ConvolutionKernel')
        if isfield(filemetadata,'ReconFilterType') && isfield(filemetadata,'ReconFilterSize')
            filemetadata = rmfield(filemetadata,'ConvolutionKernel'); % already there, remove
        else % attempt to fill
            if contains(filemetadata.ConvolutionKernel,'.00')
                loc = strfind(filemetadata.ConvolutionKernel,'.00');
                filemetadata.ConvolutionKernel(loc:loc+2) = [];
                filtersize = regexp(filemetadata.ConvolutionKernel,'\d*','Match');
                if ~isempty(filtersize)
                    filemetadata.ReconFilterSize = cell2mat(filtersize);
                    loc = strfind(filemetadata.ConvolutionKernel,filtersize{1});
                    filemetadata.ConvolutionKernel(loc:loc+length(filemetadata.ReconFilterSize)-1) = [];
                    filemetadata.ReconFilterType = filemetadata.ConvolutionKernel;
                else
                    filemetadata.ReconFilterType = filemetadata.ConvolutionKernel;
                end
                filemetadata = rmfield(filemetadata,'ConvolutionKernel');
            end
        end
    end    
    
    % -------------------------------------------------------------
    % possible dcm fields to recover - this part is truly empirical
    % going over different dcm files and figuring out fields
    % ------------------------------------------------------------    
    if exist('dcminfo','var')
        if ischar(dcminfo)
            dcminfo = flattenstruct(dicominfo(dcminfo));
        else
            dcminfo = flattenstruct(dcminfo);
        end
        % here we keep only the last dcm subfield (flattenstrct add '_' with
        % leading subfields initial to make things more tracktable but we 
        % don't need it to match dcm names)
        
        dicom_nucleotides = { '^11^Carbon', '^13^Nitrogen', '^14^Oxygen', ...
            '^15^Oxygen','^18^Fluorine', '^22^Sodium', '^38^Potassium', ...
            '^43^Scandium','^44^Scandium','^45^Titanium','^51^Manganese',...
            '^52^Iron','^52^Manganese','^52m^Manganese','^60^Copper',...
            '^61^Copper','^62^Copper','^62^Zinc','^64^Copper','^66^Gallium',...
            '^68^Gallium','^68^Germanium','^70^Arsenic','^72^Arsenic',...
            '^73^Selenium','^75^Bromine','^76^Bromine','^77^Bromine',...
            '^82^Rubidium','^86^Yttrium','^89^Zirconium','^90^Niobium',...
            '^90^Yttrium','^94m^Technetium','^124^Iodine','^152^Terbium'};
        
        fn = fieldnames(dcminfo);
        for f=1:length(fn)
            if contains(fn{f},'_') && ~contains(fn{f},{'Private','Unknown'})
                if contains(fn{f},'CodeMeaning') % appears in other places so we need to ensure it's for the tracer
                    if contains(dcminfo.(fn{f}),dicom_nucleotides)
                        dcminfo.(fn{f}(max(strfind(fn{f},'_'))+1:end)) = dcminfo.(fn{f});
                    end
                else
                    dcminfo.(fn{f}(max(strfind(fn{f},'_'))+1:end)) = dcminfo.(fn{f});
                end
                dcminfo = rmfield(dcminfo,fn{f});
            end
        end
    else
        error('%s does not exist',dcminfo)
    end
       
    %% run dmc check
    jsontoload = fullfile(root,['metadata' filesep 'dicom2bids.json']);
    if exist(jsontoload,'file')
        heuristics = jsondecode(fileread(jsontoload));
        dcmfields  = heuristics.dcmfields;
        jsonfields = heuristics.jsonfields;
    else
        error('looking for %s, but the file is missing',jsontoload)
    end
        
    for f=1:length(dcmfields) % check each field from dicom image
        if isfield(dcminfo,dcmfields{f}) % if it matches our list of dicom tags
            if isfield(filemetadata,jsonfields{f}) % and  the json field exist, 
                % then compare and inform the user if different
                if ~strcmpi(dcminfo.(dcmfields{f}),filemetadata.(jsonfields{f}))
                    if isnumeric(filemetadata.(jsonfields{f}))
                        warning(['possible mismatch between json ' jsonfields{f} ':' num2str(filemetadata.(jsonfields{f})) ' and dicom ' dcmfields{f} ':' num2str(dcminfo.(dcmfields{f}))])
                    else
                        warning(['possible mismatch between json ' jsonfields{f} ': ' filemetadata.(jsonfields{f}) ' and dicom ' dcmfields{f} ':' dcminfo.(dcmfields{f})])
                    end
                else % otherwise set the field in the json file
                    warning(['adding json info ' jsonfields{f} ': ' dcminfo.(dcmfields{f}) ' from dicom field ' dcmfields{f}])
                    filemetadata.(jsonfields{f}) = dcminfo.(dcmfields{f});
                end
            end
        end
    end
        
    %% recursive call to check status
    status = updatejsonpetfile(filemetadata);
    if isfield(filemetadata,'ConversionSoftware')
        filemetadata.ConversionSoftware = [filemetadata.ConversionSoftware ' - json edited with ONP updatejsonpetfile.m'];
    end
    filemetadata = orderfields(filemetadata);
    jsonwrite(jsonfilename,filemetadata)
end

