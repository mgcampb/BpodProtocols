function OdorLaser_FreeWater_Extinction

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
% M. Campbell 3/5/2023: 1 laser, 2 CS
% M. Campbell 10/11/2023: For extinction, just made all CS+ trials
%   omissions

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

NumRewardTrials1 = 20;
NumOdorTrials = 160; % Number of odor trials
NumRewardTrials2 = 20;
NumOptoStimTrials = 10; % unpredicted opto stim (to compare to predicted)

BpodSystem.Data.TaskDescription = 'Rewards1 OdorTrials Rewards2 UnpredOptoStim';

% Task parameters
S = BpodSystem.ProtocolSettings; % contains valve order for this mouse in field OdorValvesOdor

% These parameters are specific to each mouse and loaded from file:
if isempty(fieldnames(S))
    fprintf(['\n******\nWARNING: No saved task parameters found for this mouse.' ...
        '\nGenerating new default parameters.\n******\n']);
    S.NumOdors = input('Number of odors: ');
    S.NumLaser = input('Number of lasers: ');
    S.LaserPower = input('Laser power (mW): ');
    S.NumLaserPulse = input('Num laser pulse: '); % number of laser pulses to deliver after trace period
    S.LaserPulseDuration = input('Laser pulse duration (sec): '); % seconds
    S.LaserPulseFrequency = input('Laser pulse frequency (Hz): '); % Hz
    assert(numel(S.NumLaserPulse)==S.NumLaser && ...
        numel(S.LaserPulseDuration)==S.NumLaser && ...
        numel(S.LaserPulseFrequency)==S.NumLaser);
    % S.OdorValvesOrder = randperm(S.NumOdors);
    S.OdorValvesOrder = input('Odor Valves Order: ');
    assert(numel(S.OdorValvesOrder)==S.NumOdors);
    SaveProtocolSettings(S);
end

% These parameters are shared across animals:
S.Experimenter = 'Malcolm';
S.Mouse = mouse;
S.ForeperiodDuration = 0.5; % seconds
S.OdorDuration = 1; % seconds
S.TraceDuration = 0.5; % seconds
S.StimProbability = 0; % probability of receiving opto stim on laser trials % Changed to 0 for extinction MGC 10/11/23 (only thing changed)

S.ITIMean = 12;
S.ITIMin = 8;
S.ITIMax = 20;
S.RewardAmounts = [2 8];

% display parameters
fprintf('\nSession parameters:\n')
S
fprintf('NumRewardTrials1 = %d\nNumOdorTrials = %d\nNumRewardTrials2 = %d\nNumOptoStimTrials = %d\n',...
    NumRewardTrials1,NumOdorTrials,NumRewardTrials2,NumOptoStimTrials);

% Get opto stim duration
OptoStimDuration = S.NumLaserPulse/S.LaserPulseFrequency; % in sec

%% Define reward trial types

% assign reward sizes in blocks
nRewardAmounts = numel(S.RewardAmounts);
rewardsPerBlock = 5;
blockSize = rewardsPerBlock*nRewardAmounts;

% Rewards1:
RewardAmounts1 = nan(NumRewardTrials1, 1);
nBlocks = NumRewardTrials1/blockSize;
counter = 1;
for i = 1:nBlocks
    RewardAmount = repmat(S.RewardAmounts,1,rewardsPerBlock);
    RewardAmount = RewardAmount(randperm(blockSize));
    RewardAmounts1(counter:counter+blockSize-1) = RewardAmount;
    counter = counter+blockSize;
end

% Rewards2:
RewardAmounts2 = nan(NumRewardTrials1, 1);
nBlocks = NumRewardTrials1/blockSize;
counter = 1;
for i = 1:nBlocks
    RewardAmount = repmat(S.RewardAmounts,1,rewardsPerBlock);
    RewardAmount = RewardAmount(randperm(blockSize));
    RewardAmounts2(counter:counter+blockSize-1) = RewardAmount;
    counter = counter+blockSize;
end

%% Define odor trial types: 1 = Odor1, 2 = Odor2, etc
% Also define omission trials
TargetChunkSize = 16; % trials; chunk size in which to balance trial types
ActualChunkSize = S.NumOdors*round(TargetChunkSize/S.NumOdors);
NumChunks = ceil(NumOdorTrials/ActualChunkSize);
TrialTypesChunk = repmat(1:S.NumOdors,1,ActualChunkSize/S.NumOdors);
StimTrialsChunk = [ones(1,round(ActualChunkSize * S.StimProbability)) ...
    zeros(1,round(ActualChunkSize * (1-S.StimProbability)))];
StimTrialsChunk = StimTrialsChunk(1:ActualChunkSize);
TrialTypes = [];
StimTrials = [];
for i = 1:NumChunks
    perm_idx = randperm(ActualChunkSize);
    TrialTypes = [TrialTypes TrialTypesChunk(perm_idx)];
    StimTrials = [StimTrials StimTrialsChunk(perm_idx)];
end
TrialTypes = TrialTypes(1:NumOdorTrials);
StimTrials = StimTrials(1:NumOdorTrials);
StimTrials(TrialTypes==max(TrialTypes)) = 0; % the last trial type is nothing odor

%% Define optostim trial types

ChunkSize = 1;
NumChunks = NumOptoStimTrials/ChunkSize;
assert(rem(NumChunks,1)==0);
assert(rem(ChunkSize,S.NumLaser)==0);
OptoStimTrialTypes = [];
for i = 1:NumChunks
    OptoStimTrialTypes_this = repmat(1:S.NumLaser,1,ChunkSize/S.NumLaser);
    OptoStimTrialTypes_this = OptoStimTrialTypes_this(randperm(ChunkSize));
    OptoStimTrialTypes = [OptoStimTrialTypes OptoStimTrialTypes_this];
end

%% Pokes plot
state_colors = struct( ...
    'Foreperiod',[.9,.9,.9],...
    'Reward',[0 1 0],...
    'CS1', [0 1 1],...
    'CS2', [0 0 1],...
    'Trace', [.6 .6 .6],...
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

%% Rewards1
tic
AccumulatedReward = 0;
fprintf('\nRewards1\n');
for currentTrial = 1:NumRewardTrials1

    RewardAmount = RewardAmounts1(currentTrial);
    RewardValveTime = GetValveTimes(RewardAmount, 1);

    AccumulatedReward = AccumulatedReward+RewardAmount;

    % Calculate ITI for this trial
    ITIDuration = exprnd(S.ITIMean-S.ITIMin) + S.ITIMin;
    if ITIDuration > S.ITIMax
        ITIDuration = S.ITIMax;
    end

    fprintf('\tTrial %d:\t%duL\t\tAccumRew=%duL\tValveTime=%0.1fms\tITI=%0.1fs\n',...
        currentTrial,RewardAmount,AccumulatedReward,RewardValveTime*1000,ITIDuration);

    %--- Assemble state machine
    sma = NewStateMatrix();
    
    sma = AddState(sma,'Name','Foreperiod',...
        'Timer',S.ForeperiodDuration,...
        'StateChangeConditions',{'Tup','Reward'},...
        'OutputActions',{'BNC1',1,'BNC2',1});
    sma = AddState(sma, 'Name', 'Reward', ... 
        'Timer', RewardValveTime,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'ValveState',1,'BNC1',1,'BNC2',1}); 
    sma = AddState(sma, 'Name', 'ITI', ... 
        'Timer', ITIDuration,...
        'StateChangeConditions', {'Tup','exit'},...
        'OutputActions', {'BNC1',0,'BNC2',0});

    % Add the odor states so that pokes plot doesn't get messed up:
    sma = AddState(sma, 'Name','Trace','Timer',0,'StateChangeConditions',{},'OutputActions', {});
    for tt = 1:S.NumOdors
        sma = AddState(sma, 'Name', sprintf('CS%d',tt),'Timer', 0,'StateChangeConditions',{},'OutputActions', {}); 
    end
    sma = AddState(sma,'Name','Laser','Timer', 0,'StateChangeConditions', {},'OutputActions', {});
    
    SendStateMatrix(sma); % Send state machine to the Bpod state machine device

    RawEvents = RunStateMatrix; % Run the trial and return events
     
    BpodSystem.Data.RewardAmounts1(currentTrial) = RewardAmount;
    
    % Update online plots
    if ~isempty(fieldnames(RawEvents))
        
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial) = S;

        SaveBpodSessionData;
        
        PokesPlotLicksSlow('update');
    end
    
    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end
end

fprintf('Rewards1 finished\n');
toc;

pause(15);


%% Odor trials
fprintf('\nOdor trials\n');
for currentTrial = 1:NumOdorTrials
    
    TrialType = TrialTypes(currentTrial);
    StimTrial = StimTrials(currentTrial);
    
    % Compute variables for this trial's state machine:
    
    CS_state = sprintf('CS%d',TrialType);
    if StimTrial==1
        OutcomeState = 'Laser';
    else
        OutcomeState = 'ITI';
    end

    % Serial message to open/close odor valves
    ValveMessage = TrialType+1;
    
    % Which laser channel to trigger
    LaserMessage = min(TrialType,S.NumLaser+1);
    
    % Calculate ITI for this trial
    ITIDuration = exprnd(S.ITIMean-S.ITIMin) + S.ITIMin;
    if ITIDuration > S.ITIMax
        ITIDuration = S.ITIMax;
    end
    
    % So that ITI is the same for Stim and NoStim trials:
    if strcmp(OutcomeState,'ITI')
        ITIDuration = ITIDuration+OptoStimDuration;
    end
    
    % Display trial type
    if LaserMessage > S.NumLaser
        fprintf('\tTrial %d:\tTrialType%d\tNoLaser\tOdor%d\tStim=%d ITI=%0.1fs\n',...
            currentTrial,TrialType,S.OdorValvesOrder(TrialType),StimTrial,ITIDuration);
    else
        fprintf('\tTrial %d:\tTrialType%d\tLaser%d\tOdor%d\tStim=%d ITI=%0.1fs\n',...
            currentTrial,TrialType,LaserMessage,S.OdorValvesOrder(TrialType),StimTrial,ITIDuration);
    end
    
    if StimTrial == 0 % omit laser
        LaserMessage = S.NumLaser+1; 
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
                'BNC1', 1, 'BNC2', 1}); 
    end
    sma = AddState(sma, 'Name', 'Trace',...
        'Timer', S.TraceDuration,...
        'StateChangeConditions', {'Tup', OutcomeState},...
        'OutputActions', {'ValveModule1', 1,... % opens the blank valve, closes the odor valve
            'BNC1', 1, 'BNC2', 1}); 
    sma = AddState(sma, 'Name', 'Laser',...
        'Timer', OptoStimDuration,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'WavePlayer1', LaserMessage, 'BNC1', 0, 'BNC2', 0});
    sma = AddState(sma, 'Name', 'ITI',...
        'Timer', ITIDuration,...
        'StateChangeConditions', {'Tup', 'exit'},...
        'OutputActions', {'BNC1', 0, 'BNC2', 0});

    % Add reward state so pokes plot doesn't get messed up:
    sma = AddState(sma,'Name','Reward','Timer',0,'StateChangeConditions',{},'OutputActions',{}); 
    
    % Send state machine to Bpod device
    SendStateMatrix(sma);
    
    % Run the trial and return events
    RawEvents = RunStateMatrix;
    
    if ~isempty(fieldnames(RawEvents))
        % Save trial data
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial+NumRewardTrials1) = S;
        BpodSystem.Data.TrialTypes(currentTrial) = TrialType;
        BpodSystem.Data.StimTrials(currentTrial) = StimTrial;
        BpodSystem.Data.OdorID(currentTrial) = S.OdorValvesOrder(TrialType);
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

fprintf('Odor trials finished\n');
toc;

pause(15);

%% Second set of rewards

fprintf('\nRewards2\n')
for currentTrial = 1:NumRewardTrials2

    RewardAmount = RewardAmounts2(currentTrial);
    RewardValveTime = GetValveTimes(RewardAmount, 1);

    AccumulatedReward = AccumulatedReward+RewardAmount;

    % Calculate ITI for this trial
    ITIDuration = exprnd(S.ITIMean-S.ITIMin) + S.ITIMin;
    if ITIDuration > S.ITIMax
        ITIDuration = S.ITIMax;
    end

    fprintf('\tTrial %d:\t%duL\t\tAccumRew=%duL\tValveTime=%0.1fms\tITI=%0.1fs\n',...
        currentTrial,RewardAmount,AccumulatedReward,RewardValveTime*1000,ITIDuration);

    %--- Assemble state machine
    sma = NewStateMatrix();
    
    sma = AddState(sma,'Name','Foreperiod',...
        'Timer',S.ForeperiodDuration,...
        'StateChangeConditions',{'Tup','Reward'},...
        'OutputActions',{'BNC1',1,'BNC2',1});
    sma = AddState(sma, 'Name', 'Reward', ... 
        'Timer', RewardValveTime,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'ValveState',1,'BNC1',1,'BNC2',1}); 
    sma = AddState(sma, 'Name', 'ITI', ... 
        'Timer', ITIDuration,...
        'StateChangeConditions', {'Tup','exit'},...
        'OutputActions', {'BNC1',0,'BNC2',0});

    % Add the odor states so that pokes plot doesn't get messed up:
    sma = AddState(sma, 'Name','Trace','Timer',0,'StateChangeConditions',{},'OutputActions', {});
    for tt = 1:S.NumOdors
        sma = AddState(sma, 'Name', sprintf('CS%d',tt),'Timer', 0,'StateChangeConditions',{},'OutputActions', {}); 
    end
    sma = AddState(sma,'Name','Laser','Timer', 0,'StateChangeConditions', {},'OutputActions', {});
    
    SendStateMatrix(sma); % Send state machine to the Bpod state machine device

    RawEvents = RunStateMatrix; % Run the trial and return events
      
    BpodSystem.Data.RewardAmounts2(currentTrial) = RewardAmount;
    
    % Update online plots
    if ~isempty(fieldnames(RawEvents))
        
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial+NumRewardTrials1+NumOdorTrials) = S;

        SaveBpodSessionData;
        
        PokesPlotLicksSlow('update');
    end
    
    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end
end

fprintf('Rewards2 finished\n');
toc;

pause(15);

%% Opto stim trials
fprintf('\nOptoStim\n');
for currentTrial = 1:NumOptoStimTrials

    % Calculate ITI for this trial
    ITIDuration = exprnd(S.ITIMean-S.ITIMin) + S.ITIMin;
    if ITIDuration > S.ITIMax
        ITIDuration = S.ITIMax;
    end

    % Which laser channel to trigger
    LaserMessage = OptoStimTrialTypes(currentTrial);

    fprintf('\tTrial %d:\tLaser%d\tITI=%0.1fs\n',currentTrial,LaserMessage,ITIDuration);

    %--- Assemble state machine
    sma = NewStateMatrix();
    
    sma = AddState(sma,'Name','Foreperiod',...
        'Timer',S.ForeperiodDuration,...
        'StateChangeConditions',{'Tup','Laser'},...
        'OutputActions',{'BNC1',1,'BNC2',1});
    sma = AddState(sma, 'Name', 'Laser',...
        'Timer', OptoStimDuration,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'WavePlayer1', LaserMessage, 'BNC1', 0, 'BNC2', 0});
    sma = AddState(sma, 'Name', 'ITI', ... 
        'Timer', ITIDuration,...
        'StateChangeConditions', {'Tup','exit'},...
        'OutputActions', {'BNC1',0,'BNC2',0});

    % Add the odor states so that pokes plot doesn't get messed up:
    sma = AddState(sma, 'Name','Trace','Timer',0,'StateChangeConditions',{},'OutputActions', {});
    for tt = 1:S.NumOdors
        sma = AddState(sma, 'Name', sprintf('CS%d',tt),'Timer', 0,'StateChangeConditions',{},'OutputActions', {}); 
    end
    sma = AddState(sma, 'Name', 'Reward', 'Timer', 0, 'StateChangeConditions', {}, 'OutputActions', {}); 
    
    SendStateMatrix(sma); % Send state machine to the Bpod state machine device

    RawEvents = RunStateMatrix; % Run the trial and return events
     
    BpodSystem.Data.OptoStimTrialTypes(currentTrial) = LaserMessage;
    
    % Update online plots
    if ~isempty(fieldnames(RawEvents))
        
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial) = S;

        SaveBpodSessionData;
        
        PokesPlotLicksSlow('update');
    end
    
    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end
end

fprintf('OptoStim finished\n');
toc;

fprintf('\nProtocol finished\n')

end