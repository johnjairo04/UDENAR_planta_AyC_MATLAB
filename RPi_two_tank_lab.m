classdef RPi_two_tank_lab<handle
    properties (Access=private)
        % Raspberry pi
        ip % raspberry pi ip address
        username % raspberry pi username
        password % raspberry pi password
        myraspi % raspberry pi object

        % Timers
        Timer % timer for reading system variables
        Timer2 % timer for checking user connection

        % Control panel
        StartReg = 1025 % register for START button
        StopReg = 1026 % register for STOP button
        EmergReg = 1027 % register for EMERGENCY button

        % Communication
        serialPort3 = 'COM4' % serial port to notify raspberry pi availability
        serialDevice3 % serial port object
        tcpPortInit = 30000 % tcp port for receiving client's commands (RPi connection)
        tcpServerInit % tcp server object
        tcpPort1 = 31000 % tcp port for receiving client's commands (PLC program)
        tcpServer1 % tcp server object
        tcpPort2 = 5555 % tcp port for monitoring system variables
        tcpServer2 % tcp server object
        modbusPort = 502 % modbus port to get/send data (PLC program)
        modbusAddress % modbus server address (same as raspberry pi's)
        modbusServer % modbus server object

        % User management
        userTimeOut = 3*60; % time out (seconds) to disconnect inactive users

        % OpenPLC filename
        PLCfilename = '329424.st'
    end
    properties (Access=public)
        data_array = zeros(9, 10000); % array for storing system variables
        count = 1 % number of readings made
        PLCRunning = 0; % '1' if PLC program is running
        dataSize = 5 % number of readings to be made before updating GUI
    end
    methods
        %% Class constructor
        function obj = RPi_two_tank_lab(ip, username, password)
            % Raspberry Pi parameters
            obj.ip = ip;
            obj.username = username;
            obj.password = password;
            obj.modbusAddress = ip;
            % Create and set up TCP servers
            obj.tcpServerInit = tcpserver('0.0.0.0', obj.tcpPortInit);
            configureCallback(obj.tcpServerInit, 'byte', 1,...
                @obj.readTCPClientCommand);
            obj.tcpServer2 = tcpserver('0.0.0.0', obj.tcpPort2);
            configureCallback(obj.tcpServer2, 'byte', 1, ...
                @obj.readControlVariables);
            obj.tcpServer1 = tcpserver('0.0.0.0', obj.tcpPort1);
            configureTerminator(obj.tcpServer1, 'LF');
            configureCallback(obj.tcpServer1, 'byte', 3, ...
                @obj.readTCPCommandsPLC);
            % Create serial ports
            obj.serialDevice3 = serialport(obj.serialPort3, 921600);
            configureTerminator(obj.serialDevice3, 'LF');
            % Create timers
            obj.Timer = timer(...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', 0.05,... % system variables sampling frequency
                'StartDelay', 0.05,...
                'BusyMode', 'drop',...
                'TimerFcn', @obj.TimerFcn,...
                'ErrorFcn',@obj.TimerErrorFcn);
            stop(obj.Timer);
            obj.Timer2 = timer( ...
                'ExecutionMode', 'singleShot', ...
                'StartDelay', obj.userTimeOut, ...
                'BusyMode', 'queue', ...
                'TimerFcn', @obj.Timer2Fcn);
            stop(obj.Timer2);
        end
        %% Class methods
        % TCP communication
        function obj = readTCPClientCommand(obj, src, ~)
            % Read TCP client commands
            if src.NumBytesAvailable>0
                msg = readline(src);
                obj = obj.processTCPClientCommand(msg);
            end
        end
        function obj = processTCPClientCommand(obj, msg)
            % Process TCP client commands
            msg = split(msg, '|');
            command = msg{1};
            userID = msg{2};
            display(userID);
            log = load('user.mat'); % load log file
            user = log.user; % get user ID and status
            switch command
                % Check if a user is already connected
                case 'check'
                % Connect to raspberry pi
                case 'connect'
                    obj.count = 1; % reset counter
                    obj.data_array = zeros(9, 10000); % reset data array
                    [obj, user.Status] = obj.connectRPi();
                    user.ID = userID;
                    % Notifies raspberry pi availability to each user
                    write(obj.serialDevice3, [user.Status, '|', user.ID], 'char');
                    % Start timer for checking user connection
                    start(obj.Timer2);
                    % save log file
                    save('user.mat', 'user');
                % Disconnect raspberry pi
                case 'disconnect'
                    [obj, user.Status] = obj.disconnectRPi();
                    user.ID = '-';
                    write(obj.serialDevice3, [user.Status, '|', user.ID], 'char');
                    % Stop timer for checking user connection
                    stop(obj.Timer2);
                    % savel log file
                    save('user.mat', 'user');
            end
            % Send reply to tcp client
            writeline(obj.tcpServerInit, user.Status);
        end
        function obj = readControlVariables(obj, src, ~)
            % Read control variables sent by user. Then resend them to the
            % raspberry pi
            if strcmp(obj.Timer.Running, 'on')
                stop(obj.Timer);
            end
            try
                if src.NumBytesAvailable==3
                    msg = read(src, 3, 'uint8');
                    write(obj.modbusServer, 'holdingregs', obj.StartReg, msg, 'uint16');
                end
            catch
                
            end
            if strcmp(obj.Timer.Running, 'off')
                start(obj.Timer); 
            end
        end
        function readTCPCommandsPLC(obj, src, ~)
            % Read user commands
            try
                if src.NumBytesAvailable>0
                    msg = read(src, src.NumBytesAvailable, 'char');
                    display(msg);
                    obj.processTCPCommands(msg);
                end
            catch
                return
            end
        end
        function processTCPCommands(obj, msg)
            msg = split(msg, '|');
            command = msg{1};
            path = msg{2};
            % Process serial commands
            switch command
                case 'running'
                    %start(obj.Timer);
                % Start PLC program
                case 'start'
                    try
                        obj.count = 1; % reset counter
                        obj.data_array = zeros(9, 10000); % reset data array
                        % start OpenPLC
                        system(obj.myraspi, 'sudo systemctl start openplc');
                        % Create modbus server object
                        %obj.modbusServer = modbus('tcpip', obj.modbusAddress, obj.modbusPort);
                        obj.PLCRunning = 1;
                        % Send confirmation to user
                        writeline(obj.tcpServer1, '1');
                    catch me
                        display(me.message);
                        write(obj.tcpServer1, '0', 'char');
                    end
                % Stop PLC program
                case 'stop'
                    try 
                        stop(obj.Timer);
                        pause(0.1);
                        system(obj.myraspi, 'sudo systemctl stop openplc');
                        obj.modbusServer = [];
                        pause(0.1);
                        obj.PLCRunning = 0;
                        writematrix(obj.data_array(:, 1:obj.count)', strcat(path, '\', 'results.xlsx'));
                        writeline(obj.tcpServer1, '0');
                    catch me
                        display(me.message);
                        writeline(obj.tcpServer1, '1');
                    end
                % User connection notification
                case 'connected'
                    display('Restarting timer');
                    % Restart timer for checking user connection
                    stop(obj.Timer2);
                    start(obj.Timer2);
                % Send PLC program file to raspberry pi
                otherwise
                    if strcmp(path(1:end-1), obj.PLCfilename) % Check that PLC program name is correct
                        try
                            system(obj.myraspi, 'sudo systemctl stop openplc');
                            display('sending PLC program...');
                            system(obj.myraspi, strcat('rm OpenPLC_v3/webserver/st_files/', obj.PLCfilename));
                            putFile(obj.myraspi, command, '/home/cnn/OpenPLC_v3/webserver/st_files');
                            compile_command = strcat('(cd OpenPLC_v3/webserver/scripts/ ; sh compile_program.sh', {' '}, obj.PLCfilename, ')');
                            display(compile_command{1});
                            system(obj.myraspi, compile_command{1});
                            writeline(obj.tcpServer1, '1');
                        catch me
                            display(me.message);
                            writeline(obj.tcpServer1, '0');
                        end
                    else
                        display('Incorrect filename');
                        writeline(obj.tcpServer1, '0');
                    end
            end
        end
        %% RPi connection
        function [obj, connected] = connectRPi(obj)
            % Create connection with the raspberry pi
            connected = '0';
            try
                obj.myraspi = raspi(obj.ip, obj.username, obj.password);
                connected = '1';
            catch
                return
            end
        end
        function [obj, connected] = disconnectRPi(obj)
            % Close connection with the raspberry pi
            obj.myraspi = [];
            connected = '0';
        end
        %% Timer functions
        function obj = TimerFcn(obj, timer, ~)
            % Read system variables periodically
            act_values = read(obj.modbusServer, 'coils', 5, 5); % system variables
            i2c_values = read(obj.modbusServer, 'inputregs', 1, 4)/100;
            % Store system variables
            obj.data_array(:, obj.count) = [act_values'; i2c_values'];
            % Send variables to user after 2 consecutive readings
            try
            if mod(obj.count, obj.dataSize)==0
                write(obj.tcpServer2, reshape(obj.data_array(:, obj.count-(obj.dataSize-1):obj.count), 1, []), 'double');
                %write(obj.tcpServer2, [flip(obj.data_array(1, obj.count-(obj.dataSize-1):obj.count)), ...
                %    flip(obj.data_array(3, obj.count-(obj.dataSize-1):obj.count))], 'double');
            end
            catch
                
            end
            obj.count = obj.count+1;
        end
        function obj=TimerErrorFcn(obj, timer, ~)
            display('Timer error');
            if strcmp(class(obj.modbusServer), 'double')
                stop(obj.Timer);
                return;
            end
            start(obj.Timer);
        end
        function obj = Timer2Fcn(obj, ~, ~)
            % Stop PLC program and disconnects RPi when user is no longer active
            display('User disconnected');
            stop(obj.Timer2);
            if obj.PLCRunning
                stop(obj.Timer);
                system(obj.myraspi, 'sudo systemctl stop openplc');
            end
            obj.PLCRunning = 0;
            obj.modbusServer = [];
            [obj, user.Status] = obj.disconnectRPi();
            user.ID = '-';
            write(obj.serialDevice3, [user.Status, '|', user.ID], 'char');
            save('user.mat', 'user'); % save log file
        end
    end
end