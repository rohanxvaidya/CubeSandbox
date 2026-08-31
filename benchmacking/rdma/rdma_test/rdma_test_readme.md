In this folder, it's a project for rdma test;
Write a tool to test the rdma pingpong and ib_write_bw function;
This tool can support client and server side, we can copy the project to client and server node and build them, then use them for test;
Define the parameters including: client ip, server ip, io size, specify client or server, etc, you can add more parameters as you want to;
Define a parameter `-R` to support RMDA_CM mode;
In current server, it's a server node with RDMA IP 192.168.0.2, and the client node is 192.168.0.3, you can access the client node from current node directly. 
In server node, the work folder is "/home/mz/rdma/rdma_test"
In client node, the work folder is "/home/mz/rdma/rdma_test"
You should write the code, compile the code and test it, ensure the tool can works well on thes two node;
You have fully permission to modify the files in the work folder "/home/mz/rdma/rdma_test"