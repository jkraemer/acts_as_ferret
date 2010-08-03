Gem::Specification.new do |s|

	s.name = 'acts_as_ferret'
	s.version = '0.4.8.rails3'
	s.authors = ['Jens Kraemer']
	s.summary = 'acts_as_ferret - Ferret based full text search for any ActiveRecord model'
	s.description = 'Rails plugin that adds powerful full text search capabilities to ActiveRecord models.'
	s.email = 'jk@jkraemer.net'
	s.homepage = 'http://github.com/jkraemer/acts_as_ferret'
	s.rubyforge_project = 'acts_as_ferret'
	
	s.bindir = 'bin'
	s.executables = ['aaf_install']
	s.default_executable = 'aaf_install'
  s.require_paths = ["lib"]
	
	
	s.platform = Gem::Platform::RUBY 
  s.required_ruby_version = '>=1.8'
	s.rubygems_version = '1.3.6'
  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3
    
    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency('ferret', [">= 0.11.6"])
    else
      s.add_dependency('ferret', [">= 0.11.6"])
    end
  else
    s.add_dependency('ferret', [">= 0.11.6"])
  end
  

	s.has_rdoc = true
  s.rdoc_options << "--charset=UTF-8" << '--title' << 'ActsAsFeret - Ferret powered full text search for Rails' << '--main' << 'README'


	s.extra_rdoc_files = [
		'LICENSE',
		'README'
	]
	s.test_files = Dir['test/**/*rb']
	s.files = [
	  '*rb',
		'README',
		'LICENSE',
		'bin/*',
		'config/*',
		'doc/**/*',
		'recipes/*',
		'script/*',
		'tasks/*',
		'lib/**/*rb'
	].map{|p| Dir[p]}.flatten
	
end
