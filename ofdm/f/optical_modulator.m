% 1. frequency response
% 2. Modulator nonlinearity (not implemented)
% 3. Corrects optical power according to target power and extinction ratio
% 4. Adds intensity noise (if sim.RIN = true)
% 5. Adds chirp if tx.alpha is defined

function [Et, Pt] = optical_modulator(xt, tx, sim)
    %% Apply frequency response of the modulator
    Hmod = tx.modulator.H(sim.f).*exp(1j*2*pi*sim.f*tx.modulator.grpdelay);
    Pt = tx.kappa*real(ifft(ifftshift(Hmod).*fft(xt)));  % Note: real() is used to remove residual imag
                                                % part that appears due to numerical error        

    %% Modulator Nonlinearity
    %## To be implemented
 
    rex = 10^(tx.rexdB/10);  % defined as Pmin/Pmax    
    
    Ptx  = mean(Pt);   % measured
    
    %% Adjust transmitted power
    if isfield(tx, 'Ptx') % if Ptx was provided, then scale signal to desired Ptx      
        % Scale and add additional dc bias due to finite extinction ratio
        Pt = Pt*tx.Ptx*(1 - 2*rex)/Ptx + 2*tx.Ptx*rex; 
    else % just add additional dc bias due to finite extinction ratio
        Pt = Pt + 2*Ptx*rex; 
    end

    %% Add intensity noise
    if sim.RIN
        % Calculate RIN PSD, which depends on the instantaneous power
        Srin = 10^(tx.RIN/10)*Pt.^2;

        % noise. Srin is two-sided psd
        wrin = sqrt(Srin.*sim.fs).*randn(size(Pt));
        
        Pt = Pt + wrin;
    end 
    
    % Ensures signal is non-negative
    Pt(Pt < 0) = 0;
    
    if isfield(tx, 'alpha')
        %% Add chirp
        % Calculate electric field including chirp
        dphi = tx.alpha/2*log(Pt);         % Phase variation due to chirp (only transient chirp is considered)

        Et = sqrt(Pt).*exp(1j*dphi);
    else
        Et = sqrt(Pt);
    end       
   
end