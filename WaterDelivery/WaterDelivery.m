function WaterDelivery      

% S.Matias 10/2017: This is a protocol to deliver free water before starting training mice in a behavioral task.

% M. Campbell 11/2021: Edited for NPX rigs, got rid of sounds, changed params, etc

global BpodSystem

%% Setup (runs once before the first trial): Define parameters

S = BpodSystem.ProtocolSettings; % Loads settings file chosen in launch manager into current workspace as a struct called 'S'
if isempty(fieldnames(S))  % If chosen settings file was an empty struct, populate struct with default settings
    % Define default settings here as fields of S (i.e S.InitialDelay = 3.2)
    % Note: Any parameters in S.GUI will be shown in UI edit boxes. 
    % See ParameterGUI plugin documentation to show parameters as other UI types (listboxes, checkboxes, buttons, text)
    
    % Protocol info
    S.GUI.Protocol = mfilename;
    S.GUI.Experimenter = 'Malcolm';
    S.GUI.Subject = BpodSystem.GUIData.SubjectName; 
    S.GUIPanels.Protocol = {'Protocol', 'Experimenter', 'Subject'};
    
    % Outcome parameters
    S.GUI.RewardAmount = 4; % ul
    S.GUI.NumPulses = 200/S.GUI.RewardAmount; % ul To give 0.6 ml of water
    S.GUIPanels.Outcome = {'RewardAmount','NumPulses'};
        
    % ITI parameters
    S.GUI.ITIDistribution = 3;
    S.GUIMeta.ITIDistribution.Style = 'popupmenu';
    S.GUIMeta.ITIDistribution.String = {'Delta', 'Uniform', 'Exponential'};
    S.GUI.ITIMean = 12;
    S.GUI.ITIMin = 8;
    S.GUI.ITIMax = 20;
%     S.GUI.ITIMean = 5;
%     S.GUI.ITIMin = 4;
%     S.GUI.ITIMax = 10;
    S.GUI.ForeperiodDuration = 0.5;
    S.GUIPanels.ITI = {'ITIDistribution', 'ITIMean', 'ITIMin','ITIMax','ForeperiodDuration'}; 
end

%% Setup: Define trials

MaxTrials = ceil(S.GUI.NumPulses); % Set to some sane value, for preallocation
BpodSystem.Data.ITIDuration = nan(MaxTrials, 1);
RewardValveTime = GetValveTimes(S.GUI.RewardAmount, 1);
AccumulatedReward = 0;

%% Setup: Initialize plots 

% Initialize parameter GUI plugin
BpodParameterGUI('init', S); 

% Pokes plot
state_colors = struct( ...
    'Foreperiod',[.9 .9 .9],...
    'Reward', [0 1 0],...
    'ITI', [.9,.9,.9]);
PokesPlotLicksSlow('init', state_colors, []);

% BpodNotebook('init'); % Launches and interface to write noted about behavior and manually score trials

%% Main loop (runs once per trial)
for currentTrial = 1:MaxTrials
    
    S = BpodParameterGUI('sync', S); % Sync parameters with BpodParameterGUI plugin

    %--- Typically, a block of code here will compute variables for assembling this trial's state machine
    
     
    % Calculate ITI for this trial
    switch S.GUI.ITIDistribution
        case 1
            ITIDuration(currentTrial) = S.GUI.ITIMean;
        case 2
            ITIDuration(currentTrial) = S.GUI.ITIMin + (S.GUI.ITIMax-S.GUI.ITIMin)*rand;
        case 3
            ITIDuration(currentTrial) = exprnd(S.GUI.ITIMean);
            while ITIDuration(currentTrial) < S.GUI.ITIMin || ITIDuration(currentTrial) > S.GUI.ITIMax
                ITIDuration(currentTrial) = exprnd(S.GUI.ITIMean);
            end
    end

    %--- Assemble state machine
    sma = NewStateMachine();
    
    sma = AddState(sma,'Name','Foreperiod',...
        'Timer',S.GUI.ForeperiodDuration,...
        'StateChangeConditions',{'Tup','Reward'},...
        'OutputActions',{'BNC1',1,'BNC2',1});
    sma = AddState(sma, 'Name', 'Reward', ... 
        'Timer', RewardValveTime,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'ValveState',1,'BNC1',0,'BNC2',0}); 
    sma = AddState(sma, 'Name', 'ITI', ... 
        'Timer', ITIDuration(currentTrial),...
        'StateChangeConditions', {'Tup','exit'},...
        'OutputActions', {'BNC1',0,'BNC2',0});
    
    Acknowledged = SendStateMachine(sma); % Send state machine to the Bpod state machine device

    RawEvents = RunStateMachine; % Run the trial and return events
    AccumulatedReward = AccumulatedReward+S.GUI.RewardAmount;
    BpodSystem.Data.AccumulatedReward(currentTrial) = AccumulatedReward;    

    % Update online plots
    if ~isempty(fieldnames(RawEvents))
       
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial) = S;
       
        PokesPlotLicksSlow('update');
    end

    
    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end
    disp(['AccumulatedReward: ' num2str(AccumulatedReward) 'ul']);
end
end