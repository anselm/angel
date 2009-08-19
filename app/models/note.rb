require 'stemmer'  
require 'hpricot'  
require 'httpclient'
require 'json'
#require 'solr'
#require 'enumerated_attribute' does not work with activerecord

###########################################################################################################
#
# unique edges on nodes used to form tagging and relationships
# stores name, value, provenance
# is unique per node so two different nodes would have the same tag 'purple' independently
# ie you have to do 'select note_id from relations where kind = 'tag' && value == 'purple' ...
#
###########################################################################################################

class Relation < ActiveRecord::Base
  belongs_to :note
  #  acts_as_solr( :fields => [ :value ] )  ...disabled for now...
end

###########################################################################################################
#
# A base class used everywhere that allows relationships
#
###########################################################################################################

class Note < ActiveRecord::Base

  has_many :relations

  # acts_as_solr :fields => [:title, {:lat=>:range_float}, {:lon=>:range_float}] # slower than heck - using tsearch instead
  acts_as_tsearch :fields => ["title","description"]

  RELATIONS = %w{
					RELATION_TAG
					RELATION_CATEGORY
					RELATION_ENTITY
					RELATION_RELATION
					RELATION_FRIEND
					RELATION_URL
				}

   KINDS = %w{
					KIND_USER
					KIND_POST
					KIND_FEED
					KIND_REPORTER
					KIND_REPORT
					KIND_GROUP
					KIND_EVENT
					KIND_PLACE
					KIND_MAP
					KIND_FILTER
				}

  STATEBITS_RESERVED = 0
  STATEBITS_RESPONDED = 1
  STATEBITS_UNRESPONDED = 2
  STATEBITS_FRIENDED = 4
  STATEBITS_DIRTY = 8
  STATEBITS_GEOLOCATED = 16 

  RELATIONS.each { |k| const_set(k,k) }
  KINDS.each { |k| const_set(k,k) }

  # enum_attr :METADATA, RELATIONS, :nil => true  # fails with activerecord
  # enum_attr :KIND, KINDS, :nil => true # fails with activerecord

  # Paperclip
  has_attached_file :photo,
    :styles => {
      :thumb=> "100x100#",
      :small => "150x150>"
    }
 
end
 


###########################################################################################################
#
# Note Relations Management
# Notes have support for arbitrary relationships attached to any given note
# A typing system is implemented at this level; above the scope of activerecord
# The reasoning for this is to have everything in the same sql query space
#
###########################################################################################################

class Note

  def relation_value(kind, sibling_id = nil)
    r = nil
    if sibling_id
	  r = Relation.find(:first, :conditions => { :note_id => self.id, :kind => kind, :sibling_id => sibling_id} )
    else
	  r = Relation.find(:first, :conditions => { :note_id => self.id, :kind => kind } )
    end
    return r.value if r
    return nil
  end

  def relation_first(kind, sibling_id = nil)
    r = nil
    if sibling_id
	  r = Relation.find(:first, :conditions => { :note_id => self.id, :kind => kind, :sibling_id => sibling_id} )
    else
	  r = Relation.find(:first, :conditions => { :note_id => self.id, :kind => kind } )
    end
    return r
  end

  # TODO rate limit
  # TODO use a join
  def relation_as_notes(kind = nil, sibling_id = nil)
    query = { :note_id => self.id }
    query[:kind] = kind if kind
    query[:sibling_id] = sibling_id if sibling_id
    relations = Relation.find(:all,:conditions=>query)
	results = []
	relations.each do |r|
		note = Note.find(:first,:conditions => { :id => r.sibling_id } )
		results << note if note
	end
	return results
  end

  def relation_destroy(kind = nil, sibling_id = nil)
    query = { :note_id => self.id }
    query[:kind] = kind if kind
    query[:sibling_id] = sibling_id if sibling_id
    Relation.destroy_all(query)
  end

  def relation_add(kind, value, sibling_id = nil)
    relation = relation_first(kind,sibling_id)
	if relation
		# TODO think about this line -> return if relation.value == value
		relation.update_attributes(:value => value.to_s.strip, :sibling_id => sibling_id )
		return
	end
    Relation.create!({
                 :note_id => self.id,
                 :sibling_id => sibling_id,
                 :kind => kind,
                 :value => value.to_s.strip
               })
  end

  def relation_add_array(kind,value,sibling_id = nil)
    relation_destroy(kind,sibling_id)
    return if !value
    value.each do |v|
      Relation.create!({
                   :note_id => self.id,
                   :sibling_id => sibling_id,
                   :kind => kind,
                   :value => v.strip
                 })
    end
  end

  def relation_save_hash_tags(text)
     text.scan(/#[a-zA-Z]+/i).each do |tag|
       relation_add(Note::RELATION_TAG,tag[1..-1])
     end
  end

end

=begin

###########################################################################################################
#
# here is a test of carrot2 to cluster
# since carrot2 only clusters well for 1k documents or so we will need to reduce our query scope before here
#
###########################################################################################################

class Note

  def dcs_dump(jsonResponse)
    # puts jsonResponse
    response = JSON.parse(jsonResponse)
    descriptions = response['clusters'].map do
      |cluster| "%s [%i document(s)]" % [cluster['phrases'].join(", "), cluster['documents'].length]
    end
    puts descriptions.join("\n")
  end

  def dcs_request(uri, data)
    boundary = Array::new(16) { "%2.2d" % rand(99) }.join()
    extheader = { "content-type" => "multipart/form-data; boundary=___#{ boundary }___" }
    client = HTTPClient.new
    return client.post_content(uri, data, extheader)
  end

  def dcs_import
    uri = "http://localhost:8080/dcs/rest"
    mydata = open("mydata.xml");
    results = dcs_request(uri, {
      # "dcs.source" => "boss-web",  # examine sources TODO
      "dcs.c2stream" => mydata,
      "query" => "data mining",
      "dcs.output.format" => "JSON",
      "dcs.clusters.only" => "false" # examine TODO 
    })
    dump results
  end

end


=end
