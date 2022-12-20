function OdorLaser

% M. Campbell 8/2/2021: Protocol to deliver odors followed by laser pulses.

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

%% Setup (runs once before the first trial)

MaxTrials = 400; % Max number of trials

% Task parameters
S = BpodSystem.ProtocolSettings; % contains valve order for this mouse in field OdorValvesOdor

% These parameters are specific to each mouse and loaded from file:
if isempty(fieldnames(S))
    fprintf(['\n******\nWARNING: No saved task parameters found for this mouse.' ...
        '\nGenerating new default parameters.\n******\n']);
    S.NumOdors = input('Number of odors: ');
    S.NumLaser = input('Number of lasers: ');
    S.OdorValvesOrder = randperm(S.NumOdors);
    SaveProtocolSettings(S);
end

% These parameters are shared across animals:
S.ForeperiodDuration = 0.5; % seconds
S.OdorDuration = 1; % seconds
S.TraceDuration = 0.5; % seconds
S.NumLaserPulse = 10; % number of laser pulses to deliver after trace period
S.LaserPulseDuration = 0.02; % seconds
S.LaserPulseFrequency = 20; % Hz
S.GUI.ITIMin = 5; % seconds
S.GUI.ITIMax = 10; % seconds

% Duration of Laser state (based on parameters in S)
LaserStateDuration = ceil(S.NumLaserPulse/S.LaserPulseFrequency); % seconds

% Set up parameter GUI
BpodParameterGUI('init', S);

% Define trial types: 1 = Odor1, 2 = Odor2, etc
TargetChunkSize = 80; % trials; chunk size in which to balance trial types
ActualChunkSize = S.NumOdors*round(TargetChunkSize/S.NumOdors);
NumChunks = ceil(MaxTrials/ActualChunkSize);
TrialTypesChunk = repmat(1:S.NumOdors,1,ActualChunkSize/S.NumOdors);
TrialTypes = [];
for i = 1:NumChunks
    TrialTypes = [TrialTypes TrialTypesChunk(randperm(numel(TrialTypesChunk)))];
end
TrialTypes = TrialTypes(1:MaxTrials);

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
    ValveMessageOpen = TrialType*2+1;
    ValveMessageClose = TrialType*2+2;
    
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
        'OutputActions', {'ValveModule1', 1, 'ValveModule1', ValveMessageOpen,... % "1" closes the blank valve
            'BNC1', 1, 'BNC2', 1}); 
    sma = AddState(sma, 'Name', 'Trace',...
        'Timer', S.TraceDuration,...
        'StateChangeConditions', {'Tup', 'Laser'},...
        'OutputActions', {'ValveModule1', 2, 'ValveModule1', ValveMessageClose,... % "2" opens the blank valve
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
        return
    end
    
end

fprintf('\nProtocol finished\n');

end