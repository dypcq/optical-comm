%% Test pulse shaping and DAC
clear, clc

addpath f/ % Juniper project specific functions
addpath ../mpam % PAM
addpath ../f % general functions
addpath ../soa % for pre-amplifier 
addpath ../apd % for PIN photodetectors

%% Simulation parameters
sim.Rb = 56e9;    % bit rate in bits/sec
sim.Nsymb = 10; % Number of symbols in montecarlo simulation
sim.ros.txDSP = 4; % oversampling ratio transmitter DSP (must be integer). DAC samping rate is sim.ros.txDSP*mpam.Rs
% For DACless simulation must make Tx.dsp.ros = sim.Mct and DAC.resolution = Inf
sim.ros.rxDSP = 2; % oversampling ratio of receiver DSP. If equalization type is fixed time-domain equalizer, then ros = 1
sim.Mct = 12;      % Oversampling ratio to simulate continuous time. Must be integer multiple of DAC.ros
sim.N = sim.Nsymb*sim.Mct;
sim.shouldPlot = @(x) false;

%% Pulse shape
pulse_shape.type = 'rc'; % either 'rect', 'rrc', or 'rc'
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

%%% Generate signal
dataTX = randi([0 mpam.M-1], 1, sim.Nsymb); % Random sequence
dataTX = [0 0 0 0 0 1 0 0 0 0];
xd = mpam.signal(dataTX); % Generates signal at the DAC sampling rate

%% DAC
Tx.DAC.fs = sim.ros.txDSP*mpam.Rs; % DAC sampling rate
Tx.DAC.ros = sim.ros.txDSP; % oversampling ratio of transmitter DSP
Tx.DAC.resolution = Inf; % DAC effective resolution in bits
Tx.DAC.filt = design_filter('butter', 5, (Tx.DAC.fs/2)/(sim.fs/2)); % DAC analog frequency response

% Driving signal xd must be normalized by Vpi
[xt, xzoh] = dac(xd, Tx.DAC, sim);
% DAC response preserves amplitude of xd, hence no

%% Pulse shaping
% Note: the order of pulse shaping and DAC is interchanged just to make
% pulse shapping operation easier. Essentially, this way we're doing pulse
% shaping filtering after upsampling and ZOH. All those operations are
% linear, so the two systems are equivalent.
if strcmpi(Tx.pulse_shape.type, 'rect') % if rectangular just calculates transfer function
    Hpshape = freqz(ones(1, sim.Mct)/sim.Mct, 1, f)...
    .*exp(1j*2*pi*f*(sim.Mct-1)/2);
else
    Hpshape = freqz(Tx.pulse_shape.h/abs(std(Tx.pulse_shape.h)), 1, sim.f, Tx.DAC.fs)...
        .*exp(1j*(2*pi*sim.f/Tx.DAC.fs*((length(Tx.pulse_shape.h)-1)/2) + 0*2*pi*sim.f/sim.fs)); % remove group delay /abs(sum(Tx.pulse_shape.h))
    
    xt = real(ifft(fft(xt).*ifftshift(Hpshape)));
end

figure(1), hold on
plot(sim.t, xt)
plot(sim.t, xzoh)


var(xt)
