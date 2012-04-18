#!/bin/bash

DEBUG=0
SCRIPT_PATH=`readlink -f $0`
SCRIPT_DIR=`dirname "$SCRIPT_PATH"`
LOG_FILE="$SCRIPT_DIR/run.log"
ERROR_FILE="$SCRIPT_DIR/error.log"

HOME_DIR="/home/team"
GROUP_PREFIX="z_"
USER_PREFIX="u_"
KEY_FOLDER="keys"
BASE_PATH="/home/doc-store"

# useradd -m -d /home/team/anoopjohn anoopjohn
# userdel -r anoopjohn
# groupmems -g z_team -l
# groupadd z_team
# cat /etc/group | egrep ^z_
# cat /etc/passwd | grep "/home/team/"
# cat /etc/passwd | grep "/home/team/anoopjohn"
# usermod -e 1 -L anoopjohn
# usermod -e 99999 -U anoopjohn
# groups anoopjohn
# usermod -a -G "z_team" anoopjohn
# cat /etc/shadow | egrep ^anoopjohn | grep '!'; echo $?
# cat /etc/group | egrep ^z_team | cut -d":" -f 4 | tr "," " "
# groupdel z_team
# getfacl t | grep "# group" | cut -d":" -f 2 | sed 's/ //'
# getfacl t | grep "# owner" | cut -d":" -f 2 | sed 's/ //'
# getfacl t | grep user:u_vimal | grep "r-x"
# cat /etc/shadow | grep u_ | cut -d: -f 1 | xargs -I '{}' userdel -r {}
     
# Debug function
function db {
  if [ $DEBUG -eq 1 ];
  then
    echo "$@"
  fi
}

# Log function, handles input from stdin or from arguments
function log {
  # If there are parameters read from parameters
  if [ $# -gt 0 ]; then
    echo "[$(date +"%D %T")] $@" >> $LOG_FILE
    db "$@"
  else 
    # If there are no parameters read from stdin
    while read data
    do
      echo "[$(date +"%D %T")] $data" >> $LOG_FILE 
      db "$data"
    done
  fi
}

# Error function
# Usage: error N message
function error {
  echo "[$(date +"%D %T")] $@" >> $ERROR_FILE
  db "$@"
}

# Trim function
function trim() { echo $1; }

# Manage users in the system
function manage_user() {
  local un="$2"
  local ret=""
  local pk=""
  local k=""
  case "$1" in
    "is_present")
      cat /etc/passwd | grep ":$HOME_DIR/$un:" > /dev/null
      ret=$?
      ;;
    "is_enabled")
      ret=1
      if [[ -e "$HOME_DIR/$un/.ssh/authorized_keys" ]]; then
        ret=0
      fi
      ;;
    "create")
      pk="$3"
      # Create the user
      useradd -m -d $HOME_DIR/$un $un
      mkdir $HOME_DIR/$un/.ssh
      chmod 700 $HOME_DIR/$un/.ssh
      touch $HOME_DIR/$un/.ssh/authorized_keys
      chmod 600 $HOME_DIR/$un/.ssh/authorized_keys
      chown -R $un:$un $HOME_DIR/$un/.ssh
      # Set authorized_key(s)
      manage_user sync_keys "$un" "$pk"
      ret=0
      ;;
    "enable")
      pk="$3"
      # Set authorized_key(s)
      echo -n > $HOME_DIR/$un/.ssh/authorized_keys
      manage_user sync_keys "$un" "$pk"
      ret=0
      ;;
    "sync_keys")
      pk="$3"
      local num_keys_passed=0
      # Add key if the key is not already present
      for k in $pk
      do
        num_keys_passed=$(($num_keys_passed+1))
        key=`cat $KEY_FOLDER/$k`
        # Test if the key is already present
        cat $HOME_DIR/$un/.ssh/authorized_keys | grep "$key" > /dev/null
        # If key is not already present
        if [[ $? -ne 0 ]]; then
          # Set authorized_key
          log "Syncing key $KEY_FOLDER/$k for user $un"
          cat $KEY_FOLDER/$k >> $HOME_DIR/$un/.ssh/authorized_keys
        fi 
      done
      # If the number of keys in authorized_keys is different from the number of keys passed
      # then recreate the full authorized_keys list
      local num_keys_in_file=`cat $HOME_DIR/$un/.ssh/authorized_keys | wc -l`
      if [[ $num_keys_in_file -ne $num_keys_passed ]]; then
        log "For user $un number of keys passed($num_keys_passed) different from the number in file($num_keys_in_file). Resyncing."
        echo -n > $HOME_DIR/$un/.ssh/authorized_keys
        manage_user sync_keys "$un" "$pk"
      fi
      ret=0
      ;;
    "disable")
      # Remove authorized_keys file (after keeping a copy) to disable the user
      cat $HOME_DIR/$un/.ssh/authorized_keys >> $HOME_DIR/$un/.ssh/authorized_keys_disabled
      rm $HOME_DIR/$un/.ssh/authorized_keys
      ret=0
      ;;
    *)
      ret=0
    ;;
  esac
  ret=$((1 - $ret))
  return $ret;
}

# Synchronize a users details on the server
function sync_user() {
  local key
  # Catch errors if any
  if [[ "$username" == "" ]]; then
    error "Empty username read from configuration file"
    return
  fi
  for key in $user_keys
  do
    if [[ ! -e "$KEY_FOLDER/$key" ]]; then
      error "Key $key is not present in the folder - $KEY_FOLDER"
      return
    fi
  done
  db "Syncing $username"
  db "Status $user_status"
  db "Key $user_keys"
  local system_username="${USER_PREFIX}${username}"
  db "System user $system_username"
  manage_user is_present "$system_username"
  local is_user_present=$?
  local is_user_enabled=1
  # 1 True 0 False
  if [[ $is_user_present -eq 1 ]]; then
    db "$system_username is present"
    manage_user is_enabled "$system_username"
    is_user_enabled=$?
  fi
  # Check if the user is already present in the system and if not, create the user if status in conf is not disabled.
  if [[ "$user_status" == "enabled" ]]; then
    db "$system_username is enabled in conf"
    if [[ $is_user_present -ne 1 ]]; then
      db "$system_username is enabled in conf but not present in system"
      log "Creating user $system_username with keys $user_keys"
      manage_user create "$system_username" "$user_keys"
    else
      # If the user is already present but disabled and status is enabled in conf then enable the user account
      if [[ $is_user_enabled -ne 1 ]]; then
        db "$system_username is enabled in conf, present but disabled in system"
        log "Enabling user $system_username with keys $user_keys"
        manage_user enable "$system_username" "$user_keys" 
      else
        db "$system_username is enabled in conf, present and enabled in system"
        db "Syncing keys for $system_username with keys $user_keys"
        # If the user is enabled, check if the key has been added to the authorized keys file and if not, add it.
        manage_user sync_keys "$system_username" "$user_keys" 
      fi
    fi
  else
    db "$system_username is disabled in conf"
    # If the user is already present and status is disabled in conf then disable the user account if it is not already disabled
    if [[ $is_user_present -eq 1 ]]; then
      db "$system_username is disabled in conf but present in system"
      if [[ $is_user_enabled -eq 1 ]]; then
        db "$system_username is disabled in conf but present in system and also enabled"
        log "Disabling user $system_username"
        manage_user disable "$system_username"
      fi  
    fi
  fi
  username=""
  user_status="disabled"
  user_keys=""
}

# Manage groups in the system
function manage_group() {
  local gn="$2"
  local gu="$3"
  local u=""
  local un=""
  case "$1" in
    "is_present")
      cat /etc/group | egrep ^$gn > /dev/null
      ret=$?
      ;;
    "create")
      # Create the group
      groupadd $gn
      for u in $gu
      do
        usermod -a -G $gn ${USER_PREFIX}$u
      done
      ret=0
      ;;
    "is_user_present")
      gn=$2
      un=$3
      gu=`cat /etc/group | egrep ^$gn | cut -d":" -f 4`
      echo ",$gu," | grep ",$un," > /dev/null
      ret=$?
      ;;
    "sync_users")
      ret=1
      # For each user in the group in conf
      for u in $gu
      do
        un=${USER_PREFIX}$u
        # Check if the user is present in the system group and if not, add the user to the group
        manage_group is_user_present $gn $un
        if [[ $? -ne 1 ]]; then
          log "Adding $un to $gn"
          usermod -a -G $gn $un
          ret=0
        fi
      done
      # For each user in the group in system
      for un in `cat /etc/group | egrep ^$gn | cut -d":" -f 4 | tr "," " "`
      do
        u=`echo $un | sed "s/^${USER_PREFIX}//"`
        # Check if the user is present in the conf group and if not, remove the user from the group
        echo " $gu " | grep " $u " > /dev/null
        if [[ $? -ne 0 ]]; then
          local ugn=`groups $un | cut -d":" -f 2 | tr " " "," | sed 's/$/,/' | sed "s/,$gn,/,/" | sed 's/^,//' | sed 's/,$//'`
          log "Removing $un from $gn. Setting $ugn for $un"
          usermod -G $ugn $un
          ret=0
        fi
      done
      ;;
    "delete")
      groupdel $gn
      ret=0
      ;;
    *)
      ret=0
    ;;
  esac
  ret=$((1 - $ret))
  return $ret;
}

# Synchronize a groups details on the server
function sync_group() {
  # Catch errors if any
  if [[ "$group_name" == "" ]]; then
    error "Empty groupname read from configuration file"
    return
  fi
  local u
  local system_username
  for u in $group_users
  do
    system_username=${USER_PREFIX}$u
    # Check if the user is present in the system group and if not, add the user to the group
    manage_user is_present "$system_username"
    if [[ $? -ne 1 ]]; then
      error "User $u present in group $group_name in the configuraion file is not a valid user in the system"
      return
    fi
  done
  db "Syncing $group_name"
  db "Users $group_users"
  system_group_name="${GROUP_PREFIX}${group_name}"
  db "System group $system_group_name"
  manage_group is_present "$system_group_name"
  is_group_present=$?
  # Check if the group is already present in the system and if not, create the group if status is not disabled
  if [[ $group_status == "enabled" ]]; then
    if [[ $is_group_present -ne 1 ]]; then
      db "$system_group_name is enabled in conf but not present in system"
      log "Creating group $system_group_name with users $group_users"
      manage_group create "$system_group_name" "$group_users"
    else
      db "$system_group_name is enabled in conf and present in system"
      manage_group sync_users "$system_group_name" "$group_users"
    fi
  else
    # If the group is present and status is disabled, delete the group.
    if [[ $is_group_present -eq 1 ]]; then
      db "$system_group_name is disabled in conf but present in system"
      log "Deleting group $system_group_name"
      manage_group delete "$system_group_name"
    fi
  fi
  group_name=""
  group_status="disabled"
}

# Manage folders in the system
function manage_folder() {
  local fn="$2"
  local rou="$3"
  local rog="$4"
  local rwu="$5"
  local rwg="$6"
  local u=""
  local un=""
  local g=""
  local gn=""
  local fo=""
  local fg=""
  local folder="$BASE_PATH/$fn"
  case "$1" in
    "is_present")
      ret=1
      if [[ -d $folder ]]; then
        ret=0
      fi  
      ;;
    "create")
      # Create the folder
      log "Creating $folder"
      mkdir -p "$folder"
      chmod 700 "$folder"
      ret=$?
      ;;
    "sync_ownership")
      ret=1
      # Expect full path here
      folder=$fn
      local owner=`getfacl -p "$folder" | grep "# owner" | cut -d":" -f 2 | sed 's/ //'`
      local group=`getfacl -p "$folder" | grep "# group" | cut -d":" -f 2 | sed 's/ //'`
      local recursive=$5
      fo=${USER_PREFIX}$3
      fg=${GROUP_PREFIX}$4
      if [[ "$fo" != "$owner" ]]; then
        log "Setting owner of $folder to $fo"
        chown $fo $folder
        if [[ "$recursive" != 0 ]]; then
          find $folder -maxdepth 1 -type f -exec chown $fo {} \; | log
        fi
        ret=0
      fi
      if [[ "$fg" != "$group" ]]; then
        log "Setting group of $folder to $fg"
        chgrp $fg $folder
        if [[ "$recursive" != 0 ]]; then
          find $folder -maxdepth 1 -type f -exec chgrp $fg {} \; | log
        fi
        ret=0
      fi
      ;;
    "sync_acl")
      # Expect full path here
      local path=$fn
      local origfolder=$3
      log "Syncing ACL of $path from $origfolder"
      getfacl -p $origfolder | setfacl --set-file=- $path
      ret=0
      ;;
    "sync_newfiles")
      for fn in `find $folder`
      do
        local owner=`getfacl -p "$fn" | grep "# owner" | cut -d":" -f 2 | sed 's/ //'`
        local group=`getfacl -p "$fn" | grep "# group" | cut -d":" -f 2 | sed 's/ //'`
        # If the user and group are the same then this is a newly created file. In that case
        # Sync ownership and acls to that of the current folder
        if [[ "$owner" == "$group" ]]; then
          log "Syncing ownership and ACL of $fn"
          manage_folder sync_ownership "$fn" "$folder_owner" "$folder_group" 0
          manage_folder sync_acl "$fn" "$BASE_PATH/$folder_name"
        fi
      done
      ret=0
      ;;
    "sync_perm")
      local u_list=$5
      local u_type=$3
      local u_perm=$4
      local u_prefix=""
      u_prefix=${USER_PREFIX}
      if [[ "$u_type" = "group" ]]; then
        u_prefix=${GROUP_PREFIX}
      fi
      # For each user/group passed
      for u in $u_list
      do
        un=${u_prefix}$u
        # Check if the user/group is present in the system with the given permissions
        # and if not, add the user/group with the given permissions
        getfacl -p "$folder" | grep "$u_type:$un:" | grep "$u_perm" > /dev/null
        if [[ $? -ne 0 ]]; then
          log "Adding $u_perm permissions to $un on $folder"
          setfacl -m "$u_type:$un:$u_perm" "$folder"
          if [[ $? -ne 0 ]]; then
            error "Something went wrong with setting $u_type:$un:$u_perm for $folder"
          fi
          ret=0
        fi
      done
      local acl
      for acl in `getfacl -p "$folder" | egrep "^$u_type:" | grep -v "::" | egrep ":$u_perm\$"`
      do 
        # Check if the user/group is present in the conf with the given permissions
        # and if not, remove the acl line
        u=`echo $acl | cut -d":" -f 2 | sed "s/^$u_prefix//"`
        un=${u_prefix}$u
        echo " $u_list " | grep " $u " > /dev/null
        if [[ $? -ne 0 ]]; then
          log "Removing $u_type:$un on $folder"
          setfacl -x "$u_type:$un" "$folder"
        fi
      done;
      ;;
    "sync_permissions")
      manage_folder sync_perm "$fn" "user" "r-x" "$rou"
      manage_folder sync_perm "$fn" "group" "r-x" "$rog"
      manage_folder sync_perm "$fn" "user" "rwx" "$rwu"
      manage_folder sync_perm "$fn" "group" "rwx" "$rwg"
      ret=0
      ;;
    *)
      ret=0
    ;;
  esac
  ret=$((1 - $ret))
  return $ret;
}

# Synchronize a folders details on the server
function sync_folder() {
  # Catch errors if any
  if [[ "$folder_name" == "" ]]; then
    error "Empty folder name read from configuration file"
    return
  fi
  local list
  local i
  local u_type
  local u_prefix
  local un
  i=0
  for list in "$folder_rousers" "$folder_rogroups" "$folder_rwusers" "$folder_rwgroups" 
  do
    i=$(($i + 1))
    u_type='user'
    if [[ $i -eq 2 || $i -eq 4 ]]; then
      u_type='group'
    fi
    local u
    for u in $list
    do
      if [[ "$u_type" == "user" ]]; then
        db "Testing user $u"
        un=${USER_PREFIX}$u
        manage_user is_present "$un"
        if [[ $? -ne 1 ]]; then
          error "User $u present in folder $folder_name in the configuraion file is not a valid user in the system"
          return
        fi
      else
        db "Testing group $u"
        un=${GROUP_PREFIX}$u
        manage_group is_present "$un"
        if [[ $? -ne 1 ]]; then
          error "Group $u present in folder $folder_name in the configuraion file is not a valid group in the system"
          return
        fi
      fi
    done
  done

  db "Syncing $folder_name"
  db "Read Only Users $folder_rousers"
  db "Read Only Groups $folder_rogroups"
  db "RW Users $folder_rwusers"
  db "RW Groups $folder_rwgroups"

  manage_folder is_present "$folder_name"
  is_folder_present=$?
  
  # Check if the folder is present in the system and if not, create the folder
  if [[ $is_folder_present -ne 1 ]]; then
    manage_folder create "$folder_name"
  fi
  manage_folder sync_ownership "$BASE_PATH/$folder_name" "$folder_owner" "$folder_group" "recursive"
  manage_folder sync_permissions "$folder_name" "$folder_rousers" "$folder_rogroups" "$folder_rwusers" "$folder_rwgroups"
  manage_folder sync_newfiles "$folder_name" "$folder_owner" "$folder_group"
}

exec 2>>$ERROR_FILE

# Cd to script directory
cd $SCRIPT_DIR
# Git pull
git_log=`git pull 2>&1`
if [[ $? -ne 0 ]]; then
  error "$git_log"
fi
echo "$git_log" | grep -q 'Already up-to-date'
# If there are changes set flag to sync users and groups
if [[ $? -ne 0 ]]; then
  log "Changes in config. Syncing users and groups."
  sync_users_groups=1
else
  log "No changes in config. Skipping sync of users and groups."
  sync_users_groups=0
fi

new_username=""
new_group_name=""
username=""
group_name=""
# Loop until end of file
while read line
do
  new_section=0
  # Skip comments and empty lines
  line=`trim "$line" | sed '/^\#/d'`
  if [ "$line" == "" ]; then
    continue;
  fi
  # echo XXXXX $line
  # Check if new user
  for s_type in user group folder
  do
    pattern="^\[$s_type\s*\([^][]*\)\]$"
    new_section_name=`expr match "$line" "$pattern"`
    new_section=$((1 - $?))
    if [[ $new_section -eq 1 ]]; then
      db "New section found in $line"
      section_type=$s_type
      break;
    fi
  done
  # Process the previous section when we reach the 
  # beginning of a new section
  if [[ $new_section -eq 1 ]]; then
    db "New section - $section_type"
    db "New section name - $new_section_name"
    # Sync the last section if the corresponding names are not empty i.e. if not first section
    if [[ "$context" == "user" && "$username" != "" && sync_users_groups -eq 1 ]]; then
      sync_user
    elif [[ "$context" == "group" && "$group_name" != "" && sync_users_groups -eq 1 ]]; then
      sync_group
    elif [[ "$context" == "folder" && "$folder_name" != "" ]]; then
      sync_folder
    fi
    # Update context to context of the current section
    context=$section_type
    if [[ "$context" == "user" ]]; then
      username="$new_section_name"
      db "$username user found"
      # Set default user values
      user_status="enabled"
    elif [[ "$context" == "group" ]]; then
      group_name="$new_section_name"
      db "$group_name group found"
      # Set default group values
      group_status="enabled"
    elif [[ "$context" == "folder" ]]; then
      folder_name="$new_section_name"
      folder_rousers=""
      folder_rogroups=""
      folder_rwusers=""
      folder_rwgroups=""
      db "$folder_name folder found"
    fi
    # Read the next line
    continue;
  fi 
  # Else process each line for the previous user/group
  # Read a parameter of the form
  # name = value
  # Read param as part of line before = and value as part of line after = 
  param=`echo $line | cut --delimiter="=" -f 1`
  value=`echo $line | cut --delimiter="=" -f 2`
  param=`trim "$param"`
  value=`trim "$value"`
  db :$param: and :$value:
  eval ${context}_${param}=\"${value}\"
done < "$SCRIPT_DIR/doc-store.conf"
# Handle the last user or group
if [[ $context == "user" && sync_users_groups -eq 1 ]]; then
  sync_user
elif [[ $context == "group" && sync_users_groups -eq 1 ]]; then
  sync_group
elif [[ $context == "folder" ]]; then
  sync_folder
fi

#Add log and error files to git and commit
git add error.log run.log > /dev/null 2>&1
git_log=`git commit -m "Log and errors from server" 2>&1`
if [[ $? -ne 0 ]]; then
  error "$git_log"
fi
git_log=`git push 2>&1`
if [[ $? -ne 0 ]]; then
  error "$git_log"
fi
exit

