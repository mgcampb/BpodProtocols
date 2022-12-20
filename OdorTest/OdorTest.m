function OdorTest

% M. Campbell 01/12/2021: Protocol to test odors only.

global BpodSystem

%% Setup (runs once before the first trial)

MaxTrials = 400; % Max number of trials

% Task parameters
S = BpodSystem.ProtocolSettings; % contains valve order for this mouse in field OdorValvesOdor

S.NumOdors = 5;
S.OdorValvesOrder = 1:S.NumOdors;

% These parameters are shared across animals:
S.ForeperiodDuration = 0.5; % seconds
S.OdorDuration = 1; % seconds
S.GUI.ITIMin = 3; % seconds
S.GUI.ITIMax = 3; % seconds

% Set up parameter GUI
BpodParameterGUI('init', S);

% Define trial types: 1 = Odor1, 2 = Odor2, etc
TrialTypes = repmat(1:S.NumOdors,1,MaxTrials/S.NumOdors);

% Pokes plot
% state_colors = struct( ...
%     'Foreperiod',[.9,.9,.9],...
%     'Odor', 0.55*[0,1,1],...
%     'Trace', [.8 .8 .8],...
%     'Laser', [0 1 0],...
%     'ITI', [.9,.9,.9]);
% PokesPlot('init', state_colors, []);

% Set odors for each trial type in each mouse
% S.OdorValvesOrder is the order of odors for this mouse, 
% loaded in the line S = BpodSystem.ProtocolSettings;
ValveMessages = {['O' 1], ['C' 1]}; % Valve 1 is blank
for i = 1:S.NumOdors
    ValveMessages = [ValveMessages {['O' S.OdorValvesOrder(i)+1], ['C' S.OdorValvesOrder(i)+1]}];
end
LoadSerialMessages('ValveModule1', ValveMessages);  % Set serial messages for valve module. Valve 1 is the default that is normally on


%% Main loop (runs once per trial)
for currentTrial = 1:MaxTrials
    
    TrialType = TrialTypes(currentTrial);
    
    % Sync parameters with BpodParameterGUI plugin
    S = BpodParameterGUI('sync', S); 
    
    % Compute variables for this trial's state machine:

    % Serial message to open/close odor valves
    ValveMessageOpen = TrialType*2+1;
    ValveMessageClose = TrialType*2+2;
    
    
    % Randomly generate ITI duration
    ITIDuration = unifrnd(S.GUI.ITIMin,S.GUI.ITIMax);
    
    % Display trial type
    fprintf('Trial %d: TrialType %d (Odor %d)\n',currentTrial,TrialType, S.OdorValvesOrder(TrialType));
    
    % Create state matrix
    sma = NewStateMatrix();
    sma = AddState(sma, 'Name', 'Foreperiod',...
        'Timer', S.ForeperiodDuration,...
        'StateChangeConditions', {'Tup', 'Odor'},...
        'OutputActions', {'BNC1', 1, 'BNC2', 1});
    sma = AddState(sma, 'Name', 'Odor',...
        'Timer', S.OdorDuration,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'ValveModule1', 1, 'ValveModule1', ValveMessageOpen,... % "1" closes the blank valve
            'BNC1', 1, 'BNC2', 1}); 
    sma = AddState(sma, 'Name', 'ITI',...
        'Timer', ITIDuration,...
        'StateChangeConditions', {'Tup', 'exit'},...
        'OutputActions', {'ValveModule1', 2, 'ValveModule1', ValveMessageClose,... % "2" opens the blank valve
            'BNC1', 0, 'BNC2', 0});
    
    % Send state machine to Bpod device
    SendStateMatrix(sma);
    
    % Run the trial and return events
    RawEvents = RunStateMatrix;
    
    if ~isempty(fieldnames(RawEvents))
        % Save trial data
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial) = S;
        BpodSystem.Data.TrialTypes(currentTrial) = TrialType;
        SaveBpodSessionData;
        
        % Update online plots
        % PokesPlot('update');
    end

    % Handle pauses and exit if the user ended the session
    HandlePauseCondition;
    if BpodSystem.Status.BeingUsed == 0
        return
    end
    
end

end