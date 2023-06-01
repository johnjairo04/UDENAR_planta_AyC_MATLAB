client_tcp = tcpclient('localhost', 5555, 'ConnectTimeout', 15);

clear myraspi
myraspi = raspi('192.168.101.78', 'pi', 'raspberry');

wcam = webcam(myraspi, 1, '640x480');

while 1
    img = imresize(snapshot(wcam), 0.25);
    flat_img = reshape(img, [], 1);
    N = numel(flat_img);
    write(client_tcp, flat_img, "uint8");
    pause(0.25);
end