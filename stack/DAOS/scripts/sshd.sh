#!/bin/bash

#passwd change

ssh-keygen -q -t rsa -b 2048 -f /etc/ssh/ssh_host_rsa_key -N ''
ssh-keygen -q -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N ''
ssh-keygen -q -t dsa -f /etc/ssh/ssh_host_ed25519_key -N ''

#Port 200
echo "Port 200" >> /etc/ssh/sshd_config

echo "PermitRootLogin yes " >> /etc/ssh/sshd_config

/usr/sbin/sshd -D &


##ssh -l root 10.67.127.156 -p 200


# docker file??
# RUN mkdir /var/run/sshd
# RUN echo 'root:root' | chpasswd
# RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# # SSH login fix. Otherwise user is kicked off after login
# RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

# ENV NOTVISIBLE "in users profile"
# RUN echo "export VISIBLE=now" >> /etc/profile

# # 22 for ssh server. 7777 for gdb server.
# EXPOSE 22 7777

# RUN useradd -ms /bin/bash debugger
# RUN echo 'debugger:pwd' | chpasswd

# CMD ["/usr/sbin/sshd", "-D"]