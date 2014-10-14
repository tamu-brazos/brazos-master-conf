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
if versioncmp($::puppetversion,'3.6.1') >= 0 {
  $allow_virtual_packages = hiera('allow_virtual_packages',false)

  Package {
    allow_virtual => $allow_virtual_packages,
  }
}

$dhcp_pools = hiera('dhcp_pools', {})
create_resources('dhcp::pool', $dhcp_pools)

$dns_zones = hiera('dns_zones', {})
create_resources('dns::zone', $dns_zones)

$shellvars = hiera('shellvars', {})
create_resources('shellvar', $shellvars)

Class['mcollective::server::install']~>
Class['mcollective::server::service']

#$classes = hiera_array('classes', [])
#if member($classes, 'slurm::node') {
#  Class['sssd::service']->
#  Class['slurm::user']
#}
