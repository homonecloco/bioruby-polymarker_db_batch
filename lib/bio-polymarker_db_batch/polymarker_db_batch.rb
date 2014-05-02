
class Bio::DB::Polymarker


  def initialize( props)
    @properties =Hash[*File.read(props).split(/[=\n]+/)]
    puts @properties.inspect
  end

  def mysql_version
    con.get_server_info
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
    query="SELECT snp_file_id, filename FROM snp_file WHERE status NOT IN ('NEW', 'DONE', 'LOADED');"
    ret = 0
    if block_given?
      ret = execute_query(query){|row| yield row }
    else
      ret = execute_query(query)
    end
    ret
  end

  def each_snp_in_file(file_id)
    query="SELECT name, chromosome, sequence FROM snp, snp_file_snp WHERE snp_file_snp.snpList_snpId = snp.snpId AND snp_file_snp.snp_file_snp_file_id = '#{file_id}';"
    ret = 0
    puts query
    if block_given?
      ret = execute_query(query){|row| yield row }
    else
      ret = execute_query(query)
    end
    ret
  end

  def write_output_file_and_execute(file_id, filename)
    path =@properties["execution_path"]+"/#{file_id}_#{filename}"
    puts "Writting: #{path}"
    f=File.open(path, "w")

    each_snp_in_file(file_id) do |row|
      f.puts(row.join(","))
    end
    execute_polymarker(path)
    update_status(file_id, "SUBMITTED")
    f.close
  end

  def execute_polymarker(snp_file)
    cmd="#{@properties['wrapper_prefix'] } polymarker.rb -m #{snp_file} -o #{snp_file}_out -c #{@properties['path_to_chromosomes']} #{@properties['wrapper_suffix'] }"
    #polymarker.rb -m 1_GWAS_SNPs.csv -o 1_test -c /Users/ramirezr/Documents/TGAC/references/Triticum_aestivum.IWGSP1.21.dna_rm.genome.fa
    execute_command(cmd)
  end

  def update_status(snp_file_id, new_status)
    raise "Invalid status #{new_status}" unless ["NEW", "SUBMITTED", "RUNNING", "DONE", "ERROR"].include?(new_status)
    pst = con.prepare "UPDATE snp_file SET status = ? WHERE snp_file_id = ?"
    pst.execute new_status, snp_file_id
    con.commit
  end
  
  def review_running_status(file_id, filename)
    out_folder=@properties["execution_path"]+"/#{file_id}_#{filename}_out"
    started=File.exist?(out_folder)
    done=false
    
    if started
      lines = IO.readlines("#{out_folder}/status.txt")
    #  puts lines.inspect
      done = lines.last.split(",").include?("DONE\n") if lines.size > 1
    end
    if done 
      exons_filename="#{out_folder}/exons_genes_and_contigs.fa"
      output_primers="#{out_folder}/primers.csv"
      read_file_to_snp_file("mask_fasta", file_id, exons_filename )
      read_file_to_snp_file("polymarker_output", file_id, output_primers )
      update_status(file_id, "DONE")
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
   
   
    
    if query.start_with?( 'SELECT')
      rs = con.query(query)
      n_rows = rs.num_rows
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
    raise "Unsuported query #{query}"
    
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

