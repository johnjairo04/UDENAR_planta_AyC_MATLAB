function response = communicateTCPServer(client, message, dtype)
%     flush(client, 'input');
%     flush(client, 'output');
    write(client, message, dtype);
    while client.NumBytesAvailable==0
        pause(0.001);
    end
    response = read(client, client.NumBytesAvailable, 'char');
end