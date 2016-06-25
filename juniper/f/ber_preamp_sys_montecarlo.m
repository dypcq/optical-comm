function [ber_count, ber_awgn] = ber_preamp_sys_montecarlo(mpam, Tx, Fibers, Amp, Rx, sim)
%% Calculate BER of pre-amplified IM-DD system through montecarlo simulation
% Inputs:
% - mpam: PAM class
% - Tx: struct with transmitter paramters
% - Fibers: array of Fiber classes containing the fibers used in
% transmittion i.e., Fibers = [SMF DCF] or Fibers = [SMF];
% - Amp: pre-amplifier using SOA class
% - Rx: struct with receiver parameters
% - sim: struct with simulation parameters

% Normalized frequency
f = sim.f/sim.fs;

% ZOH and DAC frequency response
Nhold = sim.Mct/Tx.DAC.ros;
hZOH = 1/Nhold*ones(1, Nhold);
Hdac = Tx.DAC.filt.H(f).*freqz(hZOH, 1, f)...
    .*exp(1j*2*pi*f*(Nhold-1)/2);

% Modulator frequency response
if isfield(Tx, 'Mod')
    Hmod = Tx.Mod.H; % group delay was already removed
else
    Hmod = 1;
end

% Photodiode frequency response
Hpd = Rx.PD.H(sim.f);

% Channel frequency response
Hch = Hdac.*Hmod.*Hpd;

% Ajust levels to desired transmitted power and extinction ratio
mpam = mpam.adjust_levels(Tx.Ptx, Tx.rexdB);
mpam = mpam.norm_levels();

% Modulated PAM signal
dataTX = randi([0 mpam.M-1], 1, sim.Nsymb); % Random sequence
xd = mpam.signal(dataTX); % Generates signal at the DAC sampling rate

% Predistortion to compensate for MZM non-linear response
assert(Tx.Mod.Vbias >= Tx.Mod.Vswing/2, 'ber_preamp_sys_montecarlo: Vbias must be greater or equal than Vswing/2')
xd = xd - mean(xd); % Remove DC bias, since modulator is IM-MZM
xd = Tx.Mod.Vswing/2*xd/max(abs(xd)) + Tx.Mod.Vbias; % Normalized to have excursion from approx +-Vswing 
% Note: Vswing and Vswing and Vbias are normalized by Vpi/2. This scaling
% and offset is done before the DAC in order to have right pre-distortion
% function, and not to have the right voltage values that will drive the
% modulator

xd = 2/pi*asin(sqrt(xd)); % apply predistortion

% DAC
% Driving signal xd must be normalized by Vpi
xt = dac(xd, Tx.DAC, sim);
% DAC response preserves amplitude of xd, hence no 

% Pulse shaping
% Note: the order of pulse shaping and DAC is interchanged just to make
% pulse shapping operation easier. Essentially, this way we're doing pulse
% shaping filtering after upsampling and ZOH. All those operations are
% linear, so the two systems are equivalent.
if strcmpi(Tx.pulse_shape.type, 'rect') % if rectangular just calculates transfer function
    Hpshape = freqz(ones(1, sim.Mct)/sim.Mct, 1, f)...
    .*exp(1j*2*pi*f*(sim.Mct-1)/2);
else
    Hpshape = freqz(Tx.pulse_shape.h/abs(sum(Tx.pulse_shape.h)), 1, sim.f, Tx.DAC.fs)...
        .*exp(1j*2*pi*sim.f/Tx.DAC.fs*(length(Tx.pulse_shape.h)-1)/2); % remove group delay
    
    xt = real(ifft(fft(xt).*ifftshift(Hpshape)));
end

% Discard first and last symbols
xt(1:sim.Mct*sim.Ndiscard) = 0; % zero sim.Ndiscard first symbols
xt(end-sim.Mct*sim.Ndiscard+1:end) = 0; % zero sim.Ndiscard last symbbols

% Generate optical signal
Tx.Laser.PdBm = Watt2dBm(Tx.Ptx);
Ecw = Tx.Laser.cw(sim);
Etx = mzm(Ecw, xt, Tx.Mod);

% Adjust power to make sure desired power is transmitted
Etx = Etx*sqrt(Tx.Ptx/mean(abs(Etx).^2));

% Fiber propagation
Erx = Etx;
link_gain = Amp.Gain*Rx.PD.R;
for k = 1:length(Fibers)
    fiberk = Fibers(k);
   
    Hch = Hch.*fiberk.Himdd(sim.f, Tx.Laser.wavelength, Tx.alpha, 'large signal'); % frequency response of the channel (used in designing the equalizer)
    
    Erx = fiberk.linear_propagation(Erx, sim.f, Tx.Laser.wavelength); % propagation through kth fiber in Fibers
    
    link_gain = link_gain*fiberk.link_attenuation(Tx.Laser.wavelength);
end

% Amplifier
Erx = Amp.amp(Erx, sim.fs);

% Optical bandpass filter
Hopt = ifftshift(Rx.optfilt.H(f));
Erx = [ifft(fft(Erx(1, :)).*Hopt);...
    ifft(fft(Erx(2, :)).*Hopt)];

% Direct detection and add thermal noise
% PD.detect(Ein: Input electric field, fs: sampling rate of samples in Ein,
% noise statistics {'gaussian', 'no noise'}, N0: one-sided PSD of thermal
% noise)
yt = Rx.PD.detect(Erx, sim.fs, 'gaussian', Rx.N0);

% Automatic gain control
mpam = mpam.norm_levels();
yt = yt - mean(yt);
yt = yt*sqrt(var(mpam.a)/(sqrt(2)*mean(abs(yt(sim.Mct/2:sim.Mct:end).^2))));
yt = yt + mean(mpam.a);

% ADC
% ADC performs filtering, quantization, and downsampling
% For an ideal ADC, ADC.ENOB = Inf
switch lower(Rx.filtering)
    case 'antialiasing' % receiver filter is specified in ADC.filt
        Hrx = Rx.ADC.filt.H(f);
        [yk, ~, ytf] = adc(yt, Rx.ADC, sim);
    case 'matched' % receiver filter is matched filter
        Hrx = conj(Hch);
        [yk, ~, ytf] = adc(yt, Rx.ADC, sim, Hrx);
    otherwise
        error('ber_preamp_sys_montecarlo: Rx.filtering must be either antialiasing or matched')
end     

Hch = Hch.*Hrx;

% Equalization
Rx.eq.trainSeq = dataTX;
[yd, Rx.eq] = equalize(Rx.eq, yk, Hch, mpam, sim);

% Symbols to be discard in BER calculation
ndiscard = [1:Rx.eq.Ndiscard(1)+sim.Ndiscard (sim.Nsymb-Rx.eq.Ndiscard(2)-sim.Ndiscard):sim.Nsymb];
yd(ndiscard) = []; 
dataTX(ndiscard) = [];

% Demodulate
dataRX = mpam.demod(yd.');

% Counted BER
[~, ber_count] = biterr(dataRX, dataTX);

%% AWGN approximation
% Note: this calculation includes noise enhancement due to equalization,
% but dominant noise in pre-amplified system is the signal-spontaneous beat
% noise, which is not Gaussian distributed

% Noise bandwidth
if isfield(Rx, 'eq')
    % Normalize to have unit gain at DC
    H2 = abs(Hrx.*Rx.eq.Hff(sim.f/(mpam.Rs*Rx.eq.ros))).^2; 
    H2 = H2/interp1(sim.f, H2, 0);
    noiseBW = trapz(sim.f, H2)/2;
else 
    noiseBW = mpam.Rs/2;
end
fprintf('Noise bandwidth = %.2f GHz\n', noiseBW/1e9);

BWopt = Rx.optfilt.noisebw(sim.fs); % optical filter noise bandwidth; Not divided by 2 because optical filter is a bandpass filter

% Thermal noise
varTherm = Rx.N0*noiseBW; % variance of thermal noise

% RIN
if isfield(sim, 'RIN') && sim.RIN
    varRIN =  @(Plevel) 10^(Tx.Laser.RIN/10)*Plevel.^2*noiseBW;
else
    varRIN = @(Plevel) 0;
end

% Noise std for intensity level Plevel
Npol = 2; % number of polarizations. Npol = 1, if polarizer is present, Npol = 2 otherwise.
noise_std = @(Plevel) sqrt(varTherm + Rx.PD.varShot(Plevel, noiseBW) + Rx.PD.R^2*varRIN(Plevel)...
    + Rx.PD.R^2*Amp.var_awgn(Plevel/Amp.Gain, noiseBW, BWopt, Npol));
% Note: Plevel is divided by amplifier gain to obtain power at the amplifier input

% AWGN approximation
mpam = mpam.adjust_levels(Tx.Ptx*link_gain, Tx.rexdB);

ber_awgn = mpam.berAWGN(noise_std);

%% Plots
if sim.shouldPlot('Equalizer')
    figure(101)
    for k = 1:size(Rx.eq.h, 2)
        [h, w] = freqz(Rx.eq.h(:, k), 1);
        subplot(121), hold on, box on
        plot(w/(2*pi), abs(h).^2)
        
        subplot(122), hold on, box on
        plot(w/(2*pi), unwrap(angle(h)))
        
        subplot(121), hold on, box on
        xlabel('Normalized frequency')
        ylabel('|H(f)|^2')
        
        subplot(122), hold on, box on
        xlabel('Normalized frequency')
        ylabel('arg(H(f))')
    end
    drawnow
end

if sim.shouldPlot('Optical eye diagram')  
    Ntraces = 500;
    Nstart = sim.Ndiscard*sim.Mct + 1;
    Nend = min(Nstart + Ntraces*2*sim.Mct, length(Etx));
    figure(103), clf, box on
    eyediagram(abs(Etx(Nstart:Nend)).^2, 2*sim.Mct)
    title('Optical eye diagram')
    drawnow
end

if sim.shouldPlot('Received signal eye diagram')
    mpam = mpam.norm_levels();
    Ntraces = 500;
    Nstart = sim.Ndiscard*sim.Mct + 1 - ceil((sim.Mct-1)/2);
    Nend = min(Nstart + Ntraces*2*sim.Mct, length(ytf));
    figure(104), clf, box on, hold on
    eyediagram(ytf(Nstart:Nend), 2*sim.Mct)
    title('Received signal eye diagram')
    a = axis;
    h1 = plot(a(1:2), mpam.a*[1 1], '-k');
    h2 = plot(a(1:2), mpam.b*[1 1], '--k');
    h3 = plot(ceil((sim.Mct-1)/2)*[1 1], a(3:4), 'k');
    legend([h1(1) h2(1) h3], {'Levels', 'Decision thresholds', 'Sampling point'})
    drawnow
end

if sim.shouldPlot('Signal after equalization')
    mpam = mpam.norm_levels();
    figure(105), clf, box on, hold on
    h1 = plot(yd, 'o');
    a = axis;
    h2= plot(a(1:2), mpam.a*[1 1], '-k');
    h3 = plot(a(1:2), mpam.b*[1 1], '--k');
    h4 = plot(Rx.eq.Ndiscard(1)*[1 1], a(3:4), ':k');
    h5 = plot((sim.Nsymb-Rx.eq.Ndiscard(2))*[1 1], a(3:4), ':k');
    legend([h1 h2(1) h3(1) h4], {'Equalized samples', 'PAM levels',...
        'Decision thresholds', 'BER measurement window'})
    title('Signal after equalization')
    drawnow
end

if sim.shouldPlot('Frequency response')
    fplot = sim.f(sim.f > 0)/1e9;
    vind = sim.f > 0;
    figure(107), clf, box on, hold on
    plot(fplot, abs(Hpshape(vind)).^2)
    plot(fplot, abs(Hdac(vind)).^2)
    plot(fplot, abs(Hmod(vind)).^2)
    plot(fplot, abs(Hrx(vind)).^2)
    xlabel('Frequency (GHz)')
    ylabel('|H(f)|^2')
    legend('Pulse shape', 'DAC', 'Modulator', 'Receiver filtering')
%     axis([0 2*mpam.Rs 0 1.2])
    drawnow
end

if sim.shouldPlot('Heuristic noise pdf')
    figure(106)
    [nn, xx] = hist(yd(dataTX == 2), 50);
    nn = nn/trapz(xx, nn);
    bar(xx, nn)
    drawnow
end
