#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import inspect
import os,subprocess,string
# from ossaudiodev import SOUND_MIXER_ALTPCM
# 导入CSV安装包
import csv
import time
import sys #sys.exit(0)
#cat random_write/1/node1log/node-top.log |grep ceph-osd|awk {'print$1'}|sort|uniq
PID_num=int(input("PID？:"))
# print(sys.argv[0])      #daochu.py BW / daochu.py IOPS      
#print(sys.argv[1])         
def run_cmd(cmd):
    result_str=''
    process = subprocess.Popen(cmd, shell=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    result_f = process.stdout
    error_f = process.stderr
    errors = error_f.read()
    if errors: pass
    result_str = result_f.read().strip()
    # print(type(result_str))
    # print(str(result_str))
    if result_f:
        result_f.close()
    if error_f:
        error_f.close()
    return result_str
# 先手动运行以下命令获取list 并删除最后的逗号，
# for file in $(ls|grep -v daochu.py|grep -v kudas.sh|grep -v out.csv|grep -v bg); do echo "'${file}',"; done
#  for file in $(find . -name vm_random_write*|grep -v daochu.py|grep -v kudas.sh|grep -v out.csv|grep -v bg); do echo "'${file}',"; done
#random_write
#random_read
#sequential_read
#sequential_write
CASE_ID="random_write"
list_='/1/node1log'
# listOUT=[
# '/1/',
# '/2/',
# '/3/',
# '/4/',
# '/5/'
# #如果名称有变化如文件夹名为sequential_read2，那么是'2/1/',
# ]


f3 = open('out-ceshi.csv','w',encoding='utf-8-sig',newline='')
# 2. 基于文件对象构建 csv写入对象
csv_writer = csv.writer(f3)
# wb.create_sheet("NewTitle") #新建sheet并设定sheet名称
i=1
csv_writer.writerow(["osd-"+str(PID_num),"osd-"+str(PID_num)])
csv_writer.writerow(["CPU","MEM"])
for i in range(1,400):
    OutL=[str(run_cmd("cat "+CASE_ID+list_+"/node-top.log |grep "+str(PID_num)+"|awk {'print$6'}|sed '"+str(i)+"!d'"))[2:-2],
    str(run_cmd("cat "+CASE_ID+list_+"/node-top.log |grep "+str(PID_num)+"|awk {'print$10'}|sed '"+str(i)+"!d'"))[2:-1]]
    # s1=','.join(str(n) for n in ceshi)
    # s1=[333,444,555]
    # OutL[3]=str(float(OutL[0])+float(OutL[1])+float(OutL[2]))
    print("cat "+CASE_ID+list_+"/node-top.log |grep "+str(PID_num)+"|awk {'print$6'}|sed '"+str(i)+"!d'",OutL[0])
    print("cat "+CASE_ID+list_+"/node-top.log |grep "+str(PID_num)+"|awk {'print$10'}|sed '"+str(i)+"!d'",OutL[1])

    # 3. 构建列表头
    csv_writer.writerow([OutL[1],OutL[0]])
    

f3.close()
