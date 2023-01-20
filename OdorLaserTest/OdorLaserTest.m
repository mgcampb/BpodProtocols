function OdorLaserTest

% M. Campbell 11/28/2021: Protocol to test odors and lasers.

global BpodSystem

%% Setup (runs once before the first trial)

MaxTrials = 30; % Max number of trials

% Task parameters
S = BpodSystem.ProtocolSettings; % contains valve order for this mouse in field OdorValvesOdor

S.NumOdors = 3;
S.NumLaser = 2;
S.OdorValvesOrder = 1:S.NumOdors;

% These parameters are shared across animals:
S.ForeperiodDuration = 0.5; % seconds
S.OdorDuration = 0.5; % seconds
S.TraceDuration = 0.5; % seconds
S.NumLaserPulse = 5; % number of laser pulses to deliver after trace period
S.LaserPulseDuration = 0.01; % seconds
S.LaserPulseFrequency = 5; % Hz
S.GUI.ITIMin = 3; % seconds
S.GUI.ITIMax = 3; % seconds

% Duration of Laser state (based on parameters in S)
LaserStateDuration = ceil(S.NumLaserPulse/S.LaserPulseFrequency); % seconds

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
ValveMessages = {['B' 0]}; % Valve 1 is blank
for i = 1:S.NumOdors
    ValveMessages = [ValveMessages {['B' 2^S.OdorValvesOrder(i)+1]}];
end
LoadSerialMessages('ValveModule1', ValveMessages);  % Set serial messages for valve module. Valve 1 is the default that is normally on

% Set up WavePlayer (Analog Output Module for controlling lasers)
W = BpodWavePlayer('COM4'); % Make sure the COM port is correct
SR = 10000; % Sampling rate for analog output
W.SamplingRate = SR;
W.OutputRange = '0V:5V';
waveform = zeros(1,SR/S.LaserPulseFrequency);
waveform(1:(S.LaserPulseDuration * SR)) = 5;
waveform = repmat(waveform,1,S.NumLaserPulse);
W.loadWaveform(1,waveform);
WavePlayerMessages = {};
for i = 1:S.NumLaser
    WavePlayerMessages = [WavePlayerMessages {['P' 2^(i-1) 0]}]; % Send waveform 1 to the ith channel
end
WavePlayerMessages = [WavePlayerMessages {''}]; % Do nothing
LoadSerialMessages('WavePlayer1', WavePlayerMessages);

%% Main loop (runs once per trial)
for currentTrial = 1:MaxTrials
    
    TrialType = TrialTypes(currentTrial);
    
    % Sync parameters with BpodParameterGUI plugin
    S = BpodParameterGUI('sync', S); 
    
    % Compute variables for this trial's state machine:

    % Serial message to open/close odor valves
    ValveMessage = TrialType+1;
    
    % Which laser channel to trigger
    LaserMessage = min(TrialType,S.NumLaser+1);
    
    % Randomly generate ITI duration
    ITIDuration = unifrnd(S.GUI.ITIMin,S.GUI.ITIMax);
    
    % Display trial type
    if LaserMessage > S.NumLaser
        fprintf('Trial %d: TrialType %d (Odor %d, No Laser)\n',currentTrial,...
            TrialType, S.OdorValvesOrder(TrialType));
    else
        fprintf('Trial %d: TrialType %d (Odor %d, Laser %d)\n',currentTrial,...
            TrialType, S.OdorValvesOrder(TrialType), LaserMessage);
    end

    % Create state matrix
    sma = NewStateMatrix();
    sma = AddState(sma, 'Name', 'Foreperiod',...
        'Timer', S.ForeperiodDuration,...
        'StateChangeConditions', {'Tup', 'Odor'},...
        'OutputActions', {'BNC1', 1, 'BNC2', 1});
    sma = AddState(sma, 'Name', 'Odor',...
        'Timer', S.OdorDuration,...
        'StateChangeConditions', {'Tup', 'Trace'},...
        'OutputActions', {'ValveModule1', ValveMessage,... % closes the blank valve, opens the odor valve
            'BNC1', 1, 'BNC2', 1}); 
    sma = AddState(sma, 'Name', 'Trace',...
        'Timer', S.TraceDuration,...
        'StateChangeConditions', {'Tup', 'Laser'},...
        'OutputActions', {'ValveModule1', 1,... % opens the blank valve, closes the odor valve
            'BNC1', 1, 'BNC2', 1}); 
    sma = AddState(sma, 'Name', 'Laser',...
        'Timer', LaserStateDuration,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'WavePlayer1', LaserMessage, 'BNC1', 1, 'BNC2', 1});
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
        BpodSystem.Data.TrialSettings(currentTrial) = S;
        BpodSystem.Data.TrialTypes(currentTrial) = TrialType;
        SaveBpodSessionData;
        
        % Update online plots
        % PokesPlot('update');
    end

    % Handle pauses and exit if the user ended the session
    HandlePauseCondition;
    if BpodSystem.Status.BeingUsed == 0
        ModuleWrite('ValveModule1', ['B' 0]); % make sure the odor valves are closed
        return
    end
    
end

fprintf('\nProtocol finished.\n');

end