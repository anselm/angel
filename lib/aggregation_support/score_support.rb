
#
# Score ( not done )
#		objective people score is a function of distance from golden members
#		objective post score is a function of distance from golden members
#		objective post score is increased if replied to
#		objective post score is increased if new
#		objective post score is increased for magic keywords
#       subjective post score is a sum of distances from anchors
#


class AggregationSupport

	###########################################################################################
	# scoring - both objective and subjective
	###########################################################################################

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
