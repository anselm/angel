
require 'net/http'
require 'uri'
require 'open-uri'
require 'hpricot'
require 'json'

class Dynamapper

  def self.geolocate(text)
    return 0,0,0 if !text || text.length < 3 
    name = SETTINGS[:site_metacarta_userid]
    password = SETTINGS[:site_metacarta_pass]
    key = SETTINGS[:site_metacarta_key]
    lat,lon,rad = self.geolocate_via_metacarta(text,name,password,key)
    ActionController::Base.logger.info "geolocator at work: #{text} set to #{lat} #{lon} #{rad}"
    return lat,lon,rad
  end

  # return latitude,longitude,kilometers or return a point off the coast of africa that means nil
  def self.geolocate_via_metacarta(text,name,password,key)
    return 0,0,0 if !text || text.length < 3 
    text = URI.escape(text, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
    host = "ondemand.metacarta.com"
    path = "/webservices/GeoTagger/JSON/basic?version=1.0.0&doc=#{text}"
    begin
      # TODO please put a time out check on this.
      req = Net::HTTP::Get.new(path)
      req.basic_auth name,password
      http = Net::HTTP.start(host)
      response = http.request(req)
      case response
      when Net::HTTPSuccess then
        ActionController::Base.logger.info "dynamapper geolocation got #{response.body.to_s}"
        data = JSON.parse(response.body.to_s)
        lat = data["Locations"][0]["Centroid"]["Latitude"].to_f
        lon = data["Locations"][0]["Centroid"]["Longitude"].to_f
        return lat,lon,25
      end
    rescue Timeout::Error
      ActionController::Base.logger.info "dynamapper geolocation failure due to timeout"
    rescue
      ActionController::Base.logger.info "dynamapper geolocation failure no reason"
    end
    return 0,0,0
  end

  # return latitude,longitude,kilometers or return a point off the coast of africa that means nil
  def self.geolocate_via_placemaker(apikey,text)
    return 0,0,0 if !text || text.length < 3 
    url = URI.parse('http://wherein.yahooapis.com/v1/document')
    args = {'documentContent'=> text,
            'documentType'=>'text/plain',
            'appid'=>apikey
           }
	begin
      # TODO please put a time out check on this.
      response = Net::HTTP.post_form(url,args)
  	  case response
  	  when Net::HTTPSuccess then
        doc = Hpricot::XML(response.body)
        (doc/:centroid).each do |node|
          lat = (node/:latitude).innerHTML.to_f
	      lon = (node/:longitude).innerHTML.to_f
	      return lat,lon,25
	    end
	  end
	end
    return 0,0,0
  end

end

