import openpyxl
import os
import sys

#import os.path
from  openpyxl import  Workbook 


# file_directory = os.path.dirname(os.path.abspath(__file__))
# print('file path = %s' % file_directory)

currentPath = os.getcwd().replace('\\','/')    # 获取当前路径
print('Current path = %s' % currentPath)

#cpudirname = '/home/raspadmin/mz/sf_storage/build/workload/SPDK-NVMe-o-TCP/image-test4/'
#cpudirname = '/home/raspadmin/mz/sf_storage/build/workload/SPDK-NVMe-o-TCP/image-test4/sequential_read_1core_3p0_cpu/seqread_128k_1core_3p0'
cpudirname = currentPath
#cpufilename = 'sar-cpu-monitor.log'
cpufilename = 'sar-cpu-all.log'

def getfile(cpudirname, cpufilename):
    cpulogfies = []
    for root, dirs, files in os.walk(cpudirname, topdown=False):       
        for name in files:
            if name == cpufilename:
                print(os.path.join(root, name))
                cpulogfies.append(os.path.join(root, name))
    return cpulogfies


def parsefile(files):
    for file in files:
        print(file)
        dir_name, full_file_name = os.path.split(file)
        dir_name_list = dir_name.split('/')
        file_name, file_ext = os.path.splitext(full_file_name)
        fo = open(file, mode='r')
        lines = fo.readlines()
        wb = Workbook()
        ws = wb.active
        servername = ''
        if 'r04u03' in lines[0]:
            servername = 'r04u03'
        elif 'r05u33' in lines[0]:
            servername = 'r05u33'
        else:
            print('error log')
        ws.append(lines[0].split())
        for line in lines:
            line_list = []
            line_list = line.split()
            # if cpufilename == 'sar-cpu-all.log' or servername == 'r04u03':
            #     data_type = "cpu-all-usage"
            #     if 'Average' in line:
            #         ws.append(line_list)
            # if cpufilename == 'sar-cpu-monitor.log' and servername == 'r05u33':
            #     data_type = "cpu-monitor-freq"
            #     ws.append(line_list)
            if cpufilename == 'sar-cpu-all.log':
                data_type = "cpu-all-usage"
                if 'Average' in line:
                    ws.append(line_list)
            if cpufilename == 'sar-cpu-monitor.log':
                data_type = "cpu-monitor-freq"
                ws.append(line_list)
        ws = wb.create_sheet("file_name")
        file_name = dir_name_list[-2] + '_' + servername + '_' + dir_name_list[-3] + '_' + data_type
        wb.save(file_name + '.xlsx')
        fo.close()
    return

cpulogfies = []
cpulogfies = getfile(cpudirname, cpufilename)
parsefile(cpulogfies)

cpufilename = 'sar-cpu-monitor.log'
cpulogfies = []
cpulogfies = getfile(cpudirname, cpufilename)
parsefile(cpulogfies)