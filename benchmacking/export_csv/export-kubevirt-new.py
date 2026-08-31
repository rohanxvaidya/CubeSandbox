#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import inspect
import os,subprocess,string
from ossaudiodev import SOUND_MIXER_ALTPCM
# 导入CSV安装包
import csv
import time
import sys #sys.exit(0)
Argout=input("'BW' or 'IOPS' or 'lat'？:")
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
listOUT=[
'/1/',
'/2/',
'/3/',
'/4/',
'/5/'
#如果名称有变化如文件夹名为sequential_read2，那么是'2/1/',
]


f3 = open('out-lat.csv','w',encoding='utf-8-sig',newline='')
# 2. 基于文件对象构建 csv写入对象
csv_writer = csv.writer(f3)
i=0
if Argout=="lat":
    for list in listOUT:
        OutL=[str(run_cmd("bash kudas.sh "+CASE_ID+list+"ubuntu1/*_"+CASE_ID+"_*.log "+"avg"))[2:-1],str(run_cmd("bash kudas.sh "+CASE_ID+list+"ubuntu1/*_"+CASE_ID+"_*.log "+"stdev"))[2:-1],str(run_cmd("bash kudas.sh "+CASE_ID+list+"ubuntu2/*_"+CASE_ID+"_*.log "+"avg"))[2:-1],str(run_cmd("bash kudas.sh "+CASE_ID+list+"ubuntu2/*_"+CASE_ID+"_*.log "+"stdev"))[2:-1],str(run_cmd("bash kudas.sh "+CASE_ID+list+"ubuntu3/*_"+CASE_ID+"_*.log "+"avg"))[2:-1],str(run_cmd("bash kudas.sh "+CASE_ID+list+"ubuntu3/*_"+CASE_ID+"_*.log "+"stdev"))[2:-1],]
        # s1=','.join(str(n) for n in ceshi)
        # s1=[333,444,555]
        # OutL[3]=str(float(OutL[0])+float(OutL[1])+float(OutL[2]))
        print(OutL[0])
        print(OutL[1])
        print(OutL[2])
        print(OutL[3])
        print(OutL[4])
        print(OutL[5])
        # print(s1[0])
        # print(ceshi)

        # 3. 构建列表头
        csv_writer.writerow([OutL[0]])
        csv_writer.writerow([OutL[1]])
        csv_writer.writerow([OutL[2]])
        csv_writer.writerow([OutL[3]])
        csv_writer.writerow([OutL[4]])
        csv_writer.writerow([OutL[5]])
        csv_writer.writerow(["========================"])
    f3.close()
else:
    for list in listOUT:
        OutL=[
            str(run_cmd("bash kudas.sh "+CASE_ID+list+"ubuntu1/*_"+CASE_ID+"_*.log "+Argout))[2:-1],
            str(run_cmd("bash kudas.sh "+CASE_ID+list+"ubuntu2/*_"+CASE_ID+"_*.log "+Argout))[2:-1],
            str(run_cmd("bash kudas.sh "+CASE_ID+list+"ubuntu3/*_"+CASE_ID+"_*.log "+Argout))[2:-1],
            0]
        # s1=','.join(str(n) for n in ceshi)
        # s1=[333,444,555]
        OutL[3]=str(float(OutL[0])+float(OutL[1])+float(OutL[2]))
        print(OutL[0])
        print(OutL[1])
        print(OutL[2])
        print(OutL[3])
        # print(s1[0])
        # print(ceshi)

        # 3. 构建列表头
        csv_writer.writerow([OutL[0]])
        csv_writer.writerow([OutL[1]])
        csv_writer.writerow([OutL[2]])
        csv_writer.writerow([OutL[3]])
        csv_writer.writerow(["========================"])
    f3.close()