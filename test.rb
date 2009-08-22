require 'uri'

uri = URI.parse("http://news.com/blah.html#1234")


p uri
p uri.host
p uri.path

