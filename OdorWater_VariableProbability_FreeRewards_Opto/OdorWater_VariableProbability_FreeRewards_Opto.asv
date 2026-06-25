function OdorWater_VariableProbability_FreeRewards_Opto

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
% M. Campbell 1/3/2023: Changed to just deliver Odors followed by Water
% M. Campbell 7/17/2024: Added unpredicted water trials
% M. Campbell 6/23/2026: Added opto stim throughout half of trials
    % NOTE: script assumes there are two odors, first is rewarded
    % (probabilistically) second is not rewarded

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


NumTrials_pre = 8; % trials before the opto trials to make sure behavior is re-established
ChunkSize = 21; % trials; chunk size in which to balance trial types during the opto delivery
NumTrials_opto = ChunkSize*10; 
NumTrials_total = NumTrials_pre + NumTrials_opto;


BpodSystem.Data.TaskDescription = 'OdorWater_VariableProbability with free rewards and opto delivery';

% Task parameters
S = BpodSystem.ProtocolSettings; % contains valve order for this mouse in field OdorValvesOdor

% These parameters are specific to each mouse and loaded from file:
if isempty(fieldnames(S))
    fprintf(['\n******\nWARNING: No saved task parameters found for this mouse.' ...
        '\nGenerating new default parameters.\n******\n']);
    S.NumOdors = input('Number of odors: ');
    S.OdorValvesOrder = input('Odor valve order (use brackets): ');
    % S.OdorValvesOrder = randperm(S.NumOdors);
    assert(S.NumOdors == numel(S.OdorValvesOrder),'S.NumOdors must match numel(S.OdorValvesOrder)');
    SaveProtocolSettings(S);
end

% These parameters are shared across animals:
S.Experimenter = 'Malcolm';
S.Mouse = mouse;
S.ForeperiodDuration = 0.5; % seconds
S.OdorDuration = 1; % seconds
S.TraceDuration = 1; % seconds

% Opto params:
S.StimChannel = 2;
S.StimPower_mW = input('Stim power (mW): ');
S.NumLaserPulse = 1; % number of laser pulses to deliver after trace period
S.LaserPulseDuration = 3.5; % seconds
S.LaserPulseFrequency = 0.2; % Hz

S.RewardProbability = [0.9 0]; % one per odor
% S.RewardProbability = [1 0]; % one per odor
S.FracTrials_Odor = [10/ChunkSize 10/ChunkSize]; % fraction trials per odor
S.FracTrials_Free = 1-sum(S.FracTrials_Odor); % fraction free reward trials
assert(S.NumOdors == numel(S.RewardProbability),'RewardProbability must have same number of elements as there are odors'); % assert one reward probability per odor
S.RewardAmount = 4; % in uL; same for all odors

S.ITIMean = 12;
S.ITIMin = 8;
S.ITIMax = 20;

% display parameters
fprintf('\nSession parameters:\n')
S
fprintf('NumTrials_total = %d, NumTrials_pre = %d\n',NumTrials_total, NumTrials_pre);


%% Define trial types: 0 = free reward; 1 = Odor1, 2 = Odor2, etc; 
% Also define omission trials

if NumTrials_pre>0
    TrialTypes = [ones(1,round(NumTrials_pre/2)) 2*ones(1,round(NumTrials_pre/2))];
    RewardTrials = [ones(1,round(NumTrials_pre/2)) zeros(1,round(NumTrials_pre/2))];
    shuf_idx = randperm(NumTrials_pre);
    TrialTypes = TrialTypes(shuf_idx);
    RewardTrials = RewardTrials(shuf_idx);
else
    TrialTypes = [];
    RewardTrials = [];
end

NumChunks = ceil(NumTrials_opto/ChunkSize);
for chunkIdx = 1:NumChunks
    
    N_free = round(ChunkSize*S.FracTrials_Free);
    tt_this = zeros(1,N_free);
    rew_this = ones(1,N_free);
    for odorIdx = 1:S.NumOdors
        N_odor = round(ChunkSize*S.FracTrials_Odor(odorIdx));
        N_rew = round(N_odor*S.RewardProbability(odorIdx));
        tt_this = [tt_this odorIdx*ones(1,N_odor)];
        rew_this = [rew_this ones(1,N_rew) zeros(1,N_odor-N_rew)];
    end
    
    max_consec = Inf;
    while tt_this(1)==0 || ...
            (tt_this(1)~=0 && rew_this(1)==0) || ...
            max_consec > 3
        shuf_idx = randperm(ChunkSize);
        tt_this = tt_this(shuf_idx);
        rew_this = rew_this(shuf_idx);
        max_consec = max(diff([0 find(diff(tt_this)~=0) ChunkSize]));
    end
    
    TrialTypes = [TrialTypes tt_this];
    RewardTrials = [RewardTrials rew_this];          
    
end


%% Define opto tials


% OptoTrials = repmat([0 1], 1, round(numel(TrialTypes)/2));

OptoTrials = nan(size(TrialTypes));
TrialTypes_withRewardInfo = TrialTypes+10*RewardTrials;
TrialTypes_uniq = unique(TrialTypes_withRewardInfo);

% TrialTypes_uniq are:
%     1 = Odor1, unrewarded
%     2 = Odor2, unrewarded
%     10 = free reward
%     11 = Odor 1, rewarded
ChunkSize_opto = 2;
for ttIdx = 1:numel(TrialTypes_uniq)
    idx_this = find(TrialTypes_withRewardInfo==TrialTypes_uniq(ttIdx));
    NumChunks_this = round(numel(idx_this)/ChunkSize_opto);
    opto_chunk = repmat([0 1],1,round(ChunkSize_opto/2));
    OptoTrials_this = [];
    for chunkIdx = 1:NumChunks_this
        shuf_idx = randperm(ChunkSize_opto);
        OptoTrials_this = [OptoTrials_this opto_chunk(shuf_idx)];
    end
    OptoTrials(idx_this) = OptoTrials_this;
end

OptoTrials(1:NumTrials_pre) = 0;


%% Pokes plot
state_colors = struct( ...
    'Foreperiod',[.9,.9,.9],...
    'Reward',[0 1 0],...
    'CS1', [0 1 1],...
    'CS2', [0 0 1],...
    'Trace', [.6 .6 .6],...
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


%% Set up opto stim messages
% Set up WavePlayer (Analog Output Module for controlling lasers)
W = BpodWavePlayer(COM_Ports.COM_Port{strcmp(COM_Ports.Module,'BpodWavePlayer')}); % Make sure the COM port is correct
SR = 10000; % Sampling rate for analog output
W.SamplingRate = SR;
W.OutputRange = '0V:5V';
waveform = zeros(1,round(SR/S.LaserPulseFrequency));
waveform(1:(S.LaserPulseDuration * SR)) = 5;
waveform = repmat(waveform,1,S.NumLaserPulse);
W.loadWaveform(1,waveform);
WavePlayerMessages = {};
WavePlayerMessages = [WavePlayerMessages {['P' 2^(S.StimChannel-1) 0]}]; % Send StimWaveform to the StimChannel (this is message 1)
WavePlayerMessages = [WavePlayerMessages {''}]; % Do nothing (this is message 2)
LoadSerialMessages('WavePlayer1', WavePlayerMessages);


%% Odor trials
tic
AccumulatedReward = 0;
for currentTrial = 1:NumTrials_total
    
    TrialType = TrialTypes(currentTrial);
    RewardTrial = RewardTrials(currentTrial);
    OptoTrial = OptoTrials(currentTrial);
    RewardValveTime = GetValveTimes(S.RewardAmount, 1);
    if RewardTrial
        AccumulatedReward = AccumulatedReward+S.RewardAmount;
    end

    if TrialType==0
        CS_state = 'Reward';
    else
        CS_state = sprintf('CS%d',TrialType);
    end
    if RewardTrial==1
        OutcomeState = 'Reward';
    else
        OutcomeState = 'ITI';
    end
    if OptoTrial==1
        LaserMessage=1;
    else
        LaserMessage=2;
    end

    % Serial message to open/close odor valves
    ValveMessage = TrialType+1;
    
    % Calculate ITI for this trial
    ITIDuration = exprnd(S.ITIMean-S.ITIMin) + S.ITIMin;
    if ITIDuration > S.ITIMax
        ITIDuration = S.ITIMax;
    end
    
    % Display trial type
    if TrialType==0
        fprintf('\tTrial %d:\tTrialType%d\tFree\tRewardTrial=%d TotalReward=%d Opto=%d ITI=%0.1fs\n',...
            currentTrial,TrialType,RewardTrial,AccumulatedReward,OptoTrial,ITIDuration);
    else
        fprintf('\tTrial %d:\tTrialType%d\tOdor%d\tRewardTrial=%d TotalReward=%d Opto=%d ITI=%0.1fs\n',...
            currentTrial,TrialType,S.OdorValvesOrder(TrialType),RewardTrial,AccumulatedReward,OptoTrial,ITIDuration);
    end
    
    % Create state matrix
    sma = NewStateMatrix();
    sma = AddState(sma, 'Name', 'Foreperiod',...
        'Timer', S.ForeperiodDuration,...
        'StateChangeConditions', {'Tup', CS_state},...
        'OutputActions', {'BNC1', 1, 'BNC2', 1, 'WavePlayer1', LaserMessage});
    for tt = 1:S.NumOdors
        sma = AddState(sma, 'Name', sprintf('CS%d',tt),...
            'Timer', S.OdorDuration,...
            'StateChangeConditions', {'Tup', 'Trace'},...
            'OutputActions', {'ValveModule1', ValveMessage,... % closes the blank valve, opens the odor valve
                'BNC1', 0, 'BNC2', 0}); 
    end
    sma = AddState(sma, 'Name', 'Trace',...
        'Timer', S.TraceDuration,...
        'StateChangeConditions', {'Tup', OutcomeState},...
        'OutputActions', {'ValveModule1', 1,... % opens the blank valve, closes the odor valve
            'BNC1', 0, 'BNC2', 0}); 
    sma = AddState(sma, 'Name', 'Reward',...
        'Timer', RewardValveTime,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'ValveState',1,'BNC1', 0, 'BNC2', 0});
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
        BpodSystem.Data.TrialTypes(currentTrial) = TrialType;
        BpodSystem.Data.RewardTrials(currentTrial) = RewardTrial;
        BpodSystem.Data.OptoTrials(currentTrial) = OptoTrial;
        BpodSystem.Data.AccumulatedReward(currentTrial) = AccumulatedReward; 
        if TrialType==0
            BpodSystem.Data.OdorID(currentTrial) = nan;
        else
            BpodSystem.Data.OdorID(currentTrial) = S.OdorValvesOrder(TrialType);
        end
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
toc;

fprintf('\nProtocol finished\n')

end