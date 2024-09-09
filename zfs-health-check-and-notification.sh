#!/usr/bin/env bash

#### SET PATHS ####

# Get filePath to where this script is located.
thisScriptFile=$(readlink -f "${0}")
thisScriptPath=$(dirname "${thisScriptFile}")
parentDirPath=$(dirname "${thisScriptPath}")

# Set other paths.
notifyScript="${parentDirPath}/notification/discord-webhook.sh"

#### INITIALIZATION & PARAMETERS ####

# Get date.
currentDate=$(date +%s)

# Declare the array to store ZFS pools.
declare -a pools

# Initialize pool number.
poolNumber=0

# Initalize JSON report string.
poolDiscordJsonReport=""

# Define keyword signifying unhealthy condtion.
unhealthyConditions='(DEGRADED|FAULTED|OFFLINE|UNAVAIL|REMOVED|FAIL|DESTROYED|corrupt|cannot|unrecover)'

# Define max capacity (%).
maxCapacity=80

# Define scrup expiration time (days).
scrubExpirationDays=36


#### ZFS POOLS HEALT CHECK ####

# Populate the array with system ZFS pools.
while read line;
do
  pools+=($line)
done <<< "$(/sbin/zpool list | awk -F" " '{print $1}' | grep -v NAME)"

# Get total number of ZFS pools.
totalPools="${#pools[@]}"

# Check each pool.
for pool in "${pools[@]}"
do

  # Initial issues flag.
  poolIssues=0

  # Current pool name.
  poolName=${pool}

  # Increment pool number.
  poolNumber=$((poolNumber+1))


  #### GENERAL CONDITION #####

  # Set initial condition text.
  poolConditionSubText="No unhealthy states found from pool status."

  # Search for any term signifying an uhealthy condition.
  poolCondition=$(/sbin/zpool status ${pool} | egrep -i ${unhealthyConditions})

  # Set flag on any hits.
  if [ "${poolCondition}" ]; then
          poolIssues=1
          poolConditionSubText="There might be an issue with the pool health. Run "\`"zpool status ${pool}"\`" for details."
  fi

  # Get the overall pool state and set notfication text.
  poolOverallCondition=$(/sbin/zpool status ${pool} | grep state | awk '{print $2}')
  poolConditionText="${poolConditionSubText} Overall state is reporting as **${poolOverallCondition}** for this pool."


  #### CAPACITY #####

   # Set initial condition text.
  poolCapacitySubText="The pool spare capacity is within limits."

  # Get current capacity used.
  poolCapacity=$(/sbin/zpool list ${pool} -H -o capacity | cut -d'%' -f1)
  
  # Set flag if over max capacity.
  if [ $poolCapacity -ge $maxCapacity ]; then
       poolIssues=1
       poolCapacitySubText="The pool spare capacity is **low**. Run "\`"zpool list ${pool}"\`" for details."
  fi

  # Set notfication text.
  poolCapacityText="${poolCapacitySubText} The used capacity at current is **${poolCapacity}%** for this pool."


  #### ERRORS #####

  # Set initial condition text.
  poolErrorsSubText="No errors found in read, write or checksum fields."

  # Set no errors text.
  poolErrorStatus="No known data errors"

  # Search for error codes or text.
  poolErrors=$(/sbin/zpool status ${pool} | grep ONLINE | grep -v state | awk '{print $3 $4 $5}' | grep -v 000)
  poolErrorReport=$(/sbin/zpool status -v ${pool} | grep errors: | awk '{$1=""; print $0 }' | grep -v "${poolErrorStatus}")

  # Set flag if any errors found.
  if [ "${poolErrors}" ] || [ "${poolErrorReport}" ]; then
       poolIssues=1
       poolErrorsSubText="Errors were found in the read, write or checksum fields. Run "\`"zpool list -v ${pool}"\`" for details."
       poolErrorStatus=${poolErrorReport}
  fi

   # Set notfication text.
  poolErrorsText="${poolErrorsSubText} The pool status reports **${poolErrorStatus}**."


  #### SCRUB #####

  # Set initial condition text.
  poolScrupSubText="The pool scrub date has not yet been exeeded."

  # Get any special conditions.
  if [ $(/sbin/zpool status ${pool} | egrep -c "none requested") -ge 1 ]; then
      poolScrupWarningText="No status to report. A "\`"zpool scrub ${pool}"\`" command must be run before this script can monitor the scrub expiration time."

  fi
  if [ $(/sbin/zpool status ${pool} | egrep -c "scrub in progress|resilver") -ge 1 ]; then
      poolScrupWarningText="A pool scrub or resilver is currently in progress."

  fi

  # Check if any special condition.
  if [ "${poolScrupWarningText}" ]; then

    # Set notfication text.
    poolScrubText=${poolScrupWarningText}

  else

    # Get the last scrub date.
    poolScrubRawDate=$(/sbin/zpool status ${pool} | grep scrub | awk '{print $11" "$12" " $13" " $14" "$15}')
    poolScrubDate=$(date -d "$poolScrubRawDate" +%s)

    # Convert expiration to seconds.
    scrubExpirationSeconds=$(expr 26 \* 60 \* 60 \* ${scrubExpirationDays})

    # Check if next scrub date has expired.
    if [ $(($currentDate - $poolScrubDate)) -ge $scrubExpirationSeconds ]; then
        poolIssues=1
        poolScrupSubText="The pool scrub date is overdue. Check the scrub cron jobs in */etc/cron.d/zfsutils-linux* or run "\`"zpool scrub ${pool}"\`" to initialte a manual scrub."
    fi

    # Set notfication text.
    poolScrubText="${poolScrupSubText} Last scrub was performed on **${poolScrubRawDate}** for this pool."

  fi

  #### POOL JSON STRING ####

  # Set JSON notification color.
  if [ ${poolIssues} -eq 0 ]; then
       discordNotficationColor=7909721
       discordDescription="No issues found for this pool."
       discordMessageIcon="https://i.imgur.com/QqVe9k3.png"
  else
       discordNotficationColor=14495300
       discordDescription="There are issues detected for this pool. Actions required by @admin>"
       discordMessageIcon="https://i.imgur.com/lD8QUFd.png"
  fi

  # Build pool JSON string for Discord notification.
  discordEmbedsJson=''${discordEmbedsJson}'
                    {
                      "title": "**Health Summary**",
                      "author": {
                        "name": "Pool #'${poolNumber}' ('${poolName}')",
                        "icon_url": "'"${discordMessageIcon}"'"
                      },
                      "description":"'"${discordDescription}"'",
                      "color":"'"${discordNotficationColor}"'",
                      "fields": [
                      {
                        "name": "Condition",
                        "value":"'"${poolConditionText}"'"
                      },
                      {
                        "name": "Capacity",
                        "value": "'"${poolCapacityText}"'"
                      },
                      {
                        "name": "Errors",
                        "value": "'"${poolErrorsText}"'"
                      },
                      {
                        "name": "Scrub",
                        "value": "'"${poolScrubText}"'"
                      }]
                    },'

done

#### DISCORD NOTIFICATION ####

# Create content /description section
discordContentField="Report from ZFS health check script on **'$HOSTNAME'** server. The script checked **'${totalPools}'** pools.",                                    

# Pass data to Discord webhooks script for notification.
${notifyScript} -c "${discordContentField}" -e "${discordEmbedsJson}" -f "${diffReportFile}"