function OptoCalibration

% M. Campbell 8/2/2021: Protocol to deliver odors followed by laser pulses.
% M. Campbell 8/4/2022: Just does optotagging. Cleaned up some stuff.
% M. Campbell 7/28/2023: For opto calibration (range of stim params)
% M. Campbell 8/7/2023: Randomized order of parameters

global BpodSystem

COM_Ports = readtable('..\COM_Ports.txt'); % get COM ports from text file (ignored by git)

%% Setup (runs once before the first trial)

NumPulse = [10 15 20 25];
PulseDur = [0.005 0.005 0.005 0.005];
Freq = [20 30 40 50];
Power = 4.8;
NumSweeps = 5;
NumParams = 4;
MaxTrials = 1; % Trials per condition per sweep

tic;
ctr = 1;
for sIdx = 1:NumSweeps
    fprintf('Sweep %d/%d\n',sIdx,NumSweeps);
    
    % randomize order of parameters in each sweep
    randIdx = randperm(NumParams);
    NumPulse_rand = NumPulse(randIdx);
    PulseDur_rand = PulseDur(randIdx);
    Freq_rand = Freq(randIdx);
    
    for pIdx = 1:NumParams
        fprintf('\tParam %d/%d\n\t\tNumPulse=%d\n\t\tPulseDur=%0.3f\n\t\tFreq=%d\n\t\tPower=%0.1f\n',...
            pIdx,NumParams,NumPulse_rand(pIdx),PulseDur_rand(pIdx),Freq_rand(pIdx),Power)
        
        % Task parameters
        S = BpodSystem.ProtocolSettings; % contains valve order for this mouse in field OdorValvesOdor
        
        S.NumLasers = 1;
        % These parameters are shared across animals:
        S.ForeperiodDuration = 0.5; % seconds
        
        % S.NumLaserPulse = 10; % number of laser pulses to deliver after trace period
        % S.LaserPulseDuration = 0.02; % seconds
        % S.LaserPulseFrequency = 20; % Hz
        
        S.NumLaserPulse = NumPulse_rand(pIdx); % number of laser pulses to deliver after trace period
        S.LaserPulseDuration = PulseDur_rand(pIdx); % seconds
        S.LaserPulseFrequency = Freq_rand(pIdx); % Hz
        S.Power = Power; % power in mW
        
        S.ITIMin = 60; % seconds
        S.ITIMax = 80; % seconds
        
        % Duration of Laser state (based on parameters in S)
        LaserStateDuration = ceil(S.NumLaserPulse/S.LaserPulseFrequency); % seconds
        
        % Define trial types: 1 = Laser1, 2 = Laser2, etc
        TrialTypes = repmat(1:S.NumLasers,1,MaxTrials/S.NumLasers);
        
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
        for currentTrial = 1:MaxTrials
            
            TrialType = TrialTypes(currentTrial);
            
            % Compute variables for this trial's state machine:
            
            % Which laser channel to trigger
            LaserMessage = TrialType;
            
            % Randomly generate ITI duration
            ITIDuration = unifrnd(S.ITIMin,S.ITIMax);
            
            % Display trial type
            fprintf('\t\t\tTrial %d: TrialType %d\n',currentTrial,TrialType);
         
            
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
                BpodSystem.Data.TrialTypes(ctr) = TrialType;
                BpodSystem.Data.NumPulse(ctr) = S.NumLaserPulse;
                BpodSystem.Data.PulseDur(ctr) = S.LaserPulseDuration;
                BpodSystem.Data.Freq(ctr) = S.LaserPulseFrequency;
                BpodSystem.Data.Power(ctr) = S.Power;
                SaveBpodSessionData;
                
                % Update online plots
                % PokesPlot('update');
            end
        
            % Handle pauses and exit if the user ended the session
            HandlePauseCondition;
            if BpodSystem.Status.BeingUsed == 0
                return
            end

            ctr = ctr+1;
            
        end
        
        clear W;
        
        end
    end

    toc;
    fprintf('\nProtocol finished.\n');

end