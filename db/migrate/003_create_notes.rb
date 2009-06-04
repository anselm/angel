class CreateNotes < ActiveRecord::Migration
  def self.up

    create_table :notes do |t|

      t.string   :uuid
      t.string   :kind
      t.string   :provenance

      t.integer  :permissions
	  t.integer  :statebits
      t.integer  :owner_id   # party that made this
	  t.integer  :related_id  # a relationship of child parent such as a reply in a tree of messages
      t.integer  :depth
      t.integer  :score

      t.string   :title
      t.string   :link
      t.text     :description
      t.string   :depiction
      t.string   :location
      t.float    :lat
      t.float    :lon
      t.float    :rad
      t.datetime :begins
      t.datetime :ends

      t.timestamps
    end

    create_table :relations do |t|
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

