
class TwitterSupport

	###########################################################################################
	# respond
	###########################################################################################

=begin
	# Response handling is kept separate from consuming; they are asynchronous for stability and speed
	# TODO respond more intelligently
	# TODO bitmasks are borked
	def self.respond_all_this_is_currently_unused
		twitter = self.twitter_start
		results = []
		bitmask = 0
		Note.all(:statebits => bitmask).each do |note|
			party = Note.first(:id => note.owner_id)
			next if !party
			self.befriend(twitter,party)
			result = nil
			if note[:provenance] == "twitter"
				result = "!@#{party.title} thanks for the post"
				twitter.update(result)
				twitter.update("rt #{result}") if false
			end
			if result
				note.statebits = Note::STATEBITS_RESPONDED
				note.save!
				results << result
			else
				results << "failed to save note #{note.id}"
			end
		end
		return results
	end
=end

end
