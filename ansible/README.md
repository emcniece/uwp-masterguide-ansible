# Ubuntu/WordPress Master Guide: Ansible Playbook

An automated build of the tutorial series by Ashley Rich: [Hosting WordPress Yourself](https://deliciousbrains.com/hosting-wordpress-setup-secure-virtual-server/).

## How To Use

### Server Setup

This will install the basic packages needed for your system:

    ansible-playbook newserver.yml

If a particular section of this setup fails, you can re-run individual roles by specifying a tag (denoted in `newserver.yml`):

    ansible-playbook newserver.yml --tags="common"

Available tags:

- nginx
- php-fpm
- mysql
- newrelic
- redis
- wp-cli
- a5hley-tasks

Ansible will handle itself nicely on re-run so you don't have to worry about over-installing a package. If you want to skip a role, use skip-tags:

    ansible-playbook newserver.yml --skip-tags="newrelic"

### Domain Setup

This will set up a new domain on your server:

    ansible-playbook newsite.yml

Roles denoted with `site-*` are executed under this task set:

- site-common
- site-mysql
- site-nginx
- site-phpfpm
- site-wp