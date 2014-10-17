# site.pp

hiera_include('classes')

# Global modules
Firewall {
  before  => Class['iptables::post'],
  require => Class['iptables::pre'],
}

filebucket { 'main':
  server  => "puppetmaster01.brazos.tamu.edu",
  path    => false,
}

# Global defaults
File { backup => 'main' }

Exec { path => "/sbin:/bin:/usr/sbin:/usr/bin" }

#Yumrepo <| name != 'zfs' or name != 'zfs-source' |> -> Package <| title != 'yum-plugin-priorities' |>
Yumrepo <| |> -> Package <| |>

# Fix deprecation warnings for Puppet >= 3.6.1
Package {
  allow_virtual => true,
}

### create_resources ###

$dhcp_pools = hiera('dhcp_pools', {})
create_resources('dhcp::pool', $dhcp_pools)

$dns_zones = hiera('dns_zones', {})
create_resources('dns::zone', $dns_zones)

$shellvars = hiera('shellvars', {})
create_resources('shellvar', $shellvars)

$firewall_rules = hiera('firewall_rules', {})
create_resources('firewall', $firewall_rules)

$logstash_configfiles = hiera('logstash_configfiles', {})
create_resources('logstash::configfile', $logstash_configfiles)

$postfix_files = hiera('postfix_files', {})
create_resources('postfix::file', $postfix_files)

### Resource ordering ###

Class['mcollective::server::install']~>
Class['mcollective::server::service']
