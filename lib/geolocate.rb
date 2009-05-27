
require 'net/http'
require 'uri'
require 'open-uri'
require 'hpricot'
require 'json'


class Geolocate

  def self.geolocate_via_metacarta(text,name,password,key)
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
        data = JSON.parse(response.body.to_s)
        lat = data["Locations"][0]["Centroid"]["Latitude"]
        lon = data["Locations"][0]["Centroid"]["Longitude"]
        return lat,lon
      end
    rescue Timeout::Error
    rescue
    end
    return 0,0
  end

  def self.geolocate_via_placemaker(apikey,text)
puts "and geolocating #{text}"
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
          lat = (node/:latitude).innerHTML
	      lon = (node/:longitude).innerHTML
	      return lat,lon
	    end
	  end
	end
    return 0,0
  end

end

