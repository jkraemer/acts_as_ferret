# Ferret DRb server Capistrano tasks
# 
# Usage:
# in your Capfile, add acts_as_ferret's recipes directory to your load path and
# load the ferret tasks:
#
# load_paths << 'vendor/plugins/acts_as_ferret/recipes'
# load 'aaf_recipes'
#
# This will hook aaf's DRb start/stop tasks into the standard
# deploy:{start|restart|stop} tasks so the server will be restarted along with
# the rest of your application.
# Also an index directory in the shared folder will be created and symlinked
# into current/ when you deploy.
#
# In order to use the ferret:index:rebuild task, declare the models you intend to
# index in config/deploy.rb:
#
# for a shared index, do:
# set :ferret_single_index_models, [ Model, AnotherModel, YetAnotherModel ]
# This will call Model.rebuild_index( AnotherModel, YetAnotherModel )
#
# for models indexed separately, specify:
# set :ferret_models, [ Model, AnotherModel ]
# This will call Model.rebuild_index and AnotherModel.rebuild_index separately.
#
# The two methods may be combined if you have a shared index, and some models
# indexed separately. 
#
# Like to submit a patch to aaf? Automatically determining the models that use 
# acts_as_ferret so the declaration of these variables in deploy.rb isn't 
# necessary anymore would be really cool ;-)

namespace :ferret do

  desc "Stop the Ferret DRb server"
  task :stop, :roles => :app do
    run "cd #{current_path}; script/ferret_server -e #{rails_env} stop"
  end

  desc "Start the Ferret DRb server"
  task :start, :roles => :app do
    run "cd #{current_path}; script/ferret_server -e #{rails_env} start"
  end

  desc "Restart the Ferret DRb server"
  task :restart, :roles => :app do
    top.ferret.stop
    sleep 1
    top.ferret.start
  end

  namespace :index do

    desc "Rebuild the Ferret index. See aaf_recipes.rb for instructions."
    task :rebuild, :roles => :app do
      rake = fetch(:rake, 'rake')
      single_index_models = fetch(:ferret_single_index_models, nil)
      if single_index_models
        run "cd #{current_path}; RAILS_ENV=#{rails_env} MODEL='#{ferret_single_index_models.join(' ')}' #{rake} ferret:rebuild"
      end
      fetch(:ferret_models, []).each do |m|
        run "cd #{current_path}; RAILS_ENV=#{rails_env} MODEL='#{m}' #{rake} ferret:rebuild"
      end
    end

    desc "purges all indexes for the current environment"
    task :purge, :roles => :app do
      run "rm -fr #{shared_path}/index/#{rails_env}"
    end

    desc "symlinks index folder"
    task :symlink, :roles => :app do
      run "mkdir -p  #{shared_path}/index && rm -rf #{release_path}/index && ln -s #{shared_path}/index #{release_path}/index"
    end

  end

end

after "deploy:stop",    "ferret:stop"
after "deploy:start",   "ferret:start"
after "deploy:restart", "ferret:restart"
after "deploy:symlink", "ferret:index:symlink"

