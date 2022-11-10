try
    stop(timerfindall);
end
delete(timerfindall);

if exist('RPi2tanks', 'var')
    delete(RPi2tanks);
end
clear; clc; close all;
user.ID = '';
user.Status = '0';
save('user.mat', 'user');
ip_address = '192.168.101.78';
username = 'pi';
password = 'raspberry';
RPi2tanks = RPi_two_tank_lab(ip_address, username, password);