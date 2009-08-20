
######################################################################################
#
# Twitter centric Analytics
#
# This is currently a work in progress.  It consists of:
#
#	Geolocation of post using Yahoo PlaceMaker [ already done on post save ]
#   Pluck out hashtags [ already done on post save ]
#	Pluck out urls [ already done on post save ]
#	Pluck out entities using third party named entity extraction [ TODO ]
#	Pluck out sentiment using NLP [ TODO ]
#	Objective scoring [ TODO ]
#	Subjective scoring [ TODO ]
#	Clustering based on content, time and location [ TODO ]
#	Duplicate removal [ TODO ]
#
######################################################################################

class TwitterSupport

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

	###########################################################################################
	# scoring - both objective and subjective
	###########################################################################################

	#
	# Score ( not done )
	#		objective people score is a function of distance from golden members
	#		objective post score is a function of distance from golden members
	#		objective post score is increased if replied to
	#		objective post score is increased if new
	#		objective post score is increased for magic keywords
	#       subjective post score is a sum of distances from anchors
	#

	def self.score
		#
		# if we can do scoring in the sql query then do that... otherwise...
		#
		# for each post
		#
		#	score = 0 to 1 based on newness ranging over say a month
		#	score = 0 to 1 based on graph distance
		#	score = 0 to 1 based on geographic distance
		#	score = 0 to 1 based on who is bookmarking this thing; its velocity?
		#
		#	TODO fold duplicates and increase their score...
	end 

	# score friends
	def self.score_friends
	end

	# score posts
	def self.score_posts
	end

	# score everything
	def self.score_all
	end

end
