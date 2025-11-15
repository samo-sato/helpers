#!/bin/bash

echo "Following helper tools are available:"

# List all .sh files in the current directory without the .sh extension
for file in *.sh; do
  if [ -e "$file" ]; then
    echo "${file%.sh}"
  fi
done 
