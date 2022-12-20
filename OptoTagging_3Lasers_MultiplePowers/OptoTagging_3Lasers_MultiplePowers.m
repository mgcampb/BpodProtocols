function OptoTagging_3Lasers_MultiplePowers

% M. Campbell 8/2/2021: Protocol to deliver odors followed by laser pulses.
% S. Matias: Modified in 2/1/2022 to trigger 3 lasers
% M. Campbell 7/19/2022: Modified some parameters (MaxTrials, ITI duration, NumLaserPulse, TargetChunkSize)
% M.Campbell 7/19/2022: Saved as new protocol from Optotagging_3Lasers to
%   allow convenient testing of multiple laser powers in a single protocol

global BpodSystem

prompt = {'How many lasers are you using? (1, 2, or 3)'};
usrinput = inputdlg(prompt);
num_lasers = str2double(usrinput);

%% Setup (runs once before the first trial)

% MaxTrials = 200; % Max number of trials
num_blocks = 8;
MaxTrials_block = 30;
MaxTrials = MaxTrials_block * num_blocks; % Max number of trials

% Task parameters
S = BpodSystem.ProtocolSettings; % contains valve order for this mouse in field OdorValvesOdor

S.NumLasers = num_lasers;
% These parameters are shared across animals:
S.ForeperiodDuration = 0.5; % seconds
S.NumLaserPulse = 6; % number of laser pulses to deliver after trace period
S.LaserPulseDuration = 0.02; % seconds
S.LaserPulseFrequency = 10; % Hz
S.GUI.ITIMin = 2; % seconds
S.GUI.ITIMax = 4; % seconds

% Duration of Laser state (based on parameters in S)
LaserStateDuration = ceil(S.NumLaserPulse/S.LaserPulseFrequency); % seconds

% Set up parameter GUI
BpodParameterGUI('init', S); 

% Define trial types: 1 = Laser1, 2 = Laser2, etc
TargetChunkSize = S.NumLasers; % trials; chunk size in which to balance trial types
ActualChunkSize = S.NumLasers*round(TargetChunkSize/S.NumLasers );
NumChunks = ceil(MaxTrials/ActualChunkSize);
TrialTypesChunk = repmat(1:S.NumLasers ,1,ActualChunkSize/S.NumLasers );
TrialTypes = [];
for i = 1:NumChunks
    TrialTypes = [TrialTypes TrialTypesChunk(randperm(numel(TrialTypesChunk)))];
end
TrialTypes = TrialTypes(1:MaxTrials);

% Pokes plot
% state_colors = struct( ...
%     'Foreperiod',[.9,.9,.9],...
%     'Odor', 0.55*[0,1,1],...
%     'Trace', [.8 .8 .8],...
%     'Laser', [0 1 0],...
%     'ITI', [.9,.9,.9]);
% PokesPlot('init', state_colors, []);

% Set up WavePlayer (Analog Output Module for controlling lasers)
W = BpodWavePlayer('COM4'); % Make sure the COM port is correct
SR = 10000; % Sampling rate for analog output
W.SamplingRate = SR;
W.OutputRange = '0V:5V';
waveform = zeros(1,SR/S.LaserPulseFrequency);
waveform(1:(S.LaserPulseDuration * SR)) = 5;
waveform = repmat(waveform,1,S.NumLaserPulse);
W.loadWaveform(1,waveform);
WavePlayerMessages = {};
for i = 1:S.NumLasers
    WavePlayerMessages = [WavePlayerMessages {['P' 2^(i-1) 0]}]; % Send waveform 1 to the ith channel
end
WavePlayerMessages = [WavePlayerMessages {''}]; % Do nothing
LoadSerialMessages('WavePlayer1', WavePlayerMessages);

%% Main loop (runs once per trial)
for currentTrial = 1:MaxTrials
    
    trial_within_block = mod(currentTrial-1,MaxTrials_block)+1;
    block_num = ceil(currentTrial/MaxTrials_block);
    if trial_within_block==1
        prompt = sprintf('Block %d: Enter laser power in mW',block_num);
        usrinput = inputdlg(prompt);
        LaserPower_mW = str2double(usrinput);
    end
    
    TrialType = TrialTypes(currentTrial);
    
    % Sync parameters with BpodParameterGUI plugin
    S = BpodParameterGUI('sync', S); 
    
    % Compute variables for this trial's state machine:
    
    % Which laser channel to trigger
    LaserMessage = min(TrialType,S.NumLasers+1);
    
    % Randomly generate ITI duration
    ITIDuration = unifrnd(S.GUI.ITIMin,S.GUI.ITIMax);
    
    % Display trial type
     % Display trial type
    if LaserMessage > S.NumLasers
        fprintf('Trial %d: TrialType %d (No Laser) Block %d/%d, BlockTrial %d/%d, Power=%0.2f mW\n',currentTrial,...
            TrialType,block_num,num_blocks,trial_within_block,MaxTrials_block,LaserPower_mW);
    else
        fprintf('Trial %d: TrialType %d (Laser %d) Block %d/%d, BlockTrial %d/%d, Power=%0.2f mW\n',currentTrial,...
            TrialType,LaserMessage,block_num,num_blocks,trial_within_block,MaxTrials_block,LaserPower_mW);
    end
 
    
    % Create state matrix
    sma = NewStateMatrix();
    sma = AddState(sma, 'Name', 'Foreperiod',...
        'Timer', S.ForeperiodDuration,...
        'StateChangeConditions', {'Tup', 'Laser'},...
        'OutputActions', {'BNC1', 1, 'BNC2', 1});
    sma = AddState(sma, 'Name', 'Laser',...
        'Timer', LaserStateDuration,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'WavePlayer1', LaserMessage, 'BNC1', 1, 'BNC2', 1});
    sma = AddState(sma, 'Name', 'ITI',...
        'Timer', ITIDuration,...
        'StateChangeConditions', {'Tup', 'exit'},...
        'OutputActions', {'BNC1', 0, 'BNC2', 0});
    
    % Send state machine to Bpod device
    SendStateMatrix(sma);
    
    % Run the trial and return events
    RawEvents = RunStateMatrix;
    
    if ~isempty(fieldnames(RawEvents))
        % Save trial data
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial) = S;
        BpodSystem.Data.TrialTypes(currentTrial) = TrialTypes(currentTrial);
        BpodSystem.Data.LaserMessage(currentTrial) = LaserMessage;
        BpodSystem.Data.LaserPower_mW(currentTrial) = LaserPower_mW;
        BpodSystem.Data.Block(currentTrial) = block_num;
        SaveBpodSessionData;
        
        % Update online plots
        % PokesPlot('update');
    end

    % Handle pauses and exit if the user ended the session
    HandlePauseCondition;
    if BpodSystem.Status.BeingUsed == 0
        return
    end
    
end

fprintf('\nProtocol finished\n\n');

end