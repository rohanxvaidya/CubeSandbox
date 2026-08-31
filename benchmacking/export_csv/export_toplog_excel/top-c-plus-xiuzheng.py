#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import inspect
import os,subprocess,string
from ossaudiodev import SOUND_MIXER_ALTPCM
# 导入CSV安装包
import csv
import time
import sys #sys.exit(0)
#cat random_write/1/node1log/node-top.log |grep ceph-osd|awk {'print$1'}|sort|uniq
# PID_num=int(input("PID？:"))
CASE_ID=""
time_log = subprocess.Popen("date >> time_csv", shell=True, stdout=subprocess.PIPE)
print(time_log.stdout.read())
list_N=['node1log']
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
    PID_num=[24432,23548,24655,25030,24373,24789,24269,25079,24724,24769,24260,25066,23035,24480
    ]
    j=1
    for PID_ in PID_num:
        f3 = open('out-'+list_+str(j)+'.csv','w',encoding='utf-8-sig',newline='')
        # 2. 基于文件对象构建 csv写入对象
        csv_writer = csv.writer(f3)
        # wb.create_sheet("NewTitle") #新建sheet并设定sheet名称
        i=1
        csv_writer.writerow(["osd-"+str(PID_),"osd-"+str(PID_)])
        csv_writer.writerow(["CPU","MEM"])
        for i in range(1,400):
            OutL=[str(run_cmd("cat node-top.log |grep "+str(PID_)+"|awk {'print$6'}|sed '"+str(i)+"!d'"))[2:-2],
            str(run_cmd("cat node-top.log |grep "+str(PID_)+"|awk {'print$9'}|sed '"+str(i)+"!d'"))[2:-1]]
            # s1=','.join(str(n) for n in ceshi)
            # s1=[333,444,555]
            # OutL[3]=str(float(OutL[0])+float(OutL[1])+float(OutL[2]))
            print("cat node-top.log |grep "+str(PID_)+"|awk {'print$6'}|sed '"+str(i)+"!d'",OutL[0])
            print("cat node-top.log |grep "+str(PID_)+"|awk {'print$10'}|sed '"+str(i)+"!d'",OutL[1])

            # 3. 构建列表头
            csv_writer.writerow([OutL[1],OutL[0]])
        
        f3.close()
        j=j+1
import pandas as pd #pip3 install pandas
 
df1 = pd.read_csv(r'out-node1log1.csv')#读取文件
df2 = pd.read_csv(r'out-node1log2.csv')
df3 = pd.read_csv(r'out-node1log3.csv')
df4 = pd.read_csv(r'out-node1log4.csv')
df5 = pd.read_csv(r'out-node1log5.csv')
df6 = pd.read_csv(r'out-node1log6.csv')
df7 = pd.read_csv(r'out-node1log7.csv')
df8 = pd.read_csv(r'out-node1log8.csv')
df9 = pd.read_csv(r'out-node1log9.csv')
df10 = pd.read_csv(r'out-node1log10.csv')
df11 = pd.read_csv(r'out-node1log11.csv')
df12 = pd.read_csv(r'out-node1log12.csv')
df13 = pd.read_csv(r'out-node1log13.csv')
df14 = pd.read_csv(r'out-node1log14.csv')

# dg1 = pd.read_csv(r'out-node2log1.csv')#读取文件
# dg2 = pd.read_csv(r'out-node2log2.csv')
# dg3 = pd.read_csv(r'out-node2log3.csv')
# dg4 = pd.read_csv(r'out-node2log4.csv')
# dg5 = pd.read_csv(r'out-node2log5.csv')
# dg6 = pd.read_csv(r'out-node2log6.csv')
# dg7 = pd.read_csv(r'out-node2log7.csv')
# dg8 = pd.read_csv(r'out-node2log8.csv')
# dg9 = pd.read_csv(r'out-node2log9.csv')
# dg10 = pd.read_csv(r'out-node2log10.csv')
# dg11 = pd.read_csv(r'out-node2log11.csv')
# dg12 = pd.read_csv(r'out-node2log12.csv')
# dg13 = pd.read_csv(r'out-node2log13.csv')
# dg14 = pd.read_csv(r'out-node2log14.csv')
 
# dh1 = pd.read_csv(r'out-node3log1.csv')#读取文件
# dh2 = pd.read_csv(r'out-node3log2.csv')
# dh3 = pd.read_csv(r'out-node3log3.csv')
# dh4 = pd.read_csv(r'out-node3log4.csv')
# dh5 = pd.read_csv(r'out-node3log5.csv')
# dh6 = pd.read_csv(r'out-node3log6.csv')
# dh7 = pd.read_csv(r'out-node3log7.csv')
# dh8 = pd.read_csv(r'out-node3log8.csv')
# dh9 = pd.read_csv(r'out-node3log9.csv')
# dh10 = pd.read_csv(r'out-node3log10.csv')
# dh11 = pd.read_csv(r'out-node3log11.csv')
# dh12 = pd.read_csv(r'out-node3log12.csv')
# dh13 = pd.read_csv(r'out-node3log13.csv')
# dh14 = pd.read_csv(r'out-node3log14.csv')
 
file_d = [df1,df2,df3,df4,df5,df6,df7,df8,df9,df10,df11,df12,df13,df14
# dg1,dg2,dg3,dg4,dg5,dg6,dg7,dg8,dg9,dg10,dg11,dg12,dg13,dg14,
# dh1,dh2,dh3,dh4,dh5,dh6,dh7,dh8,dh9,dh10,dh11,dh12,dh13,dh14
]
 
outfile = pd.concat(file_d, axis=1)#横着拼接
# outfile = pd.concat(file)#竖着拼
 
outfile.to_csv("toall"+".csv",index=0, sep=',')#输出文件名
time.sleep(1)
del_all_csvfile = subprocess.Popen("rm -rf out-node*.csv", shell=True, stdout=subprocess.PIPE)
print(del_all_csvfile.stdout.read())
time_log = subprocess.Popen("date >> time_csv", shell=True, stdout=subprocess.PIPE)
print(time_log.stdout.read())