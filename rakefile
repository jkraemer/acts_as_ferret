require 'rake/testtask'

desc 'Test the library.'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

gemspec = eval(File.read("acts_as_ferret.gemspec"))

task :build => "#{gemspec.full_name}.gem"

file "#{gemspec.full_name}.gem" => gemspec.files + ["acts_as_ferret.gemspec"] do
  system "gem build acts_as_ferret.gemspec"
  system "gem install #{gemspec.full_name}.gem"
end
