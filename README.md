# proxmox_get_token (pm_get_token)

## Proxmox API Tokens
This script will create a new Proxmox User API Token for use with automation tools and API clients.  

A randomly generated UUID is specified as the Token ID.  Proxmox issues a randomly generated UUID as the token secret.

##### Example Proxmox API Token ID and Token Secret pair:
```
Token ID: username@pve!a04c6fbc-7e0b-458c-864e-e2fb0d76a450
Token Secret: 7439120c-2e2a-417b-a159-871361aca3fb
```

## Setup
Adding the following alias to your `~/.bashrc` will allow you to simply run `pm_get_token 192.0.2.41` from any path.

`alias pm_get_token="source $HOME/git/luftegrof/proxmox_get_token/pm_get_token.sh"`

This may be useful for example, to run `pm_get_token` from deep within your terraform directory structure.

## Defaults
* Timeout: 900 seconds (15 minutes).  You will be prompted to specify the timeout value or accept the default.
* The new token will be granted the same permissions as the provided user account.
* It is technically possible to create tokens that have a reduced set of privileges, but this version of `pm_get_token` is not capable of that at this time.

## Environment Variables
After obtaining a new API token from Proxmox, environment variables are set to help various automation tools determine your Proxmox API URL, Token ID, and Token Secret.

| Variable Name | Contents | Used By |
| --- | --- | --- |
| PM_API_URL | API URL | Telmate/Proxmox Terraform Provider |
| PM_API_TOKEN_ID | API Token ID | Telmate/Proxmox Terraform Provider |
| PM_API_TOKEN_SECRET | API Token Secret | Telmate/Proxmox Terraform Provider |
| TF_VAR_PM_API_URL | API URL | Terraform Variables from Environment Variables for use by Terraform Provisioners |
| TF_VAR_PM_TOKEN_ID | API Token ID | Terraform Variables from Environment Variables for use by Terraform Provisioners |
| TF_VAR_PM_TOKEN_SECRET | API Token Secret | Terraform Variables from Environment Variables for use by Terraform Provisioners |
| PROXMOX_URL | API URL | Various Proxmox modules for Ansible |
| PROXMOX_USER | API Token ID | Various Ansible Modules |
| PROXMOX_USERNAME | API Token ID | Various Ansible Modules |
| PROXMOX_TOKEN_ID | API Token ID | Various Ansible Modules |
| PROXMOX_TOKEN | API Token Secret | Various Ansible Modules |
| PROXMOX_TOKEN_SECRET | API Token Secret | Various Ansible Modules |
