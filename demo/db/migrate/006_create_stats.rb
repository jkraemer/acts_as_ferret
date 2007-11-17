class CreateStats < ActiveRecord::Migration
  def self.up
    create_table :stats do |t|
      t.integer :process_id, :records, :processing_time, :open_connections
      t.datetime :created_at
    end
  end

  def self.down
    drop_table :stats
  end
end
