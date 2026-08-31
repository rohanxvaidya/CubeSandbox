#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import inspect
import os,subprocess,string
from ossaudiodev import SOUND_MIXER_ALTPCM
# 导入CSV安装包
import csv
import time
import sys #sys.exit(0)
#cat random_write/1/node1log/kubevirt_vhost_sar-net.log |grep ceph-osd|awk {'print$1'}|sort|uniq
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
    PID_num=["ens78[5-6]f0"
    ]
    j=1
    for PID_ in PID_num:
        f3 = open('net-'+list_+str(j)+'.csv','w',encoding='utf-8-sig',newline='')
        # 2. 基于文件对象构建 csv写入对象
        csv_writer = csv.writer(f3)
        # wb.create_sheet("NewTitle") #新建sheet并设定sheet名称
        i=1
        csv_writer.writerow([list_,list_,list_])
        csv_writer.writerow([PID_,"rxkB/s","txkB/s"])
        csv_writer.writerow(["Average",str(run_cmd("cat "+CASE_ID+list_+"/kubevirt_vhost_sar-net.log |grep  Average|grep "+str(PID_)+"|awk {'print$5'}"))[2:-2],str(run_cmd("cat "+CASE_ID+list_+"/kubevirt_vhost_sar-net.log |grep  Average|grep "+str(PID_)+"|awk {'print$6'}"))[2:-2]])
        for i in range(1,400):
            OutL=[PID_,
            str(run_cmd("cat "+CASE_ID+list_+"/kubevirt_vhost_sar-net.log |grep -v Average|grep "+str(PID_)+"|awk {'print$6'}|sed '"+str(i)+"!d'"))[2:-2],
            str(run_cmd("cat "+CASE_ID+list_+"/kubevirt_vhost_sar-net.log |grep -v Average|grep "+str(PID_)+"|awk {'print$7'}|sed '"+str(i)+"!d'"))[2:-1]]
            # s1=','.join(str(n) for n in ceshi)
            # s1=[333,444,555]
            # OutL[3]=str(float(OutL[0])+float(OutL[1])+float(OutL[2]))
            print("cat "+CASE_ID+list_+"/kubevirt_vhost_sar-net.log |grep "+str(PID_)+"|awk {'print$6'}|sed '"+str(i)+"!d'",OutL[0])
            print("cat "+CASE_ID+list_+"/kubevirt_vhost_sar-net.log |grep "+str(PID_)+"|awk {'print$7'}|sed '"+str(i)+"!d'",OutL[1])

            # 3. 构建列表头
            csv_writer.writerow([OutL[0],OutL[1],OutL[2]])
        
        f3.close()
        j=j+1
import pandas as pd #pip3 install pandas
 
df1 = pd.read_csv(r'net-node1log1.csv')#读取文件


dg1 = pd.read_csv(r'net-node2log1.csv')#读取文件

 
dh1 = pd.read_csv(r'net-node3log1.csv')#读取文件

 
file_d = [df1,
dg1,
dh1]
 
outfile = pd.concat(file_d, axis=1)#横着拼接
# outfile = pd.concat(file)#竖着拼
 
outfile.to_csv("toallnet"+".csv",index=0, sep=',')#输出文件名
time.sleep(1)
del_all_csvfile = subprocess.Popen("rm -rf net-node*.csv", shell=True, stdout=subprocess.PIPE)
print(del_all_csvfile.stdout.read())
time_log = subprocess.Popen("date >> time_csv", shell=True, stdout=subprocess.PIPE)
print(time_log.stdout.read())