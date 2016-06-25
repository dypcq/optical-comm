%% Calculate BER of amplified IM-DD system. 
% - CD is partially compensated by DCF
% - Equalization is done using a fractionally spaced linear equalizer
% Simulations include modulator, fiber, optical amplifier characterized 
% only by gain and noise figure, optical bandpass filter, antialiasing 
% filter, sampling, and linear equalization

clear, clc

addpath f/ % Juniper project specific functions
addpath ../mpam % PAM
addpath ../f % general functions
addpath ../soa % for pre-amplifier 
addpath ../apd % for PIN photodetectors

%% Simulation parameters
sim.Rb = 56e9;    % bit rate in bits/sec
sim.Nsymb = 2^16; % Number of symbols in montecarlo simulation
sim.ros.txDSP = 2; % oversampling ratio transmitter DSP (must be integer). DAC samping rate is sim.ros.txDSP*mpam.Rs
% For DACless simulation must make Tx.dsp.ros = sim.Mct and DAC.resolution = Inf
sim.ros.rxDSP = 2; % oversampling ratio of receiver DSP. If equalization type is fixed time-domain equalizer, then ros = 1
sim.Mct = 12;      % Oversampling ratio to simulate continuous time. Must be integer multiple of DAC.ros
% sim.Me = 16;       % Number of used eigenvalues
% sim.L = 2; % de Bruijin sub-sequence length (ISI symbol length)
sim.BERtarget = 1e-4; 
sim.Ndiscard = 128; % number of symbols to be discarded from the begning and end of the sequence
sim.N = sim.Mct*sim.Nsymb; % number points in 'continuous-time' simulation
sim.Modulator = 'MZM'; % 'MZM' only
 
sim.RIN = true; % include RIN noise in montecarlo simulation
sim.phase_noise = true; % whether to simulate laser phase noise
sim.PMD = false; % whether to simulate PMD
sim.quantiz = false; % whether quantization is included
sim.stopSimWhenBERReaches0 = true; % stop simulation when counted BER reaches 0

% Control what should be plotted
sim.Plots = containers.Map();
sim.Plots('BER') = 1;
sim.Plots('Eye diagram of DAC output') = 0;
sim.Plots('Optical eye diagram') = 0;
sim.Plots('Received signal eye diagram') = 0;
sim.Plots('Signal after equalization') = 0;
sim.Plots('Equalizer') = 0;
sim.Plots('Adaptation MSE') = 0;
sim.Plots('Ouptut signal') = 0;
sim.Plots('Heuristic noise pdf') = 0;
sim.Plots('Frequency response') = 0;
sim.shouldPlot = @(x) sim.Plots.isKey(x) && sim.Plots(x);

%% Pulse shape
pulse_shape.type = 'rect'; % either 'rect', 'rrc', or 'rc'
pulse_shape.sps = sim.ros.txDSP; % number of samples per symbol
switch lower(pulse_shape.type) 
    case 'rect' % Rectangular pulse shape
        pulse_shape.h = ones(1, pulse_shape.sps); % pulse shapping filter coefficients
    case 'rrc' % Root raised cosine pulse shape
        pulse_shape.rolloff = 0.25; % 
        pulse_shape.span = 6; % number of symbols over which pulse shape spans
        pulse_shape.h = rcosdesign(pulse_shape.rolloff, pulse_shape.span, pulse_shape.sps, 'sqrt'); % pulse shapping filter coefficients
    case 'rc' % Raised cosine pulse shape
        pulse_shape.rolloff = 0.25; % 
        pulse_shape.span = 6; % number of symbols over which pulse shape spans
        pulse_shape.h = rcosdesign(pulse_shape.rolloff, pulse_shape.span, pulse_shape.sps, 'normal'); % pulse shapping filter coefficients
    otherwise
        error('Invalid pulse shape type')
end

Tx.pulse_shape = pulse_shape;

%% M-PAM
% PAM(M, bit rate, leve spacing : {'equally-spaced', 'optimized'}, pulse
% shape: struct containing properties of pulse shape 
mpam = PAM(4, sim.Rb, 'equally-spaced', pulse_shape);

%% Time and frequency
sim.fs = mpam.Rs*sim.Mct;  % sampling frequency in 'continuous-time'

dt = 1/sim.fs;
t = (0:dt:(sim.N-1)*dt);
df = 1/(dt*sim.N);
f = (-sim.fs/2:df:sim.fs/2-df);

sim.t = t;
sim.f = f;

%% Transmitter
Tx.PtxdBm = -30:-15; % transmitter power range
% Tx.PtxdBm = -15; % transmitter power range

Tx.rexdB = -22;  % extinction ratio in dB. Defined as Pmin/Pmax
Tx.alpha = 0; % chirp parameter for laser or modulator

%% DAC
Tx.DAC.fs = sim.ros.txDSP*mpam.Rs; % DAC sampling rate
Tx.DAC.ros = sim.ros.txDSP; % oversampling ratio of transmitter DSP
Tx.DAC.resolution = Inf; % DAC effective resolution in bits
Tx.DAC.filt = design_filter('bessel', 1, 0.5*Tx.DAC.fs/(sim.fs/2)); % DAC analog frequency response

%% Laser
% Laser constructor: laser(lambda (nm), PdBm (dBm), RIN (dB/Hz), linewidth (Hz), frequency offset (Hz))
% lambda : wavelength (nm)
% PdBm : output power (dBm)
% RIN : relative intensity noise (dB/Hz)
% linewidth : laser linewidth (Hz)
% freqOffset : frequency offset with respect to wavelength (Hz)
Tx.Laser = laser(1550e-9, 0, -150, 0.2e6, 0);

%% Modulator
Tx.Mod.type = sim.Modulator;    
Tx.Mod.BW = 30e9;
Tx.Mod.fc = Tx.Mod.BW/sqrt(sqrt(2)-1); % converts to relaxation frequency
Tx.Mod.grpdelay = 2/(2*pi*Tx.Mod.fc);  % group delay of second-order filter in seconds
Tx.Mod.Vbias = 0.5; % bias voltage normalized by Vpi/2
Tx.Mod.Vswing = 1;  % normalized voltage swing. 1 means that modulator is driven at full scale from -Vpi/2 to Vpi/2
Tx.Mod.H = exp(1j*2*pi*f*Tx.Mod.grpdelay)./(1 + 2*1j*f/Tx.Mod.fc - (f/Tx.Mod.fc).^2);  % laser freq. resp. (unitless) f is frequency vector (Hz)

%% Fiber
% fiber(Length in m, anonymous function for attenuation versus wavelength
% (default: att(lamb) = 0 i.e., no attenuation), anonymous function for 
% dispersion versus wavelength (default: SMF28 with lamb0 = 1310nm, S0 = 0.092 s/(nm^2.km))
SMF = fiber(80e3); 
DCF = fiber(32.5e3, @(lamb) 0, @(lamb) -0.1*(lamb-1550e-9)*1e3 - 40e-6); 

Fibers = [SMF DCF];

%% Amplifier
% Class SOA characterizes amplifier in terms of gain and noise figure
% soa(GaindB: amplifier gain in dB, NFdB: noise figure in dB, lambda: operationa wavelength, maxGaindB: maximum amplifier gain)
EDFA = soa(20, 5, 1550e-9, 20); 

%% Photodiode
% pin(R: Responsivity (A/W), Id: Dark current (A), BW: bandwidth (Hz))
% PIN frequency response is modeled as a first-order system
Rx.PD = pin(1, 10e-9, Inf);

%% Receiver
% One-sided thermal noise PSD
Rx.N0 = (30e-12).^2; 

% Optical Bandpass Filter (fiber Brag gratting)
Rx.optfilt = design_filter('fbg', 4, 200e9/(sim.fs/2));

Rx.filtering = 'antialiasing'; % {'antialiasing' or 'matched'}

%% ADC
Rx.ADC.ros = sim.ros.rxDSP;
Rx.ADC.fs = Rx.ADC.ros*mpam.Rs;
Rx.ADC.filt = design_filter('butter', 5, 0.5*Rx.ADC.fs/(sim.fs/2)); % Antialiasing filter
Rx.ADC.ENOB = 4; % effective number of bits. Quantization is only included if sim.quantiz = true and ENOB ~= Inf
Rx.ADC.rclip = 0;

%% Equalizer
% Terminology: TD = time domain, SR = symbol-rate, LE = linear equalizer

% Rx.eq.type = 'None';
Rx.eq.ros = sim.ros.rxDSP;
Rx.eq.type = 'Adaptive TD-LE';
% Rx.eq.type = 'Fixed TD-SR-LE';
Rx.eq.Ntaps = 7;
Rx.eq.mu = 1e-2;
Rx.eq.Ntrain = 0.5e4; % Number of symbols used in training (if Inf all symbols are used)
Rx.eq.Ndiscard = [1e4 512]; % symbols to be discard from begining and end of sequence due to adaptation, filter length, etc
% Rx.elefilt = design_filter('matched', mpam.pshape, 1/sim.Mct);

% % Calculate KLSE in the frequency domain
% % [D_freq, Phi_freq, Fmax_freq] = klse_freq(rx, sim);
% % 
% % KLSE Fourier Series Expansion 
% % [Rx.U_fourier, Rx.D_fourier, Rx.Fmax_fourier] = klse_fourier(rx, sim, sim.Mct*(mpam.M^sim.L + 2*sim.L)); 
% % 
% % if sim.verbose
% %     figure, hold on
% %     plot(sim.f/1e9, abs(Rx.elefilt.H(sim.f/sim.fs)).^2)
% %     plot(sim.f/1e9, abs(Rx.optfilt.H(sim.f/sim.fs)).^2)
% %     legend('electrical', 'optical')
% %     xlabel('Frequency (GHz)')
% %     ylabel('|H(f)|^2')
% %     grid on
% % end

%% Generate summary
generate_summary(mpam, Tx, Fibers, EDFA, Rx, sim);

%% Run simulation
ber = preamplified_sys_ber(mpam, Tx, Fibers, EDFA, Rx, sim);