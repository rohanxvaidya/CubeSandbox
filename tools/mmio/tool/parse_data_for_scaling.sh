#!/bin/bash

# Check if correct number of arguments are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <input_folder> <folder_count> <output_file>"
    exit 1
fi

input_folder="$1"
folder_count="$2"
output_file="$3"

# Ensure the output file is empty or create it
echo "thread_num, data"> "$output_file"

# Loop through the specified folder count
for ((i=1; i<=folder_count; i++)); do
    folder_name="${i}-thread"
    folder_path="${input_folder}/${folder_name}"

    # Check if the folder exists
    if [ ! -d "$folder_path" ]; then
        echo "Folder $folder_path does not exist. Skipping..."
        continue
    fi

    # Determine the middle file number
    middle_file=$(( (i + 1) / 2 ))  # Integer division for selecting the middle file
    target_file="${folder_path}/pcimem-test*${middle_file}.log"

    # Parse the target file and extract line 50000
    for file in $target_file; do
        if [ -f "$file" ]; then
            line=$(sed -n '50000p' "$file")
            #echo "$line" >> "$output_file"
            duration_cycle=$(echo "$line" | awk '{print $NF}')
            # Write the thread number and duration cycle to the output file
            # echo "thread_num: $i, data: $duration_cycle" >> "$output_file"
            echo "$i, $duration_cycle" >> "$output_file"
        else
            echo "File $file does not exist. Skipping..."
        fi
    done
done

echo "Data parsing completed. Output written to $output_file."
