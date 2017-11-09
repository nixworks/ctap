%% Clean SCCN data CTAP script
% As referenced in the second CTAP article:
% Cowley BU, Korpela J, (2018) Computational Testing for Automated Preprocessing 
% 2: practical demonstration of a system for scientific data-processing workflow 
% management for high-volume EEG. Frontiers in Neuroscience [IN PROGRESS]

% OPERATION STEPS
% # 1
% Get:
%   * Matlab R2016b or newer
%   * EEGLAB, latest version,
%     git clone https://adelorme@bitbucket.org/sccn_eeglab/eeglab.git
%   * CTAP
%   * The 13 files of EEG data in .bdf format from the study 'Auditory Two-
%       Choice Response Task with an Ignored Feature Difference', available at
%       http://headit.ucsd.edu/studies/9d557882-a236-11e2-9420-0050563f2612

% # 2
% Add EEGLAB and CTAP to your Matlab path. For a script to do this see 
% update_matlab_path_ctap.m at CTAP repository root: the directory containing
% 'ctap' and 'dependencies' folders.

% # 3
% Set your working directory to CTAP root

% # 4
% Set up a data directory to contain the .bdf files. Pass the complete 
% path to this directory into the variable 'data_dir_in', below

% # 5
% On the Matlab console, execute >> runctap_manu2_short


%% Setup
data_dir_in = '/home/ben/Benslab/CTAP/CTAPIIdata';
analysis_ID = 'sccn-short-pipe';

% Define step sets and their parameters
[Cfg, ctap_args] = sbf_cfg(data_dir_in, analysis_ID);

% Runtime options for CTAP:
STOP_ON_ERROR = true;
OVERWRITE_OLD_RESULTS = true;


%% Create measurement config (MC) based on folder
Cfg.MC = path2measconf(data_dir_in, '*.bdf');
% Select measurements to process
clear('Filt')
Filt.subject = 'eeg_recording_8';
Cfg.pipe.runMeasurements = get_measurement_id(Cfg.MC, Filt);


%% Select step sets to process
Cfg.pipe.runSets = {'all'}; %this is the default
% Cfg.pipe.runSets = {Cfg.pipe.stepSets(8).id};


%% Assign arguments to the selected functions, perform various checks
Cfg = ctap_auto_config(Cfg, ctap_args);


%% Run the pipe
% {
tic;
CTAP_pipeline_looper(Cfg,...
                    'debug', STOP_ON_ERROR,...
                    'overwrite', OVERWRITE_OLD_RESULTS);
toc;

%clean workspace
clear STOP_ON_ERROR OVERWRITE_OLD_RESULTS Filt ctap_args data_dir_in
%}


%% Cleanup saved .sets
% {
setpths = fullfile(Cfg.env.paths.projectRoot, Cfg.pipe.runSets);
fname = [Cfg.pipe.runMeasurements{1} '.set'];
for i = 1:numel(setpths)
    eeg = ctapeeg_load_data(fullfile(setpths{i}, fname) );
    eeg.event(isnan(str2double({eeg.event.type}))) = [];
    
    shrt_std = pop_epoch(eeg, {'200' '250'}, [-1 1]);
    shrt_dev = pop_epoch(eeg, {'100' '150'}, [-1 1]);
    
    shrt_vtx_erp = [ctap_test_erp(shrt_std); ctap_test_erp(shrt_dev)];
    plot(shrt_vtx_erp', 'Linewidth', 2)
    axis([0 shrt_std.pnts Inf Inf])
    xticks(linspace(0, shrt_std.pnts, 15))
    xtl = xticklabels;
%     xticklabels(num2str(round(linspace(shrt_std.xmin * 1000, shrt_std.xmax * 1000, 15))))
    legend({'short std' 'short dev'})
    
    long_std = pop_epoch(eeg, {'201' '251'}, [-1 1]);
    long_dev = pop_epoch(eeg, {'101' '151'}, [-1 1]);
    
    long_vtx_erp = [ctap_test_erp(long_std); ctap_test_erp(long_dev)];
    plot(shrt_vtx_erp', 'Linewidth', 2)
    xticklabels()
%     axis([shrt_std.xmin * 1000 shrt_std.xmax * 1000 inf inf])
    legend({'long std' 'long dev'})
%     pop_saveset(eeg, 'filename', savename, 'filepath', setpths{i});
end



%% Subfunctions
% Pipe definition
function [Cfg, out] = sbf_cfg(project_root_folder, ID)

% Analysis branch ID
Cfg.id = ID;

Cfg.srcid = {''};

Cfg.env.paths.projectRoot = project_root_folder;


%% Define important directories and files
Cfg.env.paths.branchSource = ''; 
Cfg.env.paths.ctapRoot = fullfile(Cfg.env.paths.projectRoot, Cfg.id);
Cfg.env.paths.analysisRoot = Cfg.env.paths.ctapRoot;

% Channel location file
Cfg.eeg.chanlocs = fullfile(Cfg.env.paths.projectRoot, 'channel_locations_8.elp');
Channels = readlocs(Cfg.eeg.chanlocs);


%% Define other important stuff
Cfg.eeg.reference = {'average'};

% EOG channel specification for artifact detection purposes
Cfg.eeg.veogChannelNames = {Channels([254 255]).labels};%'1EX3' '1EX4'};
Cfg.eeg.heogChannelNames = {Channels([252 253]).labels};%'1EX1','1EX2'};


%% Configure analysis pipe

%% Load
i = 1; %stepSet 1
stepSet(i).funH = { @CTAP_load_data,...
                    @CTAP_load_chanlocs,...
                    @CTAP_reref_data,... 
                    @CTAP_blink2event,...
                    @CTAP_select_data,...
                    @CTAP_peek_data,...
                    @CTAP_fir_filter,...
                    @CTAP_select_data,...
                    @CTAP_run_ica };
stepSet(i).id = [num2str(i) '_load'];

out.load_chanlocs = struct(...
    'overwrite', true,...
    'delchan', 1);
out.load_chanlocs.field = {{251:254 'type' 'EOG'}...
                         , {255:256 'type' 'ECG'}};
out.load_chanlocs.tidy  = {{'type' 'FID'} {'type' 'ECG'}};

out.select_data = struct(...
    'time', {[1100 2500] [100 1300]});

out.fir_filter = struct(...
    'locutoff', 1);

out.run_ica = struct(...
    'method', 'fastica',...
    'overwrite', true);
out.run_ica.channels = {'EEG' 'EOG'};

out.peek_data = struct(...
    'plotEEGset', false,...
    'plotEEGHist', false);


%% IC correction
i = i+1;  %stepSet 2
stepSet(i).funH = { @CTAP_detect_bad_comps,... %ADJUST for horizontal eye moves
                    @CTAP_reject_data,...
                    @CTAP_detect_bad_comps,... %detect blink related ICs
                    @CTAP_filter_blink_ica,...
                    @CTAP_detect_bad_channels,...%adjust the variance thresholds!
                    @CTAP_reject_data,...
                    @CTAP_interp_chan,...
                    @CTAP_peek_data };
stepSet(i).id = [num2str(i) '_artifact_correction'];


out.detect_bad_comps = struct(...
    'method', {'adjust' 'blink_template'},...
    'adjustarg', {'horiz' ''});

out.detect_bad_channels = struct(...
    'method', 'variance',...
    'channelType', {'EEG'});


%% Store to Cfg
Cfg.pipe.runSets = {'all'}; % step sets to run, the whole thing by default
Cfg.pipe.stepSets = stepSet; % record of all step sets

end