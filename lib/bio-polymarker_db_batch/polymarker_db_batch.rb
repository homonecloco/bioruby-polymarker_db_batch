require 'pp'  
class Bio::DB::Polymarker


  def initialize( props)
    @properties =Hash[*File.read(props).split(/[=\n]+/)]
    puts @properties.inspect
  end

  def mysql_version
    con.get_server_info
  end
 
 def get_snp_file(id)
  results = con.query "SELECT * FROM snp_file WHERE snp_file_id=#{id}"
  results.fetch_hash
 end

  def each_to_run
    query="SELECT snp_file_id, filename FROM snp_file WHERE status = 'NEW';"
    ret = 0
    if block_given?
      ret = execute_query(query){|row| yield row }
    else
      ret = execute_query(query)
    end
    ret
  end

  def each_running
    query="SELECT snp_file_id, filename FROM snp_file WHERE status IN ('SUBMITTED', 'RUNNING');"
    ret = 0
    if block_given?
      ret = execute_query(query){|row| yield row }
    else
      ret = execute_query(query)
    end
    ret
  end

  def each_timeout
    #TODO: validate the timeouts. 
    #SELECT * FROM snp_file WHERE datediff(NOW(), lastChange) > 3 and status != 'DONE';
    query="SELECT snp_file_id, filename FROM snp_file WHERE datediff(NOW(), submitted) > 3 AND status IN ('NEW', 'SUBMITTED', 'RUNNING');"
    ret = 0
    if block_given?
       ret = execute_query(query){|row| yield row }
    else
      ret = execute_query(query)
    end
    ret
  end

  def each_snp_in_file(file_id)
    query="SELECT name, chromosome, sequence FROM snp, snp_file_snp WHERE snp_file_snp.snpList_snpId = snp.snpId AND snp_file_snp.snp_file_snp_file_id = '#{file_id}' AND snp.process = 1;"
    ret = 0
    #puts query
    if block_given?
      ret = execute_query(query){|row| yield row }
    else
      ret = execute_query(query)
    end
    ret
  end

  def write_output_file_and_execute(file_id, filename)
    #puts "Writting: #{file_id}_#{filename}"
    path =@properties["execution_path"]+"/#{file_id}_#{filename}"
    puts "Writting: #{path}"
    f=File.open(path, "w")
    each_snp_in_file(file_id) do |row|
      f.puts(row.join(","))
    end
    f.close
    execute_polymarker(file_id, path)
    update_status(file_id, "SUBMITTED")
   
  end

  def get_preferences(file_id)
    query="SELECT name, value FROM preferences \
    join snp_file_preferences on preferenceID = preferences_preferenceID \
    where snp_file_snp_file_id = #{file_id};"
    preferences = Hash.new
    execute_query(query) do |row|
      preferences[row[0].to_sym] = row[1]
    end
    return preferences
  end

  def execute_polymarker(file_id, snp_file)
    
    preferences = get_preferences(file_id)

    cmd=@properties['wrapper_prefix']
    cmd << "polymarker.rb -m #{snp_file} -o #{snp_file}_out "
    cmd << "-c #{@properties['path_to_chromosomes']}/#{preferences[:reference]} "
    cmd << @properties['wrapper_suffix']
    #polymarker.rb -m 1_GWAS_SNPs.csv -o 1_test -c /Users/ramirezr/Documents/TGAC/references/Triticum_aestivum.IWGSP1.21.dna_rm.genome.fa
    execute_command(cmd)
  end

  def update_status(snp_file_id, new_status)
    raise "Invalid status #{new_status}" unless ["NEW", "SUBMITTED", "RUNNING", "DONE", "ERROR"].include?(new_status)
    snp_file = get_snp_file(snp_file_id)
    return if snp_file['status'] == new_status
    pst = con.prepare "UPDATE snp_file SET status = ? WHERE snp_file_id = ?"
    pst.execute new_status, snp_file_id
    con.commit
    begin
      hashed_id = "#{snp_file_id}:#{snp_file['hash']}"
      send_email(snp_file['email'],hashed_id, new_status)
    rescue
      puts "Error sending email. "
    end
  end

  def update_error_status(snp_file_id, error_message)
    snp_file = get_snp_file(snp_file_id)
    return if snp_file['status'] == "ERROR"
    pst = con.prepare "UPDATE snp_file SET status = 'ERROR', error=? WHERE snp_file_id = ?"
    puts "update_error_status: #{pst}"
    pst.execute error_message, snp_file_id
    con.commit
    new_status = "ERROR: #{error_message}"
      hashed_id = "#{snp_file_id}:#{snp_file['hash']}"
    begin
      send_email(snp_file['email'], hashed_id,  new_status)
    rescue Exception => e  
      puts "Error sending email to #{snp_file['email']}: #{e.message}"
    end
      
    begin
      send_email(@properties['email_from'], hashed_id, new_status)
    rescue Exception => e  
      puts "Error sending email to #{@properties['email_from']}: #{e.message}"
    end
  end

  def send_email(to,id, status)
    options = @properties

    msg = <<END_OF_MESSAGE
From: #{options['email_from_alias']} <#{options['email_from']}>
To: <#{to}>
Subject: Polymarker #{id} #{status}

The current status of your request (#{id}) is #{status}
The latest status and results (when done) are available in: #{options['web_domain']}/status?id=#{id}


END_OF_MESSAGE
    smtp = Net::SMTP.new options["email_server"], 587
    smtp.enable_starttls
    smtp.start( options["email_domain"], options["email_user"], options["email_pwd"], :login) do
      smtp.send_message(msg, options["email_from"], to)
    end
  end
  
  def review_running_status(file_id, filename)
    out_folder=@properties["execution_path"]+"/#{file_id}_#{filename}_out"
    started=File.exist?(out_folder)
    done=false
    

    error_message = ""
    error = false

    if started
      lines = IO.readlines("#{out_folder}/status.txt")
      puts lines.inspect

    lines.each do |l| 
      done = l.split(",").include?("DONE\n")
    end
      
      lines.each do |l|  
        error = l.include?("ERROR") unless error
        error_message << l if error
      end 
    end


    if done 
      exons_filename="#{out_folder}/exons_genes_and_contigs.fa"
      output_primers="#{out_folder}/primers.csv"
      read_file_to_snp_file("mask_fasta", file_id, exons_filename )
      read_file_to_snp_file("polymarker_output", file_id, output_primers )
      update_status(file_id, "DONE")
    elsif error
       update_error_status(file_id, error_message)
    elsif started
      update_status(file_id, "RUNNING")
    end
  end

  private

  def read_file_to_snp_file(column, id, filename )
    pst = con.prepare "UPDATE snp_file SET #{column} = ? WHERE snp_file_id = ?"
    puts "Reading: #{filename}"
    text = File.read(filename)
    pst.execute text, id
  end

  #TODO:Exception handling
  def connect
    @con = Mysql.new @properties["mysql_host"], @properties["mysql_user"], @properties["mysql_pwd"], @properties["mysql_db"]
    @con.autocommit false
    return @con
  end
  def close
    @con.close if @con
    @con = nil
  end

  def con     #TODO: reconnect if connection lost
    connect unless @con 
    @con
  end

  def execute_query(query)
    $stderr.puts query if $VERBOSE 
    #puts "to execute: #{query}"
    if query.start_with?( 'SELECT')
      rs = con.query(query)
      pp rs.inspect
      n_rows = rs.num_rows
      puts "Returned #{n_rows} rows"
      ret = Array.new unless block_given?
      n_rows.times do
        row = rs.fetch_row
        yield row if block_given?
        ret << row unless block_given?
      end
      close
      return n_rows unless block_given?
      return ret
    end
    raise "Unsuported query '#{query}'"
    
  end

  def execute_command(command, type=:text, skip_comments=true, comment_char="#", &block)
    puts "Executing #{command}"
    stdin, pipe, stderr, wait_thr = Open3.popen3(command)
    pid = wait_thr[:pid]  # pid of the started process.       
    if type == :text
      while (line = pipe.gets)
        next if skip_comments and line[0] == comment_char
        yield line.chomp if block_given?
      end
    elsif type == :binary
      while (c = pipe.gets(nil))
        yield c if block_given?
      end
    end
    exit_status = wait_thr.value  # Process::Status object returned.
    puts stderr.read 
    stdin.close
    pipe.close
    stderr.close
    return exit_status
  end

end

