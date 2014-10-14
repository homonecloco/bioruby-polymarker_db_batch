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


pol.mysql_version
pol.each_to_run do |row|
  puts row.join(",")
  puts row.inspect
  puts row[0]
  puts row[1]
  pol.write_output_file_and_execute(row[0], row[1]);
#  pol.each_snp_in_file(row[0]) do |snp|
 #    puts snp.inspect
     
  #    pol.
   #end
  
end




