# -------------------------------------------------------------------------- #
# Copyright 2014, Laurent Grawet <dev@grawet.be>                             #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #


# SSH connect timeout for V7000 operations
CONNECT_TIMEOUT=15

# flock timeout for v7000_lock function
FLOCK_TIMEOUT=600

# flock lockfile for v7000_lock function
FLOCK_LOCKFILE="/var/lock/one/.v7000.lock"

# flock file descriptor for v7000_lock function
FLOCK_FD=200

# Use ddpt instead of dd to speed up data transferts using sparse copy
USE_DDPT=1

BLOCKDEV=blockdev
DDPT=ddpt
DMSETUP=dmsetup
FIND=find
FLOCK=flock
HEAD=head
MULTIPATH=multipath
OD=od
TEE=tee

function v7000_lock {
    local STATUS
    STATUS=0
    eval "exec $FLOCK_FD> $FLOCK_LOCKFILE"
    $FLOCK -w $FLOCK_TIMEOUT -x $FLOCK_FD
    STATUS=$?
    if [ $STATUS -ne 0 ]; then
        log_error "Error, lock wait timeout (${FLOCK_TIMEOUT}s) exceeded for $FLOCK_LOCKFILE"
        error_message "Error, lock wait timeout (${FLOCK_TIMEOUT}s) exceeded for $FLOCK_LOCKFILE"
        exit $STATUS 
    fi
}

function v7000_unlock {
    $FLOCK -u $FLOCK_FD
}


function v7000_ssh_exec_and_log
{
    v7000_lock
    local SSH_EXEC_OUT SSH_EXEC_RC
    SSH_EXEC_OUT=`$SSH -o ConnectTimeout=$CONNECT_TIMEOUT "$1" "$2" 2>&1`
    SSH_EXEC_RC=$?
    v7000_unlock

    if [ $SSH_EXEC_RC -ne 0 ]; then
        log_error "Command \"$2\" failed: $SSH_EXEC_OUT"

        if [ -n "$3" ]; then
            error_message "$3"
        else
            error_message "Error executing $2: $SSH_EXEC_OUT"
        fi

        exit $SSH_EXEC_RC
    fi
}

function v7000_ssh_monitor_and_log
{
    v7000_lock
    local SSH_EXEC_OUT SSH_EXEC_RC
    SSH_EXEC_OUT=`$SSH -o ConnectTimeout=$CONNECT_TIMEOUT "$1" "$2" 2>&1`
    SSH_EXEC_RC=$?
    v7000_unlock

    if [ $SSH_EXEC_RC -ne 0 ]; then
        log_error "Command \"$2\" failed: $SSH_EXEC_OUT"

        if [ -n "$3" ]; then
            error_message "$3"
        else
            error_message "Error executing $2: $SSH_EXEC_OUT"
        fi

        exit $SSH_EXEC_RC
    fi
    echo "$SSH_EXEC_OUT"
}

function v7000_get_vdisk_uid {
    local VDISK_NAME V7K_MGMT V7K_MGMT_AUX STATUS VDISK_UID
    VDISK_NAME="$1"
    V7K_MGMT="$2"
    V7K_MGMT_AUX="$3"
    STATUS=0
    VDISK_UID=`v7000_ssh_monitor_and_log $V7K_MGMT \
        "set -e ; svcinfo lsvdisk -nohdr -delim : -filtervalue vdisk_name=$VDISK_NAME" \
        | $AWK -F\: '{print tolower($14)}'`
    if [ -z "$VDISK_UID" ] && [ -n $V7K_MGMT_AUX ]; then
        STATUS=2
        VDISK_UID=`v7000_ssh_monitor_and_log $V7K_MGMT_AUX \
            "set -e ; svcinfo lsvdisk -nohdr -delim : -filtervalue vdisk_name=$VDISK_NAME" \
            | $AWK -F\: '{print tolower($14)}'`
    fi
    if [ -n "$VDISK_UID" ]; then
        echo "$VDISK_UID"
        exit $STATUS
    else
        STATUS=1
        log_error "Error vdisk UID for $VDISK_NAME"
        error_message "Error getting vdisk UID for $VDISK_NAME"
        exit $STATUS
    fi
}

function v7000_get_vdisk_name {
    local VDISK_UID V7K_MGMT V7K_MGMT_AUX STATUS VDISK_NAME
    VDISK_UID="$1"
    V7K_MGMT="$2"
    V7K_MGMT_AUX="$3"
    STATUS=0
    VDISK_NAME=`v7000_ssh_monitor_and_log $V7K_MGMT \
        "set -e ; svcinfo lsvdisk -nohdr -delim : -filtervalue vdisk_UID=$VDISK_UID" \
        | $AWK -F\: '{print $2}'`
    if [ -z "$VDISK_NAME" ] && [ -n $V7K_MGMT_AUX ]; then
        STATUS=2
        VDISK_NAME=`v7000_ssh_monitor_and_log $V7K_MGMT_AUX \
            "set -e ; svcinfo lsvdisk -nohdr -delim : -filtervalue vdisk_UID=$VDISK_UID" \
            | $AWK -F\: '{print $2}'`
    fi
    if [ -n "$VDISK_NAME" ]; then
        echo "$VDISK_NAME"
        exit $STATUS
    else
        STATUS=1
        log_error "Error getting vdisk name for $VDISK_UID"
        error_message "Error getting vdisk name for $VDISK_UID"
        exit $STATUS 
    fi
}

function v7000_get_vdisk_size {
    local VDISK_NAME V7K_MGMT V7K_MGMT_AUX STATUS VDISK_SIZE
    VDISK_NAME="$1"
    V7K_MGMT="$2"
    V7K_MGMT_AUX="$3"
    STATUS=0
    VDISK_SIZE=`v7000_ssh_monitor_and_log $V7K_MGMT \
        "set -e ; svcinfo lsvdisk -nohdr -delim : -bytes -filtervalue vdisk_name=$VDISK_NAME" \
        | $AWK -F\: '{print $8}'`
    if [ -z "$VDISK_SIZE" ] && [ -n $V7K_MGMT_AUX ]; then
        STATUS=2
        VDISK_SIZE=`v7000_ssh_monitor_and_log $V7K_MGMT_AUX \
            "set -e ; svcinfo lsvdisk -nohdr -delim : -bytes -filtervalue vdisk_name=$VDISK_NAME" \
            | $AWK -F\: '{print $8}'`
    fi
    if [ -n "$VDISK_SIZE" ]; then
        echo "$VDISK_SIZE"
        exit $STATUS
    else
        STATUS=1
        log_error "Error getting vdisk size for $VDISK_NAME"
        error_message "Error getting vdisk size for $VDISK_NAME"
        exit $STATUS
    fi
}

function v7000_get_vdisk_attr {
    local VDISK_NAME VDISK_ATTR V7K_MGMT V7K_MGMT_AUX STATUS ATTR
    VDISK_NAME="$1"
    VDISK_ATTR="$2"
    V7K_MGMT="$3"
    V7K_MGMT_AUX="$4"
    STATUS=0
    ATTR=`v7000_ssh_monitor_and_log $V7K_MGMT \
        "set -e ; svcinfo lsvdisk -delim : $VDISK_NAME" \
        | $GREP -w $VDISK_ATTR | $AWK -F\: '{print $2}'`
    if [ -z "$ATTR" ] && [ -n $V7K_MGMT_AUX ]; then
        STATUS=2
        ATTR=`v7000_ssh_monitor_and_log $V7K_MGMT_AUX \
            "set -e ; svcinfo lsvdisk -delim : $VDISK_NAME" \
            | $GREP -w $VDISK_ATTR | $AWK -F\: '{print $2}'`
    fi
    if [ -n "$ATTR" ]; then
        echo "$ATTR"
        exit $STATUS
    else
        STATUS=1
        log_error "Error getting vdisk attribute $VDISK_ATTR for $VDISK_UID"
        error_message "Error getting vdisk attribute $VDISK_ATTR for $VDISK_UID"
        exit $STATUS 
    fi
}

function v7000_lsvdiskdependentmaps {
    local VDISK_NAME V7K_MGMT i
    local -a FCMAP
    VDISK_NAME="$1"
    V7K_MGMT="$2"

    while IFS= read -r line; do
        FCMAP[i++]="$line"
    done < <(v7000_ssh_monitor_and_log $V7K_MGMT "lsfcmap -nohdr -delim : -filtervalue source_vdisk_name=$VDISK_NAME")
    echo ${FCMAP[@]}
}

function v7000_is_rcrelationship {
    local REL_NAME V7K_MGMT REL
    REL_NAME="$1"
    V7K_MGMT="$2"
    REL=`v7000_ssh_monitor_and_log $V7K_MGMT \
        "set -e ; svcinfo lsrcrelationship -nohdr -delim : -bytes -filtervalue RC_rel_name=$REL_NAME" \
        | $AWK -F\: '{print $2}'`
    if [  "$REL" = "$REL_NAME" ]; then
        return 0
    else
        return 1
    fi
}

function v7000_is_primary {
    local REL_NAME PRIMARY_NAME V7K_MGMT PRIMARY
    REL_NAME="$1"
    PRIMARY_NAME="$2"
    V7K_MGMT="$3"
    PRIMARY=`v7000_ssh_monitor_and_log $V7K_MGMT \
        "set -e ; svcinfo lsrcrelationship -nohdr -delim : -bytes -filtervalue RC_rel_name=$REL_NAME" \
        | $AWK -F\: '{print $11}'`
    if [  "$PRIMARY" = "$PRIMARY_NAME" ]; then
        return 0
    else
        return 1
    fi
}

function v7000_map {
    local V7K_MGMT HOST VDISK MAP_CMD
    V7K_MGMT="$1"
    HOST="$2"
    VDISK="$3"
    MAP_CMD=`v7000_ssh_monitor_and_log $V7K_MGMT \
        "set -e ; svctask mkvdiskhostmap -force -host $HOST $VDISK" \
        "Error mapping vdisk $VDISK to $HOST"`
    sleep 1
}

function v7000_unmap {
    local V7K_MGMT HOST VDISK UNMAP_CMD
    V7K_MGMT="$1"
    HOST="$2"
    VDISK="$3"
    UNMAP_CMD=`v7000_ssh_monitor_and_log $V7K_MGMT \
        "set -e ; svctask rmvdiskhostmap -host $HOST $VDISK" \
        "Error unmapping vdisk $VDISK from $HOST"`
    sleep 1
}

function iscsiadm_discovery_login {
    local PORTAL
    PORTAL=("$@")
    for i in ${PORTAL[@]}; do
      echo "$ISCSIADM -m discovery -t st -p $i --login"
    done
}

function iscsiadm_node_logout {
    local PORTAL
    PORTAL=("$@")
    for i in ${PORTAL[@]}; do
      echo "$ISCSIADM -m node -p $i --logoutall all"
    done
}

function iscsiadm_session_rescan {
    echo "$ISCSIADM -m session --rescan"
    sleep 2
}

function multipath_flush {
    local MAP_NAME
    MAP_NAME="$1"
    echo "$MULTIPATH -f $MAP_NAME"
}

function multipath_rescan {
    echo "$MULTIPATH"
    sleep 4
}

function get_datastore_attr {
    local DS_ID DS_ATTR ATTR
    DS_ID="$1"
    DS_ATTR="$2"
    ATTR=`onedatastore show $DS_ID | $GREP -w $DS_ATTR | $CUT -d\" -f2`
    if [ -n $ATTR ]; then
        echo "$ATTR"
    fi
}

function clone_command {
    local IF OF
    IF="$1"
    OF="$2"
    if [ $USE_DDPT -eq 1 ]; then
        echo "$DDPT if=$IF of=$OF bs=512 bpt=128 oflag=sparse"
    else
        echo "$DD if=$IF of=$OF bs=64k conv=nocreat"
    fi
}
