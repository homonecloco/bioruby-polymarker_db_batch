#!/usr/bin/env ruby
#require 'bioruby-polyploid-tools'
require 'optparse'
require 'mysql'
require 'net/smtp'

#$: << File.expand_path(File.dirname(__FILE__) + '/../lib')
#$: << File.expand_path('.')
#path=File.expand_path(File.dirname(__FILE__) + '/../lib/bio-polymarker_db_batch.rb')
#$stderr.puts "Loading: #{path}"
#require path

#options = {}
props = ""

OptionParser.new do |opts|
  opts.banner = "Usage: run_pending_polymarker.rb [options]"
  
  opts.on("-p", "--preferences FILE" "File with the preferences") do |o|
     props = o
   end
      
end.parse!
options =Hash[*File.read(props).split(/[=\n]+/)]
to = "ricardo.ramirez-gonzalez@tgac.ac.uk"
msg = <<END_OF_MESSAGE
From: #{options['email_from_alias']} <#{options['email_from']}>
To: <#{to}>
Subject: Test from ruby

The text we are sending!
END_OF_MESSAGE

puts options.inspect
smtp = Net::SMTP.new options["email_server"], 587
smtp.enable_starttls
smtp.start( options["email_domain"], options["email_user"], options["email_pwd"], :login) do
   smtp.send_message(msg, options["email_from"], to)
end

#Net::SMTP.start(options["email_server"], 25, options["email_domain"], options["email_user"], options["email_pwd"], :cram_md5) do |smtp|
#      smtp.send_message msg, opts[:from], to
#end