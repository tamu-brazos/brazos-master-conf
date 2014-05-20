#!/usr/bin/env ruby

# If copying this template by hand, replace the settings below including the angle brackets
SETTINGS = {
  :url          => "https://foreman.brazos.tamu.edu",  # e.g. https://foreman.example.com
  :puppetdir    => "/var/lib/puppet",  # e.g. /var/lib/puppet
  :facts        => true,          # true/false to upload facts
  :timeout      => 10,
  # if CA is specified, remote Foreman host will be verified
  :ssl_ca       => "/var/lib/puppet/ssl/certs/ca.pem",      # e.g. /var/lib/puppet/ssl/certs/ca.pem
}

def url
  SETTINGS[:url] || raise("Must provide URL - please edit file")
end

def puppetdir
  SETTINGS[:puppetdir] || raise("Must provide puppet base directory - please edit file")
end

def stat_file(certname)
  FileUtils.mkdir_p "#{puppetdir}/yaml/foreman/"
  "#{puppetdir}/yaml/foreman/#{certname}.yaml"
end

def tsecs
  SETTINGS[:timeout] || 3
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
require 'yaml'
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
  # Copy of facter-2.x method for pulling in Puppet facts
  require 'facter'
  require 'puppet'
  Puppet.parse_config

  unless $LOAD_PATH.include?(Puppet[:libdir])
    $LOAD_PATH << Puppet[:libdir]
  end

  # Pull facts from Facter
  puppet_facts = Facter.to_hash
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
  begin
    certname = ARGV[0] || raise("Must provide certname as an argument")
    # send facts to Foreman - enable 'facts' setting to activate
    # if you use this option below, make sure that you don't send facts to foreman via the rake task or push facts alternatives.
    #
    # ssl_cert and key are required if require_ssl_puppetmasters is enabled in Foreman
    SETTINGS[:ssl_cert ] = "/var/lib/puppet/ssl/certs/#{certname}.pem",    # e.g. /var/lib/puppet/ssl/certs/FQDN.pem
    SETTINGS[:ssl_key] = "/var/lib/puppet/ssl/private_keys/#{certname}.pem"      # e.g. /var/lib/puppet/ssl/private_keys/FQDN.pem

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
