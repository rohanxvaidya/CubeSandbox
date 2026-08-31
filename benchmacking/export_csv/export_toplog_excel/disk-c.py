#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import inspect
import os,subprocess,string
from ossaudiodev import SOUND_MIXER_ALTPCM
# 导入CSV安装包
import csv
import time
import sys #sys.exit(0)
#cat random_write/1/node1log/kubevirt_vhost_sar-io.log |grep ceph-osd|awk {'print$1'}|sort|uniq
# PID_num=int(input("PID？:"))
CASE_ID=""
time_log = subprocess.Popen("date >> time_csv", shell=True, stdout=subprocess.PIPE)
print(time_log.stdout.read())
list_N=['node1log','node2log','node3log']
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
for list_ in list_N:
    PID_num=["nvme1n1","nvme2n1","nvme3n1","nvme4n1","nvme5n1","nvme6n1","nvme7n1"
    ]
    j=1
    f3 = open('disk-'+list_+str(j)+'.csv','w',encoding='utf-8-sig',newline='')
    csv_writer = csv.writer(f3)
    csv_writer.writerow(["DEV","rkB/s","wkB/s"])
    for PID_ in PID_num:
        
        # 2. 基于文件对象构建 csv写入对象
        
        # wb.create_sheet("NewTitle") #新建sheet并设定sheet名称
        i=1
        
        csv_writer.writerow([PID_,str(run_cmd("cat "+CASE_ID+list_+"/kubevirt_vhost_sar-io.log |grep  Average|grep "+str(PID_)+"|awk {'print$4'}"))[2:-2],str(run_cmd("cat "+CASE_ID+list_+"/kubevirt_vhost_sar-io.log |grep  Average|grep "+str(PID_)+"|awk {'print$5'}"))[2:-2]])
        print("cat "+CASE_ID+list_+"/kubevirt_vhost_sar-io.log |grep  Average|grep "+str(PID_)+"|awk {'print$4'}")
        print("cat "+CASE_ID+list_+"/kubevirt_vhost_sar-io.log |grep  Average|grep "+str(PID_)+"|awk {'print$5'}")
    f3.close()    
        
        

import pandas as pd #pip3 install pandas
 
df1 = pd.read_csv(r'disk-node1log1.csv')#读取文件


dg1 = pd.read_csv(r'disk-node2log1.csv')#读取文件

 
dh1 = pd.read_csv(r'disk-node3log1.csv')#读取文件

 
file_d = [df1,
dg1,
dh1]
 
outfile = pd.concat(file_d, axis=1)#横着拼接
# outfile = pd.concat(file)#竖着拼
 
outfile.to_csv("toalldisk"+".csv",index=0, sep=',')#输出文件名
time.sleep(1)
del_all_csvfile = subprocess.Popen("rm -rf disk-node*.csv", shell=True, stdout=subprocess.PIPE)
print(del_all_csvfile.stdout.read())
time_log = subprocess.Popen("date >> time_csv", shell=True, stdout=subprocess.PIPE)
print(time_log.stdout.read())