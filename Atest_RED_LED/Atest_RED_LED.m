function Atest_RED_LED


global BpodSystem


COM_Ports = readtable('..\COM_Ports.txt'); % get COM ports from text file (ignored by git)

mouse = BpodSystem.Status.CurrentSubjectName;

%%
S.ForeperiodDuration = 0.5;

% optotag pulse options:
S.OptotagPulseFreq = 10;
S.OptotagPulseDur = 0.02;
S.OptotagPulseNum = 1;
S.OptotagLightPower_mW = 10;
S.ITIMin_optotag = 1; % different ITI for optotagging trials (uniform distribution)
S.ITIMax_optotag = 3;
S.NumOptotagTrials1 = 30;
% Duration of Optotag state (based on parameters in S)
OptotagStateDuration = ceil(S.OptotagPulseNum/S.OptotagPulseFreq); % seconds


W = BpodWavePlayer(COM_Ports.COM_Port{strcmp(COM_Ports.Module,'BpodWavePlayer')}); % Make sure the COM port is correct
SR = 10000; % Sampling rate for analog output
W.SamplingRate = SR;
W.OutputRange = '0V:5V';

% Optotag message (one 20 ms pulse)
waveform_optotag = zeros(1,round(SR/S.OptotagPulseFreq));
waveform_optotag(1:(S.OptotagPulseDur * SR)) = 5;
waveform_optotag = repmat(waveform_optotag,1,S.OptotagPulseNum);
W.loadWaveform(1,waveform_optotag);

WavePlayerMessages = {};
redStim_idx = 1; % for triggering red LED

WavePlayerMessages = [WavePlayerMessages {['P' 2^(redStim_idx-1) 0]}]; % send optotag message
LoadSerialMessages('WavePlayer1', WavePlayerMessages);


tic
total_trial_ctr = 0;
fprintf('\nOptotag1 (%d trials)\n', S.NumOptotagTrials1);
for currentTrial = 1:S.NumOptotagTrials1
    
    total_trial_ctr = total_trial_ctr+1;

    % Calculate ITI for this trial
    ITIDuration = unifrnd(S.ITIMin_optotag,S.ITIMax_optotag);

    fprintf('\tTrial %d:\tITI=%0.1fs\n',currentTrial,ITIDuration);

    %--- Assemble state machine
    sma = NewStateMatrix();
    
    sma = AddState(sma,'Name','Foreperiod',...
        'Timer',S.ForeperiodDuration,...
        'StateChangeConditions',{'Tup','Optotag'},...
        'OutputActions',{'BNC1',1,'BNC2',1});
    sma = AddState(sma, 'Name', 'Optotag', ... 
        'Timer', OptotagStateDuration,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'WavePlayer1', 1, 'BNC1', 0, 'BNC2', 0}); 
    sma = AddState(sma, 'Name', 'ITI', ... 
        'Timer', ITIDuration,...
        'StateChangeConditions', {'Tup','exit'},...
        'OutputActions', {'BNC1',0,'BNC2',0});

    SendStateMatrix(sma); % Send state machine to the Bpod state machine device

    RawEvents = RunStateMatrix; % Run the trial and return events

    % Update online plots
    if ~isempty(fieldnames(RawEvents))
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(total_trial_ctr) = S;

        SaveBpodSessionData;

    end
    
    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end
end

fprintf('Optotag1 finished\n');
toc;