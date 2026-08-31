#!/bin/bash


function find_max_value(){

## Check if the serial data is provided as an argument
#if [ "$#" -ne 1 ]; then
#    echo "Usage: $0 'serial_data'"
#    exit 1
#fi
# Read the input serial data
serial_data="$1"

# Extract the serial name and values
serial_name=$(echo "$serial_data" | cut -d',' -f1)
values=$(echo "$serial_data" | cut -d',' -f2-)

# Convert values to an array
IFS=',' read -r -a value_array <<< "$values"

# Initialize variables to find the max value and its index
max_value=${value_array[0]}
max_index=0

# Loop through the values to find the max and its index
for i in "${!value_array[@]}"; do
    if (( $(echo "${value_array[i]} > $max_value" | bc -l) )); then
        max_value=${value_array[i]}
        max_index=$i
    fi
done

# Output the results
echo "Max value for serial \"$serial_name\": $max_value"
echo "Index of max value: $max_index"

}


bash emon.sh pro $1 $2 $3
sleep 1
data=$(grep  UNC_CHA_PIPE_REJECT2.ANYQ_TOPA_MATCH emon_${1}/__mpp_cha_uncore_view_summary.csv)
echo $data
find_max_value "$data"
