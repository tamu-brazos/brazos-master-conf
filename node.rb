#!/usr/bin/env ruby

# Script usually acts as an ENC for a single host, with the certname supplied as argument
#   if 'facts' is true, the YAML facts for the host are uploaded
#   ENC output is printed and cached
#
# If --push-facts is given as the only arg, it uploads facts for all hosts and then exits.
# Useful in scenarios where the ENC isn't used.

require 'yaml'

$settings_file = "/etc/puppet/foreman.yaml"

SETTINGS = YAML.load_file($settings_file)

def url
  SETTINGS[:url] || raise("Must provide URL in #{$settings_file}")
end

def puppetdir
  SETTINGS[:puppetdir] || raise("Must provide puppet base directory in #{$settings_file}")
end

def puppetuser
  SETTINGS[:puppetuser] || 'puppet'
end

def stat_file(certname)
  FileUtils.mkdir_p "#{puppetdir}/yaml/foreman/"
  "#{puppetdir}/yaml/foreman/#{certname}.yaml"
end

def tsecs
  SETTINGS[:timeout] || 10
end

class Http_Fact_Requests
  include Enumerable

  def initialize
    @results_array = []
  end

  def <<(val)
    @results_array << val
  end

  def each(&block)
    @results_array.each(&block)
  end

  def pop
    @results_array.pop
  end
end

require 'etc'
require 'net/http'
require 'net/https'
require 'fileutils'
require 'timeout'
begin
  require 'json'
rescue LoadError
  # Debian packaging guidelines state to avoid needing rubygems, so
  # we only try to load it if the first require fails (for RPMs)
  begin
    require 'rubygems' rescue nil
    require 'json'
  rescue LoadError => e
    puts "You need the `json` gem to use the Foreman ENC script"
    # code 1 is already used below
    exit 2
  end
end

def build_body(certname)
  require 'facter'
  require 'facter/application'
  Facter::Application.load_puppet
  # Pull facts from Facter
  facts        = Facter.to_hash
  puppet_facts = facts
  hostname     = puppet_facts['fqdn'] || certname
  {'facts' => puppet_facts, 'name' => hostname, 'certname' => certname}
end

def initialize_http(uri)
  res              = Net::HTTP.new(uri.host, uri.port)
  res.use_ssl      = uri.scheme == 'https'
  if res.use_ssl?
    if SETTINGS[:ssl_ca] && !SETTINGS[:ssl_ca].empty?
      res.ca_file = SETTINGS[:ssl_ca]
      res.verify_mode = OpenSSL::SSL::VERIFY_PEER
    else
      res.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    if SETTINGS[:ssl_cert] && !SETTINGS[:ssl_cert].empty? && SETTINGS[:ssl_key] && !SETTINGS[:ssl_key].empty?
      res.cert = OpenSSL::X509::Certificate.new(File.read(SETTINGS[:ssl_cert]))
      res.key  = OpenSSL::PKey::RSA.new(File.read(SETTINGS[:ssl_key]), nil)
    end
  end
  res
end

def generate_fact_request(certname)
  begin
    uri = URI.parse("#{url}/api/hosts/facts")
    req = Net::HTTP::Post.new(uri.request_uri)
    req.add_field('Accept', 'application/json,version=2' )
    req.content_type = 'application/json'
    req.body         = build_body(certname).to_json
    req
  rescue => e
    raise "Could not generate facts for Foreman: #{e}"
  end
end

def cache(certname, result)
  File.open(stat_file(certname), 'w') {|f| f.write(result) }
end

def read_cache(certname)
  File.read(stat_file(certname))
rescue => e
  raise "Unable to read from Cache file: #{e}"
end

def enc(certname)
  foreman_url      = "#{url}/node/#{certname}?format=yml"
  uri              = URI.parse(foreman_url)
  req              = Net::HTTP::Get.new(uri.request_uri)
  http             = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl     = uri.scheme == 'https'
  if http.use_ssl?
    if SETTINGS[:ssl_ca] && !SETTINGS[:ssl_ca].empty?
      http.ca_file = SETTINGS[:ssl_ca]
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    else
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    if SETTINGS[:ssl_cert] && !SETTINGS[:ssl_cert].empty? && SETTINGS[:ssl_key] && !SETTINGS[:ssl_key].empty?
      http.cert = OpenSSL::X509::Certificate.new(File.read(SETTINGS[:ssl_cert]))
      http.key  = OpenSSL::PKey::RSA.new(File.read(SETTINGS[:ssl_key]), nil)
    end
  end
  res = http.start { |http| http.request(req) }

  raise "Error retrieving node #{certname}: #{res.class}\nCheck Foreman's /var/log/foreman/production.log for more information." unless res.code == "200"
  res.body
end

def upload_facts(certname, req)
  return nil if req.nil?
  uri = URI.parse("#{url}/api/hosts/facts")
  begin
    res = initialize_http(uri)
    res.start { |http| http.request(req) }
    cache("#{certname}-push-facts", "Facts from this host were last pushed to #{uri} at #{Time.now}\n")
  rescue => e
    raise "Could not send facts to Foreman: #{e}"
  end
end

# Actual code starts here

if __FILE__ == $0 then
=begin
  # Setuid to puppet user if we can
  begin
    Process::GID.change_privilege(Etc.getgrnam(puppetuser).gid) unless Etc.getpwuid.name == puppetuser
    Process::UID.change_privilege(Etc.getpwnam(puppetuser).uid) unless Etc.getpwuid.name == puppetuser
    # Facter (in thread_count) tries to read from $HOME, which is still /root after the UID change
    ENV['HOME'] = Etc.getpwnam(puppetuser).dir
  rescue
    $stderr.puts "cannot switch to user #{puppetuser}, continuing as '#{Etc.getpwuid.name}'"
  end
=end

  begin
    certname = ARGV[0] || raise("Must provide certname as an argument")
    SETTINGS[:ssl_cert] = "/var/lib/puppet/ssl/certs/#{certname}.pem"
    SETTINGS[:ssl_key] = "/var/lib/puppet/ssl/private_keys/#{certname}.pem"
    # send facts to Foreman - enable 'facts' setting to activate
    # if you use this option below, make sure that you don't send facts to foreman via the rake task or push facts alternatives.
    #
    if SETTINGS[:facts]
      req = generate_fact_request certname
      upload_facts(certname, req)
    end
    #
    # query External node
    begin
      result = ""
      timeout(tsecs) do
        result = enc(certname)
        cache(certname, result)
      end
    rescue TimeoutError, SocketError, Errno::EHOSTUNREACH, Errno::ECONNREFUSED
      # Read from cache, we got some sort of an error.
      result = read_cache(certname)
    end

    puts result
  rescue => e
    warn e
    exit 1
  end
end
