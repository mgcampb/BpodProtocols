function StimPatterns_FreeWater_MultiSite_SinglePulse

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
% M. Campbell 1/25/2024: adapted for Different Stim Patterns experiment
%   (stim D1 neurons in different patterns while recording GRABDA signals in DA
%   axons in VS)
% M. Campbell 4/28/2024: Adapted for multisite stim. Got rid of PokesPlot
%   (too many states, no lick sensor anyway)
% M. Campbell 5/20/2024: 3secSq - 3 seconds of constant stim at different
%   frequencies (5, 10, 20 Hz)

global BpodSystem


COM_Ports = readtable('..\COM_Ports.txt'); % get COM ports from text file (ignored by git)


%% Setup (runs once before the first trial)

mouse = BpodSystem.Status.CurrentSubjectName;

BpodSystem.Data.TaskDescription = 'Rewards1 StimTrials Rewards2';

% Task parameters
S = BpodSystem.ProtocolSettings; 

% These parameters are shared across animals:
S.Experimenter = 'Malcolm';
S.Mouse = mouse;
S.NumLEDs = 3;
S.NumPatterns = 1;

NumRewardTrials1 = 20;
NumStimTrials = 120 * S.NumLEDs; % Number of stim trials
NumRewardTrials2 = 20;

S.ITIMean = 6;
S.ITIMin = 4;
S.ITIMax = 10;
S.RewardAmounts = [2 8];
S.ForeperiodDuration = 0.5;

S.StimPower_mW = input('Stim LED power (mW): ');

% display parameters
fprintf('\nSession parameters:\n')
S
fprintf('NumRewardTrials1 = %d\nNumStimTrials = %d\nNumRewardTrials2 = %d\n',...
    NumRewardTrials1,NumStimTrials,NumRewardTrials2);


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

%% Define stim trial types: 1 = Odor1, 2 = Odor2, etc
% Also define omission trials
NumTrialTypes = S.NumLEDs * S.NumPatterns;
ChunkSize = 2 * S.NumLEDs * S.NumPatterns; % trials; chunk size in which to balance trial types
NumChunks = ceil(NumStimTrials/ChunkSize);
TrialTypesChunk = repmat(1:NumTrialTypes,1,ChunkSize/NumTrialTypes);
TrialTypesMapping = nan(NumTrialTypes,1);
ctr = 1;
for i = 1:S.NumLEDs
    for j = 1:S.NumPatterns
        TrialTypesMapping(ctr) = 10*i+j;
        ctr = ctr+1;
    end
end
TrialTypes = [];
for i = 1:NumChunks
    perm_idx = randperm(ChunkSize);
    TrialTypes = [TrialTypes TrialTypesMapping(TrialTypesChunk(perm_idx))];
end
TrialTypes = TrialTypes(1:NumStimTrials);


%% Set up WavePlayer (Analog Output Module for controlling lasers)
W = BpodWavePlayer(COM_Ports.COM_Port{strcmp(COM_Ports.Module,'BpodWavePlayer')}); % Make sure the COM port is correct
SR = 10000; % Sampling rate for analog output
W.SamplingRate = SR;
W.OutputRange = '0V:5V';

% Create stim patterns:

% 1) Single pulse
waveform_SinglePulse = zeros(1,round(SR/20));
waveform_SinglePulse(1:(0.005 * SR)) = 5;
W.loadWaveform(1,waveform_SinglePulse);

% save waveforms:
S.stimWaveforms = {waveform_SinglePulse};

% load WavePlayerMessages messages
WavePlayerMessages = {};
for LED_idx = 1:S.NumLEDs
    WavePlayerMessages = [WavePlayerMessages {['P' 2^(LED_idx-1) 0]}]; % send waveform 1 to the LED_idx'th channel
end
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

    % Add the odor states (unused):
    for tt = 1:NumTrialTypes
        sma = AddState(sma, 'Name', sprintf('Stim%d',TrialTypesMapping(tt)),'Timer', 0,'StateChangeConditions',{},'OutputActions', {}); 
    end
    
    SendStateMatrix(sma); % Send state machine to the Bpod state machine device

    RawEvents = RunStateMatrix; % Run the trial and return events
     
    BpodSystem.Data.RewardAmounts1(currentTrial) = RewardAmount;
    
    % Update online plots
    if ~isempty(fieldnames(RawEvents))
        
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial) = S;

        SaveBpodSessionData;
        
    end
    
    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        clear W;
        return
    end
end

fprintf('Rewards1 finished\n');
toc;

pause(15);


%% Stim trials
fprintf('\nStim trials\n');
for currentTrial = 1:NumStimTrials
    
    TrialType = TrialTypes(currentTrial);
    StimPatternIdx = [];
    StimPattern = [];
    LED = floor(TrialType/10);
    StimPattern = mod(TrialType,10);
    WavePlayerMessageIdx = find(TrialTypesMapping==TrialType);
    
    % Compute variables for this trial's state machine:
   
    Stim_state = sprintf('Stim%d',TrialType);

    % Which laser pattern to trigger
    LaserMessage = WavePlayerMessageIdx;
    
    % Calculate ITI for this trial
    ITIDuration = exprnd(S.ITIMean-S.ITIMin) + S.ITIMin;
    if ITIDuration > S.ITIMax
        ITIDuration = S.ITIMax;
    end
    
    
    % Display trial type
    fprintf('\tTrial %d:\tTrialType%d\tITI=%0.1fs\n',...
        currentTrial,TrialType,ITIDuration);
    
    
    % Create state matrix
    sma = NewStateMatrix();
    sma = AddState(sma, 'Name', 'Foreperiod',...
        'Timer', S.ForeperiodDuration,...
        'StateChangeConditions', {'Tup', Stim_state},...
        'OutputActions', {'BNC1', 1, 'BNC2', 1});
    for tt = 1:NumTrialTypes
        sma = AddState(sma, 'Name', sprintf('Stim%d',TrialTypesMapping(tt)),...
            'Timer', 1,...
            'StateChangeConditions', {'Tup', 'ITI'},...
            'OutputActions', {'WavePlayer1', LaserMessage, 'BNC1', 0, 'BNC2', 0}); 
    end
    sma = AddState(sma, 'Name', 'ITI',...
        'Timer', ITIDuration,...
        'StateChangeConditions', {'Tup', 'exit'},...
        'OutputActions', {'BNC1', 0, 'BNC2', 0});

    % Add reward state (unused):
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
        SaveBpodSessionData;
        
    end

    % Handle pauses and exit if the user ended the session
    HandlePauseCondition;
    if BpodSystem.Status.BeingUsed == 0
        ModuleWrite('ValveModule1', ['B' 0]); % make sure the odor valves are closed
        clear W;
        return
    end
    
end

fprintf('Stim trials finished\n');
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

    % Add the odor states (unused):
    for tt = 1:NumTrialTypes
        sma = AddState(sma, 'Name', sprintf('Stim%d',TrialTypesMapping(tt)),'Timer', 0,'StateChangeConditions',{},'OutputActions', {}); 
    end
    
    SendStateMatrix(sma); % Send state machine to the Bpod state machine device

    RawEvents = RunStateMatrix; % Run the trial and return events
      
    BpodSystem.Data.RewardAmounts2(currentTrial) = RewardAmount;
    
    % Update online plots
    if ~isempty(fieldnames(RawEvents))
        
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial+NumRewardTrials1+NumStimTrials) = S;

        SaveBpodSessionData;

    end
    
    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        clear W;
        return
    end
end

fprintf('Rewards2 finished\n');
toc;

clear W;

fprintf('\nProtocol finished\n')

end