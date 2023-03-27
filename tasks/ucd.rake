require 'fileutils'
require 'amazing_print'

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
    # Identify some group of names to inspect 
    #   - eliminate having to inspect everything!
    #
    # 1- Species or genus group names
    #
    # 2- Missing author or year
    #
    # Loop that group of names
    # has soft_validation X?

    # Missing relationship: Aphelinus varipes Förster should be a secondary homonym or duplicate of Aphelinus varipes (Förster, 1841)
    # Missing relationship: Original genus is not selected 
    #
    #
    #
    # Second step
    #
    # Merging
  end

  desc 'cleanup geographic area based otus'
  task cleanup_geographic_area_based_otus: [ :curation ] do
    a = Otu.with_biological_associations.where('otus.project_id = ?', Current.project_id)
    puts a.count

    a.each do |o|
      p = otu_only_taxon_name(o.taxon_name_id)
      if p.empty?


        if TaxonName.where(cached: o.taxon_name.cached).where.not(id: o.taxon_name_id).any?
          puts "#{o.taxon_name.cached}            \r"
          puts Rainbow("yes").purple
        end

      else
       #  puts o # "no"
      end
 
    # puts
    # puts '---'

    end
    
  end

  def otu_only_taxon_name(taxon_name_id)
    return false if taxon_name_id.nil?
    t = TaxonName.find(taxon_name_id)

    has = []
    if !t.cached_author_year.blank?
      has.push :author 
      return has
    end

    if !t.year_of_publication.blank?
      has.push :year 
      return has
    end
    
    if t.children.any?
      has.push :children 
      return has
    end

    if t.tags.any?
      has.push :tags
      return has
    end
    
    if t.data_attributes.any?
      has.push :data_attributes 
      return has
    end

    if t.citations.any?
      has.push :citations
      return has
    end

#   self.class.reflect_on_all_associations(:has_many).each do |r|
#     next if exclude.include?(r.name)
#     return true if self.send(r.name).count(:all) > 0
#   end

#   self.class.reflect_on_all_associations(:has_one).each do |r|
#     return true if self.send(r.name).count(:all) > 0
#   end

    has
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
        if t.cached =~ /\</ || t.cached_original_combination =~ /\</
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

  # This task is idempotent.
  desc 'Ressurect ghoul family group names that are synonyms by replacing name with verbatim_name'
  task resurrect_ghoul_family_group_names: [:curation] do

    # For all family-group names that are synonyms (could also check valid ids, but this is data, not cached check
    unknown_relationship = 'TaxonNameRelationship::Iczn::Invalidating%'

    base = Protonym.where(project_id: Current.project_id)

    family_synonyms = base.joins(:taxon_name_relationships)
      .where("verbatim_name IS NOT NULL AND rank_class ILIKE '%family%'")
      .where("taxon_name_relationships.type ILIKE ?",  unknown_relationship)

    puts 'Processing these names: '
    puts %w{id verbatim_name name rank parent_name parent_rank valid_taxon_name valid_taxon_rank}.join("\t")
    puts family_synonyms.collect{|n| [n.id, n.verbatim_name, n.name, n.rank_name,  n.parent.name, n.parent.rank_name, n.valid_taxon_name.name, n.valid_taxon_name.rank_name].join("\t")}.join("\n")
    puts family_synonyms.count

    duplicates = []
    failures = []

    puts 

    family_synonyms.each do |n|
      n.name = n.verbatim_name
      n.verbatim_name = nil
    
      begin 
        n.save!
      rescue ActiveRecord::RecordInvalid
        failures.push [n.id, n.cached]
      end

      d = base.where(name: n.verbatim_name)
      if d.count > 0
        duplicates.push d.collect{|z| [z.id, z.name]}
      end
    end

    if duplicates.present?
      puts 'duplicates:'
      puts duplicates
    else
      puts 'No duplicates detected.'
    end

    if failures.present?
      puts 'Failed saves:'
      puts failures.collect{|f| f.join("\t")}.join("\n")
    else
      puts 'No failed saves.'
    end

    puts "Done."
  end

  # This task is idempotent.
  # Databases have two paradigms for storing the spelling of names. Most older
  # forms record the current form, and link to the original.  TaxonWorks does the opposite,
  # we record the original (Protonym) and link to alternate spelling/valid form.
  # This task reflects this difference, converting UCD names that were current to their original form.
  # Practically speaking this alters very little in the UI because the rednering of our names already
  # handles these nuances, it does however improve the precision/clarity of the data.
  desc 'Convert current species names to their original form when provided in verbatim' 
  task update_species_names_with_verbatim_and_legal_original_spellings: [:curation] do

    # unknown_relationship = 'TaxonNameRelationship::Iczn::Invalidating%'

    base = Protonym.where(project_id: Current.project_id)
    species_verbatim = base.where("verbatim_name IS NOT NULL AND NOT rank_class ILIKE '%FAMILY%'")
   
    puts "Considering: (#{species_verbatim.count})" 
    puts species_verbatim.collect{|n|
      [n.id, n.verbatim_name, n.name, n.rank_name,  n.parent.name, n.parent.rank_name, n.valid_taxon_name.name, n.valid_taxon_name.rank_name].join("\t")}.join("\n")

    processed = [] # Both forms of the name are detected in the three predicted forms of the name
    not_processed = []
    errored = []

    species_verbatim.each do |n|
      forms = n.predict_three_forms.values
      if forms.include?(n.name) && forms.include?(n.verbatim_name)
       begin 
         n.name = n.verbatim_name
         n.verbatim_name = nil
         n.save! 
         processed.push n.id  
       rescue ActiveRecord::RecordInvalid
         errored.push n.id 
       end
      else
        not_processed.push(n.id)
      end
    end

    puts

    puts "Processed: "
    puts processed.join("\n")
    puts
   
    puts "Not processed: "
    puts not_processed.join("\n")
    puts

    puts "Errored: "
    puts errored.join("\n")
    puts

  end


end
