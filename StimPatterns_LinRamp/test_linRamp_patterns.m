

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
% M. Campbell 6/8/2026: linear ramps to match exponential ramps from
%     ExpRamp protocol


S = struct;
S.NumPatterns = 8;
S.PulseDur = 0.005;

% Stim patterns: 
SR = 10000;
S.stimWaveforms = cell(S.NumPatterns,1);
S.gamma = [0.02 0.1:0.1:0.5]; % S.gamma = [0.02 0.1:0.1:0.7];
assert(numel(S.gamma)==S.NumPatterns-2); % assert(numel(S.gamma)==S.NumPatterns); % assert(numel(S.gamma)==S.NumPatterns-1);
S.t_end = 6;
S.FR_min = 5; % 0;
S.FR_max = 30;
t_exp = (0:S.t_end*SR)/SR;
S.buffer_t = 0.1;
t_tot = (0:(S.t_end+S.buffer_t)*SR)/SR;

FR_func_expRamp = @(t, t_end, gamma, FR_min, FR_max)((FR_max-FR_min)*exp((t_end-t)*log(gamma))+FR_min);
FR_func_linRamp = @(t0)(max(S.FR_min,S.FR_min+(t_exp-t0)*(S.FR_max-S.FR_min)/(max(t_exp)-t0)));

for i = 1:numel(S.gamma)
    target_exp = FR_func_expRamp(t_exp, S.t_end, S.gamma(i), S.FR_min, S.FR_max);
    tmin = fmincon(@(t0)(sum((FR_func_linRamp(t0)-target_exp).^2)),3,[],[],[],[],0,6);

    figure; hold on;
    target_lin = FR_func_linRamp(tmin);
    plot(t_exp,target_exp);
    plot(t_exp,target_lin);

    target_lin = [target_lin S.FR_max*ones(1,SR*S.buffer_t)];
    target_lin = fliplr(target_lin);
    waveform = PulseTrain(target_lin, t_tot, S.PulseDur);
    waveform = flipud(waveform);

    W.loadWaveform(i,waveform);
    S.stimWaveforms{i} = waveform;
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

