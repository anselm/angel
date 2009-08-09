

# Analytics
#
# Hash tags are broken out
# Urls are broken out
# Parties are broken out
# NLP is used to find interesting objects using named entity extraction
# Duplicate or similar posts are clustered

class AggregationSupport

	###########################################################################################
	# merge dupes
	# this may be very important to helping score items
	# TODO write it
	###########################################################################################

	def self.merge_dupes
		# i think we could do this on the database itself...
		# for example if something is a reply then it is a kind of cluster
		# and if something is talking about the same url then it is a kind of cluster
		# and if it has the same words then its the same topic too...
		# - i could totally delete the dupe
		# - ...
	end


	###########################################################################################
	# metadata extraction
	###########################################################################################

	# pull out useful metadata
	def self.metadata_all
	end

end
