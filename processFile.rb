#!/usr/bin/env ruby

## USAGE:
##   test.rb {filename|action} ...
## WHERE:
##   filename   = "ipg140311" or similar (anything which matches /^ip[ag]\d{6}/)
##   action     = one of "download[-(reed|goog)]", "extract", "unzip", "report", "cleanup"
##                (if not action, all actions are assumed)

require 'pathname'
require 'net/http'
require 'nokogiri'
require 'csv'

##
## Helper methods
##

def get_date_fields(filename)
  partial_year, month, day = /^...(\d\d)(\d\d)(\d\d)\./.match(filename)[1]
  full_year = (partial_year.to_i < 50 ? "20" : "19") + partial_year
  return full_year, month, day
end

def extract_download_params(filename, server_preference)
  download_server, pa_path_template, pg_path_template = nil
  if server_preference == "goog" # Google download preference (default)
    download_server = "storage.googleapis.com"
    pa_path_template = "/patents/appl_full_text/%s/%s"
    pg_path_template = "/patents/grant_full_text/%s/%s"
  elsif server_preference == "reed" # Reedtech download preference
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
  raise "cannot process file with year #{full_year}" if full_year.to_i < 2012

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
    inventor_xpath = (full_year.to_i < 2007) ? './/applicant' : './/inventor/addressbook'
    inventors = app.xpath(inventor_xpath).collect do |inventor|
      inventor.xpath('.//first-name/text()').to_s + " " + inventor.xpath('.//last-name/text()').to_s
    end
    inventors.map{|i| "[#{i}]"}.join
  end

  extractors << Extractor.new("assignee") do |app, filename|
    full_year, month, day = get_date_fields(filename)
    case full_year.to_i
    when 2012..2014
      assignees = app.xpath('.//assignees/assignee').collect do |assignee|
        assignee.xpath('./addressbook/orgname/text()').to_s
      end
      assignees.map{|a| "[#{a}]"}.join
    end
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

  extractors << Extractor.new("ptoids") do |app, filename|
    extract_govt_interest_from_app(app.to_s).scan(/\b\d{7}\b/).collect{|s| "[#{s}]"}.join
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
  raise "cannot process file with year #{full_year}" if full_year.to_i < 2012


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
    inventor_xpath = (full_year.to_i < 2007) ? './/applicant' : './/inventor/addressbook'
    inventors = grant.xpath(inventor_xpath).collect do |inventor|
      inventor.xpath('.//first-name/text()').to_s + " " + inventor.xpath('.//last-name/text()').to_s
    end
    inventors.map{|i| "[#{i}]"}.join
  end

  extractors << Extractor.new("assignee") do |grant, filename|
    full_year, month, day = get_date_fields(filename)
    case full_year.to_i
    when 2012..2014
      assignees = grant.xpath('.//assignees/assignee').collect do |assignee|
        assignee.xpath('./addressbook/orgname/text()').to_s
      end
      assignees.map{|a| "[#{a}]"}.join
    end
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

  extractors << Extractor.new("ptoids") do |grant, filename|
    extract_govt_interest_from_grant(grant.to_s).scan(/\b\d{7}\b/).collect{|s| "[#{s}]"}.join
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

def write_csv(report_filename, all_extracts, colnames)
  CSV.open(report_filename,"w") do |csv|
    csv << colnames 
    all_extracts.each do |app_extracts| 
      csv << app_extracts.map {|row| row.gsub /\n/, " "}
    end
  end
end


##
## Parse command-line arguments
##

actions   = ARGV.select{|s| s =~ /^download(-\w*)?|unzip|extract|report|cleanup$/}.uniq
filenames = (ARGV - actions).select{|arg| arg =~ /^ip[ag]\d{6}/ }
filenames = filenames.map{|f| f.gsub(/\..*$/, "")} # Removes file extension from filename

should_download = actions.empty?
server_preference = "goog"

unless actions.empty?
  actions.each do |action|
    should_download = !(action.match /download/).nil? 

    if should_download # Break once the download option has been found
      dl_suffix = action.match(/goog|reed/).to_s
      server_preference = dl_suffix unless dl_suffix == "" # Overwrite the previous server preference of "goog" if dl_suffix is "" (ie nil.to_s)
      break
    end  
  end
end

should_unzip    = actions.empty? || (actions.include? "unzip")
should_extract  = actions.empty? || (actions.include? "extract")
should_report   = actions.empty? || (actions.include? "report")
should_cleanup  = actions.include? "cleanup"

puts "actions   = #{actions}"
puts "filenames = #{filenames}"

##
## Main Loop
##

filenames.each do |filename|
  puts "begin processing #{filename}"

  begin

    zip_filename            = "#{filename}.zip"
    xml_filename            = "#{filename}.xml"
    extract_filename        = "#{filename}.extract"
    report_apps_filename    = "#{filename}.apps"
    report_grants_filename  = "#{filename}.grants"

    if should_download
      puts "  downloading #{filename}"
      
      download_server, server_path = extract_download_params zip_filename, server_preference
      download_file download_server, server_path
    end

    if should_unzip
      puts "  unzipping #{filename}"

      raise "#{zip_filename} doesn't exist" unless File.exists? zip_filename
      system("unzip -o -p #{zip_filename} > #{xml_filename}")
    end

    if should_extract
      puts "  extracting #{filename}"

      raise "#{xml_filename} doesn't exist" unless File.exists? xml_filename
      extract_file xml_filename, extract_filename
    end

    if should_report
      puts "  reporting on #{filename}"

      raise "#{extract_filename} doesn't exist" unless File.exists? extract_filename
      produce_applications_report extract_filename, report_apps_filename
      produce_grants_report       extract_filename, report_grants_filename
    end

    if should_cleanup
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
