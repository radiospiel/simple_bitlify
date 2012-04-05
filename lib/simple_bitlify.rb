require "cgi"
require "json"
require "simple_cache"

# A basic, caching, Bitlifier
module Bitly
  extend self

  TIME_TO_LIVE         = 365 * 24 * 3600   # 1 year
  TIME_TO_LIVE_FAILURE = 3600              # 1 hour

  attr :cache, true
  attr :config, true
  
  def cache
    @cache ||= SimpleCache.new("simple_bitlify")
  end

  def config
    @config ||= {
      "user" => "bitlyapidemo",
      "key"  => "R_0da49e0a9118ff35f52f629d2d71bf07"
    }
  end
  # 
  # self.config = {
  #   "user" => "radiospiel",
  #    "key" => "R_b01d6497ec9a1b2fff03fe942f7c3e1c"
  # }
     
  def self.url_base
    @url_base ||= begin
      user, key = (self.config || {}).values_at "user", "key"

      raise "Missing or invalid bitly configuration: #{config.inspect}" unless user && key
      "https://api-ssl.bitly.com/v3/shorten?login=#{user}&apiKey=#{key}"
    end
  end

  def self.shorten(url)
    return url if !url || url.index("/bit.ly/")

    cache.fetch(url) || begin
      bitly_url = "#{self.url_base}&longUrl=#{CGI.escape(url)}"
      parsed = JSON.parse get(bitly_url) 

      shortened = parsed["data"]["url"] if parsed["status_code"] == 200
      cache.store(url, shortened || url, shortened ? TIME_TO_LIVE : TIME_TO_LIVE_FAILURE)
    end
  end

  private
  
  def get(uri_str, limit = 10)
    raise 'too many redirections' if limit == 0

    uri = URI.parse(uri_str)
    
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == "https"
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)

    case response
    when Net::HTTPSuccess then
      response.body
    when Net::HTTPRedirection then
      location = response['location']
      App.logger.debug "redirected to #{location}"
      get(location, limit - 1)
    else  
      response.value
    end
  end
end
