
NumPatterns = 6;
PulseDur = 0.005;

% Stim patterns: 
SR = 10000;
stimWaveforms = cell(NumPatterns,1);
gamma = [0.02 0.1:0.1:0.5]; % gamma = [0.02 0.1:0.1:0.7];
assert(numel(gamma)==NumPatterns);
t_end = 6;
FR_min = 5; % 0;
FR_max = 30;
t_exp = (0:t_end*SR)/SR;
buffer_t = 0.1;
t_tot = (0:(t_end+buffer_t)*SR)/SR;

FR_func_expRamp = @(t, t_end, gamma, FR_min, FR_max)((FR_max-FR_min)*exp((t_end-t)*log(gamma))+FR_min);
FR_func_gaussRamp = @(lambda)((FR_max-FR_min)*exp((t_end-t_exp).^2*log(lambda))+FR_min);


for i = 1:numel(gamma)
    % target_exp = FR_func_expRamp(t_exp, t_end, gamma(i), FR_min, FR_max);
    % target_exp = [target_exp FR_max*ones(1,SR*buffer_t)];
    % 
    % waveform_exp = flipud(PulseTrain(fliplr(target_exp), t_tot, PulseDur));
    % 
    % fr_smooth = gauss_smooth([waveform_exp; 0],0.05*SR)/(5*PulseDur);
    % plot(fr_smooth);

    target_exp = FR_func_expRamp(t_exp, t_end, gamma(i), FR_min, FR_max);
    lambda_min = fmincon(@(lambda)(sum((FR_func_gaussRamp(lambda)-target_exp).^2)),3,[],[],[],[],0.00001,0.99999);
    target_gauss = FR_func_gaussRamp(lambda_min);

    figure; hold on;

    plot(t_exp,target_exp);
    plot(t_exp,target_gauss);

    target_gauss = [target_gauss FR_max*ones(1,SR*buffer_t)];
    target_gauss = fliplr(target_gauss);
    waveform = PulseTrain(target_gauss, t_tot, PulseDur);
    waveform = flipud(waveform);

    % figure; hold on;
    % plot(t_tot,waveform);

    stimWaveforms{i} = waveform;
end


save('stimWaveforms_gaussRamp.mat','stimWaveforms');


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