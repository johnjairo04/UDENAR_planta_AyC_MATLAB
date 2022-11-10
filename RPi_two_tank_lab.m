classdef RPi_two_tank_lab<handle
    properties (Access=private)
        ip
        username
        password
        myraspi
        Timer
        Timer2
        StartReg = 1025
        StopReg = 1026
        EmergReg = 1027
        serialPort = 'COM2'
        serialDevice
        serialPort2 = 'COM3'
        serialDevice2
        tcpServer
        count = 0
        data = zeros(1, 2);
        modbusPort = 502
        modbusAddress
        modbusServer
        dataSize = 1
        userTimeOut = 60;
    end
    properties (Access=public)
        test_array = zeros(2, 10000);
        test_count = 1;
        PLCRunning = 0;
    end
    methods
        %% Constructor
        function obj = RPi_two_tank_lab(ip, username, password)
            % RPi parameters
            obj.ip = ip;
            obj.username = username;
            obj.password = password;
            obj.modbusAddress = ip;

            % Create and set up TCP server
            obj.tcpServer = tcpserver('0.0.0.0', 30000);
            configureCallback(obj.tcpServer, 'byte', 1,...
                @obj.readTCPClientCommand);

            % Create serial ports
            obj.serialDevice = serialport(obj.serialPort, 115200);
            configureTerminator(obj.serialDevice, 'LF');
            configureCallback(obj.serialDevice, 'byte', 1,...
                @obj.readSerialCommand);

            obj.serialDevice2 = serialport(obj.serialPort2, 115200);
            configureCallback(obj.serialDevice2, 'byte', 1, ...
                @obj.readControlVariables);

            % Create timers
            obj.Timer = timer(...
                'ExecutionMode', 'fixedSpacing', ...    % Run timer repeatedly
                'Period', 0.01, ...                     % Period is 1 second
                'BusyMode', 'drop',...              % Queue timer callbacks when busy
                'StartDelay', 0.1,...
                'TimerFcn', @obj.TimerFcn, ...
                'ErrorFcn',@obj.TimerErrorFcn);      % Specify callback function
            stop(obj.Timer);

            obj.Timer2 = timer( ...
                'ExecutionMode', 'singleShot', ...
                'StartDelay', 5*60, ...
                'BusyMode', 'queue', ...
                'TimerFcn', @obj.Timer2Fcn);
            stop(obj.Timer2);
            display(obj.Timer);
            display(obj.Timer2);
        end
        %% Read TCP client commands
        function obj = readTCPClientCommand(obj, src, ~)
            if src.NumBytesAvailable>0
                msg = read(src, src.NumBytesAvailable, 'char');
                display(msg);
                obj = obj.processTCPClientCommand(msg);
            else
                return
            end
        end
        function obj = processTCPClientCommand(obj, msg)
            log = load('user.mat');
            user = log.user;
            switch msg
                case 'check'
                    
                case 'connect'
                    [obj, user.Status] = obj.connectRPi();
                    start(obj.Timer2);
                    save('user.mat', 'user');
                case 'disconnect'
                    [obj, user.Status] = obj.disconnectRPi();
                    stop(obj.Timer2);
                    save('user.mat', 'user');
            end
            write(obj.tcpServer, user.Status, 'char');
        end
        %% Read serial commands
        function readControlVariables(obj, src, ~)
            stop(obj.Timer);
            if src.NumBytesAvailable>0
                msg = read(src, 3, 'uint16');
                write(obj.modbusServer, 'holdingregs', obj.StartReg, msg, 'uint16');
            end
            start(obj.Timer);
        end
        function readSerialCommand(obj, src, ~)
            if src.NumBytesAvailable>0
                msg = read(src, src.NumBytesAvailable, 'char');
                msg = msg(1:end-1);
                display(msg);
                obj.processSerialCommand(msg);
            end
        end
        function processSerialCommand(obj, msg)
            switch msg
                case 'running'
                    display(msg);
                    pause(0.1);
                    start(obj.Timer);
                case 'start'
                    try
                        system(obj.myraspi, 'sudo systemctl start openplc');
                        obj.modbusServer = modbus('tcpip', obj.modbusAddress, obj.modbusPort);
                        obj.PLCRunning = 1;
                        writeline(obj.serialDevice, '1');
                    catch
                        write(obj.serialDevice, '0', 'char');
                    end
                case 'stop'
                    try 
                        stop(obj.Timer);
                        obj.modbusServer = [];
                        system(obj.myraspi, 'sudo systemctl stop openplc');
                        pause(0.1);
                        obj.PLCRunning = 0;
                        writeline(obj.serialDevice, '0');
                    catch 
                        writeline(obj.serialDevice, '1');
                    end
                case 'connected'
                    stop(obj.Timer2);
                    start(obj.Timer2);
                otherwise
                    system(obj.myraspi, 'sudo systemctl stop openplc');
                    system(obj.myraspi, 'rm OpenPLC_v3/webserver/st_files/826743.st');
                    putFile(obj.myraspi, msg, '/home/pi/OpenPLC_v3/webserver/st_files');
                    system(obj.myraspi, '(cd OpenPLC_v3/webserver/scripts/ ; sh compile_program.sh 826743.st)');
                    writeline(obj.serialDevice, '1');
                    pause(0.1);
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
        function TimerFcn(obj, ~, ~)
            try
            values = read(obj.modbusServer, 'coils', 3, 2);
            obj.test_count = obj.test_count+1;
            obj.test_array(:, obj.test_count) = values;
            if any(obj.test_array(:, obj.test_count-1)~=obj.test_array(:, obj.test_count))
                display(obj.test_array(:, obj.test_count))
                write(obj.serialDevice2, values, 'double');
            end
            catch me
                display(me.message);
            end
        end
        function TimerErrorFcn(obj, ~, ~)
            start(obj.Timer);
        end
        function obj = Timer2Fcn(obj, ~, ~)
            display('User disconnected');
            stop(obj.Timer2);
            if obj.PLCRunning
                stop(obj.Timer);
            end
            try 
                system(obj.myraspi, 'sudo systemctl stop openplc');
            catch
            end
            obj.PLCRunning = 0;
            obj.modbusServer = [];
            [obj, user.Status] = obj.disconnectRPi();
            save('user.mat', 'user');
        end
    end
end