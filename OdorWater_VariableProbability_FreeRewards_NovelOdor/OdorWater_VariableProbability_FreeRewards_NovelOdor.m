function OdorWater_VariableProbability_FreeRewards_NovelOdor

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
% M. Campbell 8/16/2024: Added interleaved novel odor (CS3) trials

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


ChunkSize = 21; % trials; chunk size in which to balance trial types
NumTrials_Conditioning = ChunkSize*10;
% ChunkSize = 20;
% NumTrials_Conditioning = ChunkSize*8;
NumNovelOdorTrials = 5;
NumTrials_Total = NumTrials_Conditioning+NumNovelOdorTrials;


BpodSystem.Data.TaskDescription = 'OdorWater_VariableProbability';

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

S.RewardProbability = [0.9 0]; % one per odor (other than novel odor)
% S.RewardProbability = [1 0]; % one per odor
S.FracTrials_Odor = [10/ChunkSize 10/ChunkSize]; % fraction trials per odor
S.FracTrials_Free = 1-sum(S.FracTrials_Odor); % fraction free reward trials
assert(S.NumOdors == numel(S.RewardProbability),'RewardProbability must have same number of elements as there are odors'); % assert one reward probability per odor
S.RewardAmount = 4; % in uL; same for all odors

S.ITIMean = 12;
S.ITIMin = 8;
S.ITIMax = 20;

% Add novel odor
S.NumOdors = S.NumOdors+1;
S.OdorValvesOrder = [S.OdorValvesOrder S.NumOdors];

% display parameters
fprintf('\nSession parameters:\n')
S
fprintf('NumTrials_Total = %d\n',NumTrials_Total);


%% Define trial types: 0 = free reward; 1 = Odor1, 2 = Odor2, etc; 
% Also define omission trials
NumChunks = ceil(NumTrials_Conditioning/ChunkSize);
TrialTypes = [];
RewardTrials = [];
for chunkIdx = 1:NumChunks
    
    N_free = round(ChunkSize*S.FracTrials_Free);
    tt_this = zeros(1,N_free);
    rew_this = ones(1,N_free);
    for odorIdx = 1:S.NumOdors-1
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

% add novel odor trials
offset = 20;
chunk = floor((NumTrials_Conditioning-offset)/NumNovelOdorTrials);
for trIdx = 1:NumNovelOdorTrials
    tr_this = offset+randperm(chunk,1);
    TrialTypes = [TrialTypes(1:tr_this) S.NumOdors TrialTypes(tr_this+1:end)];
    RewardTrials = [RewardTrials(1:tr_this) 0 RewardTrials(tr_this+1:end)];
    offset = offset+chunk+1;
end


%% Pokes plot
state_colors = struct( ...
    'Foreperiod',[.9,.9,.9],...
    'Reward',[0 1 0],...
    'CS1', [0 1 1],...
    'CS2', [0 0 1],...
    'CS3', [1 0 0],...
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


%% Odor trials
tic
AccumulatedReward = 0;
for currentTrial = 1:NumTrials_Total
    
    TrialType = TrialTypes(currentTrial);
    RewardTrial = RewardTrials(currentTrial);
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

    % Serial message to open/close odor valves
    ValveMessage = TrialType+1;
    
    % Calculate ITI for this trial
    ITIDuration = exprnd(S.ITIMean-S.ITIMin) + S.ITIMin;
    if ITIDuration > S.ITIMax
        ITIDuration = S.ITIMax;
    end
    
    % Display trial type
    if TrialType==0
        fprintf('\tTrial %d:\tTrialType%d\tFree\tRewardTrial=%d TotalReward=%d ITI=%0.1fs\n',...
            currentTrial,TrialType,RewardTrial,AccumulatedReward,ITIDuration);
    else
        fprintf('\tTrial %d:\tTrialType%d\tOdor%d\tRewardTrial=%d TotalReward=%d ITI=%0.1fs\n',...
            currentTrial,TrialType,S.OdorValvesOrder(TrialType),RewardTrial,AccumulatedReward,ITIDuration);
    end
    
    % Create state matrix
    sma = NewStateMatrix();
    sma = AddState(sma, 'Name', 'Foreperiod',...
        'Timer', S.ForeperiodDuration,...
        'StateChangeConditions', {'Tup', CS_state},...
        'OutputActions', {'BNC1', 1, 'BNC2', 1});
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