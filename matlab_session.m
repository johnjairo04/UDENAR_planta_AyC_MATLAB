try
    stop(timerfindall);
catch
end
delete(timerfindall);
if exist('RPi2tanks', 'var')
    delete(RPi2tanks);
end
clear; clc; close all;
user.ID = '-';
user.Status = '0';
save('user.mat', 'user');
ip_address = '10.20.40.58';
username = 'pi';
password = 'raspberry';
RPi2tanks = RPi_two_tank_lab(ip_address, username, password);