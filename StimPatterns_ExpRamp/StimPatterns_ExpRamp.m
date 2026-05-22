function StimPatterns_ExpRamp

% M. Campbell 8/2/2021: Protocol to deliver odors followed by laser pulses.
% M. Campbell 12/1/2021: Edited OdorLaser to create OdorLaserWater task.
% M. Campbell 10/24/2022: Edited OdorLaserWater to create OdorLaser_v2:
%   Initially used for photometry opto calibration experiments 
%   (calibrating opto stim to water reward, then repeating OdorLaser task)
%   Added omission trials
%   Made the ITI exponentially distributed
%   Added block of rewards before and after odor trials (for
%   calibration/comparison to odor/opto responses)
% M. Campbell 11/5/2022: Added unpredicted opto stim before and after odor
%   trials
% M. Campbell 3/5/2023: 1 laser, 2 CS
% M. Campbell 1/25/2024: adapted for Different Stim Patterns experiment
% (stim D1 neurons in different patterns while recording GRABDA signals in DA
% axons in VS)
% M. Campbell 7/16/2024: 7 stim patterns (original 4 plus three more: 3 sec
%   square wave at 5, 10, 20 Hz)
% M. Campbell 4/30/2026: 5 stim patterns, for thirst experiment (original
%   patterns 3-7)
% M. Campbell 5/14/2026: Sinusoid stim patterns, for revisions at Nature
% M. Campbell 5/14/2026: removed water trials
% M. Campbell 5/14/2026: exponential ramps with different gammas

global BpodSystem


COM_Ports = readtable('..\COM_Ports.txt'); % get COM ports from text file (ignored by git)

%% Setup (runs once before the first trial)

mouse = BpodSystem.Status.CurrentSubjectName;

NumStimTrials = 8*24;

BpodSystem.Data.TaskDescription = 'StimTrials';

% Task parameters
S = BpodSystem.ProtocolSettings; 

% These parameters are shared across animals:
S.Experimenter = 'Malcolm';
S.Mouse = mouse;
S.NumPatterns = 8;

S.ITI_type = 'unif'; % 'unif' or 'exp'
S.ITIMean = 18; % 12;
S.ITIMin = 13; % 8;
S.ITIMax = 23; % 20;
S.RewardAmounts = [2 8];
S.ForeperiodDuration = 0.5;

S.StimPower_mW = input('Stim LED power (mW): ');
S.PulseDur = 0.005;

% display parameters
fprintf('\nSession parameters:\n')
S
fprintf('NumStimTrials = %d\n',NumStimTrials);



%% Define stim trial types
TargetChunkSize = S.NumPatterns; % trials; chunk size in which to balance trial types
ActualChunkSize = S.NumPatterns*round(TargetChunkSize/S.NumPatterns);
TrialTypesChunk = repmat(1:S.NumPatterns,1,ActualChunkSize/S.NumPatterns);

NumChunks = ceil(NumStimTrials/ActualChunkSize);
TrialTypes = [];
for i = 1:NumChunks
    perm_idx = randperm(ActualChunkSize);
    TrialTypes = [TrialTypes TrialTypesChunk(perm_idx)];
end
TrialTypes = TrialTypes(1:NumStimTrials);



%% Set up WavePlayer (Analog Output Module for controlling lasers)
W = BpodWavePlayer(COM_Ports.COM_Port{strcmp(COM_Ports.Module,'BpodWavePlayer')}); % Make sure the COM port is correct
SR = 10000; % Sampling rate for analog output
W.SamplingRate = SR;
W.OutputRange = '0V:5V';


% Stim patterns: 
S.stimWaveforms = cell(S.NumPatterns,1);
S.gamma = [0.02 0.1:0.1:0.7];
assert(numel(S.gamma)==S.NumPatterns);
t_end = 6;
FR_min = 0;
FR_max = 30;
FR_func_expRamp = @(t, t_end, gamma, FR_min, FR_max)((FR_max-FR_min)*exp((t_end-t)*log(gamma))+FR_min);
t_exp = (0:t_end*SR)/SR;
buffer_t = 0.1;
t_tot = (0:(t_end+buffer_t)*SR)/SR;

for i = 1:numel(S.gamma)
    target = FR_func_expRamp(t_exp, t_end, S.gamma(i), FR_min, FR_max);
    target = [target FR_max*ones(1,SR*buffer_t)];
    target = fliplr(target);
    waveform = PulseTrain(target, t_tot, S.PulseDur);
    waveform = flipud(waveform);

    W.loadWaveform(i,waveform);
    S.stimWaveforms{i} = waveform;
end


% % 3 sec at 20 Hz
% waveform_3secSquare_20Hz = zeros(1,round(SR/20));
% waveform_3secSquare_20Hz(1:(S.PulseDur * SR)) = 5;
% waveform_3secSquare_20Hz = repmat(waveform_3secSquare_20Hz,1,60);
% W.loadWaveform(S.NumPatterns,waveform_3secSquare_20Hz);
% S.stimWaveforms{S.NumPatterns} = waveform_3secSquare_20Hz;
% pulsecount = sum(waveform_3secSquare_20Hz)/(5*S.PulseDur*SR);

% 6 sec at 5 Hz
% waveform_3secSquare_5Hz = zeros(1,round(SR/5));
% waveform_3secSquare_5Hz(1:(S.PulseDur * SR)) = 5;
% % waveform_3secSquare_5Hz = repmat(waveform_3secSquare_5Hz,1,30);
% waveform_3secSquare_5Hz = repmat(waveform_3secSquare_5Hz,1,31); % one extra pulse at t = 6 to line up with the other patterns which have a buffer period of 0.2 sec
% W.loadWaveform(S.NumPatterns,waveform_3secSquare_5Hz);
% S.stimWaveforms{S.NumPatterns} = waveform_3secSquare_5Hz;


% load messages to WavePlayer:
WavePlayerMessages = {};
LED_idx = 1;
for patternIdx = 1:S.NumPatterns
    WavePlayerMessages = [WavePlayerMessages {['P' 2^(LED_idx-1) patternIdx-1]}]; % send waveform patternIdx to the LED_idx'th channel
end
LoadSerialMessages('WavePlayer1', WavePlayerMessages);




%% Stim trials
tic
fprintf('\nStim trials\n');
for currentTrial = 1:NumStimTrials
    
    TrialType = TrialTypes(currentTrial);
    
    % Compute variables for this trial's state machine:
   
    Stim_state = sprintf('Stim%d',TrialType);

    % Which laser pattern to trigger
    LaserMessage = TrialType;
    
    % Calculate ITI for this trial
    if strcmp(S.ITI_type,'exp')
        ITIDuration = exprnd(S.ITIMean-S.ITIMin) + S.ITIMin;
        if ITIDuration > S.ITIMax
            ITIDuration = S.ITIMax;
        end
    elseif strcmp(S.ITI_type,'unif')
        ITIDuration = unifrnd(S.ITIMin,S.ITIMax);
    end
    
    
    % Display trial type
    fprintf('\tTrial %d:\tTrialType%d\tITI=%0.1fs\n',...
        currentTrial,TrialType,ITIDuration);
    
    
    % Create state matrix
    sma = NewStateMatrix();
    sma = AddState(sma, 'Name', 'Foreperiod',...
        'Timer', S.ForeperiodDuration,...
        'StateChangeConditions', {'Tup', Stim_state},...
        'OutputActions', {'BNC1', 1, 'BNC2', 1});
    for tt = 1:S.NumPatterns
        sma = AddState(sma, 'Name', sprintf('Stim%d',tt),...
            'Timer', 2,...
            'StateChangeConditions', {'Tup', 'ITI'},...
            'OutputActions', {'WavePlayer1', LaserMessage, 'BNC1', 0, 'BNC2', 0}); 
    end
    sma = AddState(sma, 'Name', 'ITI',...
        'Timer', ITIDuration,...
        'StateChangeConditions', {'Tup', 'exit'},...
        'OutputActions', {'BNC1', 0, 'BNC2', 0});

    % Add reward state so pokes plot doesn't get messed up:
    sma = AddState(sma,'Name','Reward','Timer',0,'StateChangeConditions',{},'OutputActions',{}); 
    
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
        
    end

    % Handle pauses and exit if the user ended the session
    HandlePauseCondition;
    if BpodSystem.Status.BeingUsed == 0
        ModuleWrite('ValveModule1', ['B' 0]); % make sure the odor valves are closed
        return
    end
    
end

fprintf('Stim trials finished\n');
toc;
clear W;

fprintf('\nProtocol finished\n')

end


function [waveform,pulse_count] = PulseTrain(target, t, PulseDur)

% target = the target firing rate function
% t = the time base, assumed to be (0:t_end*SR)/SR, in seconds
% PulseDur = the duration of each pulse, in seconds

% MGC 5/13/2026

SR = round(1/mean(diff(t)));
t_tmp = (0:max(t)*SR)/SR;
assert(all(t==t_tmp));

waveform = zeros(numel(t), 1);
t_curr = t(1);
pulse_count = 0;

while t_curr < max(t)

    FR_local = interp1(t,target,t_curr);
    ipi = 1/FR_local;
    FR_next = interp1(t,target,t_curr+ipi);
    for i = 1:100
        ipi = 1/((FR_local+FR_next)/2);
        FR_next = interp1(t,target,t_curr+ipi);
    end

    t_next = t_curr + ipi;
    startIdx =  floor(t_curr * SR) + 1;
    endIdx = floor((t_curr+PulseDur) * SR);

    if endIdx >= numel(waveform)
        endIdx = numel(waveform);
        waveform = [waveform; zeros(endIdx-numel(waveform)+10,1)];
    end
    waveform(startIdx:endIdx) = 5;
    t_curr = t_next;
    pulse_count = pulse_count + 1;

end

end