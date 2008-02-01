namespace :ferret do

  # for a shared index, declare all models that should go into this index separated by
  # space: MODEL="MyModel AnotherModel"
  desc "Rebuild a Ferret index. Specify what model to rebuild with the MODEL environment variable."
  task :rebuild do
    require File.join(RAILS_ROOT, 'config', 'environment')

    models = ENV['MODEL'].split.map(&:constantize)

    start = 1.minute.ago
    models.first.rebuild_index( *models )

    # update records that have changed since the rebuild started
    models.each do |m|
      m.records_modified_since(start).each do |object|
        object.ferret_update
      end
    end
  end
end
