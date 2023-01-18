function Odor_LickForStim

% M. Campbell 8/2/2021: Protocol to deliver odors followed by laser pulses.
% M. Campbell 12/1/2021: Edited OdorLaser to create OdorLaserWater task.
% M. Campbell 10/24/2022: Edited OdorLaserWater to create OdorLaser_v2:
%   Initially used for photometry opto calibration experiments 
%   (calibrating opto stim to water reward, then repeating OdorLaser task)
%   Added omission trials
%   Made the ITI exponentially distributed
%   Added block of rewards before and after odor trials (for
%   calibration/comparison to odor/opto responses)
% M. Campbell 11/5/2022: Added unpredicted opto stim before and after odor
%   trials
%
% M. Campbell 1/16/2023: Modified so that mice lick to obtain opto stim
%   following particular odors. Water rewards interleaved to encourage
%   licking.

global BpodSystem

airON = 0;
while ~airON
    answer = questdlg('Is the air ON?', ...
	'Yes','No');
    switch answer
        case 'Yes'
            airON = 1;
        case 'No'
            disp('The task will not start until you turn on the air :)')
            airON = 0;
    end
end

COM_Ports = readtable('..\COM_Ports.txt'); % get COM ports from text file (ignored by git)


%% Setup (runs once before the first trial)

mouse = BpodSystem.Status.CurrentSubjectName;

NumTrials = 80; % Number of trials
% TrialType1: Odor -> Lick for VS opto stim
% TrialType2: Odor -> Nothing
% In addition, rewards are delivered at random times in some trials
% (use global timer within a trial)


BpodSystem.Data.TaskDescription = 'Odor_LickForStim';

% Task parameters
S = BpodSystem.ProtocolSettings; % contains valve order for this mouse in field OdorValvesOdor

% These parameters are specific to each mouse and loaded from file:
if isempty(fieldnames(S))
    fprintf(['\n******\nWARNING: No saved task parameters found for this mouse.' ...
        '\nGenerating new default parameters.\n******\n']);
    S.NumOdors = input('Number of odors: ');
    S.NumLaser = input('Number of lasers: ');
    S.OdorValvesOrder = randperm(S.NumOdors);
    SaveProtocolSettings(S);
end

% These parameters are shared across animals:
S.Experimenter = 'Malcolm';
S.Mouse = mouse;
S.ForeperiodDuration = 0.5; % seconds
S.OdorDuration = 3; % seconds; total time that the odor is on (including pre period)
S.OdorPreDuration = 0.5; % seconds; minimum time after odor onset that mouse can lick for stim
S.StimProbability = 1.0; % probability of receiving opto stim if lick during odor on laser trials
S.TrialsPerReward_Ceiling = 1.5; % Reward is delivered at a random time, a bit less than once per this number of trials; should be at least 1

% number of params should match number of lasers/LEDs
S.NumLaserPulse = [25 25]; % number of laser pulses to deliver after trace period
S.LaserPulseDuration = [0.005 0.005]; % seconds
S.LaserPulseFrequency = [50 50]; % Hz

S.ITIMean = 12;
S.ITIMin = 8;
S.ITIMax = 20;
S.RewardAmount = 4;

% display parameters
fprintf('\nSession parameters:\n')
S
fprintf('NumTrials = %d\n',NumTrials);

% Get opto stim duration
OptoStimDuration = S.NumLaserPulse/S.LaserPulseFrequency; % in sec


%% Define trial types

% Also define omission trials
ChunkSize = 10; % trials; chunk size in which to balance odor trial types
NumChunks = ceil(NumTrials/ChunkSize);

TrialTypesChunk = repmat(1:S.NumOdors,1,ChunkSize/S.NumOdors);
StimTrialsChunk = [ones(1,round(ChunkSize * S.StimProbability)) ...
    zeros(1,round(ChunkSize * (1-S.StimProbability)))];
StimTrialsChunk = StimTrialsChunk(1:ChunkSize);

TrialTypes = [];
StimTrials = [];
for i = 1:NumChunks
    perm_idx1 = randperm(ChunkSize);
    perm_idx2 = randperm(ChunkSize);
    TrialTypes = [TrialTypes TrialTypesChunk(perm_idx1)];
    StimTrials = [StimTrials StimTrialsChunk(perm_idx1)];
end
TrialTypes = TrialTypes(1:NumTrials);
StimTrials = StimTrials(1:NumTrials);
StimTrials(TrialTypes>S.NumLaser) = 0; % trial types with no laser stim


%% Pokes plot
state_colors = struct( ...
    'Foreperiod',[.9,.9,.9],...
    'CS1_pre', [0 1 1],...
    'CS1_lick', [0 1 1],...
    'CS2_pre', [1 0 1],...
    'CS2_lick', [1 0 1],...
    'Laser', [1 0 0],...
    'ITI', [.9,.9,.9]);
PokesPlotLicksSlow('init', state_colors, []);


%% Set odors for each trial type in each mouse
% S.OdorValvesOrder is the order of odors for this mouse, 
% loaded in the line S = BpodSystem.ProtocolSettings;
ValveMessages = {['B' 0]}; % Valve 1 is blank
for i = 1:S.NumOdors
    ValveMessages = [ValveMessages {['B' 2^S.OdorValvesOrder(i)+1]}];
end
LoadSerialMessages('ValveModule1', ValveMessages);  % Set serial messages for valve module. Valve 1 is the default that is normally on


%% Set up WavePlayer (Analog Output Module for controlling lasers)
W = BpodWavePlayer(COM_Ports.COM_Port{strcmp(COM_Ports.Module,'BpodWavePlayer')}); % Make sure the COM port is correct
SR = 10000; % Sampling rate for analog output
W.SamplingRate = SR;
W.OutputRange = '0V:5V';
for i = 1:S.NumLaser
    waveform = zeros(1,round(SR/S.LaserPulseFrequency(i)));
    waveform(1:(S.LaserPulseDuration(i) * SR)) = 5;
    waveform = repmat(waveform,1,S.NumLaserPulse(i));
    W.loadWaveform(i,waveform);
end
WavePlayerMessages = {};
for i = 1:S.NumLaser
    WavePlayerMessages = [WavePlayerMessages {['P' 2^(i-1) i-1]}]; % Send waveform i to the ith channel
end
WavePlayerMessages = [WavePlayerMessages {''}]; % Do nothing
LoadSerialMessages('WavePlayer1', WavePlayerMessages);


%% Trials
tic
fprintf('\nTrials\n');
for currentTrial = 1:NumTrials
    
    TrialType = TrialTypes(currentTrial);
    StimTrial = StimTrials(currentTrial);

    RewardAmount = S.RewardAmount;
    RewardValveTime = GetValveTimes(RewardAmount, 1);
    
    % Compute variables for this trial's state machine:
    CS_state = sprintf('CS%d_pre',TrialType);
    ValveMessage = TrialType+1;
    LaserMessage = min(TrialType,S.NumLaser+1);
    if StimTrial==1
        OutcomeState = 'Laser';
    else
        OutcomeState = 'ITI';
    end

    % Calculate ITI for this trial
    ITIDuration = exprnd(S.ITIMean-S.ITIMin) + S.ITIMin;
    if ITIDuration > S.ITIMax
        ITIDuration = S.ITIMax;
    end

    % Get time of random reward
    MaxTrialDuration = S.ForeperiodDuration+S.OdorDuration+S.ITIMax;
    RewardTime = unifrnd(0,MaxTrialDuration*S.TrialsPerReward_Ceiling);
    
    % So that ITI is the same for Odor and NoOdor trials:
    if ~contains(CS_state,'CS')
        ITIDuration = ITIDuration + S.OdorDuration;
    end
    
    % Display trial type
    fprintf('\tTrial %d:\tTrialType%d\tLaser%d\tOdor%d\tStim=%d ITI=%0.1fs\n',...
        currentTrial,TrialType,LaserMessage,S.OdorValvesOrder(TrialType),StimTrial,ITIDuration);
    
    % Create state matrix
    sma = NewStateMatrix();
    sma = SetGlobalTimer(sma, 'TimerID', 1, 'Duration', RewardValveTime, 'OnsetDelay', RewardTime, 'Channel', 'Valve1',...
        'OnMessage', 1, 'OffMessage', 0); 
    sma = AddState(sma, 'Name', 'Foreperiod',...
        'Timer', S.ForeperiodDuration,...
        'StateChangeConditions', {'Tup', CS_state},...
        'OutputActions', {'BNC1', 1, 'BNC2', 1,'GlobalTimerTrig', 1});
    for tt = 1:S.NumOdors
        sma = AddState(sma, 'Name', sprintf('CS%d_pre',tt),...
            'Timer', S.OdorPreDuration,...
            'StateChangeConditions', {'Tup', sprintf('CS%d_lick',tt)},...
            'OutputActions', {'ValveModule1', ValveMessage,... % closes the blank valve, opens the odor valve (odor ON)
                'BNC1', 1, 'BNC2', 1}); 
        sma = AddState(sma, 'Name', sprintf('CS%d_lick',tt),...
            'Timer', S.OdorDuration-S.OdorPreDuration,...
            'StateChangeConditions', {'Port1In', OutcomeState,'Tup', 'ITI'},...
            'OutputActions', {'ValveModule1', ValveMessage,... % closes the blank valve, opens the odor valve (odor ON)
                'BNC1', 1, 'BNC2', 1}); 
    end
    sma = AddState(sma, 'Name', 'Laser',...
        'Timer', OptoStimDuration,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'WavePlayer1', LaserMessage, ... % trigger laser (for "nothing" odor this does nothing)
            'ValveModule1', 1, ... % opens the blank valve, closes the odor valve (odor OFF)
            'BNC1', 0, 'BNC2', 0});
    sma = AddState(sma, 'Name', 'ITI',...
        'Timer', ITIDuration,...
        'StateChangeConditions', {'Tup', 'exit'},...
        'OutputActions', {'ValveModule1', 1,... % opens the blank valve, closes the odor valve (odor OFF)
            'BNC1', 0, 'BNC2', 0});
    
    % Send state machine to Bpod device
    SendStateMatrix(sma);
    
    % Run the trial and return events
    RawEvents = RunStateMatrix;
    
    if ~isempty(fieldnames(RawEvents))
        % Save trial data
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial) = S;
        BpodSystem.Data.TrialTypes(currentTrial) = TrialType;
        BpodSystem.Data.StimTrials(currentTrial) = StimTrial;
        BpodSystem.Data.OdorID(currentTrial) = S.OdorValvesOrder(TrialType);
        BpodSystem.Data.RewardTime(currentTrial) = RewardTime;
        SaveBpodSessionData;
        
        % Update online plots
        PokesPlotLicksSlow('update');
    end

    % Handle pauses and exit if the user ended the session
    HandlePauseCondition;
    if BpodSystem.Status.BeingUsed == 0
        ModuleWrite('ValveModule1', ['B' 0]); % make sure the odor valves are closed
        return
    end
    
end

fprintf('\nProtocol finished\n')
toc;

end