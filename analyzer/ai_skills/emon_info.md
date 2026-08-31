The emon file, ususally is stored with *.dat format, it's it's a ASCII text file, with very long lines. In this emon file there are system information and lots of event data that captured in one server, including CPU, cache, memory, NUMA, PMU, interconnect, PCIe, and software/toolchain details. And for the event data, we have tool to parse the events, here we don't need consider it.
I just want you to check the header of the emon file emon.data (sometimes it's named with other name, e.g. cx7_rdma_1qp_4k_16l_2core_218G_180s.dat),  The header of this file maintains the system infomation of one server, please find the key words "Version Info" it's the last line of the header. please read and parse the emon*dat file, tell me all of the informanction about the system, including HW/SW,and write them down with a MD file.

## Where to put the files
    You can pull the *dat file out in my server node [emon_data](../emon_data/), create a coresponding folder (the folder name can use the dat file name) to contains the *dat and put the info file in the same folder.  

## permission
    Please don't ask me for permission to install tools if you want use it to parse the emon file. 
    Please don't ask me for permission to modify files in your created folder under [emon_data](../emon_data/) 


