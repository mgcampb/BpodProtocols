function SequentialRewardExpo      

% S.Matias 10/2017: This is a protocol to deliver free water before starting training mice in a behavioral task.

global BpodSystem

%% Setup (runs once before the first trial): Define parameters


S = BpodSystem.ProtocolSettings; % Loads settings file chosen in launch manager into current workspace as a struct called 'S'
    % Define default settings here as fields of S (i.e S.InitialDelay = 3.2)
    % Note: Any parameters in S.GUI will be shown in UI edit boxes. 
    % See ParameterGUI plugin documentation to show parameters as other UI types (listboxes, checkboxes, buttons, text)
  load([ BpodSystem.GUIData.SubjectName 'ExpoITI']);
  
    % Protocol info
    S.GUI.Protocol = mfilename;
    S.GUI.Experimenter = 'Simon';
    S.GUI.Subject = BpodSystem.GUIData.SubjectName; 
    S.GUIPanels.Protocol = {'Protocol', 'Experimenter', 'Subject'};
  %  BpodSystem.GUIHandles.PokesPlot.AlignOnMenu;
    % StimulusSettings - in case I want to signal water delivery with sound

    
    % Outcome parameters
    S.GUI.RewardAmount = 3; % ul
        
    % ITI parameters
    S.GUI.ITIDistributionexp_mean_ISI = 12;
    S.GUI.maxITI = S.GUI.ITIDistributionexp_mean_ISI*5 ;
    S.GUI.MaxTrials = 100; % Set to some sane value, for preallocation

   BpodSystem.Data.ITIbyTrials = ITI{S.GUI.SessionNum};
   


state_colors = struct( ...
    'ITI',[0.9 0.9 0.9],...
    'Reward', [.4,0.4,1]);
%PokesPlotLicksSlow3('init', state_colors,[],S.GUI.maxITI);


%% Setup: Define trials
disp(['Total ITI: ' num2str(sum(BpodSystem.Data.ITIbyTrials))]);

RewardValveTime = GetValveTimes(S.GUI.RewardAmount, 1);
AccumulatedReward = 0;



%% Setup: Initialize plots 

% Initialize parameter GUI plugin
BpodParameterGUI('init', S); 

% BpodNotebook('init'); % Launches and interface to write noted about behavior and manually score trials
%cd('C:\code\Bpod Local\Protocols\Simon\SequentialRewardExpo');

%% Main loop (runs once per trial)
for currentTrial = 1: S.GUI.MaxTrials
    
    S = BpodParameterGUI('sync', S); % Sync parameters with BpodParameterGUI plugin
    disp(['Trial #: ' num2str(currentTrial) '. ITI: ' num2str(BpodSystem.Data.ITIbyTrials (currentTrial)) ]);

    %--- Typically, a block of code here will compute variables for assembling this trial's state machine
   
    % Calculate ITI for this trial
  
    %--- Assemble state machine
    sma = NewStateMachine();
    
    sma = AddState(sma, 'Name', 'Reward', ... 
        'Timer', RewardValveTime,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'BNC1', 1, 'BNC2', 1,'Valve',1}); 
 
    sma = AddState(sma, 'Name', 'ITI', ...
        'Timer',   BpodSystem.Data.ITIbyTrials (currentTrial),...
        'StateChangeConditions', {'Tup','exit'},...
        'OutputActions', {});
   
    
    Acknowledged = SendStateMachine(sma); % Send state machine to the Bpod state machine device

    RawEvents = RunStateMachine; % Run the trial and return events
    AccumulatedReward = AccumulatedReward+S.GUI.RewardAmount;
    BpodSystem.Data.AccumulatedReward(currentTrial) = AccumulatedReward;
    if ~isempty(fieldnames(RawEvents)) % If you didn't stop the session manually mid-trial
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Adds raw events to a human-readable data struct: computes trial events from raw data      
  BpodSystem.Data.CurrentTrial = currentTrial;
        SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
   
    end
 %       PokesPlotLicksSlow3('update');
    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end
    disp(['AccumulatedReward: ' num2str(AccumulatedReward) 'ul']);

end
disp('SequentialRewardExpo Finished');
if currentTrial == S.GUI.MaxTrials
ProtocolSettings.GUI.SessionNum = S.GUI.SessionNum+1;
SaveProtocolSettings(ProtocolSettings);
end

end