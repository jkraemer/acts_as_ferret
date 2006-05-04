class InitialMigration < ActiveRecord::Migration
  def self.up
    create_table "comments" do |t|
      t.column "author", :string, :limit => 100, :null => false
      t.column "content", :text, :null => false
      t.column "content_id", :integer, :null => false
    end
    create_table "contents" do |t|
      t.column "title", :string, :limit => 100, :null => false
      t.column "description", :text, :null => false
    end
  end

  def self.down
    drop_table "comments"
    drop_table "contents"
  end
end
