Gem::Specification.new do |s|

	s.name = 'acts_as_ferret'
	s.version = '0.4.8.2'
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
  s.required_ruby_version = '>=1.8.6'
	s.rubygems_version = '1.3.6'
  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3
    
    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency('jk-ferret', [">= 0.11.8"])
    else
      s.add_dependency('jk-ferret', [">= 0.11.8"])
    end
  else
    s.add_dependency('jk-ferret', [">= 0.11.8"])
  end
  

	s.has_rdoc = true
  s.rdoc_options = ["--charset=UTF-8"]
	s.extra_rdoc_files = [
		'LICENSE',
		'README'
	]
	s.test_files = Dir['test/**/*rb']
	s.files = [
		'bin/*',
		'config/*',
		'doc/**/*',
		'recipes/*',
		'script/*',
		'tasks/*',
		'lib/**/*rb'
	].map{|p| Dir[p]}.flatten +
	[
		'acts_as_ferret.gemspec',
		'init.rb',
		'install.rb',
		'README',
		'LICENSE',
	]
	
end
