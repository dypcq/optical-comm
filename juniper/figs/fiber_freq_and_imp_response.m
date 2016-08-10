%% Chirped fiber IM-DD frequency response
clear, clc, close all

addpath ../../f

f = linspace(0, 50, 1e3)*1e9;
lambda = 1550e-9;
alpha = 2;

Fiber = fiber(10e3);

figure, hold on, box on
plot(f/1e9, abs(Fiber.Himdd(f, lambda, 0, 'large signal')).^2, 'LineWidth', 2)
plot(f/1e9, abs(Fiber.Himdd(f, lambda, -1, 'large signal')).^2, 'LineWidth', 2)
plot(f/1e9, abs(Fiber.Himdd(f, lambda, -2, 'large signal')).^2, 'LineWidth', 2)
plot(f/1e9, abs(Fiber.Himdd(f, lambda, -3, 'large signal')).^2, 'LineWidth', 2)
plot(f/1e9, abs(Fiber.Himdd(f, lambda, -4, 'large signal')).^2, 'LineWidth', 2)
xlabel('Frequency (GHz)', 'FontSize', 12)
ylabel('|H_{IM-DD}(f)|^2', 'FontSize', 12)
leg = legend('\alpha = 0', '-1', '-2', '-3', '-4');
set(leg, 'FontSize', 12);
set(gca, 'FontSize', 12)
title(sprintf('Large-signal IM-DD frequency response for L = %.2f km', Fiber.L/1e3))
saveas(gca, sprintf('Hfiber_large_signal_L=%dkm.png', Fiber.L/1e3))


figure, hold on, box on
plot(f/1e9, abs(Fiber.Himdd(f, lambda, 0, 'small signal')).^2, 'LineWidth', 2)
plot(f/1e9, abs(Fiber.Himdd(f, lambda, -1, 'small signal')).^2, 'LineWidth', 2)
plot(f/1e9, abs(Fiber.Himdd(f, lambda, -2, 'small signal')).^2, 'LineWidth', 2)
plot(f/1e9, abs(Fiber.Himdd(f, lambda, -3, 'small signal')).^2, 'LineWidth', 2)
plot(f/1e9, abs(Fiber.Himdd(f, lambda, -4, 'small signal')).^2, 'LineWidth', 2)
xlabel('Frequency (GHz)', 'FontSize', 12)
ylabel('|H_{IM-DD}(f)|^2', 'FontSize', 12)
leg = legend('\alpha = 0', '-1', '-2', '-3', '-4');
set(leg, 'FontSize', 12);
set(gca, 'FontSize', 12)
title(sprintf('Small-signal IM-DD frequency response for L = %.2f km', Fiber.L/1e3))
saveas(gca, sprintf('Hfiber_small_signal_L=%dkm.png', Fiber.L/1e3))


figure, hold on, box on
Fiber = fiber((20/17)*1e3);
plot(f/1e9, abs(Fiber.Himdd(f, lambda, 0, 'large signal')).^2, 'LineWidth', 4)
Fiber = fiber(2*(20/17)*1e3);
plot(f/1e9, abs(Fiber.Himdd(f, lambda, 0, 'large signal')).^2, 'LineWidth', 4)
Fiber = fiber(5*(20/17)*1e3);
plot(f/1e9, abs(Fiber.Himdd(f, lambda, 0, 'large signal')).^2, 'LineWidth', 4)
xlabel('Frequency (GHz)', 'FontSize', 18)
ylabel('|H_{IM-DD}(f)|^2', 'FontSize', 18)
legend('20 ps/nm', '40 ps/nm', '100 ps/nm', 'Location', 'SouthWest')
set(gca, 'FontSize', 18)


figure, hold on, box on
t = linspace(-0.1e-9, 0.1e-9, 1e3);
plot(t*1e9, real(Fiber.hdisp(t, lambda)), 'LineWidth', 4)
plot(t*1e9, -imag(Fiber.hdisp(t, lambda)), 'LineWidth', 4)
xlabel('Time (ns)', 'FontSize', 18)
ylabel('Impulse response')
legend('Filter 1', 'Filter 2')
set(gca, 'ytick', []);
set(gca, 'FontSize', 18)
grid on