clc;
clear;
close all;

%% 1. Signal Configuration
fs = 5000;
ADC_Resolution = 12;
Vref = 3.3;
fprintf('\n========================================\n');
fprintf('       AUDIO SIGNAL ANALYSIS\n');
fprintf('========================================\n');

%% 2. Select Two DAT Files
[files, path] = uigetfile('*.dat', ...
    'Select TWO audio DAT files', 'MultiSelect', 'on');
if isequal(files, 0)
    disp('No files selected. Program terminated.');
    return;
end
if ischar(files) || numel(files) ~= 2
    error('Please select exactly TWO DAT files.');
end
fprintf('\n---------- SELECTED FILES ----------\n');
fprintf('First file  : %s\n', files{1});
fprintf('Second file : %s\n', files{2});

%% 3. Read First DAT File
filename1 = fullfile(path, files{1});
fid = fopen(filename1, 'rb', 'ieee-le');
if fid == -1
    error('Unable to open first DAT file.');
end
data1 = fread(fid, Inf, 'uint16=>uint16');
fclose(fid);
if isempty(data1)
    error('First DAT file is empty.');
end

%% 4. Read Second DAT File
filename2 = fullfile(path, files{2});
fid = fopen(filename2, 'rb', 'ieee-le');
if fid == -1
    error('Unable to open second DAT file.');
end
data2 = fread(fid, Inf, 'uint16=>uint16');
fclose(fid);
if isempty(data2)
    error('Second DAT file is empty.');
end

%% 5. Combine Both DAT Files
combined_data = [data1; data2];
fprintf('\n---------- FILE COMBINATION ----------\n');
fprintf('Samples in File 1 : %d\n', length(data1));
fprintf('Samples in File 2 : %d\n', length(data2));
fprintf('Total samples     : %d\n', length(combined_data));

%% 6. Save Combined Data
[savefile, savepath] = uiputfile('*.dat', ...
    'Save Combined DAT File', 'Combined_Audio.dat');
if isequal(savefile, 0)
    disp('Saving cancelled. Program terminated.');
    return;
end
combined_filename = fullfile(savepath, savefile);
fid = fopen(combined_filename, 'wb', 'ieee-le');
if fid == -1
    error('Unable to create combined DAT file.');
end
fwrite(fid, combined_data, 'uint16');
fclose(fid);
fprintf('\nCombined DAT file saved successfully.\n');
fprintf('Output file: %s\n', combined_filename);

%% 7. Read Newly Created Combined DAT File
fid = fopen(combined_filename, 'rb', 'ieee-le');
if fid == -1
    error('Unable to reopen combined DAT file.');
end
x_raw = fread(fid, Inf, 'uint16=>double');
fclose(fid);
if isempty(x_raw)
    error('Combined DAT file contains no readable samples.');
end
if length(x_raw) ~= length(combined_data) || ...
        any(x_raw ~= double(combined_data))
    error('Data verification failed. Samples do not match.');
end
fprintf('\nData verification successful.\n');
fprintf('All combined ADC samples are preserved.\n');

%% 8. Signal and Acquisition Details
N = length(x_raw);
duration = N/fs;
time = (0:N-1)'/fs;
fileInfo = dir(combined_filename);
fprintf('\n========================================\n');
fprintf('       ACQUISITION DETAILS\n');
fprintf('========================================\n');
fprintf('Combined file name     : %s\n', savefile);
fprintf('File size              : %d bytes\n', fileInfo.bytes);
fprintf('Total number of samples: %d\n', N);
fprintf('Sampling frequency     : %.2f Hz\n', fs);
fprintf('Sampling period        : %.6f seconds\n', 1/fs);
fprintf('Signal duration        : %.4f seconds\n', duration);
fprintf('Nyquist frequency      : %.2f Hz\n', fs/2);
fprintf('ADC resolution         : %d bits\n', ADC_Resolution);
fprintf('ADC theoretical levels : %d\n', 2^ADC_Resolution);

%% 9. ADC Sample Statistics
sample_min = min(x_raw);
sample_max = max(x_raw);
sample_mean = mean(x_raw);
sample_std = std(x_raw);
sample_rms = sqrt(mean(x_raw.^2));
sample_vpp = sample_max - sample_min;
adc_max = 2^ADC_Resolution - 1;
voltage = x_raw * Vref/adc_max;

fprintf('\n---------- TIME-DOMAIN STATISTICS ----------\n');
fprintf('Minimum ADC count      : %.0f\n', sample_min);
fprintf('Maximum ADC count      : %.0f\n', sample_max);
fprintf('Mean ADC count         : %.2f\n', sample_mean);
fprintf('Standard deviation     : %.2f counts\n', sample_std);
fprintf('RMS ADC count          : %.2f counts\n', sample_rms);
fprintf('Peak-to-peak amplitude : %.0f counts\n', sample_vpp);
fprintf('Minimum voltage        : %.4f V\n', min(voltage));
fprintf('Maximum voltage        : %.4f V\n', max(voltage));
fprintf('Peak-to-peak voltage   : %.4f V\n', max(voltage)-min(voltage));

%% 10. Remove DC Component
x = x_raw - mean(x_raw);

%% 11. FFT-Based Power Spectrum
Y = fft(x);
PS = abs(Y).^2;
freq = (0:N-1)'*fs/N;
frequency_resolution = fs/N;
halfN = floor(N/2)+1;
PS_half = PS(1:halfN);
freq_half = freq(1:halfN);
fprintf('\n---------- FFT DETAILS ----------\n');
fprintf('FFT length           : %d points\n', N);
fprintf('Frequency resolution : %.4f Hz\n', frequency_resolution);
fprintf('Frequency range      : 0 to %.2f Hz\n', fs/2);

%% 12. Find Dominant Frequency
if halfN > 1
    [peak_power, idx] = max(PS_half(2:end));
    peak_index = idx+1;
    dominant_frequency = freq_half(peak_index);
    fprintf('\n---------- FREQUENCY ANALYSIS ----------\n');
    fprintf('Dominant frequency : %.2f Hz\n', dominant_frequency);
    fprintf('Peak FFT power     : %.4e counts^2\n', peak_power);
else
    dominant_frequency = NaN;
end

%% 13. Signal Power and RMS After DC Removal
mean_square = mean(x.^2);
rms_ac = sqrt(mean_square);
fprintf('\n---------- SIGNAL POWER ----------\n');
fprintf('AC RMS amplitude : %.2f ADC counts\n', rms_ac);
fprintf('Mean-square value: %.4f counts^2\n', mean_square);

%% 14. Plot Original Combined ADC Signal
figure('Name', 'Combined Audio Signal', 'Color', 'w');
plot(time, x_raw, 'k');
xlabel('Time (seconds)');
ylabel('ADC Count');
title('Combined Audio Signal');
grid on;
xlim([0 duration]);

%% 15. Plot DC-Removed Signal
figure('Name', 'DC Removed Audio', 'Color', 'w');
plot(time, x, 'k');
xlabel('Time (seconds)');
ylabel('Amplitude (ADC counts)');
title('Combined Audio Signal After DC Removal');
grid on;
xlim([0 duration]);

%% 16. Plot FFT Power Spectrum
figure('Name', 'FFT Power Spectrum', 'Color', 'w');
plot(freq_half, 10*log10(PS_half+eps), 'k');
xlabel('Frequency (Hz)');
ylabel('Power (dB relative to counts squared)');
title('FFT-Based Power Spectrum');
grid on;
xlim([0 fs/2]);

%% 17. Welch Power Spectral Density
windowLength = min(512, N);
window = hamming(windowLength);
overlapLength = floor(windowLength/2);
nfftWelch = max(512, 2^nextpow2(windowLength));
[Pwelch, fwelch] = pwelch( ...
    x, window, overlapLength, nfftWelch, fs);
if length(Pwelch) > 1
    [welchPeakPower, welchIndex] = max(Pwelch(2:end));
    welchIndex = welchIndex+1;
    welchDominantFrequency = fwelch(welchIndex);
    fprintf('\n---------- WELCH PSD DETAILS ----------\n');
    fprintf('Method                 : Welch PSD\n');
    fprintf('Window                 : Hamming\n');
    fprintf('Window length          : %d samples\n', windowLength);
    fprintf('Overlap                : %d samples\n', overlapLength);
    fprintf('FFT length             : %d points\n', nfftWelch);
    fprintf('Frequency resolution   : %.4f Hz\n', fs/nfftWelch);
    fprintf('Dominant PSD frequency : %.2f Hz\n', ...
        welchDominantFrequency);
    fprintf('Peak PSD value         : %.4e counts^2/Hz\n', ...
        welchPeakPower);
else
    welchDominantFrequency = NaN;
end
figure('Name', 'Welch Power Spectral Density', 'Color', 'w');
plot(fwelch, 10*log10(Pwelch+eps), 'k');
xlabel('Frequency (Hz)');
ylabel('Power/Frequency (dB/Hz)');
title('Power Spectral Density using Welch Method');
grid on;
xlim([0 fs/2]);

%% 18. Print Top Five FFT Spectral Peaks

if halfN > 2
    spectrum_for_peaks = PS_half;
    spectrum_for_peaks(1) = 0;
    [sorted_power, sorted_indices] = sort( ...
        spectrum_for_peaks, 'descend');
    number_of_peaks = min(5, length(sorted_indices));

    fprintf('\n---------- TOP FIVE SPECTRAL PEAKS ----------\n');
    fprintf('Rank    Frequency (Hz)    Power (counts^2)\n');

    for k = 1:number_of_peaks
        p = sorted_indices(k);
        fprintf('%-8d%-18.2f%.4e\n', ...
            k, freq_half(p), sorted_power(k));
    end
end

%% 19. Short-Time Fourier Transform (STFT)
fprintf('\n========================================\n');
fprintf('       STFT TIME-FREQUENCY ANALYSIS\n');
fprintf('========================================\n');

% STFT parameters
stft_window_length = 256;
stft_window = hamming(stft_window_length);
stft_overlap = 192;
stft_nfft = 1024;

% STFT calculation
[STFT, f_stft, t_stft] = spectrogram( ...
    x, stft_window, stft_overlap, stft_nfft, fs);
STFT_magnitude = abs(STFT);
STFT_power = abs(STFT).^2;
STFT_dB = 20*log10(STFT_magnitude+eps);

% STFT resolutions
stft_time_resolution = ...
    (stft_window_length-stft_overlap)/fs;
stft_frequency_resolution = fs/stft_nfft;
fprintf('\n---------- STFT PARAMETERS ----------\n');
fprintf('Method                 : STFT\n');
fprintf('Window                 : Hamming\n');
fprintf('Window length          : %d samples\n', ...
    stft_window_length);
fprintf('Window duration        : %.4f seconds\n', ...
    stft_window_length/fs);
fprintf('Overlap                : %d samples\n', ...
    stft_overlap);
fprintf('Overlap percentage     : %.2f %%\n', ...
    100*stft_overlap/stft_window_length);
fprintf('Hop size               : %d samples\n', ...
    stft_window_length-stft_overlap);
fprintf('Time resolution        : %.6f seconds\n', ...
    stft_time_resolution);
fprintf('FFT length             : %d points\n', ...
    stft_nfft);
fprintf('Frequency resolution   : %.4f Hz\n', ...
    stft_frequency_resolution);
fprintf('Number of time frames  : %d\n', length(t_stft));
fprintf('Number of frequency bins: %d\n', length(f_stft));

% STFT magnitude plot
figure('Name', 'STFT Magnitude Spectrogram', 'Color', 'w');
imagesc(t_stft, f_stft, STFT_dB);
axis xy;
xlabel('Time (seconds)');
ylabel('Frequency (Hz)');
title('Short-Time Fourier Transform - Magnitude Spectrogram');
colorbar;
colormap jet;
ylim([0 fs/2]);

% STFT power plot
figure('Name', 'STFT Power Spectrogram', 'Color', 'w');
imagesc(t_stft, f_stft, 10*log10(STFT_power+eps));
axis xy;
xlabel('Time (seconds)');
ylabel('Frequency (Hz)');
title('STFT Power Spectrogram');
colorbar;
colormap jet;
ylim([0 fs/2]);

fprintf('\nSTFT analysis completed successfully.\n');

%% 20. Wigner-Ville Distribution (WVD)
fprintf('\n========================================\n');
fprintf('       WIGNER-VILLE DISTRIBUTION\n');
fprintf('========================================\n');

% Limit WVD calculation to control memory usage

wvd_max_samples = 4096;
wvd_length = min(N, wvd_max_samples);
x_wvd = x(1:wvd_length);

% WVD calculation
% Requires MATLAB Signal Processing Toolbox
[WVD, f_wvd, t_wvd] = wvd(x_wvd, fs);

% WVD magnitude
WVD_magnitude = abs(WVD);
% WVD power display
WVD_power = WVD_magnitude.^2;

% WVD magnitude in dB
WVD_dB = 20*log10(WVD_magnitude+eps);

% WVD parameters
wvd_duration = wvd_length/fs;
wvd_frequency_resolution = mean(diff(f_wvd));
wvd_time_resolution = mean(diff(t_wvd));
fprintf('\n---------- WVD PARAMETERS ----------\n');
fprintf('Method                  : Wigner-Ville Distribution\n');
fprintf('Input signal            : DC-removed signal\n');
fprintf('Sampling frequency      : %.2f Hz\n', fs);
fprintf('Total combined samples  : %d\n', N);
fprintf('WVD samples analyzed    : %d\n', wvd_length);
fprintf('WVD signal duration     : %.4f seconds\n', ...
    wvd_duration);
fprintf('WVD frequency spacing   : %.4f Hz\n', ...
    wvd_frequency_resolution);
fprintf('WVD time spacing        : %.6f seconds\n', ...
    wvd_time_resolution);
fprintf('WVD matrix size         : %d x %d\n', ...
    size(WVD,1), size(WVD,2));

% WVD magnitude plot
figure('Name', 'Wigner-Ville Distribution', 'Color', 'w');
imagesc(t_wvd, f_wvd, WVD_magnitude);
axis xy;
xlabel('Time (seconds)');
ylabel('Frequency (Hz)');
title('Wigner-Ville Time-Frequency Distribution');
colorbar;
colormap jet;
ylim([0 fs/2]);

% WVD magnitude dB plot
figure('Name', 'WVD Magnitude in dB', 'Color', 'w');
imagesc(t_wvd, f_wvd, WVD_dB);
axis xy;
xlabel('Time (seconds)');
ylabel('Frequency (Hz)');
title('Wigner-Ville Distribution - Magnitude (dB)');
colorbar;
colormap jet;
ylim([0 fs/2]);

% WVD power plot
figure('Name', 'WVD Power Distribution', 'Color', 'w');
imagesc(t_wvd, f_wvd, WVD_power);
axis xy;
xlabel('Time (seconds)');
ylabel('Frequency (Hz)');
title('Wigner-Ville Distribution - Power');
colorbar;
colormap jet;
ylim([0 fs/2]);
fprintf('\nWVD analysis completed successfully.\n');

%% 21. Final Time-Frequency Analysis Summary
fprintf('\n========================================\n');
fprintf('   TIME-FREQUENCY ANALYSIS SUMMARY\n');
fprintf('========================================\n');
fprintf('\n---------- STFT RESULTS ----------\n');
fprintf('STFT window length       : %d samples\n', ...
    stft_window_length);
fprintf('STFT overlap             : %d samples\n', ...
    stft_overlap);
fprintf('STFT FFT length          : %d points\n', ...
    stft_nfft);
fprintf('STFT frequency resolution: %.4f Hz\n', ...
    stft_frequency_resolution);
fprintf('STFT time resolution     : %.6f seconds\n', ...
    stft_time_resolution);
fprintf('\n---------- WVD RESULTS ----------\n');
fprintf('WVD samples analyzed     : %d\n', wvd_length);
fprintf('WVD duration             : %.4f seconds\n', ...
    wvd_duration);
fprintf('WVD frequency spacing    : %.4f Hz\n', ...
    wvd_frequency_resolution);
fprintf('WVD time spacing         : %.6f seconds\n', ...
    wvd_time_resolution);

%% 22. Final Status
fprintf('\n========================================\n');
fprintf('       ANALYSIS COMPLETED\n');
fprintf('========================================\n');
fprintf('Two DAT files combined successfully.\n');
fprintf('Combined file independently verified.\n');
fprintf('FFT analysis completed.\n');
fprintf('Welch PSD analysis completed.\n');
fprintf('STFT analysis completed.\n');
fprintf('WVD analysis completed.\n');
fprintf('All graphs generated successfully.\n');
