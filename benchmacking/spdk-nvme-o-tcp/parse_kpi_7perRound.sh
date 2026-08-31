#!/bin/bash -e

# arg1 = test case
# arg2= directory for store the file for kpi data output.

TEST_OPERATION=${1:-"random_read"}
data_path=${2:-"."}
round=14  # 5 round for each kpi group

function kpi_parse() {

    if [[ "${TEST_OPERATION}" =~ "sequential" ]]; then
        # Block IO sequential R/W, the primary kpi is the bandwidth.
        find ${data_path} -name *sequential*.log -exec awk '
        BEGIN {
            test_round=0;
        }

        function kvformat(key, value) {
            unit=gensub(/^[0-9+-.]+ *(.*)/,"\\1",1, value);
            value=gensub(/^([0-9+-.]+).*/,"\\1",1, value);
            key=gensub(/(.*): *$/,"\\1",1, key);
            if (unit!="") key=key" ("unit")";
            return key": "value;
        }

        #args: 
        # key - kpi type, eg. IOPS/Throught
        # value - equation with unit, eg. avgbw=100MiB
        function equation_kvformat(key, value) {
            key_type=gensub(/(.*)=(.*)/,"\\1",1, value);
            #print "type:"key_type
            pre_value=gensub(/(.*)=(.*)/,"\\2",1, value);
            #print "pre_value:"pre_value
            unit=gensub(/^[0-9+-.]+ *(.*)/,"\\1",1, pre_value);
            #print "unit:"unit
            unit=unit"IO/s"
            value=gensub(/^([0-9+-.]+).*/,"\\1",1, pre_value);
            #print value
            key=gensub(/(.*): *$/,"\\1",1, key);
            #key=key"-"key_type
            if (unit!="") key=key" ("unit")";
            return key": "value;
        }

        /IOPS=/ {
            #format equation
            kv=gensub(/(.*)=(.*)*,/,"\\1=\\2",1, $2);
            #print "format kv:"kv
            print equation_kvformat("IOPS", kv)
        }

        /BW=/ {
            pattern="BW="
            bw_value=gensub(/BW=(.*)/,"\\1",1, $3)
            #print bw_value
            print kvformat("*Bandwidth", bw_value)
        }

        END {
            #print "test round:\t"test_round;
        }

        ' "{}" \; || true
    elif [[ "${TEST_OPERATION}" =~ "random" || "${TEST_OPERATION}" =~ "gated" ]]; then
        # Block IO random R/W, the primary kpi is the IOPS.
        find ${data_path} -name *random*.log -exec awk '
        BEGIN {
            test_round=0;
        }

        function kvformat(key, value) {
            unit=gensub(/^[0-9+-.]+ *(.*)/,"\\1",1, value);
            value=gensub(/^([0-9+-.]+).*/,"\\1",1, value);
            key=gensub(/(.*): *$/,"\\1",1, key);
            if (unit!="") key=key" ("unit")";
            return key": "value;
        }

        #args: 
        # key - kpi type, eg. IOPS/Throught
        # value - equation with unit, eg. avgbw=100MiB
        function equation_kvformat(key, value) {
            key_type=gensub(/(.*)=(.*)/,"\\1",1, value);
            #print "type:"key_type
            pre_value=gensub(/(.*)=(.*)/,"\\2",1, value);
            #print "pre_value:"pre_value
            unit=gensub(/^[0-9+-.]+ *(.*)/,"\\1",1, pre_value);
            nit=unit"IO/s"
            value=gensub(/^([0-9+-.]+).*/,"\\1",1, pre_value);
            key=gensub(/(.*): *$/,"\\1",1, key);
            #key=key"IOPS"
            if (unit!="") key=key" ("unit")";
            return key": "value;
        }

        /IOPS=/ {
            #format equation
            kv=gensub(/(.*)=(.*)*,/,"\\1=\\2",1, $2);
            #print "format kv:"kv
            print equation_kvformat("*IOPS", kv)
        }

        /BW=/ {
            pattern="BW="
            bw_value=gensub(/BW=(.*)/,"\\1",1, $3)
            #print bw_value
            print kvformat("Bandwidth", bw_value)
        }

        END {
            #print "test round:\t"test_round;
        }

        ' "{}" \; || true

    fi 
}


function grep_parse() {
if [[ "${TEST_OPERATION}" =~ "random" || "${TEST_OPERATION}" =~ "gated" ]]; then
        # Block IO random R/W, the primary kpi is the IOPS.
        grep -nr "read: IOPS=" ${data_path}/*random* | awk -v round=$round '
        BEGIN {
            test_round=0;
            r=0
            printf "round %d\n", test_round
        }

        function kvformat(key, value) {
            unit=gensub(/^[0-9+-.]+ *(.*)/,"\\1",1, value);
            value=gensub(/^([0-9+-.]+).*/,"\\1",1, value);
            key=gensub(/(.*): *$/,"\\1",1, key);
            if (unit!="") key=key" ("unit")";
            return key": "value;
        }

        #args: 
        # key - kpi type, eg. IOPS/Throught
        # value - equation with unit, eg. avgbw=100MiB
        function equation_kvformat(key, value) {
            key_type=gensub(/(.*)=(.*)/,"\\1",1, value);
            #print "type:"key_type
            pre_value=gensub(/(.*)=(.*)/,"\\2",1, value);
            #print "pre_value:"pre_value
            unit=gensub(/^[0-9+-.]+ *(.*)/,"\\1",1, pre_value);
            nit=unit"IO/s"
            value=gensub(/^([0-9+-.]+).*/,"\\1",1, pre_value);
            key=gensub(/(.*): *$/,"\\1",1, key);
            #key=key"IOPS"
            if (unit!="") key=key" ("unit")";
            # return key": "value;
            return value;
        }

        /IOPS=/ {
            #format equation
            kv=gensub(/(.*)=(.*)*,/,"\\1=\\2",1, $3);
            #print "format kv:"kv
            printf "%.1f,", equation_kvformat("*IOPS", kv)
            #print equation_kvformat("*IOPS", kv)

            pattern="BW="
            bw_value=gensub(/BW=(.*)/,"\\1",1, $4)
            #print bw_value
            value=gensub(/^([0-9+-.]+).*/,"\\1",1, bw_value);
            printf "%.1f \n", value
            #print kvformat("Bandwidth", bw_value)

            r=r+1;
            if (r >= round) {
                test_round=test_round+1
                printf "round %d\n", test_round
                r=0
            }


        }

        # /BW=/ {
        #     pattern="BW="
        #     bw_value=gensub(/BW=(.*)/,"\\1",1, $4)
        #     #print bw_value
        #     #print kvformat("Bandwidth", bw_value)
        # }

        END {
            #print "test round:\t"test_round;
        }

        ' > ${data_path}/${TEST_OPERATION}_kpi.csv
fi
if [[ "${TEST_OPERATION}" =~ "sequential" || "${TEST_OPERATION}" =~ "gated" ]]; then
        # Block IO sequential R/W, the primary kpi is the IOPS.
        grep -nr "read: IOPS=" ${data_path}/*sequential* | awk -v round=$round '
        BEGIN {
            test_round=0;
            r=0
            printf "round %d\n", test_round
        }

        function kvformat(key, value) {
            unit=gensub(/^[0-9+-.]+ *(.*)/,"\\1",1, value);
            value=gensub(/^([0-9+-.]+).*/,"\\1",1, value);
            key=gensub(/(.*): *$/,"\\1",1, key);
            if (unit!="") key=key" ("unit")";
            return key": "value;
        }

        #args: 
        # key - kpi type, eg. IOPS/Throught
        # value - equation with unit, eg. avgbw=100MiB
        function equation_kvformat(key, value) {
            key_type=gensub(/(.*)=(.*)/,"\\1",1, value);
            #print "type:"key_type
            pre_value=gensub(/(.*)=(.*)/,"\\2",1, value);
            #print "pre_value:"pre_value
            unit=gensub(/^[0-9+-.]+ *(.*)/,"\\1",1, pre_value);
            nit=unit"IO/s"
            value=gensub(/^([0-9+-.]+).*/,"\\1",1, pre_value);
            key=gensub(/(.*): *$/,"\\1",1, key);
            #key=key"IOPS"
            if (unit!="") key=key" ("unit")";
            # return key": "value;
            return value;
        }

        /IOPS=/ {
            #format equation
            kv=gensub(/(.*)=(.*)*,/,"\\1=\\2",1, $3);
            #print "format kv:"kv
            printf "%.1f,", equation_kvformat("*IOPS", kv)
            #print equation_kvformat("*IOPS", kv)

            pattern="BW="
            bw_value=gensub(/BW=(.*)/,"\\1",1, $4)
            #print bw_value
            value=gensub(/^([0-9+-.]+).*/,"\\1",1, bw_value);
            #printf "%.1f \n", value
            printf "%.1f, ,", value
            #print kvformat("Bandwidth", bw_value)

            r=r+1;
            if (r >= round) {
                test_round=test_round+1
                printf "round %d\n", test_round
                r=0
            }


        }

        # /BW=/ {
        #     pattern="BW="
        #     bw_value=gensub(/BW=(.*)/,"\\1",1, $4)
        #     #print bw_value
        #     #print kvformat("Bandwidth", bw_value)
        # }

        END {
            #print "test round:\t"test_round;
        }

        ' > ${data_path}/${TEST_OPERATION}_kpi.csv
fi
}

function output_csv() {
    
cat all_kpi.txt | awk -v round=$round '
        BEGIN {
            r=0
        }

        /IOPS/ {
            printf "%.1f,", $3
        }

        /Bandwidth/ {
            print $3
            r=r+1;
        }

        r >= round  {
            printf "round %d\n", r
            r=0
        }


        END {
            #print "test round:\t"test_round;
        }

        '  > ${data_path}/${TEST_OPERATION}_kpi.csv
}
#${data_path}
#./kpi.sh ${TEST_OPERATION}

# parse data from find file and output to files
#kpi_parse > all_kpi.txt
#output_csv

# parse data from grep and output to files
grep_parse 
