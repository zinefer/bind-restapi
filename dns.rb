#!/usr/bin/env ruby

require 'rubygems'
require 'sinatra'
require 'json'
require 'ipaddr'
require 'socket'

# curl -X POST -H 'Content-Type: application/json' -H 'X-Api-Key: secret' -d '{ "hostname": "host12.apple.com", "ip": "1.1.1.12" }' http://localhost:4567/dns
# curl -X DELETE -H 'Content-Type: application/json' -H 'X-Api-Key: secret' -d '{ "hostname": "host12.apple.com", "ip": "1.1.1.12" }' http://localhost:4567/dns

dns_params = {
  :server => 'localhost',
  :rndc_key => 'rndc-key',
  :rndc_secret => 'cf5hrPFanCzrsr7K6TbwBA==',
  :ttl => '300',
  :protected => false
}

set :bind, '0.0.0.0'
set :port, 80

# Reverse the IP address for the in-addr.arpa zone
def reverse_ip(ipaddress)
  reverse_ip = IPAddr.new ipaddress
  reverse_ip.reverse
end

# Authenticate all requests with an API key
before do
  # X-Api-Key
    return unless dns_params[:protected]
    error 401 unless env['HTTP_X_API_KEY'] =~ /secret/
end

post '/dns' do
  request_params = JSON.parse(request.body.read)
  reverse_zone = reverse_ip(request_params["ip"])
  ttl = if request_params["ttl"].nil? then dns_params[:ttl] else request_params["ttl"] end

  # Add record to forward and reverse zones, via TCP
  IO.popen("nsupdate -y #{dns_params[:rndc_key]}:#{dns_params[:rndc_secret]} -v", 'r+') do |f|
    f << <<-EOF
      server #{dns_params[:server]}
      update add #{request_params["hostname"]} #{ttl} A #{request_params["ip"]}
      send
      update add #{reverse_zone} #{ttl} PTR #{request_params["hostname"]}
      send
    EOF
    f.close_write
  end
  error 500 unless $? == 0
  status 201
end

delete '/dns' do
  request_params = JSON.parse(request.body.read)
  ip = request_params["ip"] || IPSocket::getaddress(request_params["hostname"])
  reverse_zone = reverse_ip(ip)

  # Remove record from forward and reverse zones, via TCP
  IO.popen("nsupdate -y #{dns_params[:rndc_key]}:#{dns_params[:rndc_secret]} -v", 'r+') do |f|
    f << <<-EOF
      server #{dns_params[:server]}
      update delete #{request_params["hostname"]} A
      send
      update delete #{reverse_zone} PTR
      send
    EOF
    f.close_write
  end
  error 500 unless $? == 0
end
