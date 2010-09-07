require File.expand_path("../lib/acts_as_ferret/version", __FILE__)

Gem::Specification.new do |s|

	s.name = 'acts_as_ferret'
	s.version = ActsAsFerret::VERSION
	s.authors = ['Jens Kraemer']
	s.summary = 'acts_as_ferret - Ferret based full text search for any ActiveRecord model'
	s.description = 'Rails plugin that adds powerful full text search capabilities to ActiveRecord models.'
	s.email = 'jk@jkraemer.net'
	s.homepage = 'http://github.com/jkraemer/acts_as_ferret'
	s.rubyforge_project = 'acts_as_ferret'
	
	s.bindir = 'bin'
	s.executables = ['aaf_install']
	s.default_executable = 'aaf_install'
	
	s.platform = Gem::Platform::RUBY 
  s.required_ruby_version = '>= 1.8.7'
	s.rubygems_version = '1.3.6'
	
  # the latest official published ferret gem is 0.11.6 which is incompatible with Ruby 1.9.x.
  # Therefore I decided to publish the jk-ferret gem built from git head.
  s.add_dependency 'jk-ferret', ">= 0.11.8"
  s.add_dependency 'rails', ">= 3.0"
  
	s.has_rdoc = true
  s.rdoc_options << "--charset=UTF-8" << '--title' << 'ActsAsFeret - Ferret powered full text search for Rails' << '--main' << 'README'

	s.extra_rdoc_files = [
		'LICENSE',
		'README'
	]
	
	s.test_files = Dir['test/**/*rb']
	s.files = [
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
	
	s.require_path = 'lib'
  
end
