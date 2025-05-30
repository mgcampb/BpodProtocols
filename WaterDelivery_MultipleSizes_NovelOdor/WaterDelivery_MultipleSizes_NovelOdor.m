function WaterDelivery_MultipleSizes_NovelOdor      

% S.Matias 10/2017: This is a protocol to deliver free water before starting training mice in a behavioral task.
% M. Campbell 11/2021: Edited for NPX rigs, got rid of sounds, changed params, etc
% M. Campbell 6/2022: Added multiple reward sizes
% M. Campbell 4/29/2025: Added interspersed odor deliveries

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


%% Setup (runs once before the first trial): Define parameters

mouse = BpodSystem.Status.CurrentSubjectName;

BpodSystem.Data.TaskDescription = 'Interleaved rewards and odor delivery. Trialtype = 1 is water, Trialtype = 2 is odor. Reward Amounts given in a separate vector.';

S = BpodSystem.ProtocolSettings; % Loads settings file chosen in launch manager into current workspace as a struct called 'S'
S.Experimenter = 'Malcolm';
S.Mouse = mouse;
S.RewardAmounts = [2 8];
S.MaxWater = 1000; % in uL
S.ITIDistribution = 'Exponential';
S.ITIMean = 12; % changed from 10 10/20/2022
S.ITIMin = 8; % changed from 4 10/20/2022
S.ITIMax = 20;
S.ForeperiodDuration = 0.5;
S.OdorDuration = 1; % seconds


%% Numbers of different trials
MaxTrials = 50; 
NumOdorTrials = 10;
NumWaterTrials = MaxTrials-NumOdorTrials;


%% Setup: Define trials

% assign reward sizes in blocks of 40 trials
RewardAmounts_all = nan(NumWaterTrials, 1);
nRewardAmounts = numel(S.RewardAmounts);
rewardsPerBlock = 5;
blockSize = rewardsPerBlock*nRewardAmounts;
nBlocks = NumWaterTrials/blockSize;
counter = 1;
for i = 1:nBlocks
    RewardAmount = repmat(S.RewardAmounts,1,rewardsPerBlock);
    RewardAmount = RewardAmount(randperm(blockSize));
    RewardAmounts_all(counter:counter+blockSize-1) = RewardAmount;
    counter = counter+blockSize;
end

AccumulatedReward = 0;


%% create odor trials
offset = 0;
chunk = floor((NumWaterTrials-offset)/NumOdorTrials);
for trIdx = 1:NumOdorTrials
    tr_this = offset+randperm(chunk,1);
    RewardAmounts_all = [RewardAmounts_all(1:tr_this); 0; RewardAmounts_all(tr_this+1:end)];
    offset = offset+chunk+1;
end


%% Setup: Initialize plots 

% Pokes plot
state_colors = struct( ...
    'Foreperiod',[.9 .9 .9],...
    'Reward', [0 1 0],...
    'Odor', [0 1 1],...
    'ITI', [.9 .9 .9]);
PokesPlotLicksSlow('init', state_colors, []);

% BpodNotebook('init'); % Launches and interface to write noted about behavior and manually score trials


%% Set up odor delivery
ValveMessages = {['B' 0], ['B' 3]}; % Valve 1 is blank
LoadSerialMessages('ValveModule1', ValveMessages);  % Set serial messages for valve module. Valve 1 is the default that is normally on


%% Main loop (runs once per trial)
for currentTrial = 1:MaxTrials
    
    %--- Typically, a block of code here will compute variables for assembling this trial's state machine
    RewardAmount = RewardAmounts_all(currentTrial);
    RewardValveTime = GetValveTimes(RewardAmount, 1);

    % Calculate ITI for this trial
    ITIDuration = exprnd(S.ITIMean);
    while ITIDuration < S.ITIMin || ITIDuration > S.ITIMax
        ITIDuration = exprnd(S.ITIMean);
    end
    
    AccumulatedReward = AccumulatedReward+RewardAmount;
    ValveMessage = 2; % Just one odor
    if RewardAmount==0 % odor trials
        OutcomeState = 'Odor';
        fprintf('Trial %d: ODOR \t\t\t\t AccumulatedReward: %0.1f uL \t\t ITI: %0.1f sec\n',...
            currentTrial,AccumulatedReward,ITIDuration);
    else % reward trials
        OutcomeState = 'Reward';
        fprintf('Trial %d: REWARD %0.1f uL \t AccumulatedReward: %0.1f uL \t\t ITI: %0.1f sec\n',...
            currentTrial,RewardAmount,AccumulatedReward,ITIDuration);
    end

    %--- Assemble state machine
    sma = NewStateMatrix();
    sma = AddState(sma, 'Name', 'Foreperiod',...
        'Timer', S.ForeperiodDuration,...
        'StateChangeConditions', {'Tup',OutcomeState},...
        'OutputActions', {'BNC1', 1, 'BNC2', 1});
    sma = AddState(sma, 'Name', 'Odor',...
        'Timer', S.OdorDuration,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'ValveModule1', ValveMessage,... % closes the blank valve, opens the odor valve
            'BNC1', 0, 'BNC2', 0}); 
    sma = AddState(sma, 'Name', 'Reward',...
        'Timer', RewardValveTime,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'ValveState', 1,'BNC1', 0, 'BNC2', 0});
    sma = AddState(sma, 'Name', 'ITI',...
        'Timer', ITIDuration,...
        'StateChangeConditions', {'Tup', 'exit'},...
        'OutputActions', {'ValveModule1', 1, 'BNC1', 0, 'BNC2', 0});

    % Send state machine to Bpod device
    SendStateMatrix(sma);
    
    % Run the trial and return events
    RawEvents = RunStateMatrix;
    
    if ~isempty(fieldnames(RawEvents))
        % Save trial data
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial) = S;
        BpodSystem.Data.AccumulatedReward(currentTrial) = AccumulatedReward; 
        BpodSystem.Data.RewardSize(currentTrial) = RewardAmount;
        BpodSystem.Data.OdorTrials(currentTrial) = RewardAmount==0;
        BpodSystem.Data.RewardTrials(currentTrial) = RewardAmount>0;

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

fprintf('\nProtocol finished\n');

end