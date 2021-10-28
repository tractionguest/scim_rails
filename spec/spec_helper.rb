ENV['RAILS_ENV'] = 'test'

require File.expand_path("../dummy/config/environment.rb", __FILE__)
require 'awesome_print'
require 'byebug'
require 'factory_bot_rails'
require 'faker'
require 'rspec/rails'
require 'simplecov'
require 'simplecov_json_formatter'

SimpleCov.start

Rails.backtrace_cleaner.remove_silencers!

# Load support files
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

RSpec.configure do |config|
 config.mock_with :rspec
 # config.use_transactional_fixtures = true
 config.infer_base_class_for_anonymous_controllers = false
 # config.order = "random"
 config.filter_run :focus
 config.run_all_when_everything_filtered = true

 # AAB-TODO
 # Poor mans DB reset w/o a gem or using use_transactional_fixtures
 config.before(:each) do
   cleaner = -> (model) do
     model.connection.execute("DELETE FROM #{model.table_name}")
     model.connection.execute("DELETE FROM sqlite_sequence where name = '#{model.table_name}'")
   end
   cleaner.call(User)
   cleaner.call(Company)
   cleaner.call(Group)
   cleaner.call(GroupsUser)
 end
end
