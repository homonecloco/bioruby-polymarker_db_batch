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


#pol.mysql_version
pol.each_running do |row|
  #puts row.join(",")
  #puts row.inspect
  pol.review_running_status(row[0], row[1])  
end

pol.each_timeout do |row|
  #puts "Timeouts: #{row[0]}"
  pol.update_error_status(row[0], "Timeout")
end


