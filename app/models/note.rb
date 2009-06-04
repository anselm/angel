require 'stemmer'  
require 'hpricot'  
require 'httpclient'
require 'json'
require 'solr'

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
  RELATION_NULL                = "null"
  RELATION_TAG                 = "tag"
  RELATION_OWNER               = "owner"
end

###########################################################################################################
#
# A base class used everywhere that allows relationships
#
###########################################################################################################

class Note < ActiveRecord::Base
  has_many :relations
  acts_as_solr :fields => [:title, {:lat=>:range_float}, {:lon=>:range_float}]
  KIND_NULL = "null"
  KIND_USER = "user"
  KIND_POST = "post"
  KIND_FEED = "feed"
  STATEBITS_RESERVED = 0
  STATEBITS_RESPONDED = 1
  STATEBITS_UNRESPONDED = 2
  STATEBITS_FRIENDED = 4
  STATEBITS_DIRTY = 8
  STATEBITS_GEOLOCATED = 16 
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

  def relation_get(kind, sibling_id = nil)
    r = nil
    if sibling_id
      r = Relation.first(:note_id => self.id, :kind => kind, :sibling_id => sibling_id )
    else
      r = Relation.first(:note_id => self.id, :kind => kind )
    end
    return r.value if r
    return nil
  end

  def relation_first(kind, sibling_id = nil)
    r = nil
    if sibling_id
      r = Relation.first(:note_id => self.id, :kind => kind, :sibling_id => sibling_id )
    else
      r = Relation.first(:note_id => self.id, :kind => kind )
    end
    return r
  end

  def relation_all(kind = nil, sibling_id = nil)
    query = { :note_id => self.id }
    query[:kind] = kind if kind
    query[:sibling_id] = sibling_id if sibling_id
    Relation.all(query)
  end

  def relation_destroy(kind = nil, sibling_id = nil)
    query = { :note_id => self.id }
    query[:kind] = kind if kind
    query[:sibling_id] = sibling_id if sibling_id
    Relation.destroy_all(query)
  end

  def relation_add(kind, value, sibling_id = nil)
    relation_destroy(kind,sibling_id)
    return if !value
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
       relation_add(Relation::RELATION_TAG,tag[1..-1])
     end
  end

end

############################################################################################
#
# Word index - a local search engine
#
############################################################################################

class String 
  COMMON_WORDS = ['a','able','about','above','abroad','according','accordingly','across','actually','adj','after','afterwards','again','against','ago','ahead','aint','all','allow','allows','almost','alone','along','alongside','already','also','although','always','am','amid','amidst','among','amongst','an','and','another','any','anybody','anyhow','anyone','anything','anyway','anyways','anywhere','apart','appear','appreciate','appropriate','are','arent','around','as','as','aside','ask','asking','associated','at','available','away','awfully','b','back','backward','backwards','be','became','because','become','becomes','becoming','been','before','beforehand','begin','behind','being','believe','below','beside','besides','best','better','between','beyond','both','brief','but','by','c','came','can','cannot','cant','cant','caption','cause','causes','certain','certainly','changes','clearly','cmon','co','co.','com','come','comes','concerning','consequently','consider','considering','contain','containing','contains','corresponding','could','couldnt','course','cs','currently','d','dare','darent','definitely','described','despite','did','didnt','different','directly','do','does','doesnt','doing','done','dont','down','downwards','during','e','each','edu','eg','eight','eighty','either','else','elsewhere','end','ending','enough','entirely','especially','et','etc','even','ever','evermore','every','everybody','everyone','everything','everywhere','ex','exactly','example','except','f','fairly','far','farther','few','fewer','fifth','first','five','followed','following','follows','for','forever','former','formerly','forth','forward','found','four','from','further','furthermore','g','get','gets','getting','given','gives','go','goes','going','gone','got','gotten','greetings','h','had','hadnt','half','happens','hardly','has','hasnt','have','havent','having','he','hed','hell','hello','help','hence','her','here','hereafter','hereby','herein','heres','hereupon','hers','herself','hes','hi','him','himself','his','hither','hopefully','how','howbeit','however','hundred','i','id','ie','if','ignored','ill','im','immediate','in','inasmuch','inc','inc.','indeed','indicate','indicated','indicates','inner','inside','insofar','instead','into','inward','is','isnt','it','itd','itll','its','its','itself','ive','j','just','k','keep','keeps','kept','know','known','knows','l','last','lately','later','latter','latterly','least','less','lest','let','lets','like','liked','likely','likewise','little','look','looking','looks','low','lower','ltd','m','made','mainly','make','makes','many','may','maybe','maynt','me','mean','meantime','meanwhile','merely','might','mightnt','mine','minus','miss','more','moreover','most','mostly','mr','mrs','much','must','mustnt','my','myself','n','name','namely','nd','near','nearly','necessary','need','neednt','needs','neither','never','neverf','neverless','nevertheless','new','next','nine','ninety','no','nobody','non','none','nonetheless','noone','no-one','nor','normally','not','nothing','notwithstanding','novel','now','nowhere','o','obviously','of','off','often','oh','ok','okay','old','on','once','one','ones','ones','only','onto','opposite','or','other','others','otherwise','ought','oughtnt','our','ours','ourselves','out','outside','over','overall','own','p','particular','particularly','past','per','perhaps','placed','please','plus','possible','presumably','probably','provided','provides','q','que','quite','qv','r','rather','rd','re','really','reasonably','recent','recently','regarding','regardless','regards','relatively','respectively','right','round','s','said','same','saw','say','saying','says','second','secondly','see','seeing','seem','seemed','seeming','seems','seen','self','selves','sensible','sent','serious','seriously','seven','several','shall','shant','she','shed','shell','shes','should','shouldnt','since','six','so','some','somebody','someday','somehow','someone','something','sometime','sometimes','somewhat','somewhere','soon','sorry','specified','specify','specifying','still','sub','such','sup','sure','t','take','taken','taking','tell','tends','th','than','thank','thanks','thanx','that','thatll','thats','thats','thatve','the','their','theirs','them','themselves','then','thence','there','thereafter','thereby','thered','therefore','therein','therell','therere','theres','theres','thereupon','thereve','these','they','theyd','theyll','theyre','theyve','thing','things','think','third','thirty','this','thorough','thoroughly','those','though','three','through','throughout','thru','thus','till','to','together','too','took','toward','towards','tried','tries','truly','try','trying','ts','twice','two','u','un','under','underneath','undoing','unfortunately','unless','unlike','unlikely','until','unto','up','upon','upwards','us','use','used','useful','uses','using','usually','v','value','various','versus','very','via','viz','vs','w','want','wants','was','wasnt','way','we','wed','welcome','well','well','went','were','were','werent','weve','what','whatever','whatll','whats','whatve','when','whence','whenever','where','whereafter','whereas','whereby','wherein','wheres','whereupon','wherever','whether','which','whichever','while','whilst','whither','who','whod','whoever','whole','wholl','whom','whomever','whos','whose','why','will','willing','wish','with','within','without','wonder','wont','would','wouldnt','x','y','yes','yet','you','youd','youll','your','youre','yours','yourself','yourselves','youve','z','zero']
  def words
    words = self.gsub(%r{</?[^>]+?>},'')
    words = words.gsub(/[^\w\s]/,"").split  
    d = []
    words.each do |word| 
      if (COMMON_WORDS.include?(word) or word.size > 50 or word.size < 3)
        # skip
      else
        d << word.downcase.stem
      end
    end
    return d  
  end 
end

class Word < ActiveRecord::Base
	def self.find(word)
		wrd = first(:stem => word)
		wrd = new(:stem => word,:frequency => 1) if wrd.nil?
		return wrd
	end
	def self.find_set_frequency(word)
		wrd = first(:stem => word)
		if wrd.nil?
			wrd = new(:stem => word,:frequency => 1)
		else
			wrd.frequency = wrd.frequency + 1
			wrd.save!
		end
		return wrd
	end
end

class Transit < ActiveRecord::Base
	belongs_to :word
	belongs_to :note
end

###########################################################################################################
#
# native search engine support - thought this might be convenient instead of offloading to sphinx, solr etc 
#
###########################################################################################################

class Note

  has_many :transits
  has_many :words

  def refresh
    update_attributes({:updated_at => DateTime.parse(Time.now.to_s)})
  end

  def age
    (Time.now - updated_at.to_time)/60
  end
 
  def fresh?
    age > FRESHNESS_POLICY ? false : true
  end

  #
  # this rebuilds the word frequency table so it should be used judiciously
  #
  def rebuild_word_index
    Transits.destroy!
    p = 0
    words = self.title.to_s.words
    words.each do |word|
      w = Word.find_set_frequency(word)
      l = Transit.new(:position => p,:word => w, :note => self)
      l.save
      p = p + 1
    end
  end

  #
  # rebuild everything from scratch ... for testing
  #
  def self.rebuild_all_sql
    Word.all.destroy!
    Transit.all.destroy!
    total = Note.count()
    offset = 0
    loop {
      results = Note.all( :offset => offset, :limit => 10, :order => [ :created_at.desc ] )
      puts "rebuilding notes from #{offset} of 10 to #{total}"
      results.each { |note| note.rebuild_word_index }
      offset = offset + 10
      return if offset >= total || offset > 100
    }
  end

end

###########################################################################################################
#
# this is the search engine ranking algorithm implementation 
#
# http://blog.saush.com/2009/03/write-an-internet-search-engine-with-200-lines-of-ruby-code/
#
###########################################################################################################

class Digger

  SEARCH_LIMIT = 19

  def search(for_text)
    @search_params = for_text.to_s.words
    wrds = []
    @search_params.each { |param| wrds << "stem = '#{param}'" }
    return [] if wrds.length < 1
    word_sql = "select * from words where #{wrds.join(" or ")}"
    #@search_words = repository(:default).adapter.query(word_sql)
	@search_words = Word.connection.execute(word_sql)
    tables, joins, ids = [], [], []
    posns = []
    @search_words.each_with_index { |w, index|
      tables << "Transits loc#{index}"
      joins << "loc#{index}.note_id = loc#{index+1}.note_id"
      ids << "loc#{index}.word_id = #{w.id}"
      posns << "loc#{index}.position"
    }
    joins.pop
    @common_select = "from #{tables.join(', ')} where #{(joins + ids).join(' and ')} group by loc0.note_id, #{posns.join(', ')}"
    rank[0..SEARCH_LIMIT]
    notes = []
    rank.each { |id,score| notes << Note.first(:id => id) }
    return notes
  end

  def rank
    merge_rankings(frequency_ranking, transit_ranking, distance_ranking)
  end

  def frequency_ranking
    freq_sql= "select loc0.note_id, count(loc0.note_id) as count #{@common_select} order by count desc"
    #list = repository(:default).adapter.query(freq_sql)
	list = Transit.connection.execute(word_sql)
    rank = {}
    list.size.times { |i| rank[list[i].note_id] = list[i].count.to_f/list[0].count.to_f }
    return rank
  end

  def transit_ranking
    total = []
    @search_words.each_with_index { |w, index| total << "loc#{index}.position + 1" }
    loc_sql = "select loc0.note_id, (#{total.join(' + ')}) as total #{@common_select} order by total asc"
    #list = repository(:default).adapter.query(loc_sql)
    rank = {}
    list.size.times { |i| rank[list[i].note_id] = list[0].total.to_f/list[i].total.to_f }
    return rank
  end

  def distance_ranking
    return {} if @search_words.size == 1
    dist, total = [], []
    @search_words.each_with_index { |w, index| total << "loc#{index}.position" }
    total.size.times { |index| dist << "abs(#{total[index]} - #{total[index + 1]})" unless index == total.size - 1 }
    dist_sql = "select loc0.note_id, (#{dist.join(' + ')}) as dist #{@common_select} order by dist asc"
    #list = repository(:default).adapter.query(dist_sql)
    rank = Hash.new
    list.size.times { |i| rank[list[i].note_id] = list[0].dist.to_f/list[i].dist.to_f }
    return rank
  end

  def merge_rankings(*rankings)
    r = {}
    rankings.each { |ranking| r.merge!(ranking) { |key, oldval, newval| oldval + newval} }
    r.sort {|a,b| b[1]<=>a[1]}
  end

end

###########################################################################################################
#
# a test of solr search engine using a solr_ruby plugin that suxxors - not used
#
###########################################################################################################

=begin

  # here is an attempt to use solr for the same work
  # probably should conflate add and update
  #
  def self.rebuild_all
    conn = Solr::Connection.new('http://127.0.0.1:8983/solr', :autocommit => :on )
    results = Note.all( :offset => 0, :limit => 100 , :order => [ :created_at.desc ] )
    results.each do |note|
      conn.add(:id => note.id, :title_text => note.title )
      puts "added document #{note.id} #{note.title}"
    end
  end

  def self.search(for_text)
    conn = Solr::Connection.new('http://127.0.0.1:8983/solr', :autocommit => :on )
    results = [] 
    response = conn.query(for_text)
    response.hits.each do |hit|
      note = Note.first(hit.id)
      results << note if note
    end
    return results
  end

=end

###########################################################################################################
#
# here is some scratch code for talking to solr directly
# there is another plugin called sunspot that is worth trying
# what is interesting is that this approach is very powerful - allowing diferent metadata
#
###########################################################################################################

=begin

<add>
  <doc>
    <field name="id">9885A004</field>
    <field name="name">Canon PowerShot SD500</field>
    <field name="category">camera</field>
    <field name="features">3x optical zoom</field>
    <field name="features">aluminum case</field>
    <field name="weight">6.4</field>
    <field name="price">329.95</field>
  </doc>
</add>

require 'net/http'

h = Net::HTTP.new('localhost', 8983)
hresp, data = h.get('/solr/select?q=iPod&wt=ruby', nil)
rsp = eval(data)

puts 'number of matches = ' + rsp['response']['numFound'].to_s
#print out the name field for each returned document
rsp['response']['docs'].each { |doc| puts 'name field = ' + doc['name'] }



url = URI.parse('http://localhost:3000/someservice/')
request = Net::HTTP::Post.new(url.path)
request.body = "<?xml version='1.0' encoding='UTF-8'?><somedata><name>Test Name 1</name><description>Some data for Unit testing</description></somedata>"
response = Net::HTTP.start(url.host, url.port) {|http| http.request(request)}

#Note this test PASSES!
assert_equal '201 Created', response.get_fields('Status')[0]

=end

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



class Note

=begin
  # Paperclip
  has_attached_file :photo,
    :styles => {
      :thumb=> "100x100#",
      :small => "150x150>"
    }
=end
 
end
 
