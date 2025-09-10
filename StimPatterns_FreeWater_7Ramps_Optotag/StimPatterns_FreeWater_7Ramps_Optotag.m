function StimPatterns_FreeWater_7Ramps_Optotag

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
% M. Campbell 5/8/2025: Added optotagging trials to beginning and end

global BpodSystem


COM_Ports = readtable('..\COM_Ports.txt'); % get COM ports from text file (ignored by git)

%% Setup (runs once before the first trial)

mouse = BpodSystem.Status.CurrentSubjectName;

BpodSystem.Data.TaskDescription = 'Optotag1 Rewards1 StimTrials1 Rewards2 StimTrials2 Rewards3 Optotag2';

% Task parameters
S = BpodSystem.ProtocolSettings; 

% These parameters are shared across animals:
S.Experimenter = 'Malcolm';
S.Mouse = mouse;
S.NumPatterns = 7;

% Num trials
S.NumOptotagTrials1 = 60; 
S.NumRewardTrials1 = 2*6;
S.NumStimTrials1 = 7*15;
S.NumRewardTrials2 = 2*6;
S.NumStimTrials2 = 7*15;
S.NumRewardTrials3 = 2*6;
S.NumOptotagTrials2 = 60;

% ITI duration - note different values for optotag trials
S.ITIMean = 12;
S.ITIMin = 8;
S.ITIMax = 20;

S.RewardAmounts = [2 8];
S.ForeperiodDuration = 0.5;

S.StimPower_mW = 1; % input('Stim LED power (mW): ');
S.PulseDur = 0.005;

% optotag pulse options:
S.OptotagPulseFreq = 10;
S.OptotagPulseDur = 0.02;
S.OptotagPulseNum = 1;
S.OptotagLightPower_mW = 10;
S.ITIMin_optotag = 1; % different ITI for optotagging trials (uniform distribution)
S.ITIMax_optotag = 3;
% Duration of Optotag state (based on parameters in S)
OptotagStateDuration = ceil(S.OptotagPulseNum/S.OptotagPulseFreq); % seconds


S.waveformTimeVec1 = cell(S.NumStimTrials1,1);
S.waveformTimeVec2 = cell(S.NumStimTrials2, 1);
% display parameters
fprintf('\nSession parameters:\n')
S


%% Define reward trial types

% assign reward sizes in blocks
nRewardAmounts = numel(S.RewardAmounts);
rewardsPerBlock = 2;
blockSize = rewardsPerBlock*nRewardAmounts;

% Rewards1:
RewardAmounts1 = nan(S.NumRewardTrials1, 1);
nBlocks = S.NumRewardTrials1/blockSize;
counter = 1;
for i = 1:nBlocks
    RewardAmount = repmat(S.RewardAmounts,1,rewardsPerBlock);
    RewardAmount = RewardAmount(randperm(blockSize));
    RewardAmounts1(counter:counter+blockSize-1) = RewardAmount;
    counter = counter+blockSize;
end

% Rewards2:
RewardAmounts2 = nan(S.NumRewardTrials2, 1);
nBlocks = S.NumRewardTrials2/blockSize;
counter = 1;
for i = 1:nBlocks
    RewardAmount = repmat(S.RewardAmounts,1,rewardsPerBlock);
    RewardAmount = RewardAmount(randperm(blockSize));
    RewardAmounts2(counter:counter+blockSize-1) = RewardAmount;
    counter = counter+blockSize;
end

% Rewards3:
RewardAmounts3 = nan(S.NumRewardTrials3, 1);
nBlocks = S.NumRewardTrials3/blockSize;
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

NumChunks1 = ceil(S.NumStimTrials1/ActualChunkSize);
TrialTypes1 = [];
for i = 1:NumChunks1
    perm_idx = randperm(ActualChunkSize);
    TrialTypes1 = [TrialTypes1 TrialTypesChunk(perm_idx)];
end
TrialTypes1 = TrialTypes1(1:S.NumStimTrials1);

NumChunks2 = ceil(S.NumStimTrials2/ActualChunkSize);
TrialTypes2 = [];
for i = 1:NumChunks2
    perm_idx = randperm(ActualChunkSize);
    TrialTypes2 = [TrialTypes2 TrialTypesChunk(perm_idx)];
end
TrialTypes2 = TrialTypes2(1:S.NumStimTrials2);


%% Set up WavePlayer (Analog Output Module for controlling lasers)
W = BpodWavePlayer(COM_Ports.COM_Port{strcmp(COM_Ports.Module,'BpodWavePlayer')}); % Make sure the COM port is correct
SR = 10000; % Sampling rate for analog output
W.SamplingRate = SR;
W.OutputRange = '0V:5V';

% Stim patterns: 

% Stim functions:
% exponential_func(t, ramping_rates, target_time)
%   returns 50/(r^T–1) * (r^t–1) where 50 is the target final firing rate
exponential_func = @(t, r, T) 50 ./ (r.^T - 1) .* (r.^t - 1);

% linear_slow(t, area, target_time)
%   returns (2*area/T^2) * t
linear_slow = @(t, A, T) (2*A ./ T.^2) .* t;

% linear_fast(t, area, target_time, final_firing_rate)
%   implements:
%     shift = T - 2*A / F
%     rate  = F / (T - shift)
%     out   = rate*(t-shift)  for t>=shift, else 0
linear_fast = @(t, A, T, F) ...
    (t >= (T - 2*A./F)) .* ...
     ( (F ./ (T - (T - 2*A./F))) .* (t - (T - 2*A./F)) );

t = linspace(0, 2, 2*SR);

% 1) exponential function, ramping rate = 2, target time = 2
y1 = exponential_func(t, 2, 2); 
area1 = quad(@(t) exponential_func(t, 2, 2), 0, 2);

% 2) exponential function, ramping rate = 5, target time = 2
y2 = exponential_func(t, 5, 2); 
area2 = quad(@(t) exponential_func(t, 5, 2), 0, 2);

% 3) exponential function, ramping rate = 10, target time = 2
y3 = exponential_func(t, 10, 2); 

% 4) slow linear function, ramping rate = 2, target time = 2
y4 = linear_slow(t, area1, 2);

% 5 fast linear function, ramping rate = 2, target time = 2
y5 = linear_fast(t, area1, 2, 50); % 50 is the target final firing rate, same as other functions

% 6) slow linear function, ramping rate = 5, target time = 2
y6 = linear_slow(t, area2, 2);

% 7) slow linear function, ramping rate = 5, target time = 2
y7 = linear_fast(t, area2, 2, 50);


% 8) Optotag message (one 20 ms pulse)
waveform_optotag = zeros(1,round(SR/S.OptotagPulseFreq));
waveform_optotag(1:(S.OptotagPulseDur * SR)) = 5;
waveform_optotag = repmat(waveform_optotag,1,S.OptotagPulseNum);
W.loadWaveform(8,waveform_optotag);

% load waveforms to WavePlayer:
WavePlayerMessages = {};
redStim_idx = 1; % for triggering red LED
blueStim_idx = 2; % for triggering blue laser 
for patternIdx = 1:S.NumPatterns
    WavePlayerMessages = [WavePlayerMessages {['P' 2^(redStim_idx-1) patternIdx-1]}]; % send waveform patternIdx to the LED_idx'th channel
end
WavePlayerMessages = [WavePlayerMessages {['P' 2^(blueStim_idx-1) S.NumPatterns]}]; % send optotag message
LoadSerialMessages('WavePlayer1', WavePlayerMessages);

% save waveforms to bpod output structure S (task parameters):
S.stimWaveforms = {};
S.stimFunctions = {y1, y2, y3, y4, y5, y6, y7};
% insufficient memory to save all stimWaveforms
% save stimTimeVector instead
%% Optotag1
tic
total_trial_ctr = 0;
fprintf('\nOptotag1 (%d trials)\n', S.NumOptotagTrials1);
for currentTrial = 1:S.NumOptotagTrials1
    
    total_trial_ctr = total_trial_ctr+1;

    % Calculate ITI for this trial
    ITIDuration = unifrnd(S.ITIMin_optotag,S.ITIMax_optotag);

    fprintf('\tTrial %d:\tITI=%0.1fs\n',currentTrial,ITIDuration);

    %--- Assemble state machine
    sma = NewStateMatrix();
    
    sma = AddState(sma,'Name','Foreperiod',...
        'Timer',S.ForeperiodDuration,...
        'StateChangeConditions',{'Tup','Optotag'},...
        'OutputActions',{'BNC1',1,'BNC2',1});
    sma = AddState(sma, 'Name', 'Optotag', ... 
        'Timer', OptotagStateDuration,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'WavePlayer1', S.NumPatterns+1, 'BNC1', 0, 'BNC2', 0}); 
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

    % Update online plots
    if ~isempty(fieldnames(RawEvents))
        
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(total_trial_ctr) = S;

        SaveBpodSessionData;

    end
    
    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end
end

fprintf('Optotag1 finished\n');
toc;

pause(10);


%% Rewards1
AccumulatedReward = 0;
fprintf('\nRewards1 (%d trials)\n', S.NumRewardTrials1);
for currentTrial = 1:S.NumRewardTrials1
    
    total_trial_ctr = total_trial_ctr+1;

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
    sma = AddState(sma, 'Name', 'Optotag', ... 
        'Timer', OptotagStateDuration,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'WavePlayer1', S.NumPatterns+1, 'BNC1', 0, 'BNC2', 0}); 

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
        BpodSystem.Data.TrialSettings(total_trial_ctr) = S;

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


%% StimTrials1
fprintf('\nStim trials1 (%d trials)\n', S.NumStimTrials1);
for currentTrial = 1:S.NumStimTrials1
    
    total_trial_ctr = total_trial_ctr+1;
    
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
    
    
    %%%%%%%%%
    y = S.stimFunctions{TrialType};
    [pulse_times, pulse_times_vector] = simulate_pulse_times(y);
    W.loadWaveform(TrialType, pulse_times);
    S.waveformTimeVec1{currentTrial} = pulse_times_vector;
    %%%%%%%%%

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
    sma = AddState(sma, 'Name', 'Optotag', ... 
        'Timer', OptotagStateDuration,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'WavePlayer1', S.NumPatterns+1, 'BNC1', 0, 'BNC2', 0}); 

    % Add reward state so pokes plot doesn't get messed up:
    sma = AddState(sma,'Name','Reward','Timer',0,'StateChangeConditions',{},'OutputActions',{}); 
    
    % Send state machine to Bpod device
    SendStateMatrix(sma);
    
    % Run the trial and return events
    RawEvents = RunStateMatrix;
    
    if ~isempty(fieldnames(RawEvents))
        % Save trial data
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        % BpodSystem.Data.VaryingWaveforms1{currentTrial} = pulse_times_vector;
        BpodSystem.Data.TrialSettings(total_trial_ctr) = S;
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


%% Rewards2

fprintf('\nRewards2 (%d trials)\n', S.NumRewardTrials2);
for currentTrial = 1:S.NumRewardTrials2
    
    total_trial_ctr = total_trial_ctr+1;

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
    sma = AddState(sma, 'Name', 'Optotag', ... 
        'Timer', OptotagStateDuration,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'WavePlayer1', S.NumPatterns+1, 'BNC1', 0, 'BNC2', 0}); 

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
        BpodSystem.Data.TrialSettings(total_trial_ctr) = S;

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


%% StimTrials2
fprintf('\nStim trials2 (%d trials)\n', S.NumStimTrials2);
for currentTrial = 1:S.NumStimTrials2
    
    total_trial_ctr = total_trial_ctr+1;
    
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
    
    
    %%%%%%%%%
    y = S.stimFunctions{TrialType};
    [pulse_times, pulse_times_vector] = simulate_pulse_times(y);
    W.loadWaveform(TrialType, pulse_times);
    S.waveformTimeVec2{currentTrial} = pulse_times_vector;
    %%%%%%%%%
    
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
    sma = AddState(sma, 'Name', 'Optotag', ... 
        'Timer', OptotagStateDuration,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'WavePlayer1', S.NumPatterns+1, 'BNC1', 0, 'BNC2', 0}); 

    % Add reward state so pokes plot doesn't get messed up:
    sma = AddState(sma,'Name','Reward','Timer',0,'StateChangeConditions',{},'OutputActions',{}); 
    
    % Send state machine to Bpod device
    SendStateMatrix(sma);
    
    % Run the trial and return events
    RawEvents = RunStateMatrix;
    
    if ~isempty(fieldnames(RawEvents))
        % Save trial data
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        % BpodSystem.Data.VaryingWaveforms2{currentTrial} = pulse_times_vector;
        BpodSystem.Data.TrialSettings(total_trial_ctr) = S;
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


%% Rewards3

fprintf('\nRewards3 (%d trials)\n', S.NumRewardTrials3);
for currentTrial = 1:S.NumRewardTrials3
    
    total_trial_ctr = total_trial_ctr+1;

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
    sma = AddState(sma, 'Name', 'Optotag', ... 
        'Timer', OptotagStateDuration,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'WavePlayer1', S.NumPatterns+1, 'BNC1', 0, 'BNC2', 0}); 

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
        BpodSystem.Data.TrialSettings(total_trial_ctr) = S;

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

pause(10);


%% Optotag2

fprintf('\nOptotag2 (%d trials)\n', S.NumOptotagTrials2);
for currentTrial = 1:S.NumOptotagTrials2
    
    total_trial_ctr = total_trial_ctr+1;
    
    % Calculate ITI for this trial
    ITIDuration = unifrnd(S.ITIMin_optotag,S.ITIMax_optotag);

    fprintf('\tTrial %d:\tITI=%0.1fs\n',currentTrial,ITIDuration);

    %--- Assemble state machine
    sma = NewStateMatrix();
    
    sma = AddState(sma,'Name','Foreperiod',...
        'Timer',S.ForeperiodDuration,...
        'StateChangeConditions',{'Tup','Optotag'},...
        'OutputActions',{'BNC1',1,'BNC2',1});
    sma = AddState(sma, 'Name', 'Optotag', ... 
        'Timer', OptotagStateDuration,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'WavePlayer1', S.NumPatterns+1, 'BNC1', 0, 'BNC2', 0}); 
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

    % Update online plots
    if ~isempty(fieldnames(RawEvents))
        
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(total_trial_ctr) = S;

        SaveBpodSessionData;

    end
    
    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end
end

fprintf('Optotag2 finished\n');
toc;


%%
clear W;

fprintf('\nProtocol finished\n')

end




function [pulse_times, pulse_times_vector] = simulate_pulse_times(y, target_time, window)

    if nargin < 2
        target_time = 2;
        window = 100;
    end

    num_windows = floor(numel(y) / window);
    
    % compute mean rate per window (rate is in spikes per 10 ms)
    lambdas = zeros(num_windows,1);
    for k = 1:num_windows
        idx = (k-1)*window + (1:window);
        lambdas(k) = mean(y(idx));
    end

    % prepare output at 10 kHz
    SR = 10000;  % samples per second
    PulseDur = 0.005;
    total_samples = round(target_time * SR);
    pulse_times = zeros(1, total_samples);
    pulse_times_vector = []; % save this only 

    % simulate
    for k = 1:num_windows
        rate = lambdas(k);
        lam_window = rate * window;  % expected spikes in this window
        adjustment = 3000;
        n_spikes = poissrnd(lam_window / adjustment); % divide by 3000 to match the spike rate in averaged function
        if n_spikes > 1
            startIdx = (k-1)*window + 1;
            lenBlock = round(PulseDur * SR);
            endIdx   = min(startIdx + lenBlock - 1, total_samples);
            pulse_times(startIdx:endIdx) = 5; % 5V
            pulse_times_vector(end+1) = startIdx;
        end
    end
end