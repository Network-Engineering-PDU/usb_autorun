# Update and Clean example

This example removes everything from the home directory, installs the latest compiled version of Yocto and creates a tunnel using the port provided by the office server. To do that, it performs the following tasks:

- Copy the latest image file from the office server using scp.
- Get the server port from the office server file `ttusb_port`.
- Increments the port number in the office server file `ttusb_port` by one.
- Remove all files and directories from home.
- Use the `ttsetup.sh` script to dig an ssh tunnel using the port number read from the office server.
- Reboot the system.