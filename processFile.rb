#!/usr/bin/env ruby

## USAGE:
##   test.rb {filename|action} ...
## WHERE:
##   filename   = "ipg140311.zip" or similar (anything which isn't a known action)
##   action     = one of "download", "extract"

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

def extract_download_params(filename)
  download_server = "patents.reedtech.com"

  if filename =~ /^ipa\d{6}.zip$/  # application
    full_year, month, day = get_date_fields filename
    server_path = "/downloads/ApplicationFullText/#{full_year}/#{filename}"
  elsif filename =~ /^ipg\d{6}.zip/ # grant
    full_year, month, day = get_date_fields filename
    server_path = "/downloads/GrantRedBookText/#{full_year}/#{filename}"
  else
    raise "unknown file type (#{filename})"
  end

  return download_server, server_path
end

def download_file(server, path, local_filename=nil)
  local_filename ||= Pathname.new(path).basename

  Net::HTTP.start server do |http|
    open(local_filename, "wb") do |file|
      http.request_get path do |response|
        response.read_body do |segment|
          file.write segment
        end
      end
    end
  end
end

def text_contains_nsf_term(line)
  /\bN\W*S\W*F\b|National Science Foundation/m.match(line)
end

def extract_govt_interest(text)
  processinstr1 = '<?federal-research-statement description="Federal Research Statement" end="lead"?>'
  processinstr2 = '<?federal-research-statement description="Federal Research Statement" end="tail"?>'
  matches = text.match(/#{Regexp.escape(processinstr1)}(.*)#{Regexp.escape(processinstr2)}/m)
  matches[1].strip if matches
end

def block_has_nsf_govt_interest(lines)
  gov_int = extract_govt_interest(lines.join)
  text_contains_nsf_term(gov_int)
end

def extract_file(xml_filename, extract_filename)
  File.open(extract_filename, "w") do |fout|
    ## write some boilerplates
    fout << %q{<?xml version="1.0" encoding="UTF-8"?>} << "\n"
    fout << %q{<!DOCTYPE us-patent-application SYSTEM "us-patent-application-v43-2012-12-04.dtd" [ ]>} << "\n"
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

          if current_line =~ %r{</us-patent-application>} # leaving the block
            #puts "line #{line_count}: leaving block"
            if block_has_nsf_govt_interest(current_block_lines)
              #puts "block #{block_count} contains NSF-related term"
              current_block_lines.each{|line| fout.write line}
            end
            current_block_lines = []
            inside_block = false
          end
        elsif current_line =~ %r{<us-patent-application.*>} # entering a block
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
## and return something which can be converted to a string
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

def produce_applications_report(extract_filename, report_filename)
  return unless extract_filename =~ /ipa/

  ##
  ## Create a list of Extractors
  ##

  #FIELDS = %w{appno pubdate pubnum title abstract invs assignee xref filedate govint parentcase childcase date371 pctpubno}

  extractors = []

  extractors << Extractor.new("appno") do |app, filename|
    app.xpath(".//application-reference/document-id/doc-number/text()").to_s
  end
  extractors << Extractor.new("pubdate") do |app, filename|
    app.xpath(".//publication-reference/document-id/date/text()").to_s
  end
  extractors << Extractor.new("pubnum") do |app, filename|
    app.xpath("./us-bibliographic-data-application/publication-reference/document-id/doc-number/text()").to_s
  end
  extractors << Extractor.new("title") do |app, filename|
    app.xpath('.//invention-title/text()').to_s
  end
  extractors << Extractor.new("abstract") do |app, filename|
    app.xpath(".//abstract/p/text()").to_s
  end
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
  extractors << Extractor.new("filedate") do |app, filename|
    app.xpath(".//application-reference/document-id/date/text()").to_s
  end
  extractors << Extractor.new("govint") do |app, filename|
    Nokogiri::XML.fragment(extract_govt_interest(app.to_s)).xpath("./p/text()").to_s
  end
  extractors << Extractor.new("parentcase") do |app, filename|
    app.xpath(".//us-related-documents//parent-doc/document-id/doc-number/text()").first.to_s
  end
  extractors << Extractor.new("childcase") do |app, filename|
    app.xpath(".//us-related-documents//child-doc/document-id/doc-number/text()").first.to_s
  end
  extractors << Extractor.new("date371") do |app, filename|
    app.xpath(".//us-371c124-date/date/text()").to_s
  end
  extractors << Extractor.new("pctpubno") do |app, filename|
    app.xpath(".//pct-or-regional-filing-data/document-id/doc-number/text()").to_s
  end

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

  CSV.open(report_filename,"w") do |csv|
    csv << extractors.collect{|e| e.field_name}
    all_extracts.each{|app_extract| csv << app_extract}
  end

end

def produce_grants_report(extract_filename, report_filename)
  return unless extract_filename =~ /ipg/

end

##
## Parse command-line arguments
##

actions   = ARGV.select{|s| s =~ /^download|unzip|extract|report|cleanup$/}
filenames = ARGV - actions
filenames = filenames.map{|f| f.gsub(/\..*$/, "")}

should_download = actions.empty? || (actions.include? "download")
should_unzip    = actions.empty? || (actions.include? "unzip")
should_extract  = actions.empty? || (actions.include? "extract")
should_report   = actions.empty? || (actions.include? "report")
should_cleanup  = actions.empty? || (actions.include? "cleanup")

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

      download_server, server_path = extract_download_params zip_filename
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



