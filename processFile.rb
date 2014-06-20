#!/usr/bin/env ruby

## USAGE:
##   test.rb {filename|action} ...
## WHERE:
##   filename   = "ipg140311" or similar (anything which matches /^ip[ag]\d{6}/)
##   action     = one of "download", "extract", "unzip", "report", "cleanup"
##                (if no actions, all actions except cleanup are assumed)
##                (cleanup can be toggled separately from other actions)
##   server     = either "google" or "reedtech"
##                (if neither, google is assumed)

require 'pathname'
require 'net/http'
require 'nokogiri'
require 'csv'

##
## Helper methods
##
def get_date_int(filename)
  match = filename.match(/(\d{6})/)
  match[1].to_i if not match.nil?
end

def get_date_fields(filename)
  partial_year, month, day = /^...(\d\d)(\d\d)(\d\d)\./.match(filename).captures
  full_year = (partial_year.to_i < 50 ? "20" : "19") + partial_year
  return full_year.to_i, month.to_i, day.to_i
end

def auto_extract_filenames_from_webpage(patent_types_arg, server_preference)
  patent_types = [FileRange.app_key,FileRange.grant_key].map {|e| e if patent_types_arg.include? e} # Normalizes the get/return order of the app/grant arrays
  patent_types.map do |type|
    if type
      extract_filenames_from_webpage(get_webpage(get_patent_directory_url(type, server_preference)))
    else
      nil
    end
  end
end

# patent_type can be a filename (ipa123456.zip) or simply a prefix (ipg)
def get_patent_directory_url(patent_type, server_preference)
  app_path, grant_path = nil
  if server_preference == "google"
    app_path = "https://www.google.com/googlebooks/uspto-patents-applications-text.html"
    grant_path = "https://www.google.com/googlebooks/uspto-patents-grants-text.html"
  elsif server_preference == "reedtech"
    app_path = "http://patents.reedtech.com/parbft.php"
    grant_path = "http://patents.reedtech.com/pgrbft.php"
  end

  if patent_type =~ /^app$/
    app_path
  elsif patent_type =~ /^grant$/
    grant_path
  else
    nil
  end
end  

def get_webpage(string)
  puts "Getting webpage #{string}..." # What is the best way to make this output optional?  Does it even matter?
  uri = URI(string)
  response = nil
  Net::HTTP.start uri.host do |http|
    http.request_get uri.path do |resp|
      response = resp
    end
  end
  return response
end

def extract_filenames_from_webpage(response)
  doc = Nokogiri::HTML(response.body)
  all_links = doc.xpath '//a[@href]'
  pat_links = all_links.map do |a|
    a["href"] if a["href"] =~ %r{ip(?:a|g)\d{6}.zip}
  end
  pat_links.compact
end

def extract_download_params(filename, server_preference)
  download_server, pa_path_template, pg_path_template = nil
  if server_preference == "google" # Google download preference (default)
    download_server = "storage.googleapis.com"
    pa_path_template = "/patents/appl_full_text/%s/%s"
    pg_path_template = "/patents/grant_full_text/%s/%s"
  elsif server_preference == "reedtech" # Reedtech download preference
    download_server = "patents.reedtech.com"
    pa_path_template = "/downloads/ApplicationFullText/%s/%s"
    pg_path_template = "/downloads/GrantRedBookText/%s/%s"
  end
  
  if filename =~ /^ipa\d{6}.zip$/  # application
    full_year, month, day = get_date_fields filename
    server_path = (pa_path_template % [full_year, filename])
  elsif filename =~ /^ipg\d{6}.zip/ # grant
    full_year, month, day = get_date_fields filename
    server_path = (pg_path_template % [full_year, filename])
  else
    raise "unknown file type (#{filename})"
  end
  return download_server, server_path
end

def download_file(server, path, local_filename=nil)
  local_filename ||= Pathname.new(path).basename

  if File::exists? local_filename
    puts "    (file already exists - not downloading)"
  else
    puts "    (file does not exist - downloading)"
    begin
      Net::HTTP.start server do |http|
        open(local_filename, "wb") do |file|
          http.request_get path do |response|
            response.read_body do |segment|
              file.write segment
            end
          end
        end
      end
    rescue Exception => e
      File::delete local_filename;
      raise e
    end
  end
end

def text_contains_nsf_term(line)
  /\bN\W*S\W*F\b|National Science Foundation/m.match(line)
end

def extract_govt_interest_from_app(text)
  processinstr1 = '<?federal-research-statement description="Federal Research Statement" end="lead"?>'
  processinstr2 = '<?federal-research-statement description="Federal Research Statement" end="tail"?>'
  matches = text.match(/#{Regexp.escape(processinstr1)}(.*)#{Regexp.escape(processinstr2)}/m)
  matches[1].strip if matches
end

def extract_govt_interest_from_grant(text)
  processinstr1 = '<?GOVINT description="Government Interest" end="lead"?>'
  processinstr2 = '<?GOVINT description="Government Interest" end="tail"?>'
  matches = text.match(/#{Regexp.escape(processinstr1)}(.*)#{Regexp.escape(processinstr2)}/m)
  matches[1].strip if matches
end

def block_has_nsf_govt_interest(lines, filename)
  if filename =~ /ipa/
    gov_int = extract_govt_interest_from_app(lines.join)
  elsif filename =~ /ipg/
    gov_int = extract_govt_interest_from_grant(lines.join)
  else
    raise "unknown file type (#{filename})"
  end
  text_contains_nsf_term(gov_int)
end

def extract_file(xml_filename, extract_filename)
  File.open(extract_filename, "w") do |fout|
    ## write some boilerplates
    fout << %q{<?xml version="1.0" encoding="UTF-8"?>} << "\n"
    fout << %q{<!DOCTYPE us-patent-dummy SYSTEM "dummy.dtd" [ ]>} << "\n"
    fout << %q{<root>} << "\n"

    ## extract the relavent data
    File.open(xml_filename, "r") do |fin|
      line_iter = fin.each_line
      current_block_lines = []
      inside_block        = false

      line_count  = 0
      block_count = 0

      begin
        current_line = line_iter.next

        line_count += 1
        puts "line #{line_count}" if line_count % 1e6 == 0

        if inside_block
          current_block_lines << current_line

          if current_line =~ %r{</us-patent-(application|grant)>} # leaving the block
            #puts "line #{line_count}: leaving block"
            if block_has_nsf_govt_interest(current_block_lines, extract_filename)
              #puts "block #{block_count} contains NSF-related term"
              current_block_lines.each{|line| fout.write line}
            end
            current_block_lines = []
            inside_block = false
          end
        elsif current_line =~ %r{<us-patent-(application|grant).*>} # entering a block
          #puts "line #{line_count}: entering block"
          current_block_lines << current_line

          inside_block        = true
          block_count        += 1
        end
      end while !fin.eof?
    end

    ## write some more boilerplates
    fout << %q{</root>} << "\n"
  end
end

## To use this class, pass it a block which takes Nokogiri::XML node (or whatever it's called)
## and a filename and returns something which can be converted to a string
class Extractor
  def initialize(field_name, &extractor)
    @field_name = field_name
    @extractor  = extractor
  end

  def field_name
    @field_name
  end

  def process(xml, filename)
    @extractor.call(xml, filename).to_s
  end
end

## Like Extractor, but assumes a simple xpath block
class SimpleExtractor < Extractor
  def initialize(field_name, target_xpath)
    super(field_name) do |xml, filename|
      xml.xpath(target_xpath).to_s
    end
  end
end

def produce_applications_report(extract_filename, report_filename)
  return unless extract_filename =~ /ipa/

  full_year, month, day = get_date_fields(extract_filename)

  ##
  ## Create a list of Extractors
  ##

  extractors = []

  extractors << SimpleExtractor.new("appno", ".//application-reference/document-id/doc-number/text()")
  extractors << SimpleExtractor.new("pubdate", ".//publication-reference/document-id/date/text()")
  extractors << SimpleExtractor.new("pubnum", "./us-bibliographic-data-application/publication-reference/document-id/doc-number/text()")
  extractors << SimpleExtractor.new("title", './/invention-title/text()')
  extractors << SimpleExtractor.new("abstract", ".//abstract/p/text()")

  extractors << Extractor.new("invs") do |app, filename|
    full_year, month, day = get_date_fields(filename)

    inventor_xpath = get_inventors_tag(full_year)

    inventors = app.xpath(inventor_xpath).collect do |inventor|
      inventor.xpath('.//first-name/text()').to_s + " " + inventor.xpath('.//last-name/text()').to_s
    end
    inventors.map{|i| "[#{i}]"}.join
  end

  extractors << Extractor.new("assignee") do |app, filename|
    full_year, month, day = get_date_fields(filename)
    assignees = app.xpath('.//assignees/assignee').collect do |assignee|
      assignee.xpath('./addressbook/orgname/text()').to_s
    end
    assignees.map{|a| "[#{a}]"}.join
  end

  extractors << Extractor.new("xref") do |app, filename|
    if app.at_xpath('//processing-instruction("cross-reference-to-related-applications")')
      processxref1 = '<?cross-reference-to-related-applications description="Cross Reference To Related Applications" end="lead"?>'
      processxref2 = '<?cross-reference-to-related-applications description="Cross Reference To Related Applications" end="tail"?>'
      matches = app.to_s.match(/#{Regexp.escape(processxref1)}(.*)#{Regexp.escape(processxref2)}/m)
      if matches
        Nokogiri::XML.fragment(matches[1].strip).xpath("./p/text()").to_s
      end
    else
      app.xpath(".//description/heading[contains(.,'CROSS-REFERENCE') or contains(.,'CROSSREF') or contains(.,'CROSS REFERENCE')]").to_s
    end
  end

  extractors << SimpleExtractor.new("filedate", ".//application-reference/document-id/date/text()")

  extractors << Extractor.new("govint") do |app, filename|
    Nokogiri::XML.fragment(extract_govt_interest_from_app(app.to_s)).xpath("./p/text()").to_s
  end

  extractors << Extractor.new("parentcase") do |app, filename|
    app.xpath(".//us-related-documents//parent-doc/document-id/doc-number/text()").first.to_s
  end

  extractors << Extractor.new("childcase") do |app, filename|
    app.xpath(".//us-related-documents//child-doc/document-id/doc-number/text()").first.to_s
  end

  extractors << SimpleExtractor.new("date371", ".//us-371c124-date/date/text()")
  extractors << SimpleExtractor.new("pctpubno", ".//pct-or-regional-filing-data/document-id/doc-number/text()")

  ##
  ## Run the Extractors against the file
  ##

  all_extracts = []
  File.open(extract_filename, "r") do |fin|
    doc = Nokogiri::XML(fin)

    doc.xpath('.//us-patent-application').each do |app|
      # Check that there is a Federal Research Statement. If so, continue, if not, jump to next patent app
      next unless doc.at_xpath('//processing-instruction("federal-research-statement")')

      app_extracts = extractors.collect{|e| e.process(app, extract_filename)}
      all_extracts << app_extracts
    end
  end

  ##
  ## Write the output report
  ##
  write_csv(report_filename, all_extracts, extractors.collect{|e| e.field_name})

end

def produce_grants_report(extract_filename, report_filename)
  return unless extract_filename =~ /ipg/

  full_year, month, day = get_date_fields(extract_filename)

  ##
  ## Create a list of Extractors
  ##

  extractors = []

  extractors << SimpleExtractor.new("patentno",     './/publication-reference/document-id/doc-number/text()')
  extractors << SimpleExtractor.new("patpubdate",   './/publication-reference/document-id/date/text()')
  extractors << SimpleExtractor.new("title",        './/invention-title/text()')
  extractors << SimpleExtractor.new("appno",        './/application-reference/document-id/doc-number/text()')
  extractors << SimpleExtractor.new("priorpub",     './/related-publication/document-id/doc-number/text()')
  extractors << SimpleExtractor.new("priorpubdate", './/related-publication/document-id/date/text()')
  extractors << SimpleExtractor.new("abstract",     './/abstract/p/text()')

  extractors << Extractor.new("invs") do |grant, filename|
    full_year, month, day = get_date_fields(filename)

    inventor_xpath = get_inventors_tag(full_year)

    inventors = grant.xpath(inventor_xpath).collect do |inventor|
      inventor.xpath('.//first-name/text()').to_s + " " + inventor.xpath('.//last-name/text()').to_s
    end
    inventors.map{|i| "[#{i}]"}.join
  end

  extractors << Extractor.new("assignee") do |grant, filename|
    full_year, month, day = get_date_fields(filename)
    assignees = grant.xpath('.//assignees/assignee').collect do |assignee|
      assignee.xpath('./addressbook/orgname/text()').to_s
    end
    assignees.map{|a| "[#{a}]"}.join
  end

  extractors << Extractor.new("xref") do |grant, filename|
    if grant.at_xpath('//processing-instruction("RELAPP")')
      processxref1 = '<?RELAPP description="Other Patent Relations" end="lead"?>'
      processxref2 = '<?RELAPP description="Other Patent Relations" end="tail"?>'
      matches = grant.to_s.match(/#{Regexp.escape(processxref1)}(.*)#{Regexp.escape(processxref2)}/m)
      if matches
        Nokogiri::XML.fragment(matches[1].strip).xpath("./p/text()").to_s
      end
    else
      grant.xpath(".//description/heading[contains(.,'CROSS-REFERENCE') or contains(.,'CROSSREF') or contains(.,'CROSS REFERENCE')]").to_s
    end
  end

  extractors << SimpleExtractor.new("filedate", './/application-reference/document-id/date/text()')

  extractors << Extractor.new("govint") do |grant, filename|
    Nokogiri::XML.fragment(extract_govt_interest_from_grant(grant.to_s)).xpath("./p/text()").to_s
  end

  extractors << Extractor.new("parentcase") do |app, filename|
    app.xpath(".//us-related-documents//parent-doc/document-id/doc-number/text()").first.to_s
  end

  extractors << Extractor.new("childcase") do |app, filename|
    app.xpath(".//us-related-documents//child-doc/document-id/doc-number/text()").first.to_s
  end

  extractors << SimpleExtractor.new("date371",    ".//us-371c124-date/date/text()")

  extractors << SimpleExtractor.new("pctpubno",   ".//pct-or-regional-filing-data/document-id/doc-number/text()")
  ##
  ## Run the Extractors against the file
  ##

  all_extracts = []
  File.open(extract_filename, "r") do |fin|
    doc = Nokogiri::XML(fin)

    doc.xpath('.//us-patent-grant').each do |grant|
      # Check that there is a Government Interest.
      next unless doc.at_xpath('//processing-instruction("GOVINT")')

      grant_extracts = extractors.collect{|e| e.process(grant, extract_filename)}
      all_extracts << grant_extracts
    end
  end

  ##
  ## Write the output report
  ##
  write_csv(report_filename, all_extracts, extractors.collect{|e| e.field_name})

end

def get_inventors_tag(full_year)
  if full_year.between?(2007, 2011)
    './/applicant'
  elsif full_year >= 2012
    './/inventor/addressbook'
  else
    raise "cannot process data from year #{full_year}"
  end
end

def write_csv(report_filename, all_extracts, colnames)
  CSV.open(report_filename,"w") do |csv|
    csv << colnames 
    all_extracts.each do |app_extracts| 
      csv << app_extracts.map {|row| row.gsub /\n/, " "}
    end
  end
end

class ArgumentsHandler
  def handle_args(args)
    actions           = args.select{|s| s =~ /^(download|unzip|extract|report|cleanup)$/}.uniq
    server_preference = self.parse_server_preference args
    
    ranges_handler    = FileRangesHandler.new
    ranges            = ranges_handler.handle args, server_preference
    
    filenames_handler = FilenamesHandler.new
    solo_filenames    = filenames_handler.handle args
    
    
    has_ranges, has_filenames = !ranges.empty?, !solo_filenames.empty?
    
    if has_ranges and has_filenames 
      throw StandardError.new "You can't use both ranges and filenames, you'll just confuse yourself! Are you smarter than that? Complain to a programmer!"
    end
    
    filenames    = ranges + solo_filenames # One should always be nil, and this will make it easier if we decide to allow both concurrently
    
    actions_hash = {
    should_cleanup:    !!(actions.delete "cleanup"),
    should_download:   !!(actions.empty? || (actions.include? "download") ),
    should_unzip:      !!(actions.empty? || (actions.include? "unzip")    ),
    should_extract:    !!(actions.empty? || (actions.include? "extract")  ),
    should_report:     !!(actions.empty? || (actions.include? "report")   ),
    server_preference: server_preference
    }

    return filenames, actions_hash
  end

  def parse_server_preference(args)
    server_preference = "google"
    args.each do |arg| 
      if arg =~ /^google|reedtech$/i
        server_preference = arg.downcase
        break
      end
    end
    server_preference
  end
end

class FilenamesHandler
  def handle(args)
    args.map do |arg| 
      fname_match = arg.match /(?<filename>ip[ag]\d{6})(?<ext>\..*)?/
      if fname_match
        if !fname_match["ext"].nil? 
          puts "Warning: file extention on '#{arg}' will be ignored"
        end
        fname_match["filename"]
      end
    end.compact
  end
end

class FileRangesHandler
  def handle(args, server_preference)
    ranges = get_ranges args
    expand_ranges ranges, server_preference
  end

  private
  def get_ranges(args)
    curr_keyword = nil
    fileargs = args.map do |arg| 
      if curr_keyword
        begin
          fr = FileRange.parse arg, curr_keyword
        puts "#{fr}, #{fr.nil?}"
        rescue StandardError => e # If the arg could not be parsed as a range
          throw StandardError.new "Token '#{arg}' following keyword '#{curr_keyword}' could not be parsed as a range"
        end
        curr_keyword = nil
        fr
      else      
        case arg.downcase
        when "grant", "ipg"
          curr_keyword = FileRange.grant_key
        when "app", "ipa"
          curr_keyword = FileRange.app_key
        when "both"
          curr_keyword = FileRange.both_key
        end
        nil
      end
    end
    fileargs.compact
  end

  def expand_ranges(ranges, server_preference)
    all_app_filenames, all_grant_filenames = auto_extract_filenames_from_webpage get_ptypes_present(ranges), server_preference
    all_filenames_aliased = nil
    filenames = []
    ranges.each do |range|
      if range.type == FileRange.app_key
        all_filenames_aliased = all_app_filenames
      elsif range.type == FileRange.grant_key
        all_filenames_aliased = all_grant_filenames
      elsif range.type == FileRange.both_key
        all_filenames_aliased = all_app_filenames + all_grant_filenames
      end
      all_filenames_aliased.each do |str|
        date = get_date_int str
        in_between_dates = (date >= get_date_int(range.from_date) && date <= get_date_int(range.to_date))
        #puts "#{in_between_dates}: #{get_date_int range.from_date} < #{date} < #{get_date_int range.to_date}" if in_between_dates 
        if in_between_dates
          filenames.push str.match(/(ip[ag]\d{6})/)[1]
        end
      end
    end
    filenames
  end
  
  def get_ptypes_present(ranges)
    types = []
    found_ipa, found_ipg = false, false
    ranges.each do |fa|
      if fa.type == FileRange.app_key
        found_ipa = true
        types.push "app"
      elsif fa.type == FileRange.grant_key
        found_ipg = true
        types.push "grant"
      elsif fa.type == FileRange.both_key
        found_ipa = true
        found_ipg = true
        types = [FileRange.app_key, FileRange.grant_key]
      end
      if found_ipa and found_ipg
        break
      end
    end
    types
  end
end

class FileRange
  @@grant_key, @@app_key, @@both_key = "grant", "app", "both"

  def self.grant_key
    @@grant_key
  end
  def self.app_key
    @@app_key
  end
  def self.both_key
    @@both_key
  end

  def self.parse(arg, type)
    range = arg.split "-"
    poss_formats = [ /^(?<year>\d{2,4})$/, #Year only format (yy or yyyy)
                     /^(?<type>ip[ag])?(?<year>\d{2})(?<month>\d{2})(?<day>\d{2})(?:\..*)?$/, # ip[ag]yymmdd (filename) format
                     /^(?<month>\d{2})\/(?<day>\d{2})\/(?<year>\d{2})$/ # mm/dd/yy format
                   ]
    date_matches = nil 
    poss_formats.each do |regex| 
      matches = range.map do |date|
        date.match regex
      end
      unless matches.all? {|e| e.nil?}
        date_matches = matches
        break
      end
    end
    if date_matches.any? {|date| date.captures.size == 1} # if only year was captured
      return FileRange.new type, expand_year_to_formatted_date(date_matches.first["year"], "down"), expand_year_to_formatted_date(date_matches.last["year"], "up")
    else
      return FileRange.new type, format_matchdata_date(date_matches.first), format_matchdata_date(date_matches.last) 
    end
  end 

  def initialize(type, from_date, to_date)
    @type = type
    @from_date = from_date
    @to_date = to_date
  end
  
  attr_reader :type, :from_date, :to_date

  private
  def self.expand_year_to_formatted_date(year, direction)
    year = year[2,4] if year.size == 4
    str_value = case direction.downcase
      when "up"
        "99"
      when "down"
        "00"
      else
        throw ArgumentError, "Direction must be either up or down"
    end
    if year.size == 2 # A year in the yy format
      format_date(year, str_value, str_value)
    else
      nil
    end
  end
      
  def self.format_matchdata_date(matchdata)
    format_date matchdata["year"], matchdata["month"], matchdata["day"]
  end
  def self.format_date(year, month, day)
    "#{year}#{month}#{day}"
  end
end


##
## Main Loop
##
filenames, prefs = nil
begin
  args_handler = ArgumentsHandler.new
  filenames, prefs = args_handler.handle_args ARGV
rescue StandardError => e
  puts "=== ERROR IN ARGUMENTS PARSING ==="
  puts e.message
  puts e.backtrace.inspect
end
puts "filenames   = #{filenames}"
puts "preferences =\n#{(prefs.map {|k,v| "  #{k}: #{v}" if v}).compact.join(",\n")}"
puts
filenames.each do |filename|
  puts "begin processing #{filename}"
  begin

    zip_filename            = "#{filename}.zip"
    xml_filename            = "#{filename}.xml"
    extract_filename        = "#{filename}.extract"
    report_apps_filename    = "#{filename}.apps"
    report_grants_filename  = "#{filename}.grants"

    if prefs[:should_download]
      puts "  downloading #{filename}"
      
      download_server, server_path = extract_download_params zip_filename, prefs[:server_preference]
      download_file download_server, server_path
    end

    if prefs[:should_unzip]
      puts "  unzipping #{filename}"

      raise "#{zip_filename} doesn't exist" unless File.exists? zip_filename
      system("unzip -o -p #{zip_filename} > #{xml_filename}")
    end

    if prefs[:should_extract]
      puts "  extracting #{filename}"

      raise "#{xml_filename} doesn't exist" unless File.exists? xml_filename
      extract_file xml_filename, extract_filename
    end

    if prefs[:should_report]
      puts "  reporting on #{filename}"

      raise "#{extract_filename} doesn't exist" unless File.exists? extract_filename
      produce_applications_report extract_filename, report_apps_filename
      produce_grants_report       extract_filename, report_grants_filename
    end

    if prefs[:should_cleanup]
      puts "  cleaning up #{filename}"

      File.delete zip_filename
      File.delete xml_filename
      File.delete extract_filename
      # don't delete report files!
    end

  rescue StandardError => e
    puts "=== ERROR (#{filename}) ==="
    puts e.message
    puts e.backtrace.inspect
  end

  puts "end processing #{filename}"
end
