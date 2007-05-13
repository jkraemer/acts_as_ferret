module FerretCapTasks
  def start
    run "cd #{current_path}; RAILS_ENV=production script/ferret_start"
  end

  def stop
    run "cd #{current_path}; RAILS_ENV=production script/ferret_stop"
  end

  def restart
    stop
    start
  end
end
Capistrano.plugin :ferret, FerretCapTasks
