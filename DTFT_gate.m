clc;
clear;
close all;
%% 1. Signal Configuration
fs = 5000;                 % Sampling frequency in Hz
ADC_Resolution = 12;       % STM32 ADC resolution in bits
Vref = 3.3;                % ADC reference voltage in volts

fprintf('\n========================================\n');
fprintf('       AUDIO SIGNAL ANALYSIS\n');
fprintf('========================================\n');

%% 2. Manually Select DAT File
[file, path] = uigetfile('*.dat', 'Select your audio DAT file');
if isequal(file, 0)
    disp('No file selected. Program terminated.');
    return;
end
filename = fullfile(path, file);
fprintf('\nSelected file: %s\n', filename);

%% 3. Read Binary ADC Samples
fid = fopen(filename, 'rb', 'ieee-le');
if fid == -1
    error('Unable to open the selected DAT file.');
end
x_raw = fread(fid, Inf, 'uint16=>double');
fclose(fid);
if isempty(x_raw)
    error('The selected DAT file is empty or contains no readable samples.');
end
if mod(numel(x_raw), 1) ~= 0
    error('Invalid sample data.');
end

%% 4. Signal and Acquisition Details
N = length(x_raw);
duration = N / fs;
time = (0:N-1)' / fs;
fprintf('\n---------- ACQUISITION DETAILS ----------\n');
fprintf('File name              : %s\n', file);
fprintf('Number of samples      : %d\n', N);
fprintf('File size              : %d bytes\n', dir(filename).bytes);
fprintf('Sampling frequency     : %.2f Hz\n', fs);
fprintf('Sampling period        : %.6f seconds\n', 1/fs);
fprintf('Signal duration        : %.4f seconds\n', duration);
fprintf('Nyquist frequency      : %.2f Hz\n', fs/2);
fprintf('ADC resolution         : %d bits (configured)\n', ADC_Resolution);
fprintf('ADC theoretical levels : %d\n', 2^ADC_Resolution);

%% 5. ADC Sample Statistics
sample_min = min(x_raw);
sample_max = max(x_raw);
sample_mean = mean(x_raw);
sample_std = std(x_raw);
sample_rms = sqrt(mean(x_raw.^2));
sample_vpp = sample_max - sample_min;
% Convert ADC counts to voltage, assuming 12-bit ADC and 3.3 V reference
adc_max = 2^ADC_Resolution - 1;
voltage = x_raw * Vref / adc_max;

fprintf('\n---------- TIME-DOMAIN STATISTICS ----------\n');
fprintf('Minimum ADC count      : %.0f\n', sample_min);
fprintf('Maximum ADC count      : %.0f\n', sample_max);
fprintf('Mean ADC count         : %.2f\n', sample_mean);
fprintf('Standard deviation     : %.2f counts\n', sample_std);
fprintf('RMS ADC count          : %.2f counts\n', sample_rms);
fprintf('Peak-to-peak amplitude : %.0f counts\n', sample_vpp);
fprintf('Minimum voltage        : %.4f V (estimated)\n', min(voltage));
fprintf('Maximum voltage        : %.4f V (estimated)\n', max(voltage));
fprintf('Peak-to-peak voltage   : %.4f V (estimated)\n', ...
    max(voltage) - min(voltage));

%% 6. Remove DC Component
x = x_raw - mean(x_raw);

%% 7. FFT-Based Power Spectrum
Y = fft(x);
PS = abs(Y).^2;
freq = (0:N-1)' * fs / N;
frequency_resolution = fs / N;
fprintf('\n---------- FFT DETAILS ----------\n');
fprintf('FFT length             : %d points\n', N);
fprintf('Frequency resolution   : %.4f Hz\n', frequency_resolution);
fprintf('Frequency range        : 0 to %.2f Hz (one-sided)\n', fs/2);
fprintf('Spectrum method        : FFT');

%% 8. Find Dominant Frequency
halfN = floor(N/2) + 1;
PS_half = PS(1:halfN);
freq_half = freq(1:halfN);

% Ignore DC when finding the dominant frequency
if halfN > 1
    [peak_power, idx] = max(PS_half(2:end));
    peak_index = idx + 1;
    dominant_frequency = freq_half(peak_index);
    fprintf('\n\n---------- FREQUENCY ANALYSIS ----------\n');
    fprintf('Dominant frequency     : %.2f Hz\n', dominant_frequency);
    fprintf('Peak FFT power         : %.4e (counts squared)\n', peak_power);
else
    dominant_frequency = NaN;
    fprintf('\nInsufficient samples for frequency analysis.\n');
end

%% 9. Total Signal Power and RMS After DC Removal
mean_square = mean(x.^2);
rms_ac = sqrt(mean_square);
fprintf('AC RMS amplitude       : %.2f ADC counts\n', rms_ac);
fprintf('Mean-square value      : %.4f counts squared\n', mean_square);

%% 10. Plot Original ADC Signal
figure('Name', 'Audio Signal', 'Color', 'w');
plot(time, x_raw, 'k');
xlabel('Time (seconds)');
ylabel('ADC Count');
title('Captured Audio Signal');
grid on;
xlim([0 duration]);

%% 11. Plot AC-Coupled Signal
figure('Name', 'DC-Removed Audio', 'Color', 'w');
plot(time, x, 'k');
xlabel('Time (seconds)');
ylabel('Amplitude (ADC counts)');
title('Audio Signal After DC Removal');
grid on;
xlim([0 duration]);

%% 12. Plot One-Sided FFT Power Spectrum in dB
figure('Name', 'FFT Power Spectrum', 'Color', 'w');
plot(freq_half, 10*log10(PS_half + eps), 'k');
xlabel('Frequency (Hz)');
ylabel('Power (dB relative to counts squared)');
title('FFT-Based Power Spectrum');
grid on;
xlim([0 fs/2]);

%% 13. Welch Power Spectral Density (Pwelch)

% Hamming window
windowLength = min(512, N);
window = hamming(windowLength);
% 50 percent overlap
overlapLength = floor(windowLength/2);
% FFT length for Welch estimation
nfftWelch = max(512, 2^nextpow2(windowLength));
% Welch PSD estimation
[Pwelch, fwelch] = pwelch(x, window, overlapLength, nfftWelch, fs);
% Find maximum PSD frequency, excluding DC
if length(Pwelch) > 1
    [welchPeakPower, welchIndex] = max(Pwelch(2:end));
    welchIndex = welchIndex + 1;
    welchDominantFrequency = fwelch(welchIndex);
    fprintf('\n---------- WELCH PSD DETAILS ----------\n');
    fprintf('Method                 : Welch power spectral density');
    fprintf('\nWindow                 : Hamming\n');
    fprintf('Window length          : %d samples\n', windowLength);
    fprintf('Overlap                : %d samples\n', overlapLength);
    fprintf('FFT length             : %d points\n', nfftWelch);
    fprintf('Frequency resolution   : %.4f Hz\n', fs/nfftWelch);
    fprintf('Dominant PSD frequency : %.2f Hz\n', welchDominantFrequency);
    fprintf('Peak PSD value         : %.4e counts^2/Hz\n', welchPeakPower);
else
    welchDominantFrequency = NaN;
    fprintf('\nInsufficient samples for Welch analysis.\n');
end
% Plot Welch PSD
figure('Name', 'Welch Power Spectral Density', 'Color', 'w');
plot(fwelch, 10*log10(Pwelch + eps), 'k');
xlabel('Frequency (Hz)');
ylabel('Power/Frequency (dB/Hz)');
title('Power Spectral Density using Welch Method');
grid on;
xlim([0 fs/2]);

%% 14. Print Top Five FFT Spectral Peaks
if halfN > 2
    spectrum_for_peaks = PS_half;
    spectrum_for_peaks(1) = 0;  % Exclude DC
    [sorted_power, sorted_indices] = sort( ...
        spectrum_for_peaks, 'descend');
    number_of_peaks = min(5, length(sorted_indices));
    fprintf('\n---------- TOP SPECTRAL PEAKS ----------\n');
    fprintf('Rank    Frequency (Hz)    Power (counts^2)\n');
    for k = 1:number_of_peaks
        p = sorted_indices(k);
        fprintf('%-8d%-18.2f%.4e\n', ...
            k, freq_half(p), sorted_power(k));
    end
end

fprintf('\n========================================\n');
fprintf('       ANALYSIS COMPLETED\n');
fprintf('========================================\n');