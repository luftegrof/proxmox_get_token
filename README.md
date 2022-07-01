# proxmox_get_token (pm_get_token)
This script will create a new Proxmox User API Token for use with automation tools and API clients.
It will also set up environment variables that Proxmox provisioners, providers, and modules of Terraform, Packer, and Ansible will use, by default, to determine your Proxmox API URL, Token ID, and Token Secret.

By default, the token will timeout in 900 seconds (15 minutes).  The new token will be granted the same permissions as the provided user account.

Adding the following alias to your `~/.bashrc` will allow you to run `pm_get_token 192.0.2.41` from any path.
This may be useful for, say, running `pm_get_token` from your terraform directory structure...
`alias pm_get_token="source $HOME/git/luftegrof/proxmox_get_token/pm_get_token.sh"`

