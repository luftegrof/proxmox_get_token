#!/bin/bash
#
# Copyright 2022, luftegrof at duck dot com
#
# Licensed under GPL Version 3
# See LICENSE file for info.
#
# This program will generate a Proxmox API token with the same privileges
# as your Proxmox user account.
#
# By default, it will set the token to expire in 15 minutes.

# Set to "true" to enable output of variables to the terminal.
debug="false"

# Parse the configuration file
config_file="./pm_get_token.conf"
source ${config_file}

echo -en "\n\n!!!NOTICE!!!\n"
echo -en "You must source this script with 'source ./pm_get_token.sh' or '. ./pm_get_token.sh' in order to properly set your PM_API_* environment variables.\n"
echo -en "!!!NOTICE!!!\n\n"

# Get a random ID to use as the token ID...
# The token ID must start with a letter.
tokenid_re='^[A-Za-z][A-Za-z0-9\.\-_]+'
random_id=""
until [[ "${random_id}" =~ ${tokenid_re} ]]; do
	random_id=$(cat /proc/sys/kernel/random/uuid)
	if [ "${debug}" == "true" ]; then
		echo -en "Random ID: ${random_id}\n"
	fi
done

# Prompt for the username, password, and realm.
# Perform very basic input validation.
echo -n "Proxmox Username: "
read username
if [ -n ${username} ]; then
	echo -n "Proxmox Password: "
	read -s password
	password_enc=$(php -r "echo urlencode(\"${password}\");")
	echo
	if [ -n "${password}" ]; then
		echo -n "Proxmox Realm (pve|pam) [pve]: "
		read realm
		realm=${realm:-pve}
		case "${realm}" in
			pve|pam)
			;;
			*)
				echo -en "Realm must be 'pve' or 'pam'.\n"
				return 1
			;;
		esac
		if [ -n "${realm}" ]; then
			echo -n "Token Expiration (in seconds) [900]: "
			read seconds
			seconds=${seconds:-900}
			re='^[0-9]+$'
			if [[ ${seconds} =~ ${re} ]]; then
				expire=$(date -d "+${seconds} seconds" +%s)
				echo -en "Token Expiration: $(date -d @${expire})\n"
			else
				echo -en "Expiration must be a number of seconds.\n"
				return 1
			fi
		fi
	else
		echo -en "Password may not be blank.\n"
		return 1
	fi
else
	echo -en "Username may not be blank.\n"
	return 1
fi

# Initialize the Proxmox connection:
# * Get an authentication cookie
# * Get a CSRF token
init=$(curl "https://${proxmox_server}:${proxmox_port}/api2/extjs/access/ticket" \
  --data-raw "username=${username}&password=${password_enc}&realm=${realm}" \
  --compressed \
  --silent \
  --insecure)

if [ "${debug}" == "true" ]; then
	echo -en "Authentication Result: ${init}\n"
fi

success=$(echo ${init} | jq -r '.success')

if [ ${success} == 1 ]; then
	proxmox_csrf_token=$(echo ${init} | jq -r '.data.CSRFPreventionToken')
	proxmox_csrf_token_enc=$(php -r "echo urlencode(\"${proxmox_csrf_token}\");")
	proxmox_authn_cookie=$(echo ${init} | jq -r '.data.ticket')
	proxmox_authn_cookie_enc=$(php -r "echo urlencode(\"${proxmox_authn_cookie}\");")
	proxmox_username=$(echo ${init} | jq -r '.data.username')
	if [ "${debug}" == "true" ]; then
		echo -en "proxmox_csrf_token=${proxmox_csrf_token}\n"
		echo -en "proxmox_csrf_token_enc=${proxmox_csrf_token}\n"
		echo -en "proxmox_authn_cookie=${proxmox_authn_cookie}\n"
		echo -en "proxmox_authn_cookie_enc=${proxmox_authn_cookie}\n"
		echo -en "proxmox_username=${proxmox_username}\n"
	fi
else
	echo -en "Proxmox API initialization was not successful.\n"
	echo -en "  Double-check your username, password, and realm.\n"
	return 1
fi

# Initialize the Proxmox API Token:
apitoken=$(curl https://${proxmox_server}:${proxmox_port}/api2/json/access/users/${proxmox_username}/token/${random_id} \
  -X 'POST' \
  -H "CSRFPreventionToken: ${proxmox_csrf_token}" \
  -H "Cookie: PVEAuthCookie=${proxmox_authn_cookie_enc}" \
  --data-raw "expire=${expire}" \
  --data-raw 'privsep=0' \
  --insecure \
  --silent)

token_id=$(echo ${apitoken} | jq -r ".data.\"full-tokenid\"")
secret=$(echo ${apitoken} | jq -r '.data.value')

if [ "${debug}" == "true" ]; then
	echo -en "Server Response: ${apitoken}\n"
	echo -en "API Token ID: ${token_id}\n"
	echo -en "API Token Secret: ${secret}\n"
fi

# Set up environment variables for terraform, packer, and other automation tools...
if [ -n "${token_id}" ] && [ "${token_id}" != "null" ]; then
	echo -en "Setting PM_API_TOKEN_ID environment variable...\n"
	export PM_API_TOKEN_ID="${token_id}"
	echo -en "Setting PM_API_TOKEN_SECRET environment variable...\n"
	export PM_API_TOKEN_SECRET="${secret}"
else
	echo -en "An error may have occurred.\n"
	echo -en "Server Response: ${apitoken}\n"
	return 1
fi
