function SyncPulse

% M. Campbell 06/17/2022: Just generates TTL sync pulses

global BpodSystem

%% Setup (runs once before the first trial)

MaxTrials = 1200; % Max number of trials

% Task parameters
S = BpodSystem.ProtocolSettings; 
S.GUI.ITIMin = 1; % seconds
S.GUI.ITIMax = 1; % seconds
S.PulseDuration = 1;

% Set up parameter GUI
BpodParameterGUI('init', S);

%% Main loop (runs once per trial)
for currentTrial = 1:MaxTrials

    fprintf('Trial %d/%d\n',currentTrial,MaxTrials);
    
    % Sync parameters with BpodParameterGUI plugin
    S = BpodParameterGUI('sync', S); 
    
    % Randomly generate ITI duration
    ITIDuration = unifrnd(S.GUI.ITIMin,S.GUI.ITIMax);
    
    % Create state matrix
    sma = NewStateMatrix();
    sma = AddState(sma, 'Name', 'TTL',...
        'Timer', S.PulseDuration,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'BNC1', 1, 'BNC2', 1});
    sma = AddState(sma, 'Name', 'ITI',...
        'Timer', ITIDuration,...
        'StateChangeConditions', {'Tup', 'exit'},...
        'OutputActions', {'BNC1', 0, 'BNC2', 0});
    
    % Send state machine to Bpod device
    SendStateMatrix(sma);
    
    % Run the trial and return events
    RawEvents = RunStateMatrix;
    
    if ~isempty(fieldnames(RawEvents))
        % Save trial data
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        SaveBpodSessionData;
    end

    % Handle pauses and exit if the user ended the session
    HandlePauseCondition;
    if BpodSystem.Status.BeingUsed == 0
        return
    end
    
end

fprintf('\nProtocol finished.\n');

end