#!/bin/bash

SROUCE_PATH=$1
DES_PATH=$2
START_F=$3
END_F=$4

#ACT_CMD="cp -rf"
ACT_CMD="mv "
#find ${SROUCE_PATH}/ -type f -newer $START_F! -newer $END_F --exec cp {} $DES_PATH \;
action=0
files=$(ls ${SROUCE_PATH}/) 
file_count=${#files[@]}

for file in ${files[@]}; do

#    echo "check $file"
    if [[ "$file" =~ "$START_F" ]]; then
        action=1
    fi

    if [ $action == 1 ]; then 
        echo "Action on $file ..."
        $ACT_CMD $file ${DES_PATH}/ 
        act_time=$(($act_time+1))
    fi

    if [[ "$file" =~ "$END_F" ]]; then
        action=0
    fi


done

echo "*** Action Done !, exection on $act_time files of $file_count ***"