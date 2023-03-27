require 'byebug'
require 'rainbow'
require 'require_all'
require 'rake'

Rake.add_rakelib './tasks'

if p = ENV['TW_PATH']
  a = File.join(p, '/config/environment')
  if true # Dir.exist?(a)
    puts Rainbow("TaxonWorks found at #{a}").green
    require_relative a
    true
  else
    puts Rainbow("TaxonWorks NOT found at #{a}").red
    exit
  end 
else
  puts Rainbow("ENV variable 'TW_PATH' not set, do `TW_PATH=/path/to/taxonworks && export TW_PATH`.").red
  exit 
end

desc 'default'
task :default do
  puts Rainbow("Configuration successful.").purple
end

