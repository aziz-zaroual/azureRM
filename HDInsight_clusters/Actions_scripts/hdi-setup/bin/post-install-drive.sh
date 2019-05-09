#! /bin/bash

#hdfs dfs -mkdir /user/hive/.Trash
#hdfs dfs -mkdir /user/oozie/.Trash
#hdfs dfs -mkdir /user/spark/.Trash
#hdfs dfs -mkdir /home/SPAPPLIBDTHDIDEV/.Trash
#hdfs dfs -chmod 700 -R /user/hive/.Trash
#hdfs dfs -chmod 700 -R /user/oozie/.Trash
#hdfs dfs -chmod 700 -R /user/spark/.Trash
#hdfs dfs -chmod 700 -R /home/SPAPPLIBDTHDIDEV/.Trash
#hdfs dfs -chown hive:hive -R /user/hive/.Trash
#hdfs dfs -chown oozie:oozie -R /user/oozie/.Trash
#hdfs dfs -chown spark:spark -R /user/spark/.Trash


usage ()
{
    echo "
##########################################
Configuration of some share.
Usage: sudo post-install.sh <SHARE> [options]

Parameters:
  SHARE			- not mandatory default share is build .

Example:
    ./post-install.sh staomee2r ******* /mnt/build

##########################################"
    trace_failure_end_processing 132
}


###################################################################
#
# FUNCTIONS
#
###################################################################
trace_rouge()
{
    local message="$*"
    echo "$(date +"%Y-%m-%d %H:%M:%S") $message" >> ${FULL_LOG_FILE}
    printf "$(date +"%Y-%m-%d %H:%M:%S") $(printf "\033[91m")$message$(printf "\033[0m")\n"
}

trace_violet()
{
    local message="$*"
    echo "$(date +"%Y-%m-%d %H:%M:%S") $message" >> ${FULL_LOG_FILE}
    printf "$(date +"%Y-%m-%d %H:%M:%S") $(printf "\033[95m")$message$(printf "\033[0m")\n"
}

trace_blanc()
{
    local message="$*"
    echo "$(date +"%Y-%m-%d %H:%M:%S") $( echo "${message}" | sed "s/&/\&/g" | sed "s/%/\%%/g" | sed 's#\\#\\\\#g' )" >> ${FULL_LOG_FILE}
    printf "$(date +"%Y-%m-%d %H:%M:%S") $(printf "\033[97m")$( echo "${message}" | sed "s/&/\&/g" | sed "s/%/\%%/g" | sed 's#\\#\\\\#g' )$(printf "\033[0m")\n"
}

trace_success()
{
    local message="$*"
    echo "$(date +"%Y-%m-%d %H:%M:%S") [   OK   ]  $message" >> ${FULL_LOG_FILE}
    printf "$(date +"%Y-%m-%d %H:%M:%S") $(printf "\033[92m")[   OK   ]  $message$(printf "\033[0m")\n"
}

trace_warning()
{
    local message="$*"
    echo "$(date +"%Y-%m-%d %H:%M:%S") [ WARNING ] $message" >> ${FULL_LOG_FILE}
    printf "$(date +"%Y-%m-%d %H:%M:%S") $(printf "\033[93m")[ WARNING ] $message$(printf "\033[0m")\n"
}

trace_failure()
{
    local _message="$1"
    trace_rouge "[  ERROR  ]  $_message"
}

trace_failure_end_processing ()
{
    local _exit_code="$1"
    trace_rouge "[ END ] Stop the load test script"

    if [ "${LOGS_WASB_DIR}" != "" ]; then
        trace_violet "=============================================================================="
        trace_violet "Copying the log file ${LOG_FILE} to the WASB"
        trace_violet "=============================================================================="
        hadoop fs -mkdir -p ${LOGS_WASB_DIR}/logs/
        hadoop fs -rmr ${LOGS_WASB_DIR}/logs/${LOG_FILE}
        hadoop fs -copyFromLocal ${FULL_LOG_FILE} ${LOGS_WASB_DIR}/logs/
        retcode=$?
        if [ $retcode -eq 0 ] || [ $retcode -eq 1 ]; then
            trace_success "Copy the file ${FULL_LOG_FILE} to the directory WASB ${LOGS_WASB_DIR}/logs/"
            trace_blanc " - Command: hadoop fs -copyFromLocal ${FULL_LOG_FILE} ${LOGS_WASB_DIR}/logs/"
            trace_blanc " - Return code: ${retcode}"
        else
            trace_failure "Unable to copy the file ${FULL_LOG_FILE} to the directory WASB ${LOGS_WASB_DIR}/logs/"
            trace_rouge " - Command: hadoop fs -copyFromLocal ${FULL_LOG_FILE} ${LOGS_WASB_DIR}/logs/"
            trace_rouge " - Return code: ${retcode}"
        fi
    fi
    
    exit ${_exit_code}
}

get_primary_headnode() {
    headnodes=`get_headnodes`
    echo "`(echo $headnodes | cut -d ',' -f 1)`"
}

get_primary_headnode_number() {
    primaryhn=`get_primary_headnode`
    echo "`(sed -n -e 's/hn\(.*\)-.*/\1/p' <<< $primaryhn)`"
}
getPassword() {
    KEY=`grep -A1 "fs\.azure\.account\.key\." $HADOOP_CORE_CONF | grep "<value>" | sed 's/ *//;s/<[^>]*>//g'`
    export PASSWORD=`/usr/lib/hdinsight-common/scripts/decrypt.sh $KEY`
}

getStorage() {
    PROVIDER="fs\.azure\.account\.keyprovider"
    export STORAGE=`grep $PROVIDER $HADOOP_CORE_CONF | sed "s/.*$PROVIDER\.\([a-z0-9]*\).*/\1/"`
}

mountExternalStorage() {
    usage() {
        echo "Invoke with mountExternalStorage account sharename password mountpoint"

    }
    if [ -z "$1" ]; then
            echo "Need storage account name to run"
            exit 136
            usage
    fi
    if [ -z "$2" ]; then
            echo "Need storage sharename to run"
            exit 137
            usage
    fi
    if [ -z "$3" ]; then
            echo "Need storage password to run"
            exit 138
            usage
    fi
    ACCOUNT=$1
    SHARE=$2
    PASSWORD=$3
    MOUNT=$SHARE
    mount -t cifs //$ACCOUNT.file.core.windows.net/$SHARE /mnt/$MOUNT -o vers=3.0,username=$ACCOUNT,password=$PASSWORD,dir_mode=0777,file_mode=0777,serverino
}

createFolder() {
    if [ ! -d $1 ]; then
         mkdir -p $1
    fi
}

HADOOP_CORE_CONF="/etc/hadoop/conf/core-site.xml"
SCRIPT_NAME=$0
SHARE="build"



trace_blanc "[ BEGIN ] Executing the script ${SCRIPT_NAME}"

# Check input parameter
if [ ! -z "$1" ]; then
    echo "SET SHARE" 
    SHARE=$1
fi



# PRIMARYHEADNODE=`get_primary_headnode`
# PRIMARY_HN_NUM=`get_primary_headnode_number`

# # Check if values retrieved are empty, if yes, exit with error
# if [[ -z $PRIMARYHEADNODE ]]; then
#     trace_failure "Could not determine primary headnode."
#     trace_failure_end_processing 141
# fi

# if [[ -z "$PRIMARY_HN_NUM" ]]; then
#     trace_failure "Could not determine primary headnode number."
#     trace_failure_end_processing 142
# fi


    trace_blanc "STORAGE_ACCOUNT: ${STORAGE}"
    trace_blanc "STORAGE_ACCOUNT_KEY: ******"
    trace_blanc "MOUNT_POINT: ${SHARE}"

    trace_violet "=============================================================================="
    trace_violet "Mounting azure file"
    trace_violet "=============================================================================="

    getStorage
    getPassword
    trace_violet "=============================================================================="
    trace_violet "Creating mount directory /mnt/$SHARE"
    trace_violet "=============================================================================="
    createFolder /mnt/$SHARE
    trace_violet "=============================================================================="
    trace_violet "Mounting external ${STORAGE} ${SHARE} directory /mnt/$SHARE"
    trace_violet "=============================================================================="
    
    mountExternalStorage $STORAGE $SHARE $PASSWORD
    retcode=$?0

    if [ $retcode -eq 0 ] || [ $retcode -eq 1 ]; then
    trace_success "Create the directory ${SPARK_LIBS_JARS}/"
    else
    trace_failure "Unable to mount azure file  ${STORAGE_ACCOUNT_URI}/"
    trace_rouge " - Command: mount -t cifs ${STORAGE_ACCOUNT_URI} ${MOUNT_POINT} -o vers=3.0,username=${STORAGE_ACCOUNT_NAME},password=******,dir_mode=0777,file_mode=0777,sec=ntlmssp"
    trace_rouge " - Return code: ${retcode}"
    trace_failure_end_processing 139
    fi

    path=$(printf "${MOUNT_POINT}\\%s" $(hostname))
    echo $(date) > $path
    if [ $retcode -eq 0 ] || [ $retcode -eq 1 ]; then
    trace_success "Create temp file ${path} on  mount point ${MOUNT_POINT}"
    else
    trace_failure "Unable to create file on ${MOUNT_POINT}"
    trace_rouge " - Return code: ${retcode}"
    trace_failure_end_processing 139
    fi

    rm -f $path
    if [ $retcode -eq 0 ] || [ $retcode -eq 1 ]; then
    trace_success "delete temp file ${path} on  mount point ${MOUNT_POINT}"
    else
    trace_failure "Unable to delete file on ${MOUNT_POINT}"
    trace_rouge " - Return code: ${retcode}"
    trace_failure
    fi

exit 0