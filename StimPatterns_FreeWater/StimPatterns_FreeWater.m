function StimPatterns_FreeWater

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

global BpodSystem


COM_Ports = readtable('..\COM_Ports.txt'); % get COM ports from text file (ignored by git)

%% Setup (runs once before the first trial)

mouse = BpodSystem.Status.CurrentSubjectName;

NumRewardTrials1 = 20;
NumStimTrials = 160; % Number of stim trials
NumRewardTrials2 = 20;

BpodSystem.Data.TaskDescription = 'Rewards1 StimTrials Rewards2';

% Task parameters
S = BpodSystem.ProtocolSettings; 

% These parameters are shared across animals:
S.Experimenter = 'Malcolm';
S.Mouse = mouse;
S.NumPatterns = 4;

S.ITIMean = 12;
S.ITIMin = 8;
S.ITIMax = 20;
S.RewardAmounts = [2 8];
S.ForeperiodDuration = 0.5;

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
TargetChunkSize = 8; % trials; chunk size in which to balance trial types
ActualChunkSize = S.NumPatterns*round(TargetChunkSize/S.NumPatterns);
NumChunks = ceil(NumStimTrials/ActualChunkSize);
TrialTypesChunk = repmat(1:S.NumPatterns,1,ActualChunkSize/S.NumPatterns);
TrialTypes = [];
for i = 1:NumChunks
    perm_idx = randperm(ActualChunkSize);
    TrialTypes = [TrialTypes TrialTypesChunk(perm_idx)];
end
TrialTypes = TrialTypes(1:NumStimTrials);


%% Pokes plot
StimColors = lines(4);
state_colors = struct( ...
    'Foreperiod',[.9,.9,.9],...
    'Reward',[0 1 0],...
    'Stim1', StimColors(1,:),...
    'Stim2', StimColors(2,:),...
    'Stim3', StimColors(3,:),...
    'Stim4', StimColors(4,:),...
    'ITI', [.9,.9,.9]);
PokesPlotLicksSlow('init', state_colors, []);


%% Set up WavePlayer (Analog Output Module for controlling lasers)
W = BpodWavePlayer(COM_Ports.COM_Port{strcmp(COM_Ports.Module,'BpodWavePlayer')}); % Make sure the COM port is correct
SR = 10000; % Sampling rate for analog output
W.SamplingRate = SR;
W.OutputRange = '0V:5V';

% Four stim patterns: 
WavePlayerMessages = {};

% hfig = figure;

% 1) 1 sec at 20 Hz
waveform_1secSquare = zeros(1,round(SR/20));
waveform_1secSquare(1:(0.005 * SR)) = 5;
waveform_1secSquare = repmat(waveform_1secSquare,1,20);
W.loadWaveform(1,waveform_1secSquare);
WavePlayerMessages = [WavePlayerMessages {['P' 1 0]}];
% subplot(4,1,1); plot((0:(numel(waveform_1secSquare)-1))/SR,waveform_1secSquare); xlim([0 2]); xlabel('sec'); ylabel('V'); title('Pattern 1');

% 2) 2 sec at 20 Hz
waveform_2secSquare = zeros(1,round(SR/20));
waveform_2secSquare(1:(0.005 * SR)) = 5;
waveform_2secSquare = repmat(waveform_2secSquare,1,40);
W.loadWaveform(2,waveform_2secSquare);
WavePlayerMessages = [WavePlayerMessages {['P' 1 1]}];
% subplot(4,1,2); plot((0:(numel(waveform_2secSquare)-1))/SR,waveform_2secSquare); xlim([0 2]); xlabel('sec'); ylabel('V'); title('Pattern 2');

% 3) 2 sec ramping up
waveform_rampUp = [];
freq = 4;
for i = 1:24
    numOnes = 0.005*SR;
    numZeros = round(SR/freq)-numOnes;
    waveform_rampUp = [waveform_rampUp 5*ones(1,numOnes) zeros(1,numZeros)];
    freq = freq*1.135; 
end
W.loadWaveform(3,waveform_rampUp);
WavePlayerMessages = [WavePlayerMessages {['P' 1 2]}];
% subplot(4,1,3); plot((0:(numel(waveform_rampUp)-1))/SR,waveform_rampUp); xlim([0 2]); xlabel('sec'); ylabel('V'); title('Pattern 3');

% 4) 2 sec ramping down
waveform_rampDown = fliplr(waveform_rampUp);
waveform_rampDown = [waveform_rampDown(87:end) zeros(1,86)]; % align to zero
% % old ramp down:
% waveform_rampDown = [];
% freq = 4*1.135^23;
% for i = 1:24
%     numOnes = 0.005*SR;
%     numZeros = round(SR/freq)-numOnes;
%     waveform_rampDown = [waveform_rampDown 5*ones(1,numOnes) zeros(1,numZeros)];
%     freq = freq/1.135; 
% end
W.loadWaveform(4,waveform_rampDown);
WavePlayerMessages = [WavePlayerMessages {['P' 1 3]}];
% subplot(4,1,4); plot((0:(numel(waveform_rampDown)-1))/SR,waveform_rampDown); xlim([0 2]); xlabel('sec'); ylabel('V'); title('Pattern 4');

LoadSerialMessages('WavePlayer1', WavePlayerMessages);

% save waveforms:
S.stimWaveforms = {waveform_1secSquare,waveform_2secSquare,waveform_rampUp,waveform_rampDown};


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


%% Stim trials
fprintf('\nStim trials\n');
for currentTrial = 1:NumStimTrials
    
    TrialType = TrialTypes(currentTrial);
    
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
        BpodSystem.Data.TrialTypes(currentTrial) = TrialType;
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
        BpodSystem.Data.TrialSettings(currentTrial+NumRewardTrials1+NumStimTrials) = S;

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

fprintf('\nProtocol finished\n')

end