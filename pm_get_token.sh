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
debug=0

usage() {
	echo -en "Usage:  \n\t\tsource ./pm_get_token.sh <proxmox_server> [<proxmox_port>]\n"
	echo -en "\tE.g. \n\t\tsource ./pm_get_token.sh 192.0.2.1 8006\n\n"
	if [[ "${0}" = "${BASH_SOURCE}" ]]; then
		echo -en "\n\n!!!NOTICE!!!\n"
		echo -en "You must source this script in order to properly set the required environment variables.\n"
		echo -en "!!!NOTICE!!!\n\n"
		exit 1
	fi
}

# Ensure that this script is being sourced, not just executed.
if [[ "${0}" = "${BASH_SOURCE}" ]]; then
	usage
	return 1
fi

# Environment Variables to Output:
api_url_env_vars="PM_API_URL TF_VAR_PM_API_URL PROXMOX_URL"
token_id_env_vars="PM_API_TOKEN_ID TF_VAR_PM_API_TOKEN_ID PROXMOX_USERNAME PROXMOX_USER PROXMOX_TOKEN_ID"
token_secret_env_vars="PM_API_TOKEN_SECRET TF_VAR_PM_API_TOKEN_SECRET PROXMOX_TOKEN_SECRET PROXMOX_TOKEN"

server_re='^[0-9A-Za-z\.\-]+$'
address_re='^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
number_re='^[0-9]+$'
if [ -n "${1}" ]; then
	if [[ "${1}" =~ ${server_re} ]] || [[ "${1}" =~ ${address_re} ]]; then
		proxmox_server="${1}"
	else
		echo -en "Server must be a valid name or IPv4 address.\n"
		usage
		return 1
	fi
else
	echo -en "Server must be a valid name or IPv4 address.\n"
	usage
	return 1
fi
if [[ -z ${2} ]] || ( [[ "${2}" =~ ${number_re} ]] && [[ ${2} -ge 1 ]] && [[ ${2} -le 65535 ]] ); then
	proxmox_port="${2:-8006}"
else
	echo -en "Port must be a number between 1 and 65535.\n"
	usage
	return 1
fi

# Get a random ID to use as the token ID...
# The token ID must start with a letter.
tokenid_re='^[A-Za-z][A-Za-z0-9\.\-_]+'
random_id=""
until [[ "${random_id}" =~ ${tokenid_re} ]]; do
	random_id=$(cat /proc/sys/kernel/random/uuid)
	if [ ${debug} -eq 1 ]; then
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
	password_enc=$(jq -j -R -r @uri <<<${password})
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

if [ ${debug} -eq 1 ]; then
	echo -en "Authentication Result: ${init}\n"
fi

success=$(jq -r '.success' <<<${init})

if [ ${success} == 1 ]; then
	proxmox_csrf_token=$(jq -r '.data.CSRFPreventionToken' <<<${init})
	proxmox_csrf_token_enc=$(jq -j -R -r @uri <<<${proxmox_csrf_token})
	proxmox_authn_cookie=$(jq -r '.data.ticket' <<<${init})
	proxmox_authn_cookie_enc=$(jq -j -R -r @uri <<<${proxmox_authn_cookie})
	proxmox_username=$(jq -r '.data.username' <<<${init})
	if [ ${debug} -eq 1 ]; then
		echo -en "proxmox_csrf_token=${proxmox_csrf_token}\n"
		echo -en "proxmox_csrf_token_enc=${proxmox_csrf_token_enc}\n"
		echo -en "proxmox_authn_cookie=${proxmox_authn_cookie}\n"
		echo -en "proxmox_authn_cookie_enc=${proxmox_authn_cookie_enc}\n"
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

token_id=$(jq -r ".data.\"full-tokenid\"" <<<${apitoken})
secret=$(jq -r '.data.value' <<<${apitoken})

if [ ${debug} -eq 1 ]; then
	echo -en "Server Response: ${apitoken}\n"
	echo -en "API Token ID: ${token_id}\n"
	echo -en "API Token Secret: ${secret}\n"
fi

# Set up environment variables for terraform, packer, and other automation tools...
if [ -n "${token_id}" ] && [ "${token_id}" != "null" ]; then
	for api_url_env_var in ${api_url_env_vars}; do
		export ${api_url_env_var}="https://${proxmox_server}:${proxmox_port}/api2/json"
		if  [ ${debug} -eq 1 ]; then
			printf "%s=%s\n" ${api_url_env_var} $(printenv ${api_url_env_var})
		else
			echo -en "Setting ${api_url_env_var} environment variable...\n"
		fi
	done
	for token_id_env_var in ${token_id_env_vars}; do
		export ${token_id_env_var}="${token_id}"
		if  [ ${debug} -eq 1 ]; then
			printf "%s=%s\n" ${token_id_env_var} $(printenv ${token_id_env_var})
		else
			echo -en "Setting ${token_id_env_var} environment variable...\n"
		fi
	done
	for token_secret_env_var in ${token_secret_env_vars}; do
		export ${token_secret_env_var}="${secret}"
		if  [ ${debug} -eq 1 ]; then
			printf "%s=%s\n" ${token_secret_env_var} $(printenv ${token_secret_env_var})
		else
			echo -en "Setting ${token_secret_env_var} environment variable...\n"
		fi
	done
else
	echo -en "An error may have occurred.\n"
	echo -en "Server Response: ${apitoken}\n"
	return 1
fi

# While we're at it, let's clean up any expired tokens...
token_list=$(curl https://${proxmox_server}:${proxmox_port}/api2/json/access/users/${proxmox_username}/token \
	-X 'GET' \
	-H "Authorization: PVEAPIToken=${token_id}=${secret}" \
	--insecure \
	--silent)
expired_tokens=$(jq -r '.data[] | select(.expire < now)' <<<"${token_list}")
current_tokens=$(jq -r '.data[] | select(.expire > now)' <<<"${token_list}")
for expired_token in $(jq -r '.tokenid' <<<"${expired_tokens}"); do
	result=$(curl https://${proxmox_server}:${proxmox_port}/api2/json/access/users/${proxmox_username}/token/${expired_token} \
	-X 'DELETE' \
	-H "Authorization: PVEAPIToken=${token_id}=${secret}" \
	--insecure \
	--silent)
	if [ "${result}" != '{"data":null}' ]; then
		echo -en "An error may have occurred.\n"
		echo -en "Server Response: ${result}\n"
		return 1
	fi
done
if [ -n "${expired_tokens}" ]; then
	printf "\n\nExpired Tokens Deleted for %s on %s:\n\n" "${proxmox_username}" "${proxmox_server}"
	printf "Token ID: %s\tExpired: %s\n" $(jq -r '. | .tokenid, (.expire|todate)' <<<"${expired_tokens}")
fi
if [ -n "${current_tokens}" ]; then
	 printf "\n\nUnexpired Tokens for %s on %s:\n\n" "${proxmox_username}" "${proxmox_server}"
	 printf "Token ID: %s\tExpires: %s\n" $(jq -r '. | .tokenid, (.expire|todate)' <<<"${current_tokens}")
fi
