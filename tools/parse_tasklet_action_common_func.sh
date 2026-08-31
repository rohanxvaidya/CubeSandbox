#!/bin/bash -e

# arg1 = file
# arg2 = begin string , e.g  "contention_begin"
# arg3 = end string, e.g "contention_end"

file_name=${1:-"."}
begin_pattern=${2:-"tasklet_action_common"}
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
           # printf "Round-%d\n", test_round
           print "print duration_tasklet_action_common , duration_tasklet_trylock_func , duration_mlx5_cq_tasklet_cb ,  duration_wake_up_var"
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




        /tasklet_action_common/ {
            # print $4","$5
            begin_line=NR
            data_round_start=1  ## begine now


            # print "line-"begin_line ", "begin_tsc

        }


        /tasklet_trylock_func/ {
            if (data_round_start==1) {
                duration_tasklet_trylock_func=$5
            }
        }

        /tasklet_clear_sched/ {
             if (data_round_start==1) {
                tasklet_clear_sched_start=1
                line_tasklet_clear_sched=NR
            }
        }

        ## tasklet_clear_sched time.
        /funcgraph_exit/ {
            if (data_round_start==1 ) {
                if (tasklet_clear_sched_start==1) {
                    current_line=NR
                    if (current_line==line_tasklet_clear_sched+4) {
                        duration_tasklet_clear_sched=$5
                    }
                }

                if (mlx5_cq_tasklet_cb_start==1) {
                    current_line=NR
                    if (current_line==line_mlx5_cq_tasklet_cb+3) {
                        duration_mlx5_cq_tasklet_cb=$5
                    }
                }

                if (wake_up_var_start==1) {
                    current_line=NR
                    if (current_line==line_wake_up_var+2) {
                        duration_wake_up_var=$5
                    }

                ## handle the last time
                    current_line=NR
                    if (current_line==line_mlx5_cq_tasklet_cb+7) {
                        duration_tasklet_action_common=$5

                    ### finish the handle. 

                    print duration_tasklet_action_common ", " duration_tasklet_trylock_func ", " duration_mlx5_cq_tasklet_cb ", " duration_wake_up_var

                    line_tasklet_clear_sched=0
                    line_mlx5_cq_tasklet_cb=0
                    line_wake_up_var=0

                    duration_tasklet_action_common=0
                    duration_wake_up_var=0
                    duration_mlx5_cq_tasklet_cb=0
                    duration_tasklet_clear_sched=0
                    duration_tasklet_trylock_func=0

                    }

                }

            }
        }

        /mlx5_cq_tasklet_cb/ {
            if (data_round_start==1 ) {
                mlx5_cq_tasklet_cb_start=1
                line_mlx5_cq_tasklet_cb=NR
            }
        }

        /wake_up_var/ {
            if (data_round_start==1 ) {
                current_line=NR
                if (current_line==line_mlx5_cq_tasklet_cb+4) {
                    line_wake_up_var=NR
                    wake_up_var_start=1
                }
            }
        }


        END {
            #print "test round:\t"test_round;
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

cat ${file_name} |sed 's/: /  /g' |sed 's/+/ /g' > ${dir_path}/${standard_file}
# parse data from grep and output to files
parse_tsc_begin_end 
echo "..."
echo "Done! The output file is: [${dir_path}/${outputfile}]"
