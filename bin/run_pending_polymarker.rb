#!/usr/bin/env ruby
require 'bioruby-polyploid-tools'
require 'optparse'
require 'mysql'
$: << File.expand_path(File.dirname(__FILE__) + '/../lib')
$: << File.expand_path('.')
path=File.expand_path(File.dirname(__FILE__) + '/../lib/bio-polymarker_db_batch.rb')
#$stderr.puts "Loading: #{path}"
require path

options = {}


OptionParser.new do |opts|
  opts.banner = "Usage: run_pending_polymarker.rb [options]"
  
  opts.on("-p", "--preferences FILE" "File with the preferences") do |o|
     options[:preferences] = o
   end
      
end.parse!

pol=Bio::DB::Polymarker.new(options[:preferences])
pol.connect
pol.mysql_version
pol.close