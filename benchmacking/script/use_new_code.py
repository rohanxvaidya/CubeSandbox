#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import inspect
import os,subprocess,string

# 导入CSV安装包
import csv
import time
import sys #sys.exit(0)

# 19*1024/2/3/3 * (0.6)=648.5G
# write case 会在prefill=1时强制重建rbd并prefill
krbdcase=0 # 1为krbdcase 会map rbd ; 0为普通rbdcase
prefill=1
create_rbd_once=1
del_rbd_end=1 #只在完成测试后删除rbd
first_write_case_is_seqwrite=0 
fio_draw_pic=0 # 画fio图用的
perf_data=0 # 画火焰图用的
blk_size="540G"
cpus_allowed="16-31,80-95"
# sar_runtime="1900"
runtime="600"
ramp_time="300"
overtime="180"
dstat_disk1="nvme1n1,nvme2n1,nvme3n1,nvme4n1,nvme5n1,nvme6n1,nvme7n1"
dstat_disk2="nvme1n1,nvme2n1,nvme3n1,nvme4n1,nvme5n1,nvme6n1,nvme7n1"
dstat_disk3="nvme1n1,nvme2n1,nvme3n1,nvme4n1,nvme5n1,nvme6n1,nvme7n1"
node1="192.168.88.56"  #node1 主控节点 必须得有 top -c 数据只有主控节点完整
node2="192.168.88.157"
node3="192.168.88.71" # 如果没有node3 则设空 node3=""
CODE_DIR="/opt/wie-shell/" # 文件夹末尾请一定要带"/"

clean_rbd=0 #默认值0 是否每次都清除rbd
force_prefill_before_seqwrtie=0 #默认值0 如果perfill为0 又想连续测seqwrite时候用 一般只有tune时候遇到
sure_prefill_seqw=1  # 默认值1 意思是seqwrite也不prefill,给自己留的接口 一般填1就行
########
haveID=0
jishuqi=0
line_num=1
prefill_time=0
############
fiodict_numjob_2_mix= {'readorwrite': 'randrw', 'bs': '4k','rwmixread': '70','iodepth':'16','numjob':'2'}
fiodict1M_numjob_2_seqwrite = {'readorwrite': 'write', 'bs': '1M','rwmixread': '0','iodepth':'8','numjob':'2'}
fiodict1M_numjob_2_seqread = {'readorwrite': 'read','bs': '1M','rwmixread': '100','iodepth':'8','numjob':'2'}
fiodict_numjob_2_randwrite = {'readorwrite': 'randwrite', 'bs': '4k','rwmixread': '0','iodepth':'64','numjob':'2'}
fiodict_numjob_2_randread = {'readorwrite': 'randread', 'bs': '4k','rwmixread': '100','iodepth':'64','numjob':'2'}

fiodict_numjob_4_mix= {'readorwrite': 'randrw', 'bs': '4k','rwmixread': '70','iodepth':'16','numjob':'4'}
fiodict1M_numjob_4_seqwrite = {'readorwrite': 'write', 'bs': '1M','rwmixread': '0','iodepth':'8','numjob':'4'}
fiodict1M_numjob_4_seqread = {'readorwrite': 'read','bs': '1M','rwmixread': '100','iodepth':'8','numjob':'4'}
fiodict_numjob_4_randwrite = {'readorwrite': 'randwrite', 'bs': '4k','rwmixread': '0','iodepth':'64','numjob':'4'}
fiodict_numjob_4_randread = {'readorwrite': 'randread', 'bs': '4k','rwmixread': '100','iodepth':'64','numjob':'4'}

fiodict_numjob_6_mix= {'readorwrite': 'randrw', 'bs': '4k','rwmixread': '70','iodepth':'16','numjob':'6'}
fiodict1M_numjob_6_seqwrite = {'readorwrite': 'write', 'bs': '1M','rwmixread': '0','iodepth':'8','numjob':'6'}
fiodict1M_numjob_6_seqread = {'readorwrite': 'read','bs': '1M','rwmixread': '100','iodepth':'8','numjob':'6'}
fiodict_numjob_6_randwrite = {'readorwrite': 'randwrite', 'bs': '4k','rwmixread': '0','iodepth':'64','numjob':'6'}
fiodict_numjob_6_randread = {'readorwrite': 'randread', 'bs': '4k','rwmixread': '100','iodepth':'64','numjob':'6'}

fiodict_numjob_8_mix= {'readorwrite': 'randrw', 'bs': '4k','rwmixread': '70','iodepth':'16','numjob':'8'}
fiodict1M_numjob_8_seqwrite = {'readorwrite': 'write', 'bs': '1M','rwmixread': '0','iodepth':'8','numjob':'8'}
fiodict1M_numjob_8_seqread = {'readorwrite': 'read','bs': '1M','rwmixread': '100','iodepth':'8','numjob':'8'}
fiodict_numjob_8_randwrite = {'readorwrite': 'randwrite', 'bs': '4k','rwmixread': '0','iodepth':'64','numjob':'8'}
fiodict_numjob_8_randread = {'readorwrite': 'randread', 'bs': '4k','rwmixread': '100','iodepth':'64','numjob':'8'}

fiodict=[fiodict_numjob_2_randread]
# fiodict=[fiodict_randread]

if node1:
    cpuset = subprocess.Popen("ssh root@"+node1+" 'sudo cpupower frequency-set -g performance'", shell=True, stdout=subprocess.PIPE)
    print(cpuset.stdout.read())
if node2:
    cpuset = subprocess.Popen("ssh root@"+node2+" 'sudo cpupower frequency-set -g performance'", shell=True, stdout=subprocess.PIPE)
    print(cpuset.stdout.read())
if node3:
    cpuset = subprocess.Popen("ssh root@"+node3+" 'sudo cpupower frequency-set -g performance'", shell=True, stdout=subprocess.PIPE)
    print(cpuset.stdout.read())

def get_variable_name(variable):
    callers_local_vars=inspect.currentframe().f_back.f_locals.items()
    return[f'{var_name}' for var_name,var_val in callers_local_vars if var_val is variable][0]
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
# node1_hostname=`ssh root@$NODE1 hostname`
# node2_hostname=`ssh root@$NODE2 hostname`
# node3_hostname=`ssh root@$NODE3 hostname`
node1_hostname=str(run_cmd("ssh root@"+node1+" hostname"))[2:-1]
print(node1_hostname)
node2_hostname=str(run_cmd("ssh root@"+node2+" hostname"))[2:-1]
print(node2_hostname)
node3_hostname=str(run_cmd("ssh root@"+node3+" hostname"))[2:-1]
print(node3_hostname)

rm_rf_continue = subprocess.Popen("rm -rf continue.txt", shell=True, stdout=subprocess.PIPE)
print(rm_rf_continue.stdout.read())

f_continue = open(r'continue.txt', 'a') #若文件不存在，系统自动创建。'a'表示可连续写入到文件，保留原内容，在原 #内容之后写入。可修改该模式（'w+','w','wb'等）
f_continue.write("1")
# f_continue.write('\n')
f_continue.close()

if perf_data:
    rm_rf_perf_data = subprocess.Popen("rm -rf perf.sh", shell=True, stdout=subprocess.PIPE)
    print(rm_rf_perf_data.stdout.read())
    f_perf = open(r'perf.sh', 'a') #若文件不存在，系统自动创建。'a'表示可连续写入到文件，保留原内容，在原 #内容之后写入。可修改该模式（'w+','w','wb'等）
    f_perf.write("#!/bin/bash -x")
    f_perf.write('\n')
    f_perf.write("PID_num=`top -b -n 1|grep -v grep|grep ceph-osd |awk '{print $1}'|sed '1!d'`")
    f_perf.write('\n')
    f_perf.write("tmux new -d -s perf_tmux")
    f_perf.write('\n')
    f_perf.write("tmux new -d -s perf_tmux_2")
    f_perf.write('\n')
    f_perf.write("tmux send-keys -t perf_tmux.0 \"cd /tmp && perf record -p $PID_num  -F 99 --call-graph dwarf -- sleep 30\" ENTER")
    f_perf.write('\n')
    f_perf.write("tmux send-keys -t perf_tmux_2.0 \"cd /opt && perf record -F 99 -p $PID_num -g -- sleep 30\" ENTER")
    f_perf.write('\n')
    f_perf.close()

def del_rbd_def():
    global node1,node2,node3,krbdcase
    if krbdcase:
        if node1:
            time.sleep(1)
            umap_rbd_1 = subprocess.Popen("ssh root@"+node1+" 'rbd unmap  -o force /dev/rbd0 && rbd unmap  -o force /dev/rbd1  && rbd unmap  -o force  /dev/rbd2'", shell=True, stdout=subprocess.PIPE)
            print(umap_rbd_1.stdout.read())
        if node2:
            time.sleep(1)
            umap_rbd_2 = subprocess.Popen("ssh root@"+node2+" 'rbd unmap  -o force /dev/rbd0 && rbd unmap  -o force /dev/rbd1  && rbd unmap  -o force /dev/rbd2'", shell=True, stdout=subprocess.PIPE)
            print(umap_rbd_2.stdout.read())
        if node3:
            time.sleep(1)
            umap_rbd_3 = subprocess.Popen("ssh root@"+node3+" 'rbd unmap  -o force /dev/rbd0 && rbd unmap  -o force /dev/rbd1  && rbd unmap  -o force /dev/rbd2'", shell=True, stdout=subprocess.PIPE)
            print(umap_rbd_3.stdout.read())
        time.sleep(10)

    if node1:
        del_rbd_fin = subprocess.Popen("rbd -p replicapool  rm rbd1 && rbd -p replicapool  rm rbd2  && rbd -p replicapool  rm rbd3", shell=True, stdout=subprocess.PIPE)
        print(del_rbd_fin.stdout.read())
    if node2:
        del_rbd_fin = subprocess.Popen("rbd -p replicapool  rm rbd4 && rbd -p replicapool  rm rbd5  && rbd -p replicapool  rm rbd6", shell=True, stdout=subprocess.PIPE)
        print(del_rbd_fin.stdout.read())
    if node3:
        del_rbd_fin = subprocess.Popen("rbd -p replicapool  rm rbd7 && rbd -p replicapool  rm rbd8  && rbd -p replicapool  rm rbd9", shell=True, stdout=subprocess.PIPE)
        print(del_rbd_fin.stdout.read())

def create_rbd_def():
    global node1,node2,node3,blk_size,krbdcase

    if node1:
        create_rbd = subprocess.Popen("rbd -p replicapool create --size "+blk_size+" rbd1 && rbd -p replicapool create --size "+blk_size+" rbd2 && rbd -p replicapool create --size "+blk_size+" rbd3", shell=True, stdout=subprocess.PIPE)
        print(create_rbd.stdout.read())
    if node2:
        create_rbd = subprocess.Popen("rbd -p replicapool create --size "+blk_size+" rbd4 && rbd -p replicapool create --size "+blk_size+" rbd5 && rbd -p replicapool create --size "+blk_size+" rbd6", shell=True, stdout=subprocess.PIPE)
        print(create_rbd.stdout.read())
    if node3:
        create_rbd = subprocess.Popen("rbd -p replicapool create --size "+blk_size+" rbd7 && rbd -p replicapool create --size "+blk_size+" rbd8 && rbd -p replicapool create --size "+blk_size+" rbd9", shell=True, stdout=subprocess.PIPE)
        print(create_rbd.stdout.read())
    if krbdcase:
        time.sleep(10)
        if node1:
            map_rbd_1 = subprocess.Popen("ssh root@"+node1+" 'rbd map replicapool/rbd1 && rbd map replicapool/rbd2  && rbd map replicapool/rbd3'", shell=True, stdout=subprocess.PIPE)
            print(map_rbd_1.stdout.read())
            time.sleep(1)
        if node2:
            map_rbd_2 = subprocess.Popen("ssh root@"+node2+" 'rbd map replicapool/rbd4 && rbd map replicapool/rbd5  && rbd map replicapool/rbd6'", shell=True, stdout=subprocess.PIPE)
            print(map_rbd_2.stdout.read())
            time.sleep(1)
        if node3:
            map_rbd_3 = subprocess.Popen("ssh root@"+node3+" 'rbd map replicapool/rbd7 && rbd map replicapool/rbd8  && rbd map replicapool/rbd9'", shell=True, stdout=subprocess.PIPE)
            print(map_rbd_3.stdout.read())
            time.sleep(1)

def prefill_rbd_def():
    global node1,node2,node3,prefill_time,blk_size
    if node1:
        prefill_ = subprocess.Popen("rm -rf prefill-1.fio && ssh root@"+node1+" 'rm -rf /tmp/prefill.fio'", shell=True, stdout=subprocess.PIPE)
        print(prefill_.stdout.read())
        f = open(r'prefill-1.fio', 'a') #若文件不存在，系统自动创建。'a'表示可连续写入到文件，保留原内容，在原 #内容之后写入。可修改该模式（'w+','w','wb'等）
        f.write("[global]")
        f.write('\n')
        if krbdcase:
            f.write("ioengine=libaio")
        else:
            f.write("ioengine=rbd")
        f.write('\n')
        f.write("numjobs=1")
        f.write('\n')
        f.write("thread=1")
        f.write('\n')
        f.write("invalidate=0")
        f.write('\n')
        if int(krbdcase)==0:
            f.write("clientname=admin")
        f.write('\n')
        if int(krbdcase)==0:
            f.write("pool=replicapool")
        f.write('\n')
        f.write("iodepth=8")
        f.write('\n')
        f.write("size="+blk_size)
        f.write('\n')
        f.write("rw=write")
        f.write('\n')
        f.write("rwmixread=0")
        f.write('\n')
        # f.write("percentage_random="+str(i['percentage_random']))
        # f.write('\n')
        f.write("bs=4M")
        f.write('\n')
        f.write("direct=1")
        f.write('\n')
        f.write("cpus_allowed="+cpus_allowed)
        f.write('\n')
        f.write("cpus_allowed_policy=split")
        f.write('\n')        
        # f.write("latency_target="+str(i['latency_target']))
        # f.write('\n')
        # f.write("latency_window=1000000")
        # f.write('\n')
        f.write("group_reporting")
        f.write('\n')
        # f.write("write_bw_log=rw")
        # f.write('\n')
        # f.write("log_avg_msec=500")
        # f.write('\n')
        # f.write("allow_mounted_write=1")
        # f.write('\n')
        f.write("[job1]")
        f.write('\n')
        f.write("name=job1")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd0")
        else:
            f.write("rbdname=rbd1")
        f.write('\n')
        f.write("[job2]")
        f.write('\n')
        f.write("name=job2")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd1")
        else:
            f.write("rbdname=rbd2")
        f.write('\n')
        f.write("[job3]")
        f.write('\n')
        f.write("name=job3")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd2")
        else:
            f.write("rbdname=rbd3")

        f.close()
    if node2:
        prefill_ = subprocess.Popen("rm -rf prefill-2.fio && ssh root@"+node2+" 'rm -rf /tmp/prefill.fio'", shell=True, stdout=subprocess.PIPE)
        print(prefill_.stdout.read())
        f = open(r'prefill-2.fio', 'a') #若文件不存在，系统自动创建。'a'表示可连续写入到文件，保留原内容，在原 #内容之后写入。可修改该模式（'w+','w','wb'等）
        f.write("[global]")
        f.write('\n')
        if krbdcase:
            f.write("ioengine=libaio")
        else:
            f.write("ioengine=rbd")
        f.write('\n')
        f.write("numjobs=1")
        f.write('\n')
        f.write("thread=1")
        f.write('\n')
        f.write("invalidate=0")
        f.write('\n')
        if int(krbdcase)==0:
            f.write("clientname=admin")
        f.write('\n')
        if int(krbdcase)==0:
            f.write("pool=replicapool")
        f.write('\n')
        f.write("iodepth=8")
        f.write('\n')
        f.write("size="+blk_size)
        f.write('\n')
        f.write("rw=write")
        f.write('\n')
        f.write("rwmixread=0")
        f.write('\n')
        # f.write("percentage_random="+str(i['percentage_random']))
        # f.write('\n')
        f.write("bs=4M")
        f.write('\n')
        f.write("direct=1")
        f.write('\n')
        f.write("cpus_allowed="+cpus_allowed)
        f.write('\n')
        f.write("cpus_allowed_policy=split")
        f.write('\n')        
        # f.write("latency_target="+str(i['latency_target']))
        # f.write('\n')
        # f.write("latency_window=1000000")
        # f.write('\n')
        f.write("group_reporting")
        f.write('\n')
        # f.write("write_bw_log=rw")
        # f.write('\n')
        # f.write("log_avg_msec=500")
        # f.write('\n')
        # f.write("allow_mounted_write=1")
        # f.write('\n')
        f.write("[job1]")
        f.write('\n')
        f.write("name=job1")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd0")
        else:
            f.write("rbdname=rbd4")
        f.write('\n')
        f.write("[job2]")
        f.write('\n')
        f.write("name=job2")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd1")
        else:
            f.write("rbdname=rbd5")
        f.write('\n')
        f.write("[job3]")
        f.write('\n')
        f.write("name=job3")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd2")
        else:
            f.write("rbdname=rbd6")

        f.close()
    if node3:
        prefill_ = subprocess.Popen("rm -rf prefill-3.fio && ssh root@"+node3+" 'rm -rf /tmp/prefill.fio'", shell=True, stdout=subprocess.PIPE)
        print(prefill_.stdout.read())
        f = open(r'prefill-3.fio', 'a') #若文件不存在，系统自动创建。'a'表示可连续写入到文件，保留原内容，在原 #内容之后写入。可修改该模式（'w+','w','wb'等）
        f.write("[global]")
        f.write('\n')
        if krbdcase:
            f.write("ioengine=libaio")
        else:
            f.write("ioengine=rbd")
        f.write('\n')
        f.write("numjobs=1")
        f.write('\n')
        f.write("thread=1")
        f.write('\n')
        f.write("invalidate=0")
        f.write('\n')
        if int(krbdcase)==0:
            f.write("clientname=admin")
        f.write('\n')
        if int(krbdcase)==0:
            f.write("pool=replicapool")
        f.write('\n')
        f.write("iodepth=8")
        f.write('\n')
        f.write("size="+blk_size)
        f.write('\n')
        f.write("rw=write")
        f.write('\n')
        f.write("rwmixread=0")
        f.write('\n')
        # f.write("percentage_random="+str(i['percentage_random']))
        # f.write('\n')
        f.write("bs=4M")
        f.write('\n')
        f.write("direct=1")
        f.write('\n')
        f.write("cpus_allowed="+cpus_allowed)
        f.write('\n')
        f.write("cpus_allowed_policy=split")
        f.write('\n')        
        # f.write("latency_target="+str(i['latency_target']))
        # f.write('\n')
        # f.write("latency_window=1000000")
        # f.write('\n')
        f.write("group_reporting")
        f.write('\n')
        # f.write("allow_mounted_write=1")
        # f.write('\n')
        # f.write("write_bw_log=rw")
        # f.write('\n')
        # f.write("log_avg_msec=500")
        # f.write('\n')
        f.write("[job1]")
        f.write('\n')
        f.write("name=job1")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd0")
        else:
            f.write("rbdname=rbd7")
        f.write('\n')
        f.write("[job2]")
        f.write('\n')
        f.write("name=job2")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd1")
        else:
            f.write("rbdname=rbd8")
        f.write('\n')
        f.write("[job3]")
        f.write('\n')
        f.write("name=job3")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd2")
        else:
            f.write("rbdname=rbd9")

        f.close()
    if node1:
        pre_fio_ = subprocess.Popen("scp prefill-1.fio root@"+node1+":/tmp/prefill.fio", shell=True, stdout=subprocess.PIPE)
        print(pre_fio_.stdout.read())
        print(pre_fio_)
        pre_1 = subprocess.Popen("ssh root@"+node1+" sudo sync", shell=True, stdout=subprocess.PIPE)
        print(pre_1.stdout.read())
        print(pre_1)
        pre_2 = subprocess.Popen("ssh root@"+node1+" echo 3 > /proc/sys/vm/drop_caches", shell=True, stdout=subprocess.PIPE)
        print(pre_2.stdout.read())
        print(pre_2)
        time.sleep(1) 
        pre_fio_1 = subprocess.Popen("ssh root@"+node1+" 'fio /tmp/prefill.fio' > prefill-1.out 2>&1 &", shell=True, stdout=subprocess.PIPE)
    if node2:
        pre_fio_ = subprocess.Popen("scp prefill-2.fio root@"+node2+":/tmp/prefill.fio", shell=True, stdout=subprocess.PIPE)
        print(pre_fio_.stdout.read())
        print(pre_fio_)
        pre_1 = subprocess.Popen("ssh root@"+node2+" sudo sync", shell=True, stdout=subprocess.PIPE)
        print(pre_1.stdout.read())
        print(pre_1)
        pre_2 = subprocess.Popen("ssh root@"+node2+" echo 3 > /proc/sys/vm/drop_caches", shell=True, stdout=subprocess.PIPE)
        print(pre_2.stdout.read())
        print(pre_2)
        time.sleep(1) 
        pre_fio_2 = subprocess.Popen("ssh root@"+node2+" 'fio /tmp/prefill.fio' > prefill-2.out 2>&1 &", shell=True, stdout=subprocess.PIPE)
    if node3:
        pre_fio_ = subprocess.Popen("scp prefill-3.fio root@"+node3+":/tmp/prefill.fio", shell=True, stdout=subprocess.PIPE)
        print(pre_fio_.stdout.read())
        print(pre_fio_)
        pre_1 = subprocess.Popen("ssh root@"+node3+" sudo sync", shell=True, stdout=subprocess.PIPE)
        print(pre_1.stdout.read())
        print(pre_1)
        pre_2 = subprocess.Popen("ssh root@"+node3+" echo 3 > /proc/sys/vm/drop_caches", shell=True, stdout=subprocess.PIPE)
        print(pre_2.stdout.read())
        print(pre_2)
        time.sleep(1) 
        pre_fio_3 = subprocess.Popen("ssh root@"+node3+" 'fio /tmp/prefill.fio' > prefill-3.out 2>&1 &", shell=True, stdout=subprocess.PIPE)
    havepreID=0
    jishuqipre=1
    time.sleep(3) 
    while True:
        psfioprefill=str(run_cmd("ps aux|grep -v grep|grep prefill.fio"))[2:-1]
        print(psfioprefill)
        #psfio=str(run_cmd("echo $?"))[2:-1]
        #print(psfio)
        if psfioprefill=="":
            print("no fioprefill processID")
            if havepreID==1:
                jishuqipre=jishuqipre+1
                print("jishuqi fio processID "+str(jishuqipre))
                if jishuqipre>=3:
                    break
        else:
            print("have fioprefill processID")
            havepreID=1
        time.sleep(30)
    prefill_time=prefill_time+1 

if int(create_rbd_once)==1:
    create_rbd_def()
if prefill:
    prefill_rbd_def()
def writecsv(n,m):
    global haveID,jishuqi,line_num
    for i in range(n):
        osd_0=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-0-|awk '{print $2}'"))[2:-2]
        osd_1_=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-1-|awk '{print $2}'"))[2:-2]
        osd_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-2-|awk '{print $2}'"))[2:-2]
        osd_3=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-3-|awk '{print $2}'"))[2:-2]
        osd_4=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-4-|awk '{print $2}'"))[2:-2]
        osd_5=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-5-|awk '{print $2}'"))[2:-2]
        osd_6=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-6-|awk '{print $2}'"))[2:-2]
        osd_7=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-7-|awk '{print $2}'"))[2:-2]
        # osd_8=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-8-|awk '{print $2}'"))[2:-2]
        # osd_9=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-9-|awk '{print $2}'"))[2:-2]
        # osd_10=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-10-|awk '{print $2}'"))[2:-2]
        # osd_11=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-11-|awk '{print $2}'"))[2:-2]
        # osd_12=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-12-|awk '{print $2}'"))[2:-2]
        # osd_13=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-13-|awk '{print $2}'"))[2:-2]
        # osd_14=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-14-|awk '{print $2}'"))[2:-2]
        # osd_15=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-15-|awk '{print $2}'"))[2:-2]
        # osd_16=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-16-|awk '{print $2}'"))[2:-2]
        # osd_17=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-17-|awk '{print $2}'"))[2:-2]
        # osd_18=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-18-|awk '{print $2}'"))[2:-2]
        # osd_19=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-19-|awk '{print $2}'"))[2:-2]
        # osd_20=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-20-|awk '{print $2}'"))[2:-2]
        # osd_21=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-21-|awk '{print $2}'"))[2:-2]
        # osd_22=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-22-|awk '{print $2}'"))[2:-2]
        # osd_23=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-23-|awk '{print $2}'"))[2:-2]
        # osd_24=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-24-|awk '{print $2}'"))[2:-2]
        # osd_25=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-25-|awk '{print $2}'"))[2:-2]
        # osd_26=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-26-|awk '{print $2}'"))[2:-2]
        # osd_27=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-27-|awk '{print $2}'"))[2:-2]
        # osd_28=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-28-|awk '{print $2}'"))[2:-2]
        # osd_29=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-29-|awk '{print $2}'"))[2:-2]

        mon_a=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-mon-a|awk '{print $2}'"))[2:-2]
        mgr_a=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-mgr-a|awk '{print $2}'"))[2:-2]
        tools=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-tools|awk '{print $2}'"))[2:-2]
        operator=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-operator|awk '{print $2}'"))[2:-2]
        crashcollector=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-crashcollector|sed '1!d'|awk '{print $2}'"))[2:-2]
        csi_rbdplugin=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep csi-rbdplugin|grep -v csi-rbdplugin-provisioner|sed '1!d'|awk '{print $2}'"))[2:-2]
        csi_rbdplugin_provisioner=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep csi-rbdplugin-provisioner|sed '1!d'|awk '{print $2}'"))[2:-2]
        csi_cephfsplugin=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep csi-cephfsplugin|grep -v csi-cephfsplugin-provisioner|sed '1!d'|awk '{print $2}'"))[2:-2]
        csi_cephfsplugin_provisioner=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep csi-cephfsplugin-provisioner|sed '1!d'|awk '{print $2}'"))[2:-2]
        csv_writer.writerow([i+m,osd_0,osd_1_,osd_2,osd_3,osd_4,osd_5,osd_6,osd_7,mon_a,mgr_a,tools,operator,crashcollector,csi_rbdplugin,csi_rbdplugin_provisioner,csi_cephfsplugin,csi_cephfsplugin_provisioner])
        # crashcollector_ceph1,crashcollector_ceph2,crashcollector_ceph3,csi_rbdplugin_lt,csi_rbdplugin_sc,csi_rbdplugin_tc,csi_rbdplugin_provisioner_kj,csi_rbdplugin_provisioner_qs,csi_cephfsplugin_7f,csi_cephfsplugin_ck,csi_cephfsplugin_w9,csi_cephfsplugin_provisioner_6r,csi_cephfsplugin_provisioner_h8])


        osd_0_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-0-|awk '{print $3}'"))[2:-3]
        osd_1__2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-1-|awk '{print $3}'"))[2:-3]
        osd_2_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-2-|awk '{print $3}'"))[2:-3]
        osd_3_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-3-|awk '{print $3}'"))[2:-3]
        osd_4_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-4-|awk '{print $3}'"))[2:-3]
        osd_5_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-5-|awk '{print $3}'"))[2:-3]
        osd_6_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-6-|awk '{print $3}'"))[2:-3]
        osd_7_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-7-|awk '{print $3}'"))[2:-3]
        # osd_8_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-8-|awk '{print $3}'"))[2:-3]
        # osd_9_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-9-|awk '{print $3}'"))[2:-3]
        # osd_10_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-10-|awk '{print $3}'"))[2:-3]
        # osd_11_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-11-|awk '{print $3}'"))[2:-3]
        # osd_12_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-12-|awk '{print $3}'"))[2:-3]
        # osd_13_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-13-|awk '{print $3}'"))[2:-3]
        # osd_14_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-14-|awk '{print $3}'"))[2:-3]
        # osd_15_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-15-|awk '{print $3}'"))[2:-3]
        # osd_16_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-16-|awk '{print $3}'"))[2:-3]
        # osd_17_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-17-|awk '{print $3}'"))[2:-3]
        # osd_18_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-18-|awk '{print $3}'"))[2:-3]
        # osd_19_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-19-|awk '{print $3}'"))[2:-3]
        # osd_20_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-20-|awk '{print $3}'"))[2:-3]
        # osd_21_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-21-|awk '{print $3}'"))[2:-3]
        # osd_22_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-22-|awk '{print $3}'"))[2:-3]
        # osd_23_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-23-|awk '{print $3}'"))[2:-3]
        # osd_24_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-24-|awk '{print $3}'"))[2:-3]
        # osd_25_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-25-|awk '{print $3}'"))[2:-3]
        # osd_26_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-26-|awk '{print $3}'"))[2:-3]
        # osd_27_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-27-|awk '{print $3}'"))[2:-3]
        # osd_28_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-28-|awk '{print $3}'"))[2:-3]
        # osd_29_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-osd-29-|awk '{print $3}'"))[2:-3]
    

    

        mon_a_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-mon-a|awk '{print $3}'"))[2:-3]
        mgr_a_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-mgr-a|awk '{print $3}'"))[2:-3]
        tools_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-tools|awk '{print $3}'"))[2:-3]
        operator_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-operator|awk '{print $3}'"))[2:-3]
        crashcollector_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep rook-ceph-crashcollector|sed '1!d'|awk '{print $3}'"))[2:-3]
        csi_rbdplugin_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep csi-rbdplugin|grep -v csi-rbdplugin-provisioner|sed '1!d'|awk '{print $3}'"))[2:-3]
        csi_rbdplugin_provisioner_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep csi-rbdplugin-provisioner|sed '1!d'|awk '{print $3}'"))[2:-3]
        csi_cephfsplugin_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep csi-cephfsplugin|grep -v csi-cephfsplugin-provisioner|sed '1!d'|awk '{print $3}'"))[2:-3]
        csi_cephfsplugin_provisioner_2=str(run_cmd("kubectl top pod -n rook-ceph --use-protocol-buffers|grep csi-cephfsplugin-provisioner|sed '1!d'|awk '{print $3}'"))[2:-3]
        csv_writer2.writerow([i+m,osd_0_2,osd_1__2,osd_2_2,osd_3_2,osd_4_2,osd_5_2,osd_6_2,osd_7_2,mon_a_2,mgr_a_2,tools_2,operator_2,crashcollector_2,csi_rbdplugin_2,csi_rbdplugin_provisioner_2,csi_cephfsplugin_2,csi_cephfsplugin_provisioner_2])

        # psfio=str(run_cmd("kubectl exec -it fio-configmap -- ps aux|grep -v grep|grep fio.fio"))[2:-1]
        print("NO.:"+str(line_num))
        writeL = subprocess.Popen("echo 'NO.:"+str(line_num)+"'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
        print(writeL.stdout.read())
        line_num=line_num+1

        psfio=str(run_cmd("ps aux|grep -v grep|grep fio.fio"))[2:-1]
        print(psfio)
        #psfio=str(run_cmd("echo $?"))[2:-1]
        #print(psfio)
        if psfio=="":
            print("no fio processID")

            psfio1 = subprocess.Popen("echo 'no fio processID '>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
            print(psfio1.stdout.read())
            psfio2 = subprocess.Popen("date>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
            print(psfio2.stdout.read())
            psfio3 = subprocess.Popen("echo '-----'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
            print(psfio3.stdout.read())
            if haveID==1:
                jishuqi=jishuqi+1
                print("jishuqi fio processID "+str(jishuqi))
                if jishuqi>=3:
                    break
        else:
            print("have fio processID")
            psfio1 = subprocess.Popen("echo 'have fio processID '>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
            print(psfio1.stdout.read())
            psfio2 = subprocess.Popen("date>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
            print(psfio2.stdout.read())
            psfio3 = subprocess.Popen("echo '-----'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
            print(psfio3.stdout.read())
            haveID=1
        ##################
        if node1:
            psMeM=str(run_cmd("ssh root@"+node1+" free -g | grep 'Mem'  | awk '{print $7}'"))[2:-1]
            print(psMeM)
            psMeMnode1 = subprocess.Popen("echo '---node1 mem is "+str(psMeM)+"'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
            print(psMeMnode1.stdout.read())
            if int(psMeM) <= 20:
                psMeMnode1 = subprocess.Popen("echo '---node1 mem is full'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
                print(psMeMnode1.stdout.read())
                break
        #############
        if node2:
            psMeM2=str(run_cmd("ssh root@"+node2+" free -g | grep 'Mem'  | awk '{print $7}'"))[2:-1]
            print(psMeM2)
            psMeMnode2 = subprocess.Popen("echo '---node2 mem is "+str(psMeM2)+"'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
            print(psMeMnode2.stdout.read())
            if int(psMeM2) <= 20:
                psMeMnode2 = subprocess.Popen("echo '---node2 mem is full'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
                print(psMeMnode2.stdout.read())
                break
        if node3:
            psMeM3=str(run_cmd("ssh root@"+node3+" free -g | grep 'Mem'  | awk '{print $7}'"))[2:-1]
            print(psMeM3)
            psMeMnode3 = subprocess.Popen("echo '---node3 mem is "+str(psMeM3)+"'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
            print(psMeMnode3.stdout.read())
            if int(psMeM3) <= 20:
                psMeMnode3 = subprocess.Popen("echo '---node3 mem is full'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
                print(psMeMnode3.stdout.read())
                break
        time.sleep(30)
for i in fiodict:
    #global prefill_time
    haveID=0
    jishuqi=0
    line_num=1
    # print(i['iodepth'],i['rwmixread'])
    print(i)
    continue_txt=str(run_cmd("cat continue.txt"))[2:-1]
    if int(continue_txt) == 0:
        willbreak = subprocess.Popen("echo '---break'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
        print(willbreak.stdout.read())
        break
    if prefill:
        if str(get_variable_name(i))[-8:] == "seqwrite":
            if prefill_time > first_write_case_is_seqwrite :
                if sure_prefill_seqw:
                    del_rbd_def()
                    create_rbd_def()
                    prefill_rbd_def()
            prefill_time=prefill_time+1 
            print("prefill_time="+str(prefill_time))
    elif force_prefill_before_seqwrtie:
        if str(get_variable_name(i))[-8:] == "seqwrite":
            if prefill_time:
                del_rbd_def()
                create_rbd_def()
                prefill_rbd_def()
            prefill_time=prefill_time+1
            print("prefill_time="+str(prefill_time))
# import sh
# import codecs

# wait user input
# iodepth = input("(iodepth= 1 or 2 or 4 or 8) Enter iodepth =")
# rwmixread = input("(rwmixread= 70 or 80 or 50 or 95) Enter rwmixread =")
# percentage_random = input("(percentage_random= 100,100 or 20,80 or 50,0 or 0,0 or 50,50) Enter percentage_random =")
# bs = input("(bs= 4k,4k or 8k,8k or 32k,8k or 32k,32k or 1024k,1024k or 32k,32k) Enter bs =")
# latency_target = input("(latency_target= 1000 or 5000 or 10000) Enter latency_target =")
# Dev = input("(Dev= /dev/sda or /datadir/t0) Enter Dev =")


# creat fio
    if node1:
        pre = subprocess.Popen("rm -rf fio*.fio && ssh root@"+node1+" 'rm -rf /tmp/fio.fio'", shell=True, stdout=subprocess.PIPE)
        print(pre.stdout.read())
        if fio_draw_pic:
            pre = subprocess.Popen("ssh root@"+node1+" 'rm -rf /tmp/*rw_*.log'", shell=True, stdout=subprocess.PIPE)
            print(pre.stdout.read())
        if perf_data:
            pre_perf = subprocess.Popen("ssh root@"+node1+" 'rm -rf /tmp/perf.data /opt/perf.data'", shell=True, stdout=subprocess.PIPE)
            print(pre_perf.stdout.read())
        f = open(r'fio-1.fio', 'a') #若文件不存在，系统自动创建。'a'表示可连续写入到文件，保留原内容，在原
                            #内容之后写入。可修改该模式（'w+','w','wb'等）
        f.write("[global]")
        f.write('\n')
        if krbdcase:
            f.write("ioengine=libaio")
        else:
            f.write("ioengine=rbd")        
        f.write('\n')
        f.write("numjobs="+str(i['numjob']))
        f.write('\n')
        f.write("thread=1")
        f.write('\n')
        f.write("invalidate=0")
        f.write('\n')
        if int(krbdcase)==0:
            f.write("clientname=admin")
        f.write('\n')
        if int(krbdcase)==0:
            f.write("pool=replicapool")
        f.write('\n')
        f.write("iodepth="+str(i['iodepth']))
        f.write('\n')
        f.write("size="+blk_size)
        f.write('\n')
        f.write("rw="+str(i['readorwrite']))
        f.write('\n')
        f.write("rwmixread="+str(i['rwmixread']))
        f.write('\n')
        # f.write("percentage_random="+str(i['percentage_random']))
        # f.write('\n')
        f.write("bs="+str(i['bs']))
        f.write('\n')
        f.write("direct=1")
        f.write('\n')
        f.write("cpus_allowed="+cpus_allowed)
        f.write('\n')
        f.write("cpus_allowed_policy=split")
        f.write('\n')        
        f.write("time_based=1")
        f.write('\n')
        f.write("runtime="+runtime)
        f.write('\n')
        f.write("ramp_time="+ramp_time)
        f.write('\n')
        # f.write("latency_target="+str(i['latency_target']))
        # f.write('\n')
        # f.write("latency_window=1000000")
        # f.write('\n')
        f.write("group_reporting")
        f.write('\n')
        if fio_draw_pic:
            if str(get_variable_name(i))[0:9] == "fiodict1M":
                f.write("write_bw_log=rw")
                f.write('\n')
            if str(get_variable_name(i))[0:8] == "fiodict_":
                f.write("write_iops_log=rw")
                f.write('\n')
            f.write("log_avg_msec=500")
            f.write('\n')
        # f.write("allow_mounted_write=1")
        # f.write('\n')
        f.write("[job1]")
        f.write('\n')
        f.write("name=job1")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd0")
        else:
            f.write("rbdname=rbd1")
        f.write('\n')
        f.write("[job2]")
        f.write('\n')
        f.write("name=job2")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd1")
        else:
            f.write("rbdname=rbd2")
        f.write('\n')
        f.write("[job3]")
        f.write('\n')
        f.write("name=job3")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd2")
        else:
            f.write("rbdname=rbd3")

        f.close()
    if node2:
        pre = subprocess.Popen("ssh root@"+node2+" 'rm -rf /tmp/fio.fio'", shell=True, stdout=subprocess.PIPE)
        print(pre.stdout.read())
        if fio_draw_pic:
            pre = subprocess.Popen("ssh root@"+node2+" 'rm -rf /tmp/*rw_*.log'", shell=True, stdout=subprocess.PIPE)
            print(pre.stdout.read())
        if perf_data:
            pre_perf = subprocess.Popen("ssh root@"+node2+" 'rm -rf /tmp/perf.data /opt/perf.data'", shell=True, stdout=subprocess.PIPE)
            print(pre_perf.stdout.read())
###########################
        f = open(r'fio-2.fio', 'a') #若文件不存在，系统自动创建。'a'表示可连续写入到文件，保留原内容，在原
                            #内容之后写入。可修改该模式（'w+','w','wb'等）
        f.write("[global]")
        f.write('\n')
        if krbdcase:
            f.write("ioengine=libaio")
        else:
            f.write("ioengine=rbd")        
        f.write('\n')
        f.write("numjobs="+str(i['numjob']))
        f.write('\n')
        f.write("thread=1")
        f.write('\n')
        f.write("invalidate=0")
        f.write('\n')
        if int(krbdcase)==0:
            f.write("clientname=admin")
        f.write('\n')
        if int(krbdcase)==0:
            f.write("pool=replicapool")
        f.write('\n')
        f.write("iodepth="+str(i['iodepth']))
        f.write('\n')
        f.write("size="+blk_size)
        f.write('\n')
        f.write("rw="+str(i['readorwrite']))
        f.write('\n')
        f.write("rwmixread="+str(i['rwmixread']))
        f.write('\n')
        # f.write("percentage_random="+str(i['percentage_random']))
        # f.write('\n')
        f.write("bs="+str(i['bs']))
        f.write('\n')
        f.write("direct=1")
        f.write('\n')
        f.write("cpus_allowed="+cpus_allowed)
        f.write('\n')
        f.write("cpus_allowed_policy=split")
        f.write('\n')        
        f.write("time_based=1")
        f.write('\n')
        f.write("runtime="+runtime)
        f.write('\n')
        f.write("ramp_time="+ramp_time)
        f.write('\n')
        # f.write("latency_target="+str(i['latency_target']))
        # f.write('\n')
        # f.write("latency_window=1000000")
        # f.write('\n')
        f.write("group_reporting")
        f.write('\n')
        if fio_draw_pic:
            if str(get_variable_name(i))[0:9] == "fiodict1M":
                f.write("write_bw_log=rw")
                f.write('\n')
            if str(get_variable_name(i))[0:8] == "fiodict_":
                f.write("write_iops_log=rw")
                f.write('\n')
            f.write("log_avg_msec=500")
            f.write('\n')
        # f.write("allow_mounted_write=1")
        # f.write('\n')
        f.write("[job1]")
        f.write('\n')
        f.write("name=job1")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd0")
        else:
            f.write("rbdname=rbd4")
        f.write('\n')
        f.write("[job2]")
        f.write('\n')
        f.write("name=job2")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd1")
        else:
            f.write("rbdname=rbd5")
        f.write('\n')
        f.write("[job3]")
        f.write('\n')
        f.write("name=job3")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd2")
        else:
            f.write("rbdname=rbd6")

        f.close()
    if node3:
        pre = subprocess.Popen("ssh root@"+node3+" 'rm -rf /tmp/fio.fio'", shell=True, stdout=subprocess.PIPE)
        print(pre.stdout.read())
        if fio_draw_pic:
            pre = subprocess.Popen("ssh root@"+node3+" 'rm -rf /tmp/*rw_*.log'", shell=True, stdout=subprocess.PIPE)
            print(pre.stdout.read())
        if perf_data:
            pre_perf = subprocess.Popen("ssh root@"+node3+" 'rm -rf /tmp/perf.data /opt/perf.data'", shell=True, stdout=subprocess.PIPE)
            print(pre_perf.stdout.read())
###########################
        f = open(r'fio-3.fio', 'a') #若文件不存在，系统自动创建。'a'表示可连续写入到文件，保留原内容，在原
                            #内容之后写入。可修改该模式（'w+','w','wb'等）
        f.write("[global]")
        f.write('\n')
        if krbdcase:
            f.write("ioengine=libaio")
        else:
            f.write("ioengine=rbd")        
        f.write('\n')
        f.write("numjobs="+str(i['numjob']))
        f.write('\n')
        f.write("thread=1")
        f.write('\n')
        f.write("invalidate=0")
        f.write('\n')
        if int(krbdcase)==0:
            f.write("clientname=admin")
        f.write('\n')
        if int(krbdcase)==0:
            f.write("pool=replicapool")
        f.write('\n')
        f.write("iodepth="+str(i['iodepth']))
        f.write('\n')
        f.write("size="+blk_size)
        f.write('\n')
        f.write("rw="+str(i['readorwrite']))
        f.write('\n')
        f.write("rwmixread="+str(i['rwmixread']))
        f.write('\n')
        # f.write("percentage_random="+str(i['percentage_random']))
        # f.write('\n')
        f.write("bs="+str(i['bs']))
        f.write('\n')
        f.write("direct=1")
        f.write('\n')
        f.write("cpus_allowed="+cpus_allowed)
        f.write('\n')
        f.write("cpus_allowed_policy=split")
        f.write('\n')        
        f.write("time_based=1")
        f.write('\n')
        f.write("runtime="+runtime)
        f.write('\n')
        f.write("ramp_time="+ramp_time)
        f.write('\n')
        # f.write("latency_target="+str(i['latency_target']))
        # f.write('\n')
        # f.write("latency_window=1000000")
        # f.write('\n')
        f.write("group_reporting")
        f.write('\n')
        # f.write("allow_mounted_write=1")
        # f.write('\n')
        if fio_draw_pic:
            if str(get_variable_name(i))[0:9] == "fiodict1M":
                f.write("write_bw_log=rw")
                f.write('\n')
            if str(get_variable_name(i))[0:8] == "fiodict_":
                f.write("write_iops_log=rw")
                f.write('\n')
            f.write("log_avg_msec=500")
            f.write('\n')
        f.write("[job1]")
        f.write('\n')
        f.write("name=job1")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd0")
        else:
            f.write("rbdname=rbd7")
        f.write('\n')
        f.write("[job2]")
        f.write('\n')
        f.write("name=job2")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd1")
        else:
            f.write("rbdname=rbd8")
        f.write('\n')
        f.write("[job3]")
        f.write('\n')
        f.write("name=job3")
        f.write('\n')
        if krbdcase:
            f.write("filename=/dev/rbd2")
        else:
            f.write("rbdname=rbd9")
        f.close()

    if int(clean_rbd)==1:
        create_rbd_def()

    localtime = time.asctime( time.localtime(time.time()) )
    print ("本地时间为 :", localtime)

    str_new = str(get_variable_name(i))+"-"+localtime.replace(" ", "-")
    str_new = str_new.replace(":", "-")
    premkdir = subprocess.Popen('mkdir '+str_new+"out", shell=True, stdout=subprocess.PIPE)
    print(premkdir.stdout.read())
    if fio_draw_pic:
        if node1:
            premkdir1_fio_draw = subprocess.Popen("mkdir "+str_new+"out/"+node1_hostname+"-fio_draw_log", shell=True, stdout=subprocess.PIPE)
            print(premkdir1_fio_draw.stdout.read())
        if node2:
            premkdir2_fio_draw = subprocess.Popen("mkdir "+str_new+"out/"+node2_hostname+"-fio_draw_log", shell=True, stdout=subprocess.PIPE)
            print(premkdir2_fio_draw.stdout.read())
        if node3:
            premkdir3_fio_draw = subprocess.Popen("mkdir "+str_new+"out/"+node3_hostname+"-fio_draw_log", shell=True, stdout=subprocess.PIPE)
            print(premkdir3_fio_draw.stdout.read())
    starttimelog = subprocess.Popen("echo 'start '>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
    print(starttimelog.stdout.read())
    starttimelog = subprocess.Popen("date>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
    print(starttimelog.stdout.read())
    starttimelog = subprocess.Popen("echo '-----'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
    print(starttimelog.stdout.read())

    start_ceph_s = subprocess.Popen("ceph -s >>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
    print(start_ceph_s.stdout.read())

    start_ceph_df = subprocess.Popen("ceph osd df >>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
    print(start_ceph_df.stdout.read())

    pre_cp = subprocess.Popen("cp -r fio*.fio "+str_new+"out/", shell=True, stdout=subprocess.PIPE)
    print(pre_cp.stdout.read())
# write_file = open('rand-read.fio.out', 'w')
# write_file.write(str(localtime))
# fio = subprocess.Popen('date && fio rand-read.fio >> rand-read.fio.out', shell=True, stdout=subprocess.PIPE)
# perf = subprocess.Popen('sh perf.sh', shell=True, stdout=subprocess.PIPE)
# aaad = p.stdout.readlines()
# print(p.stdout.read())
# aaa=p.stdout.read()
# print(str(aaa))
####下面是重头戏
    time.sleep(30)


    shijian=str(run_cmd('date'))[2:-1]
    print(shijian)
    if node1:
        pre_fio_sar = subprocess.Popen("scp fio-1.fio root@"+node1+":/tmp/fio.fio", shell=True, stdout=subprocess.PIPE)
        print(pre_fio_sar.stdout.read())
        print(pre_fio_sar)
        pre_1 = subprocess.Popen("ssh root@"+node1+" sudo sync", shell=True, stdout=subprocess.PIPE)
        print(pre_1.stdout.read())
        print(pre_1)
        pre_2 = subprocess.Popen("ssh root@"+node1+" echo 3 > /proc/sys/vm/drop_caches", shell=True, stdout=subprocess.PIPE)
        print(pre_2.stdout.read())
        print(pre_2)
        pre_3 = subprocess.Popen("ssh root@"+node1+" rm -rf /tmp/*dstat*", shell=True, stdout=subprocess.PIPE)
        print(pre_3.stdout.read())
        print(pre_3)
    if node2:
        pre_fio_sar = subprocess.Popen("scp fio-2.fio root@"+node2+":/tmp/fio.fio", shell=True, stdout=subprocess.PIPE)
        print(pre_fio_sar.stdout.read())
        pre_1 = subprocess.Popen("ssh root@"+node2+" sudo sync", shell=True, stdout=subprocess.PIPE)
        print(pre_1.stdout.read())
        pre_2 = subprocess.Popen("ssh root@"+node2+" echo 3 > /proc/sys/vm/drop_caches", shell=True, stdout=subprocess.PIPE)
        print(pre_2.stdout.read())
        pre_3 = subprocess.Popen("ssh root@"+node2+" rm -rf /tmp/*dstat*", shell=True, stdout=subprocess.PIPE)
        print(pre_3.stdout.read())
    if node3:
        pre_fio_sar = subprocess.Popen("scp fio-3.fio root@"+node3+":/tmp/fio.fio ", shell=True, stdout=subprocess.PIPE)
        print(pre_fio_sar.stdout.read())
        pre_1 = subprocess.Popen("ssh root@"+node3+" sudo sync", shell=True, stdout=subprocess.PIPE)
        print(pre_1.stdout.read())
        pre_2 = subprocess.Popen("ssh root@"+node3+" echo 3 > /proc/sys/vm/drop_caches", shell=True, stdout=subprocess.PIPE)
        print(pre_2.stdout.read())
        pre_3 = subprocess.Popen("ssh root@"+node3+" rm -rf /tmp/*dstat*", shell=True, stdout=subprocess.PIPE)
        print(pre_3.stdout.read())
##################
    if node1:
        psMeM=str(run_cmd("ssh root@"+node1+" free -g | grep 'Mem'  | awk '{print $7}'"))[2:-1]
        print(psMeM)
        psMeMnode1 = subprocess.Popen("echo '---node1 mem is "+str(psMeM)+"'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
        print(psMeMnode1.stdout.read())
        if int(psMeM) <= 20:
            psMeMnode1 = subprocess.Popen("echo '---node1 mem is full'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
            print(psMeMnode1.stdout.read())
            break
    #############
    if node2:
        psMeM2=str(run_cmd("ssh root@"+node2+" free -g | grep 'Mem'  | awk '{print $7}'"))[2:-1]
        print(psMeM2)
        psMeMnode2 = subprocess.Popen("echo '---node2 mem is "+str(psMeM2)+"'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
        print(psMeMnode2.stdout.read())
        if int(psMeM2) <= 20:
            psMeMnode2 = subprocess.Popen("echo '---node2 mem is full'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
            print(psMeMnode2.stdout.read())
            break
    if node3:
        psMeM3=str(run_cmd("ssh root@"+node3+" free -g | grep 'Mem'  | awk '{print $7}'"))[2:-1]
        print(psMeM3)
        psMeMnode3 = subprocess.Popen("echo '---node3 mem is "+str(psMeM3)+"'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
        print(psMeMnode3.stdout.read())
        if int(psMeM3) <= 20:
            psMeMnode3 = subprocess.Popen("echo '---node3 mem is full'>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
            print(psMeMnode3.stdout.read())
            break
##########

    # 1. 创建文件对象
    f1 = open(str_new+"out/"+'top-ceph-cpu.csv','w',encoding='utf-8-sig',newline='')
    f2 = open(str_new+"out/"+'top-ceph-mem.csv','w',encoding='utf-8-sig',newline='')
    # 2. 基于文件对象构建 csv写入对象
    csv_writer = csv.writer(f1)
    csv_writer2 = csv.writer(f2)
    # 3. 构建列表头
    csv_writer.writerow([localtime,"rook-ceph-osd-0","rook-ceph-osd-1","rook-ceph-osd-2","rook-ceph-osd-3","rook-ceph-osd-4","rook-ceph-osd-5","rook-ceph-osd-6","rook-ceph-osd-7","rook-ceph-mon-a","rook-ceph-mgr-a","rook-ceph-tools","rook-ceph-operator","rook-ceph-crashcollector","csi-rbdplugin","csi-rbdplugin-provisioner","csi-cephfsplugin","csi-cephfsplugin-provisioner"])
    csv_writer2.writerow([localtime,"rook-ceph-osd-0","rook-ceph-osd-1","rook-ceph-osd-2","rook-ceph-osd-3","rook-ceph-osd-4","rook-ceph-osd-5","rook-ceph-osd-6","rook-ceph-osd-7","rook-ceph-mon-a","rook-ceph-mgr-a","rook-ceph-tools","rook-ceph-operator","rook-ceph-crashcollector","csi-rbdplugin","csi-rbdplugin-provisioner","csi-cephfsplugin","csi-cephfsplugin-provisioner"])

    writecsv(2,0)
# dstat = subprocess.Popen('dstat -tcmynd -D total,sda,sdb --output dstat.csv 2>&1 &', shell=True, stdout=subprocess.PIPE)
    # dstat= subprocess.Popen("dstat -tcmynd -D total,sdb,sdc,sdd,sde,sdf,sdg| tee "+str_new+"out/"+"dstat.txt 2>&1 &", shell=True, stdout=subprocess.PIPE)
    sar_collect_top= subprocess.Popen("cd "+CODE_DIR+"Storage-performance-analysis && ./run.sh --telem  --delay_run=5s --duration="+str(int(runtime)+int(overtime))+"s ", shell=True, stdout=subprocess.PIPE)
    # print(sar_collect_top.stdout.read())
    # if node1:
    #     sar_collect_1 = subprocess.Popen("ssh root@"+node1+" 'bash /tmp/sar_collect.sh "+sar_runtime+" 2>&1 &'", shell=True, stdout=subprocess.PIPE)
    # if node2:
    #     sar_collect_2 = subprocess.Popen("ssh root@"+node2+" 'bash /tmp/sar_collect.sh "+sar_runtime+" 2>&1 &'", shell=True, stdout=subprocess.PIPE)
    # if node3:
    #     sar_collect_3 = subprocess.Popen("ssh root@"+node3+" 'bash /tmp/sar_collect.sh "+sar_runtime+" 2>&1 &'", shell=True, stdout=subprocess.PIPE)

# top -c -b -d5 | grep -iE 'osd|fio|kubelet|reactor' 无法远程获取正确的log
    if node1:
        # top_collect_1 = subprocess.Popen("top -c -b -d5 | grep -iE 'ceph|fio|kubelet|reactor|qemu|vhost|build' >"+str_new+"out/"+"`ssh root@"+node1+" hostname`_top.log 2>&1 &", shell=True, stdout=subprocess.PIPE)
        fio_1 = subprocess.Popen("ssh root@"+node1+" 'cd /tmp && fio /tmp/fio.fio' >"+str_new+"out/"+"`ssh root@"+node1+" hostname`-fio-1.out 2>&1 &", shell=True, stdout=subprocess.PIPE)
        dstatout1= subprocess.Popen("ssh root@"+node1+" 'dstat -tcmynd -D total,"+dstat_disk1+" | tee /tmp/`hostname`-dstat-1.txt 2>&1 &'", shell=True, stdout=subprocess.PIPE)

    if node2:
        # top_collect_2 = subprocess.Popen("ssh root@"+node2+" top -b -d5 | grep -iE 'ceph|fio|kubelet|reactor|qemu|vhost|build' >"+str_new+"out/"+"`ssh root@"+node2+" hostname`_top.log 2>&1 &", shell=True, stdout=subprocess.PIPE)
        fio_2 = subprocess.Popen("ssh root@"+node2+" 'cd /tmp && fio /tmp/fio.fio' >"+str_new+"out/"+"`ssh root@"+node2+" hostname`-fio-2.out 2>&1 &", shell=True, stdout=subprocess.PIPE)
        dstatout2= subprocess.Popen("ssh root@"+node2+" 'dstat -tcmynd -D total,"+dstat_disk2+" | tee /tmp/`hostname`-dstat-2.txt 2>&1 &'", shell=True, stdout=subprocess.PIPE)

    if node3:
        # top_collect_3 = subprocess.Popen("ssh root@"+node3+" top -b -d5 | grep -iE 'ceph|fio|kubelet|reactor|qemu|vhost|build' >"+str_new+"out/"+"`ssh root@"+node3+" hostname`_top.log 2>&1 &", shell=True, stdout=subprocess.PIPE)
        fio_3 = subprocess.Popen("ssh root@"+node3+" 'cd /tmp && fio /tmp/fio.fio' >"+str_new+"out/"+"`ssh root@"+node3+" hostname`-fio-3.out 2>&1 &", shell=True, stdout=subprocess.PIPE)
        dstatout3= subprocess.Popen("ssh root@"+node3+" 'dstat -tcmynd -D total,"+dstat_disk3+" | tee /tmp/`hostname`-dstat-3.txt 2>&1 &'", shell=True, stdout=subprocess.PIPE)

    writecsv(15,10)   
    if perf_data:
        if node1:
            node1_osd_PID=str(run_cmd("ssh root@"+node1+" top -b -n 1|grep -v grep|grep ceph-osd |awk '{print $1}'|sed '1!d'"))[2:-1]
            print(node1_osd_PID)
            print("cd /tmp && perf record -p  "+node1_osd_PID+" -F 99 --call-graph dwarf -- sleep 60 ")
            perf_scp = subprocess.Popen("scp perf.sh root@"+node1+":/tmp/", shell=True, stdout=subprocess.PIPE)
            time.sleep(1)
            perf_1 = subprocess.Popen("ssh root@"+node1+" 'bash /tmp/perf.sh'", shell=True, stdout=subprocess.PIPE)

        if node2:
            node2_osd_PID=str(run_cmd("ssh root@"+node2+" top -b -n 1|grep -v grep|grep ceph-osd |awk '{print $1}'|sed '1!d'"))[2:-1]
            print(node2_osd_PID)
            print("ssh root@"+node2+" 'cd /tmp && perf record -p "+node2_osd_PID+" -F 99 --call-graph dwarf -- sleep 60 '")
            perf_scp = subprocess.Popen("scp perf.sh root@"+node2+":/tmp/", shell=True, stdout=subprocess.PIPE)
            time.sleep(1)
            perf_2 = subprocess.Popen("ssh root@"+node2+" 'bash /tmp/perf.sh'", shell=True, stdout=subprocess.PIPE)
        if node3:
            node3_osd_PID=str(run_cmd("ssh root@"+node3+" top -b -n 1|grep -v grep|grep ceph-osd |awk '{print $1}'|sed '1!d'"))[2:-1]
            print(node3_osd_PID)
            print("ssh root@"+node3+" 'cd /tmp && perf record -p "+node3_osd_PID+" -F 99 --call-graph dwarf -- sleep 60 '")
            perf_scp = subprocess.Popen("scp perf.sh root@"+node3+":/tmp/", shell=True, stdout=subprocess.PIPE)
            time.sleep(1)
            perf_3 = subprocess.Popen("ssh root@"+node3+" 'bash /tmp/perf.sh'", shell=True, stdout=subprocess.PIPE)
    writecsv(5000,20)
# 5. 关闭文件
    f1.close()
    f2.close()
    time.sleep(0.5)
    if node1:
        killdstat = subprocess.Popen("kill -9 $(ps aux|grep dstat|grep -v grep|awk '{print $2}')", shell=True, stdout=subprocess.PIPE)
        print(killdstat.stdout.read())
 
        killdstata = subprocess.Popen(" ssh root@"+node1+" kill -9 $(ps aux|grep dstat|grep -v grep|awk '{print $2}'|sed '1!d') ", shell=True, stdout=subprocess.PIPE)
        print(killdstata.stdout.read())
        killdstata = subprocess.Popen(" ssh root@"+node1+" kill -9 $(ps aux|grep dstat|grep -v grep|awk '{print $2}'|sed '1!d') ", shell=True, stdout=subprocess.PIPE)
        print(killdstata.stdout.read())

        scpa = subprocess.Popen("scp -r root@"+node1+":/tmp/*dstat-1.txt "+str_new+"out/", shell=True, stdout=subprocess.PIPE)
        print(scpa.stdout.read())
        if fio_draw_pic:
            scpa1_fio_draw = subprocess.Popen("scp -r root@"+node1+":/tmp/*rw_*.log "+str_new+"out/"+node1_hostname+"-fio_draw_log/", shell=True, stdout=subprocess.PIPE)
            print(scpa1_fio_draw.stdout.read())
        if perf_data:
            scpa1_perf= subprocess.Popen("scp -r root@"+node1+":/tmp/perf.data "+str_new+"out/"+node1_hostname+"-perf.data", shell=True, stdout=subprocess.PIPE)
            print(scpa1_perf.stdout.read())
            scpa1_perf= subprocess.Popen("scp -r root@"+node1+":/opt/perf.data "+str_new+"out/"+node1_hostname+"-hotspot-perf.data", shell=True, stdout=subprocess.PIPE)
            print(scpa1_perf.stdout.read())
        # sara = subprocess.Popen("scp -r root@"+node1+":/tmp/sar_log "+str_new+"out/sar_log_node1", shell=True, stdout=subprocess.PIPE)
        # print(sara.stdout.read())
        # killdtop1 = subprocess.Popen("kill -9 $(ps aux|grep 'ssh root@"+node1+" top -c'|grep -v grep|awk '{print $2}'|sed '1!d')", shell=True, stdout=subprocess.PIPE)
        # print(killdtop1.stdout.read())
        # killdtop11 = subprocess.Popen("ssh root@"+node1+" kill -9 $(ps aux|grep 'top -c'|grep -v grep|awk '{print $2}'|sed '1!d')", shell=True, stdout=subprocess.PIPE)
        # print(killdtop11.stdout.read())

    if node2:
        killdstata = subprocess.Popen(" ssh root@"+node2+" kill -9 $(ps aux|grep dstat|grep -v grep|awk '{print $2}'|sed '1!d') ", shell=True, stdout=subprocess.PIPE)
        print(killdstata.stdout.read())
        killdstata = subprocess.Popen(" ssh root@"+node2+" kill -9 $(ps aux|grep dstat|grep -v grep|awk '{print $2}'|sed '1!d') ", shell=True, stdout=subprocess.PIPE)
        print(killdstata.stdout.read())

        scpa = subprocess.Popen("scp -r root@"+node2+":/tmp/*dstat-2.txt "+str_new+"out/", shell=True, stdout=subprocess.PIPE)
        print(scpa.stdout.read())
        if fio_draw_pic:
            scpa2_fio_draw = subprocess.Popen("scp -r root@"+node2+":/tmp/*rw_*.log "+str_new+"out/"+node2_hostname+"-fio_draw_log/", shell=True, stdout=subprocess.PIPE)
            print(scpa2_fio_draw.stdout.read())
        if perf_data:
            scpa2_perf= subprocess.Popen("scp -r root@"+node2+":/tmp/perf.data "+str_new+"out/"+node2_hostname+"-perf.data", shell=True, stdout=subprocess.PIPE)
            print(scpa2_perf.stdout.read())
            scpa2_perf= subprocess.Popen("scp -r root@"+node2+":/opt/perf.data "+str_new+"out/"+node2_hostname+"-hotspot-perf.data", shell=True, stdout=subprocess.PIPE)
            print(scpa2_perf.stdout.read())
        # sara = subprocess.Popen("scp -r root@"+node2+":/tmp/sar_log "+str_new+"out/sar_log_node2", shell=True, stdout=subprocess.PIPE)
        # print(sara.stdout.read())
        # killdtop1 = subprocess.Popen("kill -9 $(ps aux|grep 'ssh root@"+node2+" top -b'|grep -v grep|awk '{print $2}'|sed '1!d')", shell=True, stdout=subprocess.PIPE)
        # print(killdtop1.stdout.read())
        # killdtop11 = subprocess.Popen("ssh root@"+node2+" kill -9 $(ps aux|grep 'top -b'|grep -v grep|awk '{print $2}'|sed '1!d')", shell=True, stdout=subprocess.PIPE)
        # print(killdtop11.stdout.read())

    if node3:
        killdstata = subprocess.Popen(" ssh root@"+node3+" kill -9 $(ps aux|grep dstat|grep -v grep|awk '{print $2}'|sed '1!d') ", shell=True, stdout=subprocess.PIPE)
        print(killdstata.stdout.read())
        killdstata = subprocess.Popen(" ssh root@"+node3+" kill -9 $(ps aux|grep dstat|grep -v grep|awk '{print $2}'|sed '1!d') ", shell=True, stdout=subprocess.PIPE)
        print(killdstata.stdout.read())

        scpa = subprocess.Popen("scp -r root@"+node3+":/tmp/*dstat-3.txt "+str_new+"out/", shell=True, stdout=subprocess.PIPE)
        print(scpa.stdout.read())
        if fio_draw_pic:
            scpa3_fio_draw = subprocess.Popen("scp -r root@"+node3+":/tmp/*rw_*.log "+str_new+"out/"+node3_hostname+"-fio_draw_log/", shell=True, stdout=subprocess.PIPE)
            print(scpa3_fio_draw.stdout.read())
        if perf_data:
            scpa3_perf= subprocess.Popen("scp -r root@"+node3+":/tmp/perf.data "+str_new+"out/"+node3_hostname+"-perf.data", shell=True, stdout=subprocess.PIPE)
            print(scpa3_perf.stdout.read())
            scpa3_perf= subprocess.Popen("scp -r root@"+node3+":/opt/perf.data "+str_new+"out/"+node3_hostname+"-hotspot-perf.data", shell=True, stdout=subprocess.PIPE)
            print(scpa3_perf.stdout.read())
        # sara = subprocess.Popen("scp -r root@"+node3+":/tmp/sar_log "+str_new+"out/sar_log_node3", shell=True, stdout=subprocess.PIPE)
        # print(sara.stdout.read())
        # killdtop1 = subprocess.Popen("kill -9 $(ps aux|grep 'ssh root@"+node3+" top -b'|grep -v grep|awk '{print $2}'|sed '1!d')", shell=True, stdout=subprocess.PIPE)
        # print(killdtop1.stdout.read())
        # killdtop11 = subprocess.Popen("ssh root@"+node3+" kill -9 $(ps aux|grep 'top -b'|grep -v grep|awk '{print $2}'|sed '1!d')", shell=True, stdout=subprocess.PIPE)
        # print(killdtop11.stdout.read()) 
    while True:
        pstopsar=str(run_cmd("kubectl get po |grep telemetry-daemon-"))[2:-1]
        print(pstopsar)
        #psfio=str(run_cmd("echo $?"))[2:-1]
        #print(psfio)
        if pstopsar=="":
            print("no telemetry-daemon-pods")
            break
        else:
            print("have telemetry-daemon-pods")
        time.sleep(30)       
    scpab = subprocess.Popen("mv "+CODE_DIR+"Storage-performance-analysis/logs/* "+CODE_DIR+str_new+"out/", shell=True, stdout=subprocess.PIPE)
    print(scpab.stdout.read())
    #delab = subprocess.Popen("rm -rf Storage-performance-analysis/logs/* ", shell=True, stdout=subprocess.PIPE)
    #print(delab.stdout.read())
    if int(clean_rbd)==1:
        del_rbd_def()
    # print(killdstat.stdout.read())

# for num in aaa:
#     print (num)
#     print(type(num))
# print(type(aaa)) #list
    end_ceph_s = subprocess.Popen("ceph -s >>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
    print(end_ceph_s.stdout.read())

    end_ceph_df = subprocess.Popen("ceph osd df >>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
    print(end_ceph_df.stdout.read())
    print("fin")
    shijianend=str(run_cmd('date'))[2:-1]
    print(shijianend)
    endtimelog = subprocess.Popen("echo 'fin '>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
    print(endtimelog.stdout.read())
    endtimelog = subprocess.Popen("date>>"+str_new+"out/"+"time.log", shell=True, stdout=subprocess.PIPE)
    print(endtimelog.stdout.read())

    time.sleep(30)
if int(del_rbd_end)==1:
    del_rbd_def()
# umap_rbd_fin = subprocess.Popen("ssh root@192.168.126.37 'rbd unmap /dev/rbd0 && rbd unmap /dev/rbd1  && rbd unmap /dev/rbd2 && rbd -p replicapool  rm rbd1 && rbd -p replicapool  rm rbd2  && rbd -p replicapool  rm rbd3' &&  ssh root@192.168.126.40 'rbd unmap /dev/rbd0 && rbd unmap /dev/rbd1  && rbd unmap /dev/rbd2 && rbd -p replicapool  rm rbd4 && rbd -p replicapool  rm rbd5  && rbd -p replicapool  rm rbd6'", shell=True, stdout=subprocess.PIPE)
# print(umap_rbd_fin.stdout.read())
# 1. 创建文件对象
# f = open('top.csv','w',encoding='utf-8-sig',newline='')

# # 2. 基于文件对象构建 csv写入对象
# csv_writer = csv.writer(f)

# # 3. 构建列表头
# csv_writer.writerow(["姓名","年龄","性别"])

# # 4. 写入csv文件内容
# # for num in aaa:
# #     print (num)
# #     print(type(num))
# #     csv_writer.writerow(["l",'18',str(num)])
# csv_writer.writerow(["l",'18',bbb])
# csv_writer.writerow(["c",'20','男'])
# csv_writer.writerow(["w",'22','女'])

# # 5. 关闭文件
# f.close()

# if __name__ == "__main__":
#     file_name = "data.csv"
#     with open(file_name, "wb") as f:
#         f.write(codecs.BOM_GBK)
#         csv_write = csv.writer(f)
#         csv_write.writerows([["姓名", "年龄"], ["张三", 18]])
