require 'fileutils'
require 'awesome_print'

namespace :ucd do

  desc 'set the project id'
  task :curation do
    Current.project_id = 16 # sixteen
    Current.user_id = 1 # matt

    raise if Current.project_id != 16 
  end

  # https://github.com/chalcid/jncdb/issues/18
  desc 'cleanup identifiers'
  task cleanup_identifiers: [:curation ] do
    begin
      j = 0
      n = nil
      errors = []

      Identifier::Local::Import.where(identifier_object_type: 'Source', project_id: Current.project_id).find_each do |i|
        o = i.identifier_object

        next if o.year_suffix.nil?

        stripped_identifier = nil
        parts = i.identifier.split(/\d+/)
        year = i.identifier.match(/\d+/).to_s

        stripped_identifier = parts[0] + year
        current_suffix = parts.size == 2 ? parts[1] : '' 

        print Rainbow( o.year_suffix + ' / ' + current_suffix +  ' : ').purple
        print Rainbow(i.identifier).red
        print ' : ' 
        print Rainbow(stripped_identifier).yellow
        print ' : '   

        new_identifier = stripped_identifier + o.year_suffix

        if ((current_suffix == o.year_suffix) && (current_suffix != 'a')) || ( (o.year_suffix == 'a') && (stripped_identifier == i.identifier))
          e = "#{i.identifier} is current"
          puts Rainbow(e).gray

          # First pass uncomment
          errors.push e + ' (may be an error)'
          next
        end

        case o.year_suffix
        when 'a'
          new_identifier = stripped_identifier
        else
          new_identifier = stripped_identifier + o.year_suffix
        end

        print Rainbow(new_identifier).green
        print "\n"

        i.update(identifier: new_identifier)

        # Second pass uncomment
        # errors.push "* [] odd format #{i.identifier}"
        j += 1
      end
    rescue ActiveRecord::RecordInvalid => e
      a = "failed to save #{i.id} - #{e.error}"
      errors.push a
      puts Rainbow(a).red
    end

    t = Identifier::Local::Import.where(identifier_object_type: 'Source', project_id: Current.project_id).all.count 
    puts Rainbow("Done. Updated #{j} of #{t} records.").gold

    puts '----'
    puts errors.collect{|e| "* [ ] #{e}"}.join("\n")
  end

  def pipes_to_i(string)
    s = ''
    open = true
    string.scan(/./).each do |l|
      if l == '|'
        s << (open ? '<i>' : '</i>')
        open = !open
      else
        s << l
      end
    end
    s
  end

  # https://github.com/chalcid/jncdb/issues/9 + 
  #  rake tw:project_import:ucd:cleanup_italics_in_source_titles project_id=16 user_id=1 
  desc 'cleanup italics in source titles'
  task cleanup_italics_in_source_titles: [:curation]  do
    errors = []
    z = Source.joins(:project_sources).where(project_sources: {project_id: Current.project_id}).where("title ilike '%|%'")
    puts "Found #{z.count} records." 

    begin
      i = 0
      Source.joins(:project_sources).where(project_sources: {project_id: Current.project_id}).where("title ilike '%|%'").find_each do |s|
        errors.push("#{s.id} : #{s.title}") if (s.title.scan('|').count % 2) != 0

        print "#{i}\r" 
        # puts Rainbow(s.title).red
        a = pipes_to_i(s.title)
        # puts Rainbow(a).green

        s.update(title: a)
        i += 1
      end
    rescue ActiveRecord::RecordInvalid => e
      errors.push "#{s.id} - invalid title after translate"
    end

    puts
    print "----\n* [ ] "
    puts errors.join("\n* [ ] ")
  end

  task cleanup_host_based_otus: [:data_directory, :environment, :user_id, :project_id ] do

  end

  task cleanup_geographic_area_based_otus: [:curation ] do
    a = Otu.joins(:asserted_distribution).where('otus.project_id = ?', Current.project_id)
  end

  desc 'prepare pdfs'
  task :prepare_pdfs do
    d = ENV['UCD_DATA_DIRECTORY'] 
    raise "!! data_directory not set, do `UCD_DATA_DIRECTORY=/path/to/pdfs && export UCD_DATA_DIRECTORY`" if d.nil? 
    processed =  File.join(d, 'processed')

    FileUtils.mkdir_p processed + '/X'
    FileUtils.mkdir_p processed + '/Y'

    # check for pdfs 

    puts "found pdf dirs:"
    puts Rainbow(pdf_dirs(d).join("\n")).purple
    puts
  end

  def pdf_dirs(d)
    Dir.chdir(d)
    Dir.glob('**/*').select{|f| File.directory?(f) && (f =~ /pdf\_/)}
  end

  # MUST RUN identifier fixer first !!
  desc 'add pdfs'
  task add_pdfs: [:prepare_pdfs, :curation ] do
    i = 0
    @user = User.find(Current.user_id)

    data_dir = ENV['UCD_DATA_DIRECTORY']

    errors = []
    has_pdf = []
    errors_not_found = []

    bad_pdf = []

    pdf_dirs(data_dir).each do |d|

      xy = nil
      if d =~ /_X/
        xy = 'X'
      else
        xy = 'Y'
      end

      puts "processing #{d}"

      Dir["#{d}/*.*"].each do |f|

        begin
          filename = f.split('/').last 
          n = filename.split('.').first
          if s = Identifier::Local::Import.where(namespace_id: 35, identifier: n, project_id: Current.project_id, identifier_object_type: 'Source').first
            if o = s.identifier_object
              if  o.documents.size > 0
                puts Rainbow("#{n} has pdf").yellow 
                has_pdf.push n
                next
              else

                doc = Documentation.new(
                  by: Current.user_id,
                  project_id: Current.project_id,
                  document_attributes: {
                    by: @user,
                    project_id: Current.project_id,
                    document_file: File.open(f),
                    is_public: xy == 'Y' ? false : true
                  },
                  documentation_object: o
                )

                doc.save!
                puts "#{n} : #{o.id} : #{doc.id}"

                a = File.join(data_dir, d, filename)
                b = File.join(data_dir, 'processed', xy, filename)

                # puts "moving #{a} to\n    #{b}"
                FileUtils.mv(a, b)

              end
            end
          else
            puts Rainbow("#{n} NOT FOUND").red
            errors_not_found.push n
          end

        rescue ActiveRecord::RecordInvalid => e
          errors.push "#{n} => #{e.to_s}"
          next

        rescue NameError, "uninitialized constant Document::MalformedPDFError" => e
          bad_pdf.push n
          next
        end

      end # files
    end # pdf dirs

    puts
    puts "# Unmatched source (#{errors_not_found.count})"
    puts errors_not_found.collect{|e| "* [ ] #{e}"}.join("\n")

    puts
    puts "# Invalid records (#{errors.count})"
    puts errors.collect{|e| "* [ ] #{e}"}.join("\n")

    puts
    puts "# Has pdf (#{has_pdf.count})"
    puts has_pdf.collect{|e| "* [ ] #{e}"}.join("\n")

    puts
    puts "# Malformed/bad pdf (#{bad_pdf.count})"
    puts bad_pdf.collect{|e| "* [ ] #{e}"}.join("\n")
  end

  task regenerate_bad_cached_html: [:curation ] do
    a = TaxonName.where("cached_original_combination ILIKE '%\>%' or cached ILIKE '%\>%'").distinct 
    b = a.count
    puts "Found #{b} records."

    errors = []
    a.find_each do |t|
      begin
        print "#{b}    \r"
        t.save!
        b = b - 1
        t.reload
        if t.cached_html =~ /\</ || t.cached_original_combination_html =~ /\</
          errors.push "#{t.id} #{t.name} #{t.cached_html}"
        end

      rescue ActiveRecord::RecordInvalid => e
        puts Rainbow(e).red
        errors.push "#{t.id} : #{e}"
      end
    end

    puts
    puts errors.collect{|a| "* [ ] #{a}"}.join("\n")
  end

end
