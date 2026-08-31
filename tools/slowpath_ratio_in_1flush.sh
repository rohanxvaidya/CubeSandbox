#!/bin/bash -e

# arg1 = file
# arg2 = begin string , e.g  "contention_begin"
# arg3 = end string, e.g "contention_end"

file_name=${1:-"."}
cpu_count=${2:-"512"}
end_pattern=${3:-"end"}
round=${round:-5}  # 5 round for each kpi group
title=${title:-0}  # have withDSA/noDSA title or not

dir_path="${pwd}"

outputfile="slowpath_ratio_${file_name}.csv"
standard_file="std_${file_name}"


function parse_tsc_begin_end() {

    find . -name ${standard_file} -exec awk -v round=$round -v cpu_nr=$cpu_count '
        BEGIN {
            data_round=0;
            line=1
            spinlock_entry_count=0
            spinlock_slowpath_entry_count=0
           # printf "Round-%d\n", test_round
        }

        function kvformat(key, value) {
            unit=gensub(/^[0-9+-.]+ *(.*)/,"\\1",1, value);
            value=gensub(/^([0-9+-.]+).*/,"\\1",1, value);
            key=gensub(/(.*): *$/,"\\1",1, key);
            if (unit!="") key=key" ("unit")";
            return key": "value;
        }

        # {
        # print $4, $5
        # }

        #args: 
        # key - kpi type, eg. IOPS/Throught
        # value - equation with unit, eg. avgbw=100MiB
        function equation_kvformat(key, value) {
            key_type=gensub(/(.*)=(.*)/,"\\1",1, value);
            #print "type:"key_type
            pre_value=gensub(/(.*)=(.*)/,"\\2",1, value);
            #print "pre_value:"pre_value
            unit=gensub(/^[0-9+-.]+ *(.*)/,"\\1",1, pre_value);
            #unit=unit"IO/s"
            value=gensub(/^([0-9+-.]+).*/,"\\1",1, pre_value);
            if (unit=="") {
                value=value/1000
            }
            key=gensub(/(.*): *$/,"\\1",1, key);
            #key=key"IOPS"
            if (unit!="") key=key" ("unit")";
            # return key": "value;
            return value;
        }

        #args: 
        # key=value - T1=11111
        function equation_value_format(value_eq) {
            #key_type=gensub(/(.*)=(.*)/,"\\1",1, value_eq);
            #print "type:"key_type
            pre_value=gensub(/(.*)=(.*)/,"\\2",1, value_eq);
            #print "pre_value:"pre_value
            value=gensub(/^([0-9+-.]+).*/,"\\1",1, pre_value);

            return value;
        }

        /queued_spin_lock_slowpath/ {
            # print $4","$5
            begin_line=NR
            begin_tsc=$4
            data_round=1  ## begine now

            spinlock_slowpath_entry_count=spinlock_slowpath_entry_count+1
            oneround_spinlock_slowpath_entry_count = oneround_spinlock_slowpath_entry_count + 1
            # print "line-"begin_line ", "begin_tsc
        }

        /spin_lock_irq/ {
            spinlock_entry_count=spinlock_entry_count+1
            oneround_spinlock_entry_count=oneround_spinlock_entry_count+1
            //prinf "spinlock_entry_count: , "spinlock_entry_count

        }

        /flush_workqueue_prep_pwqs/ {
            # print $4","$5
            begin_line=NR

            begin_pwqs=1
            data_round=1  ## begine now
            flush_workqueue_prep_pwqs_count=flush_workqueue_prep_pwqs_count+1

            print "spinlock_entry_count: , " oneround_spinlock_entry_count
            print "spinlock_slowpath_entry_count: , " oneround_spinlock_slowpath_entry_count
            oneround_spinlock_slowpath_entry_count = 0
            oneround_spinlock_entry_count=0

        }



        END {
            #print "test round:\t"test_round;
            print ""
            print "Total flush_workqueue_prep_pwqs_count:, " flush_workqueue_prep_pwqs_count
            print "Total spinlock_entry_count:, " spinlock_entry_count
            print "Total spinlock_slowpath_entry_count:  , " spinlock_slowpath_entry_count
            avg_slowpath_count_per_flush = spinlock_slowpath_entry_count/flush_workqueue_prep_pwqs_count

            avg_spinlock_entry_per_flush = spinlock_entry_count / flush_workqueue_prep_pwqs_count
            print "avg_spinlock_entry_per_flush:, " avg_spinlock_entry_per_flush
            print "avg_slowpath_count_per_flush:, " avg_slowpath_count_per_flush

            # contention_count=cpu_nr + 1
            # print "contention_count_per_flush:, " contention_count
            # avg_slowpath_ratio = avg_slowpath_count_per_flush /contention_count
            # print "avg_slowpath_ratio: , " avg_slowpath_ratio

            avg_slowpath_ratio = spinlock_slowpath_entry_count /spinlock_entry_count
            print "avg_slowpath_ratio: , " avg_slowpath_ratio


        }

        ' > ${dir_path}/${outputfile} "{}" \; || true

}


realfilepath=`(realpath $file_name)`
dir_path=${realfilepath%/*}
echo "File directory: ${dir_path}"
#dir_path=${file%/*}

echo "*** Start to parse the file: $realfilepath ***"
#grep -E "${begin_pattern}|${end_pattern}" ${file_name} |sed 's/:/ /g' |sed 's/+/ /g' > ${standard_file}
#grep -E "${begin_pattern}}" -A1 ${file_name} |sed 's/:/ /g' |sed 's/+/ /g' > "std_${file_name}"

cat ${file_name} |sed 's/: /  /g' |sed 's/, / /g' > ${dir_path}/${standard_file}
# parse data from grep and output to files

#standard_file=$realfilepath
parse_tsc_begin_end 
echo "..."
echo "Done! The output file is: [${dir_path}/${outputfile}]"

