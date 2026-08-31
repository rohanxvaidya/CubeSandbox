#!/bin/bash  #bash kudas.sh 

# echo ${array1[0]}
# echo ${array1[1]}

BW=$(cat $1 |grep BW=|awk -F, '{print $2}'|awk -F= '{print $2}'|awk -F'MiB' '{print $1}' )
# echo $(check "array")
# echo ${array[0]}
# for each in $BW
#     do
#         # echo $each
#         BW_array[$i]=$each
#         i=$(($i+1))
#         # i=$i+1
#         # listTest=(value1,value2,value3)
#     done

IOPS=$(cat $1 |grep IOPS|awk -F, '{print $1}'|awk -F= '{print $2}'|awk -F'k' '{print $1}')

avg=`cat $1|grep lat|sed '3!d'|awk -F, '{print $3}'`
stdev=`cat $1|grep lat|sed '3!d'|awk -F, '{print $4}'`
if [[ $2 == "BW" ]]
then
echo ${BW}
elif [[ $2 == "IOPS" ]]
then
echo ${IOPS}
elif [[ $2 == "avg" ]]
then
echo ${avg}
elif [[ $2 == "stdev" ]]
then
echo ${stdev}
fi

# R=$(cat $1 |grep -v read/write|grep read)
# if [[ $R == "" ]]
# then
# if [[ $2 == "AVG" ]]
# then
#     echo "----/${AVG_lat_array[0]}-${AVG_clat_array[0]}-${th90_array[0]}-${th95_array[0]}-${th99_array[0]}"
# elif [[ $2 == "IOPS" ]]
# then
#     echo "/${IOPS_array[0]}"
# elif [[ $2 == "BW" ]]
# then
#     echo "/${BW_array[0]:0:-2}"
# fi 
# else
# if [[ $2 == "AVG" ]]
# then
#     echo "${AVG_lat_array[0]}-${AVG_clat_array[0]}-${th90_array[0]}-${th95_array[0]}-${th99_array[0]}/${AVG_lat_array[1]}-${AVG_clat_array[1]}-${th90_array[1]}-${th95_array[1]}-${th99_array[1]}"
# elif [[ $2 == "IOPS" ]]
# then
#     echo "${IOPS_array[0]}/${IOPS_array[1]}"
# elif [[ $2 == "BW" ]]
# then
#     echo "${BW_array[0]:0:-2}/${BW_array[1]:0:-2}"
# fi 
# fi
# echo "${AVG_lat_array[0]}-${AVG_clat_array[0]}-${th90_array[0]}-${th95_array[0]}-${th99_array[0]}/${AVG_lat_array[1]}-${AVG_clat_array[1]}-${th90_array[1]}-${th95_array[1]}-${th99_array[1]},${IOPS_array[0]}/${IOPS_array[1]},${BW_array[0]:0:-2}/${BW_array[1]:0:-2}"