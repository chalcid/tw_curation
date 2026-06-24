require 'csv'

# Do not reference rake tasks in TW
namespace :taxonworks do
  namespace :utility do

    # Matches each coden in data/repositories.csv to a Repository in TaxonWorks
    # via the Repository#acronym field, and reports the result.
    # For unmatched codens, a second pass uses Levenshtein distance to compare
    # the COLL.txt depository text against Repository#name for fuzzy candidates.
    #
    # rake taxonworks:utility:match_repositories
    desc 'match codens in data/repositories.csv to Repository acronyms'
    task :match_repositories do
      data_dir = File.dirname(__FILE__) + '/data'

      codens = CSV.read(File.join(data_dir, 'repositories.csv')).flatten.collect(&:strip).reject(&:blank?)

      coll_file = File.join(data_dir, 'COLL.txt')
      coll = CSV.read(coll_file, col_sep: "\t", headers: true, quote_char: '"', encoding: 'ISO-8859-1:UTF-8').each_with_object({}) do |row, h|
        acronym = row[0]&.strip
        name    = row[1]&.strip
        h[acronym] = name if acronym && name
      end

      FUZZY_THRESHOLD = 10

      matched   = []
      not_found = []
      ambiguous = []

      codens.each do |coden|
        repositories = Repository.where(acronym: coden)

        case repositories.size
        when 0
          not_found.push coden
        when 1
          r = repositories.first
          matched.push [coden, r.id, r.name, coll[coden]]
        else
          ambiguous.push [coden, repositories.pluck(:id).join(';')]
        end
      end

      # Second pass: fuzzy match unmatched codens via COLL.txt text against Repository#name
      # using PostgreSQL fuzzystrmatch levenshtein() in a single batch query.
      # levenshtein() has a 255-char limit, so both sides are truncated with left().
      coll_pairs = not_found.filter_map { |coden| coden == 'dest' ? nil : (text = coll[coden]) && [coden, text] }

      fuzzy = []

      if coll_pairs.any?
        conn = ActiveRecord::Base.connection
        values_sql = coll_pairs.map { |coden, text| "(#{conn.quote(coden)}, #{conn.quote(text)})" }.join(', ')

        sql = <<~SQL
          WITH coll_data(coden, coll_text) AS (
            VALUES #{values_sql}
          ),
          distances AS (
            SELECT
              c.coden,
              c.coll_text,
              r.id   AS repository_id,
              r.name AS repository_name,
              levenshtein(left(lower(r.name), 255), left(lower(c.coll_text), 255)) AS distance
            FROM coll_data c
            CROSS JOIN #{Repository.quoted_table_name} r
          ),
          ranked AS (
            SELECT *, rank() OVER (PARTITION BY coden ORDER BY distance) AS rnk
            FROM distances
          )
          SELECT coden, coll_text, repository_id, repository_name, distance
          FROM ranked
          WHERE rnk = 1 AND distance <= #{FUZZY_THRESHOLD}
          ORDER BY distance
        SQL

        fuzzy = conn.select_all(sql).rows
      end

      puts "Matched (#{matched.size})"
      puts %w[coden repository_id repository_name coll_name].join("\t")
      puts matched.collect { |m| m.join("\t") }.join("\n")

      puts
      puts "Ambiguous (#{ambiguous.size})"
      puts ambiguous.collect { |a| a.join("\t") }.join("\n")

      puts
      puts "Not found (#{not_found.size})"
      puts not_found.collect { |c| [c, coll[c]].compact.join("\t") }.join("\n")

      puts
      puts "Fuzzy candidates from COLL.txt (distance <= #{FUZZY_THRESHOLD}) (#{fuzzy.size})"
      puts %w[coden coll_text repository_id repository_name distance].join("\t")
      puts fuzzy.collect { |r| r.join("\t") }.join("\n")

      # Build a coden -> [repository_id, repository_name] lookup from all unambiguous hits.
      # Exact acronym match takes priority over fuzzy.
      resolved = {}
      fuzzy.each   { |coden, _, repo_id, repo_name, _| resolved[coden] = [repo_id, repo_name] }
      matched.each { |coden, repo_id, repo_name, _|    resolved[coden] = [repo_id, repo_name] }

      usage_counts = DataAttribute.where(controlled_vocabulary_term_id: 356)
        .group(:value)
        .count

      puts
      puts "COLL.txt full report (#{coll.size})"
      puts %w[coden coll_name repository_id repository_name count].join("\t")
      puts coll.map { |coden, coll_text|
        repo_id, repo_name = resolved[coden]
        [coden, coll_text, repo_id, repo_name, usage_counts[coden].to_i].join("\t")
      }.join("\n")
    end

  end
end
