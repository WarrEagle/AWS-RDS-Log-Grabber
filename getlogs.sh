#!/usr/bin/env bash
#
# RDS Log filename grabber and download utility. By Michael Quale
# Reguires Python3.7, PIP3 and BOTO3 to send mail. Requires pgBadger to generate reports https://github.com/darold/pgbadger.git
#
# Get list of log file names from RDS via API call. Change Database Identifier to match your environment
#
set -e
# DB Information to grab logs from.
DATABASEID="ciam-qa-db-2"
OUTPUT="text"
REGION="us-east-1"

# Ask for how far back to fetch logs in seconds. Defaults to 86400 or 24 hours. 
# Make sure log retention is also set accordingly.
read -e -p "Enter time range of files in seconds to retrieve:" -i "172400" time

# Do some weird date timestamp wrangling to retrieve file n amount of seconds from current epoch
# Then also convert with offset back into human readable format to confirm with the user.The add 000 to keep the AWS CLI happy
date=$(echo $(($(date +%s) - $time )))
hdate=$(echo "$(date -j -r $date)")
date=$date"000"

# get list of log files based on last written timestamp in milliseconds create list of results to parse and format for second API call
aws rds describe-db-log-files --db-instance-identifier $DATABASEID --file-last-written $date  --output=$OUTPUT > temp/logs.txt

read -e -p "Retrieving files from $hdate to latest available. Press Any Key " c

# cleanup aisle #1 remove unnecessary output characters
sed -i '' 's/^.................................//' temp/logs.txt
cut -f 1  temp/logs.txt > temp/filenames.txt

# Cleanup temp directory for storing logs with time stamp.
rm -f temp/*.log

# Loop through list of filenams and execute AWS API call to download and store them locally.
while read -r name; do
    echo "Reading file: $name"
    fname=$(echo "$name" | cut -c 7-) # strip initial 'error/' from $line string for naming log files.
    aws rds download-db-log-file-portion --db-instance-identifier $DATABASEID \
        --output $OUTPUT --log-file-name $name \
        --region us-east-1 > "temp/${fname}.log"   
    echo "Logged file written: $fname"
done < temp/filenames.txt

# Import log files into pgbadger and generate html report 
exec pgbadger -p "%t:%r:%u@%d:[%p]:" temp/postgresql.log.*  -o reports/report.html

# Send report via SES to email addresses by calling python script to send email. 
exec python3 sendmail.py