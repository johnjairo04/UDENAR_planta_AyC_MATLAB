classdef RPi_two_tank_lab<handle
    properties (Access=private)
        ip % ip address for raspberry pi
        username % raspberry pi username
        password % raspberry pi password
        myraspi % raspberry pi object
        Timer % timer for reading system variables
        Timer2 % timer for checking user connection
        StartReg = 1025 % register for START button
        StopReg = 1026 % register for STOP button
        EmergReg = 1027 % register for EMERGENCY button
        serialPort = 'COM2' % serial port for receiveng user commands 
        serialDevice % serial port object
        serialPort2 = 'COM3' % serial port for sending system variables/getting control commands
        serialDevice2 % serial port 2 object
        serialPort3 = 'COM4'
        serialDevice3 
        tcpPortInit = 30000
        tcpServerInit % tcp server object
        tcpPort1 = 31000
        tcpServer1
        tcpPort2 = 5555
        tcpServer2
        modbusPort = 502 % modbus port to get/send data to raspberry pi
        modbusAddress % modbus server address
        modbusServer % modbus server object
        userTimeOut = 60; % time out to disconnect inactive user
    end
    properties (Access=public)
        data_array = zeros(2, 10000); % array for storing system variables
        count = 1 % count for number readings of system variables
        PLCRunning = 0; % '1' if PLC program is running
        dataSize = 2
    end
    methods
        %% Class constructor
        function obj = RPi_two_tank_lab(ip, username, password)
            % RPi parameters
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

            % Create serial ports
            obj.tcpServer1 = tcpserver('0.0.0.0', obj.tcpPort1);
            configureTerminator(obj.tcpServer1, 'LF');
            configureCallback(obj.tcpServer1, 'byte', 3, ...
                @obj.readSerialCommand);
%             obj.serialDevice = serialport(obj.serialPort, 921600);
%             configureTerminator(obj.serialDevice, 'LF');
%             configureCallback(obj.serialDevice, 'byte', 1,...
%                 @obj.readSerialCommand); % User's commands
%             obj.serialDevice2 = serialport(obj.serialPort2, 921600);
%             configureCallback(obj.serialDevice2, 'byte', 1, ...
%                 @obj.readControlVariables); % send and receive data
            obj.serialDevice3 = serialport(obj.serialPort3, 921600);
            configureTerminator(obj.serialDevice3, 'LF'); % notify RPi availability
            % Create timers
            obj.Timer = timer(...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', 0.1,...
                'BusyMode', 'drop',...
                'TimerFcn', @obj.TimerFcn,...
                'ErrorFcn',@obj.TimerErrorFcn);
            stop(obj.Timer);
            obj.Timer2 = timer( ...
                'ExecutionMode', 'singleShot', ...
                'StartDelay', 3*60, ...
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
                % Check if a user is connected
                case 'check'
                % Connect raspberry pi
                case 'connect'
                    obj.count = 1;
                    [obj, user.Status] = obj.connectRPi();
                    user.ID = userID;
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

        % Serial communication
        function obj = readControlVariables(obj, src, ~)
            % Read control variables sent by user and send them to the
            if strcmp(obj.Timer.Running, 'on')
                stop(obj.Timer);
            end
            % raspberry pi
            try
                if src.NumBytesAvailable==3
                    display(src.NumBytesAvailable);
                    msg = read(src, 3, 'uint8');
                    write(obj.modbusServer, 'holdingregs', obj.StartReg, msg, 'uint16');
                end
            catch
                
            end
            if strcmp(obj.Timer.Running, 'off')
                start(obj.Timer); 
            end
        end
        function readSerialCommand(obj, src, ~)
            % Read user commands
            try
                if src.NumBytesAvailable>0
                    msg = read(src, src.NumBytesAvailable, 'char');
                    display(msg);
                    obj.processSerialCommand(msg);
                    %obj.processSerialCommand(msg(1:end-1));
                end
            catch
                return
            end
        end
        function processSerialCommand(obj, msg)
            msg = split(msg, '|');
            command = msg{1};
            path = msg{2};
            display(command);
            display(path);
            % Process serial commands
            switch command
                case 'running'
                    start(obj.Timer);
                % Start PLC program
                case 'start'
                    try
                        system(obj.myraspi, 'sudo systemctl start openplc');
                        % Create modbus server object
                        obj.modbusServer = modbus('tcpip', obj.modbusAddress, obj.modbusPort);
                        obj.PLCRunning = 1;
                        % Send confirmation to user
                        writeline(obj.tcpServer1, '1');
                    catch
                        write(obj.tcpServer1, '0', 'char');
                    end
                % Stop PLC program
                case 'stop'
                    try 
                        stop(obj.Timer);
                        obj.modbusServer = [];
                        system(obj.myraspi, 'sudo systemctl stop openplc');
                        pause(0.1);
                        obj.PLCRunning = 0;
                        writematrix(obj.data_array', strcat(path, '\', 'results.xlsx'));
                        %copyfile App\results.xlsx 'path'
                        writeline(obj.tcpServer1, '0');
                    catch me
                        display(me.message);
                        writeline(obj.tcpServer1, '1');
                    end
                % User connection confirmation
                case 'connected'
                    % Restart timer for checking user connection
                    stop(obj.Timer2);
                    start(obj.Timer2);
                % Send PLC program file to raspberry pi
                otherwise
                    try
                        system(obj.myraspi, 'sudo systemctl stop openplc');
                        system(obj.myraspi, 'rm OpenPLC_v3/webserver/st_files/826743.st');
                        putFile(obj.myraspi, command, '/home/pi/OpenPLC_v3/webserver/st_files');
                        system(obj.myraspi, '(cd OpenPLC_v3/webserver/scripts/ ; sh compile_program.sh 826743.st)');
                        writeline(obj.tcpServer1, '1');
                    catch 
                        writeline(obj.tcpServer1, '0');
                    end
            end
        end
        %% RPi connection
        function [obj, connected] = connectRPi(obj)
            connected = '0';
            try 
                obj.myraspi = raspi(obj.ip, obj.username, obj.password);
                connected = '1';
            catch
                return
            end
        end
        function [obj, connected] = disconnectRPi(obj)
            obj.myraspi = [];
            connected = '0';
        end
        %% Timer functions
        function obj = TimerFcn(obj, timer, ~)
            values = read(obj.modbusServer, 'coils', 3, 2); % system variables
            % Store system variables
            obj.data_array(:, obj.count) = values;
            % Send variables to user after 50 consecutive readings
            try
            if mod(obj.count, obj.dataSize)==0
                write(obj.tcpServer2, [flip(obj.data_array(1, obj.count-(obj.dataSize-1):obj.count)), ...
                    flip(obj.data_array(2, obj.count-(obj.dataSize-1):obj.count))], 'uint8');
            end
            catch
                
            end
            obj.count = obj.count+1;
            % Read system variables periodically
%             try
%                 values = read(obj.modbusServer, 'coils', 3, 2); % system variables
%                 % Store system variables
%                 obj.data_array(:, obj.count) = values;
%                 % Send variables to user after 50 consecutive readings
%                 if mod(obj.count, obj.dataSize)==0
%                     write(obj.tcpServer2, [flip(obj.data_array(1, obj.count-(obj.dataSize-1):obj.count)), ...
%                         flip(obj.data_array(2, obj.count-(obj.dataSize-1):obj.count))], 'uint8');
%                 end
%                 obj.count = obj.count+1;
%             catch me
%                 display('Read error');
%             end
        end
        function obj=TimerErrorFcn(obj, timer, ~)
            display('Timer error');
            start(obj.Timer);
        end
        function obj = Timer2Fcn(obj, ~, ~)
            % Stops PLC program and disconnects RPi when user is not active
            % anymore
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