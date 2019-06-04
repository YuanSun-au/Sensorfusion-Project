function [xhat, meas] = filterTemplate9(calAcc, calGyr, calMag)
% FILTERTEMPLATE  Filter template
%
% This is a template function for how to collect and filter data
% sent from a smartphone live.  Calibration data for the
% accelerometer, gyroscope and magnetometer assumed available as
% structs with fields m (mean) and R (variance).
%
% The function returns xhat as an array of structs comprising t
% (timestamp), x (state), and P (state covariance) for each
% timestamp, and meas an array of structs comprising t (timestamp),
% acc (accelerometer measurements), gyr (gyroscope measurements),
% mag (magnetometer measurements), and orint (orientation quaternions
% from the phone).  Measurements not availabe are marked with NaNs.
%
% As you implement your own orientation estimate, it will be
% visualized in a simple illustration.  If the orientation estimate
% is checked in the Sensor Fusion app, it will be displayed in a
% separate view.
%
% Note that it is not necessary to provide inputs (calAcc, calGyr, calMag).

  %% Setup necessary infrastructure
  import('com.liu.sensordata.*');  % Used to receive data.

  %% Filter settings
  t0 = [];  % Initial time (initialize on first data received)
  nx = 4;   % Assuming that you use q as state variable.
  
  % Add your filter settings here.
  %Old Q4
%   Rw = 1.0e-06.*diag([0.3134,0.2919,0.5301]);
%   Ra = 1.0e-03.*diag([0.3052,0.2217,0.1234]);
%   g0 = [0.0657;-0.1461;9.9522];
%   outlier_rejection_factor = 0.35;
%   Rm = diag([0.2075 0.1622 0.2881]);
%   mean_mag = [41.5659;-4.2069;-41.2221];
%   m0 = [0; sqrt(mean_mag(1)^2+mean_mag(2)^2); mean_mag(3)];
%   L = norm(m0);
%   alpha = 0.01;
%   accOut=1;
%   magOut=1;
  
    %New Q2
  Rw = 1.0e-06.*diag([0.4318,0.8781,0.2957]);
  Ra = 1.0e-03.*diag([0.1431,0.2136,0.1694]);
  g0 = [0.1489;0.1067;9.8363];
  outlier_rejection_factor = 0.1;
  Rm = diag([0.1894;0.1714;0.1826]);
  mean_mag = [7.8887;1.4198;-44.4954];
  m0 = [0; sqrt(mean_mag(1)^2+mean_mag(2)^2); mean_mag(3)];
  L = norm(m0);
  alpha = 0.01;
  accOut=1;
  magOut=1;
  
  % Current filter state.
  x = [1; 0; 0 ;0];
  P = eye(nx, nx);

  % Saved filter states.
  xhat = struct('t', zeros(1, 0),...
                'x', zeros(nx, 0),...
                'P', zeros(nx, nx, 0));

  meas = struct('t', zeros(1, 0),...
                'acc', zeros(3, 0),...
                'gyr', zeros(3, 0),...
                'mag', zeros(3, 0),...
                'orient', zeros(4, 0));
  try
    %% Create data link
    server = StreamSensorDataReader(3400);
    % Makes sure to resources are returned.
    sentinel = onCleanup(@() server.stop());

    server.start();  % Start data reception.

    % Used for visualization.
    figure(1);
    subplot(1, 2, 1);
    ownView = OrientationView('Own filter', gca);  % Used for visualization.
    googleView = [];
    counter = 0;  % Used to throttle the displayed frame rate.

    %% Filter loop
    while server.status()  % Repeat while data is available
      % Get the next measurement set, assume all measurements
      % within the next 5 ms are concurrent (suitable for sampling
      % in 100Hz).
      data = server.getNext(5);

      if isnan(data(1))  % No new data received
        continue;        % Skips the rest of the look
      end
      t = data(1)/1000;  % Extract current time

      if isempty(t0)  % Initialize t0
        t0 = t;
      end

      acc = data(1, 2:4)';
      if ~any(isnan(acc)) 
         if norm(acc)<norm(g0)*(1+outlier_rejection_factor) && norm(acc)>norm(g0)*(1-outlier_rejection_factor)  % Acc measurements are available and checking the norm of the accelerometer measurements.
            [x, P] = mu_g(x, P, acc, Ra, g0);
            accOut = 0;
         else
            accOut = 1;
         end
       end
      
      gyr = data(1, 5:7)';
      if ~any(isnan(gyr))  % Gyro measurements are available.
          [x, P] = tu_qw(x, P, gyr, t-t0-meas.t(end), Rw); 
          [x, P] = mu_normalizeQ(x,P);
      else
            P= randomWalk(P);
      end

      mag = data(1, 8:10)';
      if ~any(isnan(mag))  % Mag measurements are available.
            L = (1-alpha)*L+alpha*norm(mag); %AR(1)-filter
            if L>30 && L<60 
            [x, P] = mu_m(x, P, mag, m0, Rm);
            [x, P] = mu_normalizeQ(x,P);
            magOut =0;
            else 
            magOut = 1;
            end
       end

      orientation = data(1, 18:21)';  % Google's orientation estimate.

      % Visualize result
      if rem(counter, 10) == 0
        setOrientation(ownView, x(1:4));
        ownView.setAccDist(accOut);
        ownView.setMagDist(magOut); 
        title(ownView, 'OWN', 'FontSize', 16);
        if ~any(isnan(orientation))
          if isempty(googleView)
            subplot(1, 2, 2);
            % Used for visualization.
            googleView = OrientationView('Google filter', gca);
          end
          setOrientation(googleView, orientation);
          title(googleView, 'GOOGLE', 'FontSize', 16);
        end
      end
      counter = counter + 1;

      % Save estimates
      xhat.x(:, end+1) = x;
      xhat.P(:, :, end+1) = P;
      xhat.t(end+1) = t - t0;

      meas.t(end+1) = t - t0;
      meas.acc(:, end+1) = acc;
      meas.gyr(:, end+1) = gyr;
      meas.mag(:, end+1) = mag;
      meas.orient(:, end+1) = orientation;
    end
  catch e
    fprintf(['Unsuccessful connecting to client!\n' ...
      'Make sure to start streaming from the phone *after*'...
             'running this function!']);
  end
end
