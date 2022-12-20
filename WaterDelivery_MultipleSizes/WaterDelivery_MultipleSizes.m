function WaterDelivery_MultipleSizes      

% S.Matias 10/2017: This is a protocol to deliver free water before starting training mice in a behavioral task.

% M. Campbell 11/2021: Edited for NPX rigs, got rid of sounds, changed params, etc

% M. Campbell 6/2022: Added multiple reward sizes

global BpodSystem

%% Setup (runs once before the first trial): Define parameters

S = BpodSystem.ProtocolSettings; % Loads settings file chosen in launch manager into current workspace as a struct called 'S'
S.Experimenter = 'Malcolm';
S.RewardAmounts = [1 2 4 8];
S.MaxWater = 1000; % in uL
S.ITIDistribution = 'Exponential';
S.ITIMean = 12; % changed from 10 10/20/2022
S.ITIMin = 8; % changed from 4 10/20/2022
S.ITIMax = 20;
S.ForeperiodDuration = 0.5;


%% Setup: Define trials

MaxTrials = 60; % changed from 120 10/20/2022

% assign reward sizes in blocks of 40 trials
RewardAmounts_all = nan(MaxTrials, 1);
nRewardAmounts = numel(S.RewardAmounts);
rewardsPerBlock = 5;
blockSize = rewardsPerBlock*nRewardAmounts;
nBlocks = MaxTrials/blockSize;
counter = 1;
for i = 1:nBlocks
    RewardAmount = repmat(S.RewardAmounts,1,rewardsPerBlock);
    RewardAmount = RewardAmount(randperm(blockSize));
    RewardAmounts_all(counter:counter+blockSize-1) = RewardAmount;
    counter = counter+blockSize;
end

AccumulatedReward = 0;

%% Setup: Initialize plots 


% Pokes plot
state_colors = struct( ...
    'Foreperiod',[.9 .9 .9],...
    'Reward', [0 1 0],...
    'ITI', [.9 .9 .9]);
PokesPlotLicksSlow('init', state_colors, []);

% BpodNotebook('init'); % Launches and interface to write noted about behavior and manually score trials


%% Main loop (runs once per trial)
for currentTrial = 1:MaxTrials
    
    %--- Typically, a block of code here will compute variables for assembling this trial's state machine
    RewardAmount = RewardAmounts_all(currentTrial);
    RewardValveTime = GetValveTimes(RewardAmount, 1);

    AccumulatedReward = AccumulatedReward+RewardAmount;
    fprintf('Trial %d: %d uL. ValveTime: %0.1f ms. AccumulatedReward: %d uL\n',...
        currentTrial,RewardAmount,RewardValveTime*1000,AccumulatedReward);
     
    % Calculate ITI for this trial
    ITIDuration = exprnd(S.ITIMean);
    while ITIDuration < S.ITIMin || ITIDuration > S.ITIMax
        ITIDuration = exprnd(S.ITIMean);
    end

    %--- Assemble state machine
    sma = NewStateMachine();
    
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
    
    SendStateMachine(sma); % Send state machine to the Bpod state machine device

    RawEvents = RunStateMachine; % Run the trial and return events
    
    BpodSystem.Data.AccumulatedReward(currentTrial) = AccumulatedReward;    
    BpodSystem.Data.RewardAmounts(currentTrial) = RewardAmount;
    
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

fprintf('\nProtocol finished\n');

end