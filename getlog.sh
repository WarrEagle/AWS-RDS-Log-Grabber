#!/bin/bash

# Get the DB log files

set -e

REGION=us-east-1
DB_INSTANCE=rds-db-xuse1-uat-gm-emis-1
USE_CSV=0
START_DATE=`date -u +'2022-03-25-1100'`
END_DATE=`date -u +'%Y-%m-%d-0100'`

usage () {
    echo "USAGE: $0 [OPTIONS]"
    echo "Options:"
    echo "    -r  : AWS Region. Default '$REGION'"
    echo "    -d  : RDS PostgreSQL Instance Name. Default '$DB_INSTANCE'"
    echo "    -c  : Use CSV log files. Allowed values 0 or 1. Default '$USE_CSV'"
    echo "    -s  : Start date of log file [YYYY-MM-DD or YYYY-MM-DD-HH]. Defaults to current date (in UTC) '$START_DATE'"
    echo "    -e  : End date of log file [YYYY-MM-DD or YYYY-MM-DD-HH]. Defaults to next day (in UTC) '$END_DATE'"
    echo
    exit 1
}

log () {
    echo "`date +%Y%m%d-%H%M%S`: ${@}"
}

while getopts :r:d:c:s:e:h option
do
    case "${option}" in
        r)
            REGION=${OPTARG};;
        d)
            DB_INSTANCE=${OPTARG};;
        c)
            USE_CSV=${OPTARG}
            if [ "$USE_CSV" -ne "0" -a "$USE_CSV" -ne "1" ]; then
                echo "ERROR: Invalid value for argument '-c'"
                usage
            fi
            ;;
        s)
            START_DATE=${OPTARG};;
        e)
            END_DATE=${OPTARG};;
        h)
            usage;;
        \?)
            echo 1>&2 "ERROR: Invalid argument passed."
            usage;;
    esac
done

echo
log "Fetching logs generated between dates [ $START_DATE ] and [ $END_DATE ] (UTC)."

download=0

if [ $USE_CSV -eq 1 ]; then
    logfilelist=$(aws --region $REGION rds describe-db-log-files --db-instance-identifier $DB_INSTANCE --no-paginate --output text | grep "error/postgresql.log.*.csv" | cut -f3 | cut -d '/' -f2 | sort)
else
    logfilelist=$(aws --region $REGION rds describe-db-log-files --db-instance-identifier $DB_INSTANCE --no-paginate --output text | grep -v ".csv" | grep "error/postgresql.log.*" | cut -f3 | cut -d '/' -f2 | sort)
fi

for logfile in $logfilelist; do
    if [[ $logfile == *"$START_DATE"* ]]; then
        download=1
    fi

    if [ $download -eq 1 ]
    then
        log "Downloading log file = $logfile"
        aws --region $REGION rds download-db-log-file-portion --db-instance-identifier $DB_INSTANCE --output text --starting-token 0 --log-file-name error/$logfile > temp/$logfile
    fi

    if [[ $logfile == *"$END_DATE"* ]]; then
        break
    fi
done

log "PostgreSQL Logs download completed."
echo
# Import log files into pgbadger and generate html report 
reportname=$(date +"%Y%m%d-%H%M%S")
exec pgbadger -p "%t:%r:%u@%d:[%p]:" temp/postgresql.log.*  -o reports/report-${reportname}.html

# Send report via SES to email addresses by calling python script to send email. 
exec python3 sendmail.py

