require 'csv'

# Do not reference rake tasks in TW
namespace :taxonworks do
  namespace :type_material do

    PROJECT_ID = (ENV['PROJECT_ID_OVERRIDE'] || 16).to_i # sixteen
    USER_ID = 1 # matt

    # Predicate (ControlledVocabularyTerm / Predicate) ids, stored in
    # DataAttribute#controlled_vocabulary_term_id
    PREDICATES = {
      country:     349, # Species:Country     -> CollectingEvent / GeographicArea
      prim_type:   353, # Species:PrimType    -> TypeMaterial#type_type
      type_sex:    354, # Species:TypeSex     -> BiocurationClassification(s)
      designator:  355, # Species:Designator  -> Citation on the TypeMaterial
      depository:  356, # Species:Depository  -> CollectionObject#repository_id
      type_number: 357  # Species:TypeNumber  -> Identifier::Local::CatalogNumber
    }.freeze

    # Predicate 353 value -> TypeMaterial#type_type. 'NS' means skip the name entirely.
    TYPE_TYPE_MAP = {
      'NS' => :skip,
      'LT' => 'lectotype',
      'ST' => 'syntype',
      'HT' => 'holotype',
      'NT' => 'neotype'
    }.freeze

    # Predicate 354 value -> sex(es). :todo values are logged for manual handling.
    TYPE_SEX_MAP = {
      'M' => [:male],
      'm' => [:male],
      'f' => [:female],
      'F' => [:female],
      'D' => [:female],
      'N' => [:male, :female],
      'T' => :todo,
      'G' => :todo
    }.freeze

    # sex -> BiocurationClass id
    BIOCURATION_CLASS = {
      male:   425,
      female: 426
    }.freeze

    NAMESPACE_SOURCE_IMPORT = 35  # Identifier::Local::Import namespace for Source matching (Predicate 355)
    NAMESPACE_CATALOG_NUMBER = 105 # Identifier::Local::CatalogNumber namespace (Predicate 357)

    # Converts DataAttributes on a TaxonName into TypeMaterial and related records
    # (CollectionObject, BiocurationClassifications, CollectingEvent, Citation, Identifier).
    #
    # Modes (mode=preview is the default and never writes):
    #   rake taxonworks:type_material:build mode=preview
    #   rake taxonworks:type_material:build mode=save
    desc 'build TypeMaterial (and related records) from TaxonName DataAttributes'
    task :build do
      Current.user_id = USER_ID
      Current.project_id = PROJECT_ID
      raise 'project_id not set' if Current.project_id != PROJECT_ID

      mode = (ENV['mode'] || 'preview').downcase.to_sym
      raise "mode must be 'preview' or 'save', got '#{mode}'" unless [:preview, :save].include?(mode)

      coll_map = load_coll_to_repository

      # Accumulators for the report
      todos = []                 # GitHub-markdown checkbox issues
      created_repositories = []  # [coden, name, id-or-:preview]
      processed = []             # taxon_name_ids that produced a (valid) TypeMaterial
      skipped = []               # [taxon_name_id, reason]
      failed = []                # [taxon_name_id, errors]

      # Within-run caches. Per the spec, CollectingEvents and missing Repositories
      # must be created in THIS task; never reference pre-existing DB CollectingEvents.
      collecting_events = {}     # geographic_area_id -> CollectingEvent (created this run)
      repositories = {}          # coden -> repository_id (nil when unresolved)
      geographic_areas = {}      # geographic_area_id -> boolean (exists in db?)

      # Scope: TaxonNames carrying one or more of the target attributes.
      attributes = InternalAttribute
        .where(
          controlled_vocabulary_term_id: PREDICATES.values,
          attribute_subject_type: 'TaxonName',
          project_id: PROJECT_ID
        )

      by_taxon_name = attributes.to_a.group_by(&:attribute_subject_id)

      # Optional limit=N for quick test runs over a subset of TaxonNames.
      total_taxon_names = by_taxon_name.size
      if (limit = ENV['limit'])
        by_taxon_name = by_taxon_name.first(limit.to_i).to_h
      end

      puts "Mode: #{mode}"
      puts "Project: #{PROJECT_ID}"
      puts "TaxonNames with target attributes: #{total_taxon_names}#{limit ? " (limited to #{by_taxon_name.size})" : ''}"
      puts

      ActiveRecord::Base.transaction do
        by_taxon_name.each do |taxon_name_id, attrs|
          # Index this name's attributes by predicate.
          # values_for[:prim_type] => array of String values for predicate 353, etc.
          values_for = {}
          PREDICATES.each do |key, predicate_id|
            values_for[key] = attrs.select { |a| a.controlled_vocabulary_term_id == predicate_id }.map(&:value)
          end

          # --- Predicate 353 first: determines type_type, gates everything ---
          prim = values_for[:prim_type].first
          if prim.nil?
            skipped.push [taxon_name_id, 'no PrimType (353) present']
            next
          end

          type_type = TYPE_TYPE_MAP[prim]
          if type_type.nil?
            skipped.push [taxon_name_id, "PrimType (353) value '#{prim}' not in lookup"]
            todos.push "TaxonName #{taxon_name_id}: PrimType (353) value '#{prim}' not in lookup"
            next
          elsif type_type == :skip
            skipped.push [taxon_name_id, "PrimType (353) is 'NS'"]
            next
          end

          protonym = Protonym.where(project_id: PROJECT_ID, id: taxon_name_id).first
          if protonym.nil?
            skipped.push [taxon_name_id, 'not a Protonym in this project']
            next
          end

          # --- Build the CollectionObject (a Specimen) ---
          collection_object = Specimen.new(total: 1, project_id: PROJECT_ID)

          # Predicate 356 -> repository_id (optional)
          if (coden = values_for[:depository].first)
            repository_id = resolve_repository(coden, coll_map, repositories, created_repositories, todos, taxon_name_id)
            collection_object.repository_id = repository_id if repository_id
          end

          # Predicate 354 -> BiocurationClassifications (optional, may be several)
          sexes = []
          values_for[:type_sex].each do |v|
            mapped = TYPE_SEX_MAP[v]
            if mapped.nil?
              todos.push "TaxonName #{taxon_name_id}: TypeSex (354) value '#{v}' not in lookup"
            elsif mapped == :todo
              todos.push "TaxonName #{taxon_name_id}: TypeSex (354) value '#{v}' requires manual review"
            else
              sexes.concat(mapped)
            end
          end
          sexes.uniq.each do |sex|
            collection_object.biocuration_classifications.build(
              biocuration_class_id: BIOCURATION_CLASS[sex],
              project_id: PROJECT_ID
            )
          end

          # Predicate 349 -> CollectingEvent referencing a GeographicArea (optional)
          if (country = values_for[:country].first)
            geographic_area_id = country.to_i
            if geographic_area_id > 0 && geographic_area_exists?(geographic_area_id, geographic_areas)
              collection_object.collecting_event = find_or_build_collecting_event(geographic_area_id, collecting_events)
            else
              todos.push "TaxonName #{taxon_name_id}: Country (349) value '#{country}' is not a valid GeographicArea id"
            end
          end

          # Predicate 357 -> Identifier::Local::CatalogNumber (optional, may be several)
          values_for[:type_number].each do |number|
            collection_object.identifiers.build(
              type: 'Identifier::Local::CatalogNumber',
              namespace_id: NAMESPACE_CATALOG_NUMBER,
              identifier: number,
              project_id: PROJECT_ID
            )
          end

          # --- Build the TypeMaterial linking CollectionObject to the Protonym ---
          type_material = TypeMaterial.new(
            protonym: protonym,
            collection_object: collection_object,
            type_type: type_type,
            project_id: PROJECT_ID
          )

          # Predicate 355 -> Citation on the TypeMaterial (optional)
          if (designator = values_for[:designator].first)
            source_id = source_id_for(designator)
            if source_id
              type_material.origin_citation = Citation.new(
                source_id: source_id,
                is_original: true,
                project_id: PROJECT_ID
              )
            else
              todos.push "TaxonName #{taxon_name_id}: Designator (355) '#{designator}' did not match an Identifier::Local::Import (namespace #{NAMESPACE_SOURCE_IMPORT})"
            end
          end

          # --- Persist ---
          # Both modes build and save the full object graph; preview simply rolls
          # the whole transaction back at the end, so its results are exact.
          # Each name is wrapped in a savepoint (requires_new) so that a failure
          # (model- or database-level) rolls back only this name and the run
          # continues, per spec.
          begin
            ActiveRecord::Base.transaction(requires_new: true) do
              type_material.save!
            end
            # Cache the now-persisted CollectingEvent for reuse within this run.
            if collection_object.collecting_event && (gid = collection_object.collecting_event.geographic_area_id)
              collecting_events[gid] ||= collection_object.collecting_event
            end
            processed.push taxon_name_id
          rescue ActiveRecord::RecordInvalid => e
            failed.push [taxon_name_id, e.record.errors.full_messages.join('; ')]
          rescue ActiveRecord::StatementInvalid => e
            failed.push [taxon_name_id, e.message.lines.first.to_s.strip]
          end
        end

        if mode == :preview
          puts '(preview mode) rolling back transaction'
          raise ActiveRecord::Rollback
        end
      end

      render_report(mode, processed, skipped, failed, created_repositories, todos)
    end

    # ---- helpers ----

    # Loads data/COLL_to_repository.tsv keyed by coden.
    def load_coll_to_repository
      file = File.join(File.dirname(__FILE__), 'data', 'COLL_to_repository.tsv')
      # The file is tab-delimited with unquoted fields that may themselves contain
      # double quotes, so disable CSV quote processing (treat " as a literal char).
      CSV.read(file, col_sep: "\t", headers: true, quote_char: "\x00", encoding: 'ISO-8859-1:UTF-8')
        .each_with_object({}) do |row, h|
          coden = row['coden']&.strip
          next if coden.nil? || coden.empty?
          h[coden] = {
            coll_name: row['coll_name']&.strip,
            repository_id: row['repository_id']&.strip,
            missing: row['missing']&.strip
          }
        end
    end

    # Returns a repository_id for the given coden, creating a Repository when the
    # COLL row is flagged missing. Returns nil when there is no usable match.
    # Created Repositories are persisted within the run's transaction (rolled back
    # in preview mode).
    def resolve_repository(coden, coll_map, cache, created_repositories, todos, taxon_name_id)
      return cache[coden] if cache.key?(coden)

      row = coll_map[coden]
      if row.nil?
        todos.push "TaxonName #{taxon_name_id}: Depository (356) coden '#{coden}' not found in COLL_to_repository.tsv"
        return (cache[coden] = nil)
      end

      if row[:repository_id] && !row[:repository_id].empty?
        return (cache[coden] = row[:repository_id].to_i)
      end

      if row[:missing] == '1'
        repository = Repository.create!(name: row[:coll_name], acronym: coden)
        created_repositories.push [coden, row[:coll_name], repository.id]
        return (cache[coden] = repository.id)
      end

      # No repository_id and not flagged missing -> do not populate.
      todos.push "TaxonName #{taxon_name_id}: Depository (356) coden '#{coden}' has no repository_id and is not flagged missing"
      cache[coden] = nil
    end

    # Reuses a CollectingEvent created earlier in this run for the same
    # GeographicArea, otherwise builds a fresh one. Never references a
    # pre-existing database CollectingEvent.
    def find_or_build_collecting_event(geographic_area_id, cache)
      cache[geographic_area_id] || CollectingEvent.new(geographic_area_id: geographic_area_id, project_id: PROJECT_ID)
    end

    # Cached existence check for a GeographicArea id (avoids FK violations on save).
    def geographic_area_exists?(geographic_area_id, cache)
      return cache[geographic_area_id] if cache.key?(geographic_area_id)
      cache[geographic_area_id] = GeographicArea.where(id: geographic_area_id).exists?
    end

    # Predicate 355: maps a designator value to a Source via Identifier::Local::Import.
    def source_id_for(value)
      Identifier::Local::Import
        .where(
          namespace_id: NAMESPACE_SOURCE_IMPORT,
          identifier: value,
          identifier_object_type: 'Source',
          project_id: PROJECT_ID
        )
        .limit(1)
        .pick(:identifier_object_id)
    end

    def render_report(mode, processed, skipped, failed, created_repositories, todos)
      puts
      puts '=' * 72
      puts "Report (#{mode})"
      puts '=' * 72

      puts
      puts "Processed (#{processed.size})"
      puts processed.join("\n")

      puts
      puts "Skipped (#{skipped.size})"
      puts skipped.collect { |id, reason| "#{id}\t#{reason}" }.join("\n")

      puts
      puts "Failed (#{failed.size})"
      puts failed.collect { |id, errors| "#{id}\t#{errors}" }.join("\n")

      puts
      puts "Repositories created#{mode == :preview ? ' (preview, not saved)' : ''} (#{created_repositories.size})"
      puts created_repositories.collect { |coden, name, id| "#{coden}\t#{name}\t#{id}" }.join("\n")

      puts
      puts "# TODO (#{todos.size})"
      puts todos.collect { |t| "* [ ] #{t}" }.join("\n")
    end

  end
end
