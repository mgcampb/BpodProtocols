function StimPatterns_FreeWater_7Patterns

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
% (stim D1 neurons in different patterns while recording GRABDA signals in DA
% axons in VS)
% M. Campbell 7/16/2024: 7 stim patterns (original 4 plus three more: 3 sec
%   square wave at 5, 10, 20 Hz)

global BpodSystem


COM_Ports = readtable('..\COM_Ports.txt'); % get COM ports from text file (ignored by git)

%% Setup (runs once before the first trial)

mouse = BpodSystem.Status.CurrentSubjectName;

NumRewardTrials1 = 2*8;
NumStimTrials1 = 7*15;
NumRewardTrials2 = 2*8;
NumStimTrials2 = 7*15;
NumRewardTrials3 = 2*8;

BpodSystem.Data.TaskDescription = 'Rewards1 StimTrials1 Rewards2 StimTrials2 Rewards3';

% Task parameters
S = BpodSystem.ProtocolSettings; 

% These parameters are shared across animals:
S.Experimenter = 'Malcolm';
S.Mouse = mouse;
S.NumPatterns = 7;

S.ITIMean = 12;
S.ITIMin = 8;
S.ITIMax = 20;
S.RewardAmounts = [2 8];
S.ForeperiodDuration = 0.5;

S.StimPower_mW = input('Stim LED power (mW): ');
S.PulseDur = 0.002;

% display parameters
fprintf('\nSession parameters:\n')
S
fprintf('NumRewardTrials1 = %d\nNumStimTrials1 = %d\nNumRewardTrials2 = %d\nNumStimTrials2 = %d\nNumRewardTrials2 = %d\n',...
    NumRewardTrials1,NumStimTrials1,NumRewardTrials2,NumStimTrials2,NumRewardTrials3);


%% Define reward trial types

% assign reward sizes in blocks
nRewardAmounts = numel(S.RewardAmounts);
rewardsPerBlock = 2;
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
RewardAmounts2 = nan(NumRewardTrials2, 1);
nBlocks = NumRewardTrials2/blockSize;
counter = 1;
for i = 1:nBlocks
    RewardAmount = repmat(S.RewardAmounts,1,rewardsPerBlock);
    RewardAmount = RewardAmount(randperm(blockSize));
    RewardAmounts2(counter:counter+blockSize-1) = RewardAmount;
    counter = counter+blockSize;
end

% Rewards3:
RewardAmounts3 = nan(NumRewardTrials3, 1);
nBlocks = NumRewardTrials3/blockSize;
counter = 1;
for i = 1:nBlocks
    RewardAmount = repmat(S.RewardAmounts,1,rewardsPerBlock);
    RewardAmount = RewardAmount(randperm(blockSize));
    RewardAmounts3(counter:counter+blockSize-1) = RewardAmount;
    counter = counter+blockSize;
end


%% Define stim trial types
TargetChunkSize = 7; % trials; chunk size in which to balance trial types
ActualChunkSize = S.NumPatterns*round(TargetChunkSize/S.NumPatterns);
TrialTypesChunk = repmat(1:S.NumPatterns,1,ActualChunkSize/S.NumPatterns);

NumChunks1 = ceil(NumStimTrials1/ActualChunkSize);
TrialTypes1 = [];
for i = 1:NumChunks1
    perm_idx = randperm(ActualChunkSize);
    TrialTypes1 = [TrialTypes1 TrialTypesChunk(perm_idx)];
end
TrialTypes1 = TrialTypes1(1:NumStimTrials1);

NumChunks2 = ceil(NumStimTrials2/ActualChunkSize);
TrialTypes2 = [];
for i = 1:NumChunks2
    perm_idx = randperm(ActualChunkSize);
    TrialTypes2 = [TrialTypes2 TrialTypesChunk(perm_idx)];
end
TrialTypes2 = TrialTypes2(1:NumStimTrials2);


%% Set up WavePlayer (Analog Output Module for controlling lasers)
W = BpodWavePlayer(COM_Ports.COM_Port{strcmp(COM_Ports.Module,'BpodWavePlayer')}); % Make sure the COM port is correct
SR = 10000; % Sampling rate for analog output
W.SamplingRate = SR;
W.OutputRange = '0V:5V';

% Stim patterns: 

% 1) 1 sec at 20 Hz
waveform_1secSquare_20Hz = zeros(1,round(SR/20));
waveform_1secSquare_20Hz(1:(S.PulseDur * SR)) = 5;
waveform_1secSquare_20Hz = repmat(waveform_1secSquare_20Hz,1,20);
W.loadWaveform(1,waveform_1secSquare_20Hz);

% 2) 2 sec at 20 Hz
waveform_2secSquare_20Hz = zeros(1,round(SR/20));
waveform_2secSquare_20Hz(1:(S.PulseDur * SR)) = 5;
waveform_2secSquare_20Hz = repmat(waveform_2secSquare_20Hz,1,40);
W.loadWaveform(2,waveform_2secSquare_20Hz);

% 3) 2 sec ramping up
waveform_rampUp = [];
freq = 4;
for i = 1:24
    numOnes = S.PulseDur*SR;
    numZeros = round(SR/freq)-numOnes;
    waveform_rampUp = [waveform_rampUp 5*ones(1,numOnes) zeros(1,numZeros)];
    freq = freq*1.135; 
end
W.loadWaveform(3,waveform_rampUp);

% 4) 2 sec ramping down
waveform_rampDown = fliplr(waveform_rampUp);
waveform_rampDown = [waveform_rampDown(87:end) zeros(1,86)]; % align to zero
W.loadWaveform(4,waveform_rampDown);

% 5) 3 sec at 5 Hz
waveform_3secSquare_5Hz = zeros(1,round(SR/5));
waveform_3secSquare_5Hz(1:(S.PulseDur * SR)) = 5;
waveform_3secSquare_5Hz = repmat(waveform_3secSquare_5Hz,1,15);
W.loadWaveform(5,waveform_3secSquare_5Hz);

% 6) 3 sec at 10 Hz
waveform_3secSquare_10Hz = zeros(1,round(SR/10));
waveform_3secSquare_10Hz(1:(S.PulseDur * SR)) = 5;
waveform_3secSquare_10Hz = repmat(waveform_3secSquare_10Hz,1,30);
W.loadWaveform(6,waveform_3secSquare_10Hz);

% 7) 3 sec at 20 Hz
waveform_3secSquare_20Hz = zeros(1,round(SR/20));
waveform_3secSquare_20Hz(1:(S.PulseDur * SR)) = 5;
waveform_3secSquare_20Hz = repmat(waveform_3secSquare_20Hz,1,60);
W.loadWaveform(7,waveform_3secSquare_20Hz);

% load waveforms to WavePlayer:
WavePlayerMessages = {};
LED_idx = 1;
for patternIdx = 1:S.NumPatterns
    WavePlayerMessages = [WavePlayerMessages {['P' 2^(LED_idx-1) patternIdx-1]}]; % send waveform patternIdx to the LED_idx'th channel
end
LoadSerialMessages('WavePlayer1', WavePlayerMessages);

% save waveforms to bpod output structure S (task parameters):
S.stimWaveforms = {};
S.stimWaveforms = {waveform_1secSquare_20Hz,waveform_2secSquare_20Hz,waveform_rampUp,waveform_rampDown,...
    waveform_3secSquare_5Hz,waveform_3secSquare_10Hz,waveform_3secSquare_20Hz};


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
    for tt = 1:S.NumPatterns
        sma = AddState(sma, 'Name', sprintf('Stim%d',tt),'Timer', 0,'StateChangeConditions',{},'OutputActions', {}); 
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
        return
    end
end

fprintf('Rewards1 finished\n');
toc;

pause(10);


%% First set of stim trials
fprintf('\nStim trials1\n');
for currentTrial = 1:NumStimTrials1
    
    TrialType = TrialTypes1(currentTrial);
    
    % Compute variables for this trial's state machine:
   
    Stim_state = sprintf('Stim%d',TrialType);

    % Which laser pattern to trigger
    LaserMessage = TrialType;
    
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
    for tt = 1:S.NumPatterns
        sma = AddState(sma, 'Name', sprintf('Stim%d',tt),...
            'Timer', 2,...
            'StateChangeConditions', {'Tup', 'ITI'},...
            'OutputActions', {'WavePlayer1', LaserMessage, 'BNC1', 0, 'BNC2', 0}); 
    end
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
        BpodSystem.Data.TrialTypes1(currentTrial) = TrialType;
        SaveBpodSessionData;
        
    end

    % Handle pauses and exit if the user ended the session
    HandlePauseCondition;
    if BpodSystem.Status.BeingUsed == 0
        ModuleWrite('ValveModule1', ['B' 0]); % make sure the odor valves are closed
        return
    end
    
end

fprintf('Stim trials1 finished\n');
toc;

pause(10);


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
    for tt = 1:S.NumPatterns
        sma = AddState(sma, 'Name', sprintf('Stim%d',tt),'Timer', 0,'StateChangeConditions',{},'OutputActions', {}); 
    end
    
    SendStateMatrix(sma); % Send state machine to the Bpod state machine device

    RawEvents = RunStateMatrix; % Run the trial and return events
      
    BpodSystem.Data.RewardAmounts2(currentTrial) = RewardAmount;
    
    % Update online plots
    if ~isempty(fieldnames(RawEvents))
        
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial+NumRewardTrials1+NumStimTrials1) = S;

        SaveBpodSessionData;

    end
    
    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end
end

fprintf('Rewards2 finished\n');
toc;

pause(10);


%% First set of stim trials
fprintf('\nStim trials2\n');
for currentTrial = 1:NumStimTrials2
    
    TrialType = TrialTypes2(currentTrial);
    
    % Compute variables for this trial's state machine:
   
    Stim_state = sprintf('Stim%d',TrialType);

    % Which laser pattern to trigger
    LaserMessage = TrialType;
    
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
    for tt = 1:S.NumPatterns
        sma = AddState(sma, 'Name', sprintf('Stim%d',tt),...
            'Timer', 2,...
            'StateChangeConditions', {'Tup', 'ITI'},...
            'OutputActions', {'WavePlayer1', LaserMessage, 'BNC1', 0, 'BNC2', 0}); 
    end
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
        BpodSystem.Data.TrialSettings(currentTrial+NumRewardTrials1+NumStimTrials1+NumRewardTrials2) = S;
        BpodSystem.Data.TrialTypes2(currentTrial) = TrialType;
        SaveBpodSessionData;
        
    end

    % Handle pauses and exit if the user ended the session
    HandlePauseCondition;
    if BpodSystem.Status.BeingUsed == 0
        ModuleWrite('ValveModule1', ['B' 0]); % make sure the odor valves are closed
        return
    end
    
end

fprintf('Stim trials2 finished\n');
toc;

pause(10);


%% Third set of rewards

fprintf('\nRewards3\n')
for currentTrial = 1:NumRewardTrials3

    RewardAmount = RewardAmounts3(currentTrial);
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
    for tt = 1:S.NumPatterns
        sma = AddState(sma, 'Name', sprintf('Stim%d',tt),'Timer', 0,'StateChangeConditions',{},'OutputActions', {}); 
    end
    
    SendStateMatrix(sma); % Send state machine to the Bpod state machine device

    RawEvents = RunStateMatrix; % Run the trial and return events
      
    BpodSystem.Data.RewardAmounts3(currentTrial) = RewardAmount;
    
    % Update online plots
    if ~isempty(fieldnames(RawEvents))
        
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial+NumRewardTrials1+NumStimTrials1+NumRewardTrials2+NumStimTrials2) = S;

        SaveBpodSessionData;

    end
    
    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end
end

fprintf('Rewards3 finished\n');
toc;


%%
clear W;

fprintf('\nProtocol finished\n')

end