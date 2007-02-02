class CreateRemoteContents < ActiveRecord::Migration
  def self.up
    create_table :remote_contents do |t|
      t.column :title, :string
      t.column :content, :string
    end
  end

  def self.down
    drop_table :remote_contents
  end
end
