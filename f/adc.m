function [ys, varQ, xa] = adc(x, ADC, sim, Hrx)
%% Analog-to-digital conversion: filters, downsample, and quantize signal x
% Inputs:
% - x : input signal
% - ADC : ADC parameters. Must contain fields {filt, ros}. 
% If sim.quantiz is true, then quantization is performed and ADC must contain
% the additional fields {ENOB, rclip}, ENOB and clipping ratio. 
% Clipping ratio is defined as the percentage of the signal amplitude that 
% is clipped in both extremes (see code)
% - sim : simulation parameters {sim.f, sim.fs, sim.Mct}
% - Hrx (optional): if provided, adc.m ignores frequency response from ADC
% and use Hrx instead
% Outputs:
% - y : output signal
% - varQ : quantization noise variance

% Filter
% Filter by lowpass filter (antialiasing filter)
if not(exist('Hrx', 'var')) % check if ADC filter is defined
    Hrx = ifftshift(ADC.filt.H(sim.f/sim.fs).*... % rx filter frequency response
        exp(1j*2*pi*sim.f/sim.fs*(sim.Mct-1)/2)); % time shift so that first sample correspond to the center of symbol
else % if Hrx exists use Hrx instead. This is typically a matched filter
    Hrx = ifftshift(Hrx.*exp(1j*2*pi*sim.f/sim.fs*((sim.Mct-1)/2))); % time shift so that first sample correspond to the center of symbol
end

xa = real(ifft(fft(x).*Hrx)); % filter                                   

% Downsample
xs = xa(1:sim.Mct/ADC.ros:end);

% Quantize
if isfield(sim, 'quantiz') && sim.quantiz && ~isinf(ADC.ENOB)
    enob = ADC.ENOB;
    rclip = ADC.rclip;
    
    xmax = max(xs);
    xmin = min(xs);
    xamp = xmax - xmin;    
    
    % Clipping
    % clipped: [xmin, xmin + xamp*rclip) and (xmax - xamp*rclip, xmax]
    % not clipped: [xmin + xamp*rclip, xmax - xamp*rclip]
    xmin = xmin + xamp*rclip; % discounts portion to be clipped
    xmax = xmax - xamp*rclip;
    xamp = xmax - xmin;
    
    dx = xamp/(2^(enob)-1);
    
    codebook = xmin:dx:xmax;
    partition = codebook(1:end-1) + dx/2;
    [~, ys, varQ] = quantiz(xs, partition, codebook); 
else
    ys = xs;
    varQ = 0;
end