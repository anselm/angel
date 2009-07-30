class CreateNotes < ActiveRecord::Migration
  def self.up

    create_table :notes do |t|

      t.string   :type
      t.string   :kind
      t.string   :uuid
      t.string   :provenance

      t.integer  :permissions
      t.integer  :statebits
      t.integer  :owner_id   # party that made this
      t.integer  :related_id  # a relationship of child parent such as a reply in a tree of messages

      t.string   :title
      t.string   :link
      t.text     :description
      t.string   :depiction
      t.string   :location
      t.string	 :tagstring
      t.float    :lat
      t.float    :lon
      t.float    :rad
      t.integer  :depth	# zoom depth hint for map view
      t.integer  :score	# an objective score
      t.datetime :begins
      t.datetime :ends

      t.timestamps
    end

    create_table :relations do |t|
      t.string   :type
      t.string   :kind
      t.text     :value
      t.integer  :note_id
      t.integer  :sibling_id
      t.timestamps
    end

  end
  def self.down
    drop_table   :notes
    drop_table   :relations
  end
end

