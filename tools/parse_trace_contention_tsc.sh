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

        /_begin/ {
            # print $4","$5
            begin_line=NR
            begin_tsc=$4
            data_round=1  ## begine now

            # print "line-"begin_line ", "begin_tsc

            # if (line==1) {
            #     printf "Round-%d\n", test_round
            # }
            # line=line+1;
            # if (line > line_per_round) {
            #     line=1
            #     test_round=test_round+1 
            #     # set end flag after noDSA, withDAS case finished current cycle(test_round).
            #     round_end=1  
            # }

            # line=line+1;
            # if (line > line_per_round) {
            #     test_round=test_round+1
            #     printf "Round-%d\n", test_round
            #     line=0
            # }

        }

        /_end/ {
            # print $4","$5
            end_tsc=$4
            end_line=NR
            if (data_round==1) {
                # it is the round. then end it
                data_round=0

                # only count the the same set of begin and end.
                if (begin_line+1==end_line) {
                tsc_duration=end_tsc-begin_tsc
                print begin_tsc ", " end_tsc ", " tsc_duration

                }
            }

            # if (line==1) {
            #     printf "Round-%d\n", test_round
            # }
            # line=line+1;
            # if (line > line_per_round) {
            #   line=1
            #   test_round=test_round+1 
            # }

            # line=line+1;
            # if (line > line_per_round) {
            #     test_round=test_round+1
            #     printf "Round-%d\n", test_round
            #     line=0
            # }
            # if (title==1) {
            #     printf "noDSA,"
            # }


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
