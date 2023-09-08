# ZFS Health Check Script

Bash script to check the health of the ZFS pools on a Linux server running OpenZFS and send a notification with a summary to a Discord server channel The script checks ZFS pools overall condition, capacity, errors and time since last scrub. If an issue is detected with a pool a role on the Discord channel is pinged.

## Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Script Details](#script-details)
  - [Initialization and Parameters](#initialization-and-parameters)
  - [ZFS Pools Health Check](#zfs-pools-health-check)
  - [Discord Notification](#discord-notification)
- [Health Checks](#health-checks)
  - [Condition](#condition)
  - [Capacity](#capacity)
  - [Errors](#errors)
  - [Scrub Expired](#scrub-expired)   
- [Discord Webhook Script](#discord-webhook-script)   

## Overview

This Bash script performs a health check on ZFS pools, identifying and reporting any potential issues with the pools' health. It provides detailed information about each pool's condition, capacity, errors, and scrub status. The script can send notifications to Discord with the health status of the monitored pools.

**Compatibility Note:** This script has been tested on **Ubuntu Server 22.04** and should work on other Linux operating systems running OpenZFS.

## Requirements

Before using this script, make sure you have the following requirements:

- OpenZFS
- Discord Channel (if you want to receive notifications)

## Script Details

### Initialization and Parameters

The script initializes necessary variables, sets paths, and defines parameters such as maximum capacity, scrub expiration time, and keywords signifying unhealthy conditions.

### ZFS Pools Health Check

The script performs a health check on each ZFS pool detected on the system. It evaluates the following aspects for each pool:

**General Condition**: Checks for any unhealthy states and overall pool state.
**Capacity**: Monitors pool capacity and warns if it exceeds a specified maximum.
**Errors**: Identifies errors in read, write, or checksum fields.
**Scrub**: Checks the last scrub date and notifies if it's overdue.

The script constructs a JSON report for each pool's health status and assembles a Discord notification based on the results.

### Discord Notification

If any issues are detected during the ZFS pool health check, the script sends a Discord notification with a detailed report for each pool. The notification includes information about the condition, capacity, errors, and scrub status.

## Health Checks

### Condition

Check if all zfs volumes are in good condition.
Looking for any keyword signifying a degraded or broken array.

### Capacity

Makes sure the pool capacity is below 80% for best performance. The
percentage depends on how large the volume is.

ZFS uses a copy-on-write scheme. The file system writes new data to sequential free blocks first and when the uberblock has been updated the new inode pointers become valid. This method is true only when the pool has enough free sequential blocks. If the pool is at capacity and space limited, ZFS will be have to randomly write blocks. This means ZFS can not create an optimal set of sequential writes and write performance is severely impacted.

### Errors

Check the columns for READ, WRITE and CKSUM (checksum) drive errors on all volumes and all drives using "zpool status". If any non-zero errors are reported an email will be sent out. You should then look to replace the faulty drive and run "zpool scrub" on the affected volume after resilvering.
 
### Scrub Expired

Check if all volumes have been scrubbed in at least the last 8 days. The general guide is to scrub volumes on desktop quality drives once a week and volumes on enterprise class drives once a month. You can always use cron to schedule "zpool scrub" in off hours. We scrub our volumes every Sunday morning for example.

Scrubbing traverses all the data in the pool once and verifies all blocks can be read. Scrubbing proceeds as fast as the devices allows, though the priority of any I/O remains below that of normal calls. This operation might negatively impact performance, but the file system will remain usable and responsive while scrubbing occurs. To initiate an explicit scrub, use the "zpool scrub" command.

The scrubExpire variable is in seconds. So for 8 days we calculate 8 days times 24 hours times 3600 seconds to equal 691200 seconds.

## Discord Webhook Script

To enable Discord notifications, you will need a separate `discord-webhook.sh` script for sending notifications. You can find and clone this script from another GitHub repository dedicated to Discord webhooks:

[GitHub Repository: discord-webhook-notification](https://github.com/norsemanGrey/discord-webhook-notification)

Make sure to configure and set up the `discord-webhook.sh` script correctly, and ensure it's available in your environment for the notifications to work.
