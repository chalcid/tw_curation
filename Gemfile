ruby '3.2.1'

# Coming from TW
# gem 'rake'
# gem 'byebug'
# gem 'rainbow'

gem 'require_all'

if ENV['TW_PATH'] && (ENV['TW_PATH'].length != 0)
  if !Dir.exist?(ENV['TW_PATH']) 
    puts "Can not find" + ENV['TW_PATH']
  else
    eval_gemfile(ENV['TW_PATH'] + '/Gemfile')
  end
else
  puts "ENV variable 'TW_PATH' not set, do `TW_PATH=/path/to/taxonworks && export TW_PATH`."
  exit
end
