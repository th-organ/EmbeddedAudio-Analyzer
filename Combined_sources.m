
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

%% 5. Combine Both DAT Files in the Same Order

combined_data = [data1; data2];

fprintf('\n---------- FILE COMBINATION ----------\n');
fprintf('Samples in File 1 : %d\n', length(data1));
fprintf('Samples in File 2 : %d\n', length(data2));
fprintf('Total samples     : %d\n', length(combined_data));

%% 6. Save Combined Data into a New DAT File

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

%% 7. Read the Newly Created Combined DAT File

fid = fopen(combined_filename, 'rb', 'ieee-le');

if fid == -1
    error('Unable to reopen combined DAT file.');
end

x_raw = fread(fid, Inf, 'uint16=>double');
fclose(fid);

if isempty(x_raw)
    error('Combined DAT file contains no readable samples.');
end

% Verify that all samples were preserved
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

% ADC count to voltage conversion
adc_max = 2^ADC_Resolution - 1;
voltage = x_raw * Vref/adc_max;

fprintf('\n---------- TIME-DOMAIN STATISTICS ----------\n');

fprintf('Minimum ADC count      : %.0f\n', sample_min);
fprintf('Maximum ADC count      : %.0f\n', sample_max);
fprintf('Mean ADC count         : %.2f\n', sample_mean);
fprintf('Standard deviation     : %.2f counts\n', sample_std);
fprintf('RMS ADC count          : %.2f counts\n', sample_rms);
fprintf('Peak-to-peak amplitude : %.0f counts\n', sample_vpp);
fprintf('Minimum voltage       : %.4f V\n', min(voltage));
fprintf('Maximum voltage       : %.4f V\n', max(voltage));
fprintf('Peak-to-peak voltage  : %.4f V\n', max(voltage)-min(voltage));

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

%% 17. Welch Power Spectral Density (Pwelch)

% Hamming window
windowLength = min(512, N);
window = hamming(windowLength);

% 50 percent overlap
overlapLength = floor(windowLength/2);

% FFT length
nfftWelch = max(512, 2^nextpow2(windowLength));

% Welch PSD estimation
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

% Plot Welch PSD
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

%% 19. Final Status

fprintf('\n========================================\n');
fprintf('       ANALYSIS COMPLETED\n');
fprintf('========================================\n');

fprintf('Two DAT files combined successfully.\n');
fprintf('Combined file independently verified.\n');
fprintf('FFT analysis completed.\n');
fprintf('Welch PSD analysis completed.\n');
fprintf('All graphs generated successfully.\n');
