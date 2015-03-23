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

Mailalias {
  notify  => Exec['site newaliases']
}

### Global resources ###

exec { 'site newaliases':
  command     => 'newaliases',
  path        => ['/usr/bin','/usr/sbin','/bin','/sbin'],
  refreshonly => true,
}

### create_resources ###

$apache_vhosts = hiera('apache_vhosts', {})
create_resources('apache::vhost', $apache_vhosts)

$brazos_firewall_ssh_reject_out = hiera('brazos_firewall_ssh_reject_out', {})
create_resources('brazos::firewall::ssh_reject_out', $brazos_firewall_ssh_reject_out)

$dhcp_hosts = hiera('dhcp_hosts', {})
create_resources('dhcp::host', $dhcp_hosts)

$dhcp_pools = hiera('dhcp_pools', {})
create_resources('dhcp::pool', $dhcp_pools)

$dns_zones = hiera('dns_zones', {})
create_resources('dns::zone', $dns_zones)

$file_lines = hiera('file_lines', {})
create_resources('file_line', $file_lines)

$firewall_rules = hiera_hash('firewall_rules', {})
create_resources('firewall', $firewall_rules)

$ini_settings = hiera_hash('ini_settings', {})
create_resources('ini_setting', $ini_settings)

$logstash_configfiles = hiera('logstash_configfiles', {})
create_resources('logstash::configfile', $logstash_configfiles)

$mailaliases = hiera('mailaliases', {})
create_resources('mailalias', $mailaliases)

$network_aliases = hiera('network_aliases', {})
create_resources('network::alias', $network_aliases)

$postfix_files = hiera('postfix_files', {})
create_resources('postfix::file', $postfix_files)

$shellvars = hiera('shellvars', {})
create_resources('shellvar', $shellvars)

$slurm_qoses = hiera('slurm_qoses', {})
create_resources('slurm_qos', $slurm_qoses)

### Resource ordering ###

Class['mcollective::server::install']~>
Class['mcollective::server::service']
