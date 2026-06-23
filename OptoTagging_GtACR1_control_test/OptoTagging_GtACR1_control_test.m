function OptoTagging_GtACR1_control_test

% M. Campbell 8/2/2021: Protocol to deliver odors followed by laser pulses.
% M. Campbell 8/4/2022: Just does optotagging. Cleaned up some stuff.
% M. Campbell 6/23/2026: For testing crosstalk between blue and red in
% antidromic optotagging of DA neurons with Chrimson for potential GtACR1
% experiment

global BpodSystem

COM_Ports = readtable('..\COM_Ports.txt'); % get COM ports from text file (ignored by git)


%% Setup (runs once before the first trial)



% Task parameters
S = BpodSystem.ProtocolSettings; % contains valve order for this mouse in field OdorValvesOdor


S.NumLasers = 2;
% These parameters are shared across animals:
S.ForeperiodDuration = 0.5; % seconds
S.StimChannel = input('Stim channel (red = 1, blue = 2): ');
S.StimPower_mW = input('Stim power (mW): ');
if S.StimChannel==1   
    
    MaxTrials = 40; % Max number of trials

    S.NumLaserPulse = 1; % number of laser pulses to deliver after trace period
    S.LaserPulseDuration = 0.02; % seconds
    S.LaserPulseFrequency = 1; % Hz
    
    S.GUI.ITIMin = 2; % 5; % seconds
    S.GUI.ITIMax = 4; % 10; % seconds

elseif S.StimChannel==2

    MaxTrials = 20; % Max number of trials

    S.NumLaserPulse = 1; % number of laser pulses to deliver after trace period
    S.LaserPulseDuration = 3; % seconds
    S.LaserPulseFrequency = 0.2; % Hz
    
    S.GUI.ITIMin = 10; % 5; % seconds
    S.GUI.ITIMax = 20; % 10; % seconds
end

% Duration of Laser state (based on parameters in S)
LaserStateDuration = ceil(S.NumLaserPulse/S.LaserPulseFrequency); % seconds

% Set up parameter GUI
BpodParameterGUI('init', S); 

% Define trial types: 1 = Laser1, 2 = Laser2, etc
% TrialTypes = repmat(1:S.NumLasers,1,MaxTrials/S.NumLasers);
% Randomize order each cycle:
TrialTypes = S.StimChannel*ones(MaxTrials,1);

% Set up WavePlayer (Analog Output Module for controlling lasers)
W = BpodWavePlayer(COM_Ports.COM_Port{strcmp(COM_Ports.Module,'BpodWavePlayer')}); % Make sure the COM port is correct
SR = 10000; % Sampling rate for analog output
W.SamplingRate = SR;
W.OutputRange = '0V:5V';
waveform = zeros(1,round(SR/S.LaserPulseFrequency));
waveform(1:(S.LaserPulseDuration * SR)) = 5;
waveform = repmat(waveform,1,S.NumLaserPulse);
W.loadWaveform(1,waveform);
WavePlayerMessages = {};
for i = 1:S.NumLasers
    WavePlayerMessages = [WavePlayerMessages {['P' 2^(i-1) 0]}]; % Send waveform 1 to the ith channel
end
WavePlayerMessages = [WavePlayerMessages {''}]; % Do nothing
LoadSerialMessages('WavePlayer1', WavePlayerMessages);

%% Main loop (runs once per trial)
tic;
for currentTrial = 1:MaxTrials
    
    TrialType = TrialTypes(currentTrial);

    % Sync parameters with BpodParameterGUI plugin
    S = BpodParameterGUI('sync', S); 
    
    % Compute variables for this trial's state machine:
    
    % Which laser channel to trigger
    LaserMessage = TrialType;
    
    % Randomly generate ITI duration
    ITIDuration = unifrnd(S.GUI.ITIMin,S.GUI.ITIMax);
    
    % Display trial type
    fprintf('Trial %d: TrialType %d\n',currentTrial,TrialType);
 
    
    % Create state matrix
    sma = NewStateMatrix();
    sma = AddState(sma, 'Name', 'Foreperiod',...
        'Timer', S.ForeperiodDuration,...
        'StateChangeConditions', {'Tup', 'Laser'},...
        'OutputActions', {'BNC1', 1, 'BNC2', 1});
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
toc;
fprintf('\nProtocol finished.\n');

end