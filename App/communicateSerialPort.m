function response = communicateSerialPort(port, message, dtype)
%     flush(port, "input");
%     flush(port, 'output');
    write(port, message, dtype);
    while port.NumBytesAvailable==0
        pause(0.0001);
    end
    response = read(port, port.NumBytesAvailable, 'char');
    display(response);
end