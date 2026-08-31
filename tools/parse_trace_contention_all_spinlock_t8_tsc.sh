#!/bin/bash -e

# arg1 = file
# arg2 = begin string , e.g  "contention_begin"
# arg3 = end string, e.g "contention_end"

file_name=${1:-"."}
begin_pattern=${2:-"begin"}
end_pattern=${3:-"end"}
round=${round:-5}  # 5 round for each kpi group
title=${title:-0}  # have withDSA/noDSA title or not

dir_path="${pwd}"

outputfile="tsc_cycle_${file_name}.csv"
standard_file="std_${file_name}"


function parse_tsc_begin_end() {

    find . -name ${standard_file} -exec awk -v round=$round -v title=$title '
        BEGIN {
            data_round=0;
            line=1
            iops_all=0
            bw_all=0
            round_end=0
            round_i=1
            tsc_duration=0
            spinlock_entry_count=0
            spinlock_slowpath_entry_count=0
            slowpath_mcs_quick_lock=0
            quick_lock=0

            spinlock_slowpath_entry_count=0
            slowpath_quick_exit=0
            slowpath_queueing=0
            slowpath_mcs_wait_next=0
            slowpath_quick_before_queue=0

           # printf "Round-%d\n", test_round
           print "T1, T2, T3, T4, T5, T6, T7, T8, try_lock_tsc_d, slowpath_quickexit_tsc_d, slowpath_queueing_tsc_d, slowpath_mcs_quick_lock_tsc_d, slowpath_spin_pending_lock_d, slowpath_wait_next_tsc_d "
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

        /_begin/ {
            # print $4","$5
            begin_line=NR
            begin_tsc=$4
            data_round=1  ## begine now
            spinlock_entry_count=spinlock_entry_count+1

            # print "line-"begin_line ", "begin_tsc



        }

        # /_mid/ {
        #     mid_tsc=$4
        #     mid_line=NR
        #     if (data_round==1) {
        #         # it is the round. then end it
        #         #    data_round=0

        #         # only count the the same set of begin and end.
        #         if (begin_line+1==mid_line) {
        #         # tsc_duration=end_tsc-begin_tsc
        #         # print begin_tsc ", " end_tsc ", " tsc_duration
        #         mid_line=NR
        #         mid_tsc=$4
        #         } else {
        #             mid_line=0
        #         }
        #     }
        # }

        # /_end/ {
        #     # print $4","$5
        #     end_tsc=$4
        #     end_line=NR
        #     if (data_round==1) {
        #         # it is the round. then end it
        #         data_round=0

        #         # only count the the same set of begin and end.
        #         if (begin_line+2==end_line) {
        #             if (begin_line+1==mid_line) {
        #                 end_tsc=$4
        #                 tsc_duration_1=mid_tsc-begin_tsc
        #                 tsc_duration_2=end_tsc-mid_tsc
        #                 tsc_duration=end_tsc-begin_tsc

        #                 print begin_tsc ", " mid_tsc ", " end_tsc ", " tsc_duration_1, ", " tsc_duration_2 ", " tsc_duration
        #             }

        #         }
        #     }

        # }

        /_end_/ {
            #format equation
            #print $8 ", " $9 
            #kv=gensub(/(.*)=(.*)*,/,"\\1=\\2",1, $8);
            if (data_round==1) {
                # it is the round. then end it
                data_round=0
            }
            end_line=NR
            if (begin_line+1==end_line) {
                spinlock_slowpath_entry_count=spinlock_slowpath_entry_count+1

                t1=gensub(/(.*)=(.*)/,"\\2",1, $8);

                #print "format kv:"t1
                #print "value=" equation_value_format($8)

                t2=gensub(/(.*)=(.*)/,"\\2",1, $9);
                t3=gensub(/(.*)=(.*)/,"\\2",1, $10);
                t4=gensub(/(.*)=(.*)/,"\\2",1, $11);
                t5=gensub(/(.*)=(.*)/,"\\2",1, $12);
                t6=gensub(/(.*)=(.*)/,"\\2",1, $13);
                t7=gensub(/(.*)=(.*)/,"\\2",1, $14);
                t8=gensub(/(.*)=(.*)/,"\\2",1, $15);

                # if (t1 && t2 && t3 && t4) {
                #     tsc_duration_1=t2-t1
                #     tsc_duration_2=t3-t2
                #     tsc_duration_3=t4-t3

                #     print t1 ", " t2 ", " t3 ", " t4 ", t5 ", " t6 ", " t7 ", " t8 ", " try_lock_tsc_d ", " tsc_duration_2  ", " tsc_duration_3            
                # }

                ## -- try lock first.
                try_lock_tsc_d=t2-begin_tsc
                ## -- then entry slowpath
                slowpath_quickexit_tsc_d=t3-t2

                if (t4==0 && t5==0 ) {
                    slowpath_quick_exit = slowpath_quick_exit + 1
                } 

                if (t4!=0 && t5==0 ) {
                    slowpath_quick_before_queue = slowpath_quick_before_queue + 1
                } 

                if (t4!=0 && t5!=0 ) {
                    slowpath_queueing_tsc_d = t5 - t4
                    slowpath_queueing = slowpath_queueing + 1 


                    if (t6 == 0) {
                        slowpath_mcs_quick_lock = slowpath_mcs_quick_lock + 1
                        slowpath_mcs_quick_lock_tsc_d = t7 - t5
                    } else {
                        slowpath_mcs_wait_next = slowpath_mcs_wait_next + 1
                        slowpath_spin_pending_lock_d = t6 - t5

                        slowpath_wait_next_tsc_d = t7 - t6
                    }
                }

                print t1 ", " t2 ", " t3 ", " t4 ", "t5 ", " t6 ", " t7 ", " t8 ", " try_lock_tsc_d ", " slowpath_quickexit_tsc_d  ", " slowpath_queueing_tsc_d ", "slowpath_mcs_quick_lock_tsc_d ", "slowpath_spin_pending_lock_d ", "slowpath_wait_next_tsc_d         

            }


        }


        END {
            #print "test round:\t"test_round;
            print "spinlock_entry, "spinlock_entry_count
            quick_lock = spinlock_entry_count - spinlock_slowpath_entry_count
            quick_lock_ratio = quick_lock/spinlock_entry_count
            print "quick_lock, " quick_lock ",   quick_lock_ratio:, "  quick_lock_ratio

            slowpath_ratio = spinlock_slowpath_entry_count/spinlock_entry_count
            print "spinlock_slowpath_entry, " spinlock_slowpath_entry_count ", slowpath_ratio:, " slowpath_ratio

            slowpath_quick_lock_ratio = slowpath_quick_exit / spinlock_slowpath_entry_count
            print "slowpath_quick_lock, " slowpath_quick_exit ", slowpath_quick_lock_ratio: ," slowpath_quick_lock_ratio

            print "slowpath_quick_before_queue, " slowpath_quick_before_queue

            slowpath_queueing_ratio=slowpath_queueing/spinlock_slowpath_entry_count
            print "slowpath_queueing count, " slowpath_queueing ", slowpath_queueing_ratio: , " slowpath_queueing_ratio

            print "slowpath_mcs_quick_lock, " slowpath_mcs_quick_lock
            print "slowpath_mcs_wait_next, " slowpath_mcs_wait_next
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
parse_tsc_begin_end 
echo "..."
echo "Done! The output file is: [${dir_path}/${outputfile}]"
